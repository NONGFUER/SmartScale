#include "AuthService.h"
#include "core/NetworkUtils.h"
#include "data/repositories/UserRepo.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkRequest>
#include <QDebug>
#include <QElapsedTimer>

// ==========================================================================
//  构造 / 析构
// ==========================================================================

AuthService::AuthService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
    connect(m_networkMgr, &QNetworkAccessManager::finished,
            this, &AuthService::onNetworkReply);
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

    // admin 账号优先使用离线登录，隐患
    if (userCode.toLower() == "admin") {
        qDebug() << "[Auth] admin 账号，优先走离线验证";
        tryOfflineLogin(userCode, password);
        return;
    }

    // 其他账号先尝试在线，失败后自动降级
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

    Q_EMIT currentUserChanged();
    Q_EMIT tokenChanged();
    Q_EMIT userInfoChanged();
    Q_EMIT modeChanged();
    Q_EMIT logoutCompleted();
}

void AuthService::refreshToken()
{
    if (m_refreshToken.isEmpty()) {
        qWarning() << "[Auth] 刷新 Token 失败: 当前无 RefreshToken";
        Q_EMIT tokenRefreshFailed("未登录或无刷新令牌");
        return;
    }
    tryRefreshToken();
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
    bodyObj["Sn"]       = "";     // 设备序列号
    bodyObj["Role"]     = 2;      // 角色类型
    bodyObj["Dev"]      = 4;      // 设备类型

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
    QNetworkRequest request = createApiRequest(NetworkUtils::Api::REFRESH_TOKEN);

    // Body 为 RefreshToken（JSON 字符串）
    QJsonObject bodyObj;
    bodyObj["refreshToken"] = m_refreshToken;
    QJsonDocument bodyDoc(bodyObj);
    QByteArray bodyData = bodyDoc.toJson(QJsonDocument::Compact);

    qDebug() << "[Auth] 刷新 Token 请求...";

    // 记录请求开始时间
    QElapsedTimer timer;
    timer.start();

    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_isRefreshToken", true);
    reply->setProperty("_startTime", QVariant::fromValue(timer));
}

// ==========================================================================
//  网络回调处理
// ==========================================================================

void AuthService::onNetworkReply(QNetworkReply *reply)
{
    bool isRefresh = reply->property("_isRefreshToken").isValid()
                     && reply->property("_isRefreshToken").toBool();
    bool isLogin   = reply->property("_pendingUserCode").isValid();

    if (!isRefresh && !isLogin) {
        reply->deleteLater();
        return;
    }

    reply->deleteLater();

    // --- 检查网络错误 ---
    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[Auth] 网络错误:" << reply->errorString();
        if (isRefresh) {
            Q_EMIT tokenRefreshFailed("网络连接失败");
        } else {
            // 在线失败，尝试离线降级
            qDebug() << "[Auth] 在线不可用，降级到离线登录";
            tryOfflineLogin(m_pendingUserCode, m_pendingPassword);
        }
        return;
    }

    // --- 解析响应 JSON（登录 / 刷新共用） ---
    QByteArray data = reply->readAll();

    // 打印请求耗时
    if (reply->property("_startTime").isValid()) {
        QElapsedTimer timer = reply->property("_startTime").value<QElapsedTimer>();
        qInfo() << "[HTTP] 请求耗时:" << timer.elapsed() << "ms";
    }

    qDebug() << "[Auth] 响应数据:" << data;

    QString newToken, newRefreshToken, userName, errMsg;
    QDateTime expiresAt;
    int userId = -1;

    if (parseAuthResponse(data, newToken, newRefreshToken, expiresAt,
                          userId, userName, errMsg)) {
        // 刷新时用户名沿用当前用户；登录时使用服务端返回的
        QString finalUser = isRefresh ? m_currentUser : userName;
        handleAuthSuccess(finalUser, userId,
                          newToken, newRefreshToken,
                          expiresAt, m_role, m_isOnlineMode);
        if (isRefresh) {
            Q_EMIT tokenRefreshed(newToken);
        }
    } else {
        if (isRefresh) {
            Q_EMIT tokenRefreshFailed(errMsg);
        } else {
            // 在线认证失败（服务器返回错误），降级到离线
            qDebug() << "[Auth] 在线认证失败，降级到离线登录:" << errMsg;
            tryOfflineLogin(m_pendingUserCode, m_pendingPassword);
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
                                     int &outUserId,
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
    outUserName    = userData.value("userName").toString();
    outUserId      = userData.value("userId").toInt(-1);
    QString expiresAtStr = userData.value("accessTokenExpiration").toString();

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
                                    int userId,
                                    const QString &token,
                                    const QString &refreshToken,
                                    const QDateTime &expiresAt,
                                    const QString &role,
                                    bool online)
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
    Q_EMIT loginSuccess();
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
