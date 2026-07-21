#include "AuthService.h"
#include "core/NetworkUtils.h"
#include "data/repositories/UserRepo.h"
#include "services/UserIngredientService.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QDir>
#include <QSettings>

// ==========================================================================
//  构造 / 析构
// ==========================================================================

AuthService::AuthService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
    connect(m_networkMgr, &QNetworkAccessManager::finished,
            this, &AuthService::onNetworkReply);
    loadProductFromCache();
    loadLastLogin();  // 加载记住的登录信息
    loadLoginHistory();  // 加载最近登录历史
}

AuthService::~AuthService()
{
}

// ==========================================================================
//  公开接口：login / logout
// ==========================================================================

void AuthService::login(const QString &userCode, const QString &password)
{
    qDebug() << "[Auth] 登录请求:" << userCode;

    m_pendingUserCode = userCode;
    m_pendingPassword = password;

    // admin 账号保留原有特殊处理流程：直接走离线登录（不经过在线流程）
    if (userCode.toLower() == "admin") {
        qDebug() << "[Auth] admin 账号，走离线验证（特殊处理流程）";
        tryOfflineLogin(userCode, password);
        return;
    }

    // 其他账号仅尝试在线登录；服务端请求失败时直接报错，不再降级到离线模式
    tryOnlineLogin(userCode, password);
}

void AuthService::logout()
{
    qDebug() << "[Auth] 用户退出登录:" << m_currentUser;
    m_currentUser.clear();
    m_token.clear();
    m_refreshToken.clear();
    m_tokenExpiresAt = QDateTime();
    m_userId = -1;
    m_role.clear();
    m_isOnlineMode = false;
    m_custId = 0;
    m_devId = 0;
    m_avatarUrl.clear();

    // 退出时清除保存的凭据（保留记住偏好设置）
    if (!m_lastUserCode.isEmpty()) {
        clearSavedLoginData();
        Q_EMIT lastLoginChanged();
    }

    Q_EMIT currentUserChanged();
    Q_EMIT tokenChanged();
    Q_EMIT userInfoChanged();
    Q_EMIT modeChanged();
    Q_EMIT logoutCompleted();
}

void AuthService::refreshToken()
{
    // 委托到统一入口（带并发锁）
    requestTokenRefresh();
}

// ==========================================================================
//  Token 刷新协调器（无感刷新核心）
// ==========================================================================

void AuthService::requestTokenRefresh()
{
    // === 并发锁：防止多个调用方同时触发多次刷新请求 ===
    if (m_isRefreshing) {
        qDebug() << "[Auth] Token 刷新已在进行中，跳过重复请求"
                 << "(failCount=" << m_refreshFailCount << ")";
        return;
    }

    // 防御：空或纯空白字符串都不允许发请求
    if (m_refreshToken.trimmed().isEmpty()) {
        qWarning() << "[Auth] 刷新 Token 失败: RefreshToken 为空或纯空白"
                   << "len=" << m_refreshToken.length();
        Q_EMIT tokenRefreshFailed("未登录或无刷新令牌");
        Q_EMIT tokenRefreshCompleted(false, "未登录或无刷新令牌");
        return;
    }

    m_isRefreshing = true;
    qDebug() << "[Auth] Token 刷新开始 (failCount=" << m_refreshFailCount << ")";
    tryRefreshToken();
}

bool AuthService::isRefreshingToken() const
{
    return m_isRefreshing;
}

bool AuthService::isUnauthorizedError(QNetworkReply *reply)
{
    if (!reply) return false;
    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    // HTTP 401 = Unauthorized（Token 过期或无效）
    // 也兼容服务端返回 403 Forbidden（部分后端用 403 表示 Token 无效）
    return (statusCode == 401 || statusCode == 403)
           && reply->error() != QNetworkReply::NoError;
}

// ==========================================================================
//  在线登录
// ==========================================================================

void AuthService::tryOnlineLogin(const QString &userCode, const QString &password)
{
    QNetworkRequest request = createApiRequest(NetworkUtils::Api::LOGIN);

    // 构造请求体: { UserCode, Password, Sn, Role, Dev }
    QJsonObject bodyObj;
    bodyObj["UserCode"] = userCode;
    bodyObj["Password"] = password;
    bodyObj["Sn"]       = m_deviceSn;  // 设备序列号（由 WeightSensor 注入）
    bodyObj["Role"]     = 2;      // 角色类型
    bodyObj["Dev"]      = 4;      // 设备类型
    bodyObj["zone"]     = "Asia/Shanghai";     // 区域

    QJsonDocument bodyDoc(bodyObj);
    QByteArray bodyData = bodyDoc.toJson(QJsonDocument::Compact);

    // 打印请求体
    qInfo() << "[HTTP] Body:" << bodyData;

    // 记录请求开始时间
    QElapsedTimer timer;
    timer.start();

    // 将用户名附加到 reply 上，供回调中使用
    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_pendingUserCode", userCode);
    reply->setProperty("_startTime", QVariant::fromValue(timer));
}

void AuthService::tryRefreshToken()
{
    // 二次防御：即使 refreshToken() 放行，也确保不会发出空 token 请求
    if (m_refreshToken.trimmed().isEmpty()) {
        qWarning() << "[Auth] tryRefreshToken 拦截: m_refreshToken 为空/纯空白"
                   << "len=" << m_refreshToken.length();
        Q_EMIT tokenRefreshFailed("未登录或无刷新令牌");
        return;
    }

    QNetworkRequest request = createApiRequest(NetworkUtils::Api::REFRESH_TOKEN);

    // 后端 [FromBody] string refreshToken 期望的是 JSON 字符串值（带引号），
    // 而非 JSON 对象 {"refreshToken": "..."}
    QByteArray bodyData = "\"" + m_refreshToken.toUtf8() + "\"";

    // 完整诊断日志：与登录请求保持一致，便于定位后端 "refreshToken field is required"
    qDebug() << "[Auth] 刷新 Token 请求:"
             << "m_refreshToken.len=" << m_refreshToken.length()
             << "prefix=" << (m_refreshToken.length() > 20
                              ? m_refreshToken.left(20) + "..."
                              : m_refreshToken);
    qInfo() << "[HTTP] Body:" << bodyData;

    // 记录请求开始时间
    QElapsedTimer timer;
    timer.start();

    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_isRefreshToken", true);
    reply->setProperty("_startTime", QVariant::fromValue(timer));
}

void AuthService::tryFetchProductBySn()
{
    // 在线模式且 token 有效时才调用，离线模式跳过
    if (!m_isOnlineMode || m_token.isEmpty()) {
        qDebug() << "[Auth] 跳过 Product/by-sn 请求: 非在线模式或无 token";
        return;
    }

    QNetworkRequest request = createApiRequest(NetworkUtils::Api::PRODUCT_BY_SN, m_token);

    // 后端 [FromBody] string sn 期望 JSON 字符串值（带引号），与 refresh-token 接口同模式
    QByteArray bodyData = "\"" + m_deviceSn.toUtf8() + "\"";

    qInfo() << "[Auth] 请求 Product/by-sn, sn=" << m_deviceSn;
    qInfo() << "[HTTP] Body:" << bodyData;

    QElapsedTimer timer;
    timer.start();

    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_isProductBySn", true);
    reply->setProperty("_startTime", QVariant::fromValue(timer));
}

void AuthService::tryFetchUserInfo()
{
    // 在线模式且 token 有效时才调用
    if (!m_isOnlineMode || m_token.isEmpty()) {
        qDebug() << "[Auth] 跳过 User/by-id 请求: 非在线模式或无 token";
        return;
    }

    QNetworkRequest request = createApiRequest(NetworkUtils::Api::USER_BY_ID, m_token);

    // 后端 [FromBody] string 期望 JSON 字符串值（带引号），与 refresh-token 同模式
    QByteArray bodyData = "\"" + QString::number(m_userId).toUtf8() + "\"";

    qInfo() << "[Auth] 请求 User/by-id 获取用户信息（含头像）, userId=" << m_userId;
    qInfo() << "[HTTP] Body:" << bodyData;

    QElapsedTimer timer;
    timer.start();

    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_isUserInfo", true);
    reply->setProperty("_startTime", QVariant::fromValue(timer));
}

// ==========================================================================
//  网络回调处理
// ==========================================================================

void AuthService::onNetworkReply(QNetworkReply *reply)
{
    bool isRefresh    = reply->property("_isRefreshToken").isValid()
                        && reply->property("_isRefreshToken").toBool();
    bool isLogin      = reply->property("_pendingUserCode").isValid();
    bool isProductBySn = reply->property("_isProductBySn").isValid()
                        && reply->property("_isProductBySn").toBool();
    bool isUserInfo   = reply->property("_isUserInfo").isValid()
                        && reply->property("_isUserInfo").toBool();

    if (!isRefresh && !isLogin && !isProductBySn && !isUserInfo) {
        reply->deleteLater();
        return;
    }

    reply->deleteLater();

    // --- 打印请求耗时 ---
    if (reply->property("_startTime").isValid()) {
        QElapsedTimer timer = reply->property("_startTime").value<QElapsedTimer>();
        qInfo() << "[HTTP] 请求耗时:" << timer.elapsed() << "ms";
    }

    // --- Product/by-sn 分支：解析 productId 并缓存，失败不影响登录态 ---
    if (isProductBySn) {
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[Auth] Product/by-sn 网络错误:" << reply->errorString();
            // 失败也继续串行链
            tryFetchUserInfo();
            return;
        }
        QByteArray data = reply->readAll();
        qDebug() << "[Auth] Product/by-sn 响应:" << data;

        QJsonParseError parseErr;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);
        if (parseErr.error != QJsonParseError::NoError) {
            qWarning() << "[Auth] Product/by-sn JSON 解析失败:" << parseErr.errorString();
            tryFetchUserInfo();
            return;
        }

        QJsonObject root = doc.object();
        // 后端标准包装: { success, data: { productId, ... } }；兼容直接返回产品对象
        QJsonObject dataObj = root.value("data").toObject();
        QJsonObject src     = dataObj.isEmpty() ? root : dataObj;

        // productId 可能是字符串或数字
        QJsonValue pidVal = src.value("productId");
        QString productId;
        if (pidVal.isString()) {
            productId = pidVal.toString();
        } else if (pidVal.isDouble()) {
            productId = QString::number(pidVal.toInt());
        }

        if (productId.isEmpty()) {
            qWarning() << "[Auth] Product/by-sn 响应中未找到 productId, keys=" << src.keys();
            tryFetchUserInfo();
            return;
        }

        m_productId = productId;
        saveProductToCache();
        Q_EMIT productIdChanged();
        qInfo() << "[Auth] Product/by-sn 成功: productId=" << m_productId << "（已缓存）";
        // 串行链：Product/by-sn 完成 → 触发 User/by-id
        tryFetchUserInfo();
        return;
    }

    // --- User/by-id 分支：解析用户信息（头像等），失败不影响登录态 ---
    if (isUserInfo) {
        QString userNm = m_currentUser;  // 昵称兜底为登录用户名
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[Auth] User/by-id 网络错误:" << reply->errorString();
        } else {
            QByteArray data = reply->readAll();
            qDebug() << "[Auth] User/by-id 响应:" << data;

            QJsonParseError parseErr;
            QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);
            if (parseErr.error != QJsonParseError::NoError) {
                qWarning() << "[Auth] User/by-id JSON 解析失败:" << parseErr.errorString();
            } else {
                QJsonObject root = doc.object();
                QJsonObject dataObj = root.value("data").toObject();
                QJsonObject src     = dataObj.isEmpty() ? root : dataObj;

                QString avatar = src.value("img").toString();
                if (!avatar.isEmpty() && avatar != m_avatarUrl) {
                    m_avatarUrl = avatar;
                    Q_EMIT avatarChanged();
                    qInfo() << "[Auth] User/by-id 成功: avatarUrl=" << m_avatarUrl.left(80) + "...";
                } else {
                    qDebug() << "[Auth] User/by-id 返回但 avatar 为空或未变化";
                }

                QString custNm = src.value("custNm").toString();
                if (!custNm.isEmpty() && custNm != m_custNm) {
                    m_custNm = custNm;
                    Q_EMIT custNmChanged();
                    qInfo() << "[Auth] User/by-id 成功: custNm=" << m_custNm;
                } else {
                    qDebug() << "[Auth] User/by-id 返回但 custNm 为空或未变化";
                }

                // 昵称优先取后端 userNm 字段，缺省回退到登录用户名
                QString backendUserNm = src.value("userNm").toString();
                if (!backendUserNm.isEmpty()) {
                    userNm = backendUserNm;
                }
            }
        }

        // 记录最近登录历史（在线登录成功后，三元组齐全或尽力填充；不存密码）
        addLoginHistory(m_pendingUserCode, userNm, m_custNm);

        // 串行链：User/by-id 完成 → 触发食材列表拉取
        if (m_ingredientSvc) {
            m_ingredientSvc->fetchIngredients();
        }
        return;
    }

    // --- 检查网络错误 ---
    // 设计原则：服务端请求失败（网络层或业务层）时直接中断流程并返回错误，
    // 不再降级到离线模式。仅 admin 账号经由 login() 中的特殊处理流程走离线登录。
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[Auth] 网络错误:" << reply->errorString();
        if (isRefresh) {
            m_refreshFailCount++;
            m_isRefreshing = false;
            QString errMsg = QStringLiteral("网络连接失败 (连续%1次)").arg(m_refreshFailCount);
            Q_EMIT tokenRefreshFailed(errMsg);
            Q_EMIT tokenRefreshCompleted(false, errMsg);
            qDebug() << "[Auth] Token 刷新失败, 连续失败次数:" << m_refreshFailCount
                     << "/" << kMaxRefreshFailures;
        } else {
            // 在线登录网络请求失败：直接报错，不再降级到离线
            // 注意：reply->errorString()（含 URL/SSL/HTTP 等技术细节）已通过上面 qWarning 记入日志，
            // 此处只向 QML 推送友好提示，避免用户在登录弹窗看到"Error transferring <URL> - server replied: ..."。
            qWarning() << "[Auth] 在线登录网络请求失败，直接返回错误";
            Q_EMIT loginFailed(QStringLiteral("网络连接失败，请检查网络后重试"));
        }
        return;
    }

    // --- 解析响应 JSON（登录 / 刷新共用） ---
    QByteArray data = reply->readAll();

    qDebug() << "[Auth] 响应数据:" << data;

    QString newToken, newRefreshToken, userName, errMsg;
    QDateTime expiresAt;
    qint64 userId = -1;

    if (parseAuthResponse(data, newToken, newRefreshToken, expiresAt,
                          userId, userName, errMsg)) {
        // 刷新时用户名沿用当前用户；登录时使用服务端返回的
        QString finalUser = isRefresh ? m_currentUser : userName;
        // 在线登录成功必然为在线模式（online=true）；
        // 刷新时沿用当前 m_isOnlineMode（仅在线登录会持有可刷新的 token）。
        // 注意：PRODUCT_BY_SN 的触发条件逻辑（handleAuthSuccess 内 if(online) 守卫
        // 及 tryFetchProductBySn 内部防御检查）保持现状，此处仅修正 online 参数传值，
        // 修复原 m_isOnlineMode 在登录前恒为 false 导致在线登录被误判为 OFFLINE 的 Bug。
        const bool online = isRefresh ? m_isOnlineMode : true;
        handleAuthSuccess(finalUser, userId,
                          newToken, newRefreshToken,
                          expiresAt, m_role, online,
                          !isRefresh); // Token 刷新不触发 loginSuccess/拉取产品
        if (isRefresh) {
            // 刷新成功：解锁、重置失败计数、通知所有等待方
            m_refreshFailCount = 0;
            m_isRefreshing = false;
            Q_EMIT tokenRefreshed(newToken);
            Q_EMIT tokenRefreshCompleted(true, QString());
            qDebug() << "[Auth] Token 刷新成功, 新Token长度=" << newToken.length();
        }
    } else {
        if (isRefresh) {
            m_refreshFailCount++;
            m_isRefreshing = false;
            qWarning() << "[Auth] Token 刷新业务失败:" << errMsg
                       << "连续失败次数:" << m_refreshFailCount << "/" << kMaxRefreshFailures;
            Q_EMIT tokenRefreshFailed(errMsg);
            Q_EMIT tokenRefreshCompleted(false, errMsg);
        } else {
            // 在线认证业务失败（服务端返回 success=false）：直接报错，不再降级到离线
            qWarning() << "[Auth] 在线认证业务失败，直接返回错误:" << errMsg;
            Q_EMIT loginFailed(errMsg);
        }
    }
}

// ==========================================================================
//  离线降级
// ==========================================================================

void AuthService::setUserRepo(UserRepo *repo)
{
    m_userRepo = repo;
}

void AuthService::setIngredientService(UserIngredientService *svc)
{
    m_ingredientSvc = svc;
}

void AuthService::setDeviceSn(const QString &sn)
{
    if (m_deviceSn == sn) return;
    m_deviceSn = sn;
    Q_EMIT deviceSnChanged();
    qDebug() << "[Auth] 设备 SN 更新:" << (sn.isEmpty() ? "<empty>" : sn);
}

void AuthService::tryOfflineLogin(const QString &userCode, const QString &password)
{
    if (!m_userRepo) {
        qWarning() << "[Auth] 离线登录失败: UserRepo 未注入";
        Q_EMIT loginFailed("网络连接失败，且无本地用户数据");
        return;
    }

    qDebug() << "[Auth] 尝试离线登录:" << userCode;

    // 查询本地用户
    User user = m_userRepo->findByUsername(userCode);
    if (user.id <= 0) {
        Q_EMIT loginFailed("用户不存在");
        return;
    }

    if (!m_userRepo->verifyPassword(userCode, password)) {
        Q_EMIT loginFailed("密码错误");
        return;
    }

    if (!user.isActive) {
        Q_EMIT loginFailed("账号已被禁用");
        return;
    }

    // 离线登录成功（无 Token）
    handleAuthSuccess(user.displayName.isEmpty() ? userCode : user.displayName,
                      user.id,
                      QString(),   // 无 token
                      QString(),   // 无 refreshToken
                      QDateTime(), // 无过期时间
                      "offline",
                      false);      // isOnlineMode = false

    qDebug() << "[Auth] 离线登录成功:" << userCode;
}

// ==========================================================================
//  网络请求辅助
// ==========================================================================

QNetworkRequest AuthService::createApiRequest(const QString &apiPath,
                                               const QString &token) const
{
    return NetworkUtils::createApiRequest(NetworkUtils::API_BASE_URL, apiPath, token);
}

bool AuthService::parseAuthResponse(const QByteArray &data,
                                     QString &outToken,
                                     QString &outRefreshToken,
                                     QDateTime &outExpiresAt,
                                     qint64 &outUserId,
                                     QString &outUserName,
                                     QString &outErrMsg)
{
    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);

    if (parseErr.error != QJsonParseError::NoError) {
        outErrMsg = "服务器响应格式异常";
        qWarning() << "[Auth] JSON 解析失败:" << parseErr.errorString();
        return false;
    }

    QJsonObject root = doc.object();
    bool success = root.value("success").toBool(false);

    if (!success) {
        QString msg = root.value("message").toString();
        outErrMsg = msg.isEmpty() ? "操作失败" : msg;
        qWarning() << "[Auth] 操作失败:" << outErrMsg;
        return false;
    }

    QJsonObject userData = root.value("data").toObject();
    outToken       = userData.value("accessToken").toString();
    outRefreshToken= userData.value("refreshToken").toString();
    // 诊断：检测后端是否返回 refreshToken 字段（原因 A: 字段缺失/大小写不一致）
    if (outRefreshToken.isEmpty()) {
        qWarning() << "[Auth] 后端返回的 refreshToken 为空!"
                   << "data keys=" << userData.keys()
                   << "是否含 refreshToken 字段="
                   << userData.contains("refreshToken")
                   << "是否含 RefreshToken 字段="
                   << userData.contains("RefreshToken");
    } else {
        qDebug() << "[Auth] 解析到 refreshToken: len=" << outRefreshToken.length();
    }
    outUserName    = userData.value("userName").toString();
    QJsonValue uidVal = userData.value("userId");
    outUserId = uidVal.isString() ? uidVal.toString().toLongLong() : uidVal.toVariant().toLongLong();
    QString expiresAtStr = userData.value("accessTokenExpiration").toString();
    qDebug() << "[Auth] data keys:" << userData.keys();

    // 解析 USER 域字段
    QJsonValue custVal = userData.value("custId");
    m_custId = custVal.isString() ? custVal.toString().toLongLong() : custVal.toVariant().toLongLong();
    m_devId  = userData.value("devId").toVariant().toLongLong();
    qDebug() << "[Auth] custId raw value:" << custVal << "type:" << custVal.type() << "parsed:" << m_custId;

    // UTC → 本地时间
    outExpiresAt = QDateTime::fromString(expiresAtStr, Qt::ISODate);
    if (outExpiresAt.isValid()) {
        outExpiresAt = outExpiresAt.toLocalTime();
    }

    qDebug() << "[Auth] 认证响应解析成功: user=" << outUserName
             << "userId=" << outUserId
             << "expiresAt=" << outExpiresAt.toString(Qt::ISODate);
    return true;
}

// ==========================================================================
//  统一处理登录/刷新成功
// ==========================================================================

void AuthService::handleAuthSuccess(const QString &username,
                                    qint64 userId,
                                    const QString &token,
                                    const QString &refreshToken,
                                    const QDateTime &expiresAt,
                                    const QString &role,
                                    bool online,
                                    bool isInitialLogin)
{
    m_currentUser     = username;
    m_token           = token;
    m_refreshToken    = refreshToken;
    m_tokenExpiresAt  = expiresAt;
    m_userId          = userId;
    m_role            = role;
    m_isOnlineMode    = online;

    qDebug() << "[Auth] 认证成功:"
             << "user=" << username
             << "mode=" << (online ? "ONLINE" : "OFFLINE")
             << "role=" << role
             << "expiresAt=" << expiresAt.toString(Qt::ISODate);

    Q_EMIT currentUserChanged();
    Q_EMIT tokenChanged();
    Q_EMIT userInfoChanged();
    Q_EMIT modeChanged();

    // 首次登录成功时，如果用户选择了"记住登录"则保存凭据
    if (isInitialLogin && m_rememberLogin) {
        saveLastLogin();
        Q_EMIT lastLoginChanged();
    }

    // 仅在首次登录时 emit loginSuccess 并拉取产品/食材；
    // Token 刷新跳过，避免上传过程中触发多余网络请求
    if (isInitialLogin) {
        Q_EMIT loginSuccess();
        if (online) {
            // 串行调度：Product/by-sn → User/by-id → UserIngr/paged
            // 避免并发导致 by-id 偶尔无返回
            tryFetchProductBySn();
        }
    }
}

// ==========================================================================
//  Token 预检方法
// ==========================================================================

bool AuthService::isTokenExpiringSoon(int thresholdSeconds) const
{
    if (!m_tokenExpiresAt.isValid() || m_token.isEmpty()) {
        return true;  // 无过期时间或无 Token，视为需刷新
    }
    return QDateTime::currentDateTime().secsTo(m_tokenExpiresAt) < thresholdSeconds;
}

bool AuthService::isTokenValid() const
{
    if (m_token.isEmpty()) return false;
    if (!m_tokenExpiresAt.isValid()) return true;  // 有 Token 但无过期信息，视为有效
    return QDateTime::currentDateTime() < m_tokenExpiresAt;
}

// ==========================================================================
//  productId 本地缓存读写
//  路径: ~/.cache/smartscale/product.json
// ==========================================================================

void AuthService::loadProductFromCache()
{
    QString path = QDir::homePath() + "/.cache/smartscale/product.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qInfo() << "[Auth] 无本地 productId 缓存，等待登录后从 API 拉取";
        return;
    }

    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseErr);
    file.close();

    if (parseErr.error != QJsonParseError::NoError) {
        qWarning() << "[Auth] productId 缓存 JSON 解析失败:" << parseErr.errorString();
        return;
    }

    QString pid = doc.object().value("productId").toString();
    if (!pid.isEmpty()) {
        m_productId = pid;
        qInfo() << "[Auth] 从缓存加载 productId=" << m_productId;
    }
}

void AuthService::saveProductToCache() const
{
    if (m_productId.isEmpty()) return;

    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    QString path = dir + "/product.json";

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[Auth] 写入 productId 缓存失败:" << file.errorString();
        return;
    }

    QJsonObject obj;
    obj["productId"] = m_productId;
    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    file.close();
    qDebug() << "[Auth] productId 已写入缓存:" << path;
}

// ==========================================================================
//  记住登录功能
//  存储: ~/.config/SmartScale/last_login.conf
// ==========================================================================

static const QString kLastLoginPath = QDir::homePath() + "/.config/SmartScale/last_login.conf";

void AuthService::loadLastLogin()
{
    QSettings settings(kLastLoginPath, QSettings::IniFormat);
    m_rememberLogin = settings.value("remember", false).toBool();
    m_lastUserCode  = settings.value("userCode").toString();
    m_lastPassword  = settings.value("password").toString();  // 简单 base64 编码存储

    if (m_rememberLogin && !m_lastUserCode.isEmpty()) {
        qInfo() << "[Auth] 加载记住登录: user=" << m_lastUserCode;
    }
}

void AuthService::saveLastLogin()
{
    if (!m_rememberLogin) return;

    QString dir = QDir::homePath() + "/.config/SmartScale";
    QDir().mkpath(dir);

    QSettings settings(kLastLoginPath, QSettings::IniFormat);
    settings.setValue("remember", true);
    settings.setValue("userCode", m_pendingUserCode);
    settings.setValue("password", m_pendingPassword.toUtf8().toBase64());
    settings.sync();

    m_lastUserCode = m_pendingUserCode;
    m_lastPassword = m_pendingPassword;
    qInfo() << "[Auth] 记住登录已保存:" << m_lastUserCode;
}

void AuthService::clearSavedLoginData()
{
    QFile::remove(kLastLoginPath);
    m_lastUserCode.clear();
    m_lastPassword.clear();
    qInfo() << "[Auth] 清除记住的登录信息";
}

void AuthService::setRememberLogin(bool remember)
{
    if (m_rememberLogin == remember) return;
    m_rememberLogin = remember;
    Q_EMIT rememberLoginChanged();
}

bool AuthService::hasSavedLogin() const
{
    return m_rememberLogin && !m_lastUserCode.isEmpty() && !m_lastPassword.isEmpty();
}

void AuthService::autoLogin()
{
    if (!hasSavedLogin()) {
        qWarning() << "[Auth] 自动登录失败: 无保存的登录信息";
        Q_EMIT loginFailed("无保存的登录信息");
        return;
    }

    // 解码密码
    QByteArray decoded = QByteArray::fromBase64(m_lastPassword.toUtf8());
    QString password = QString::fromUtf8(decoded);

    qInfo() << "[Auth] 使用记住的账号自动登录:" << m_lastUserCode;
    login(m_lastUserCode, password);
}

void AuthService::clearSavedLogin()
{
    clearSavedLoginData();
    setRememberLogin(false);
    Q_EMIT lastLoginChanged();
}

// ==========================================================================
//  最近登录历史
//  存储: ~/.cache/smartscale/login_history.json（含记住的密码 base64，最多 10 条）
// ==========================================================================

void AuthService::loadLoginHistory()
{
    QString path = QDir::homePath() + "/.cache/smartscale/login_history.json";
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        return;
    }

    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &parseErr);
    file.close();

    if (parseErr.error != QJsonParseError::NoError) {
        qWarning() << "[Auth] login_history 缓存 JSON 解析失败:" << parseErr.errorString();
        return;
    }

    QJsonArray arr = doc.array();
    m_loginHistory.clear();
    for (const QJsonValue &v : arr) {
        m_loginHistory.append(v.toObject().toVariantMap());
    }
    qInfo() << "[Auth] 加载最近登录历史:" << m_loginHistory.size() << "条";
}

void AuthService::saveLoginHistory() const
{
    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    QString path = dir + "/login_history.json";

    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[Auth] 写入 login_history 缓存失败:" << file.errorString();
        return;
    }

    QJsonArray arr;
    for (const QVariant &e : m_loginHistory) {
        arr.append(QJsonObject::fromVariantMap(e.toMap()));
    }
    file.write(QJsonDocument(arr).toJson(QJsonDocument::Compact));
    file.close();
    qDebug() << "[Auth] login_history 已写入缓存:" << path;
}

void AuthService::addLoginHistory(const QString &userCode,
                                  const QString &userNm,
                                  const QString &custNm)
{
    if (userCode.trimmed().isEmpty()) return;

    // 去重：移除同 userCode 的旧记录
    for (int i = m_loginHistory.size() - 1; i >= 0; --i) {
        QVariantMap e = m_loginHistory.at(i).toMap();
        if (e.value("userCode").toString() == userCode) {
            m_loginHistory.removeAt(i);
        }
    }

    QVariantMap entry;
    entry["userCode"] = userCode;
    entry["userNm"]   = userNm.isEmpty() ? userCode : userNm;
    entry["custNm"]   = custNm;
    entry["lastTime"] = QDateTime::currentSecsSinceEpoch();
    // 注意：password 不在此处写入，由 rememberHistoryPassword 在快捷登录成功后单独保存
    m_loginHistory.prepend(entry);

    // 截断到最多 10 条
    while (m_loginHistory.size() > 10) {
        m_loginHistory.removeLast();
    }

    saveLoginHistory();
    Q_EMIT loginHistoryChanged();
    qInfo() << "[Auth] 新增最近登录历史:" << userCode
            << "当前共" << m_loginHistory.size() << "条";
}

void AuthService::removeLoginHistory(int index)
{
    if (index < 0 || index >= m_loginHistory.size()) return;
    m_loginHistory.removeAt(index);
    saveLoginHistory();
    Q_EMIT loginHistoryChanged();
}

void AuthService::clearLoginHistory()
{
    if (m_loginHistory.isEmpty()) return;
    m_loginHistory.clear();
    saveLoginHistory();
    Q_EMIT loginHistoryChanged();
}

bool AuthService::hasRememberedPassword(const QString &userCode) const
{
    // 优先：历史记录中该账号是否存有密码（快捷登录选中即登录的基础）
    for (const QVariant &e : m_loginHistory) {
        QVariantMap m = e.toMap();
        if (m.value("userCode").toString() == userCode
                && !m.value("password").toString().isEmpty()) {
            return true;
        }
    }
    // 回退：记住登录的单账号密码（兼容旧行为）
    return m_rememberLogin && !m_lastUserCode.isEmpty()
           && m_lastUserCode == userCode && !m_lastPassword.isEmpty();
}

void AuthService::loginByHistory(int index)
{
    if (index < 0 || index >= m_loginHistory.size()) {
        qWarning() << "[Auth] 历史一键登录失败: 索引越界" << index;
        Q_EMIT loginFailed("历史记录不存在");
        return;
    }

    QVariantMap entry = m_loginHistory.at(index).toMap();
    QString userCode = entry.value("userCode").toString();

    // 优先用历史记录中保存的密码，缺省回退记住登录的单账号密码
    QString pwdB64 = entry.value("password").toString();
    if (pwdB64.isEmpty() && m_rememberLogin && m_lastUserCode == userCode) {
        pwdB64 = m_lastPassword;
    }
    if (pwdB64.isEmpty()) {
        qWarning() << "[Auth] 历史一键登录失败: 该账号未记住密码" << userCode;
        Q_EMIT loginFailed("该账号未记住密码");
        return;
    }

    // 解码保存的密码
    QByteArray decoded = QByteArray::fromBase64(pwdB64.toUtf8());
    QString password = QString::fromUtf8(decoded);

    qInfo() << "[Auth] 通过历史记录一键登录:" << userCode;
    login(userCode, password);
}

void AuthService::rememberHistoryPassword(const QString &userCode, const QString &password)
{
    if (userCode.trimmed().isEmpty() || password.isEmpty()) return;
    for (int i = 0; i < m_loginHistory.size(); ++i) {
        QVariantMap e = m_loginHistory.at(i).toMap();
        if (e.value("userCode").toString() == userCode) {
            e["password"] = password.toUtf8().toBase64();
            m_loginHistory.replace(i, e);
            saveLoginHistory();
            Q_EMIT loginHistoryChanged();
            qInfo() << "[Auth] 已记住快捷登录密码:" << userCode;
            return;
        }
    }
    qWarning() << "[Auth] 未找到对应历史账号，无法记住密码:" << userCode;
}

int AuthService::firstRememberedHistoryIndex() const
{
    for (int i = 0; i < m_loginHistory.size(); ++i) {
        QVariantMap e = m_loginHistory.at(i).toMap();
        if (!e.value("password").toString().isEmpty()) {
            return i;
        }
    }
    return -1;
}
