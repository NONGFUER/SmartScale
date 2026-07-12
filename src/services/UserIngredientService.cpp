#include "UserIngredientService.h"
#include "AuthService.h"
#include "core/NetworkUtils.h"
#include "utils/FoodTranslator.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QDebug>
#include <QFile>
#include <QDir>
#include <QDateTime>
#include <QUuid>
#include <QCryptographicHash>
#include <QSet>
#include <QUrl>
#include <QSslConfiguration>
#include <QSslSocket>

UserIngredientService::UserIngredientService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
    connect(m_networkMgr, &QNetworkAccessManager::finished,
            this, &UserIngredientService::onNetworkReply);

    // 启动时从本地缓存加载，使选择弹窗在登录前也能渲染
    loadFromCache();
}

void UserIngredientService::setAuthService(AuthService *auth)
{
    m_authService = auth;
    // 接入统一 Token 刷新协调器：刷新完成后自动重发排队请求
    if (m_authService) {
        QObject::connect(m_authService, &AuthService::tokenRefreshCompleted,
                         this, &UserIngredientService::onTokenRefreshCompleted,
                         Qt::UniqueConnection);
    }
}

void UserIngredientService::fetchIngredients()
{
    if (m_loading) return;
    if (!m_authService || m_authService->token().isEmpty()) {
        qWarning() << "[UserIngr] 未登录，无法拉取食材列表";
        return;
    }

    // === Token 预检 ===
    if (m_authService->isTokenExpiringSoon()) {
        qDebug() << "[UserIngr] Token 即将过期，排队等待刷新后拉取";
        PendingRequest req{PendingRequestType::Fetch};
        m_pendingRequests.enqueue(req);
        if (!m_refreshing && !m_authService->isRefreshingToken()) {
            m_refreshing = true;
            m_authService->requestTokenRefresh();
        }
        return;
    }

    m_loading = true;
    Q_EMIT loadingChanged();

    auto request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_INGR_PAGED, m_authService->token());

    QJsonObject body;
    body["page"]      = 1;
    body["pageSize"]  = 10000;
    body["keyword"]   = "";
    body["custId"]    = m_authService->custId();
    body["cateId"]    = 0;
    body["enable"]    = "All";
    body["aiDet"]     = "All";
    body["changeUrl"] = true;

    QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    qInfo() << "[UserIngr] 请求食材列表, payload:" << payload;

    QNetworkReply *reply = m_networkMgr->post(request, payload);
    reply->setProperty("requestType", "userIngrFetch");
}

// ============================================================
//  创建新食材（POST /api/user/UserIngr/create）
// ============================================================
void UserIngredientService::createIngredient(const QString &ingrNm, const QString &cateId, const QString &cateNm)
{
    if (m_loading) return;
    if (!m_authService || m_authService->token().isEmpty()) {
        qWarning() << "[UserIngr] 未登录，无法创建食材";
        Q_EMIT createFailed("未登录");
        return;
    }

    // === Token 预检 ===
    if (m_authService->isTokenExpiringSoon()) {
        qDebug() << "[UserIngr] Token 即将过期，排队等待刷新后创建食材";
        PendingRequest req{PendingRequestType::Create, ingrNm, cateId, cateNm};
        m_pendingRequests.enqueue(req);
        if (!m_refreshing && !m_authService->isRefreshingToken()) {
            m_refreshing = true;
            m_authService->requestTokenRefresh();
        }
        return;
    }

    m_loading = true;
    Q_EMIT loadingChanged();

    // 生成随机编码作为 ingrCd：取 UUID 去掉连字符，截取前 12 位小写
    QString ingrCd = QUuid::createUuid().toString(QUuid::WithoutBraces).left(12).toLower();

    auto request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_INGR_CREATE, m_authService->token());

    QJsonObject body;
    body["ingrCd"] = ingrCd;
    body["ingrNm"] = ingrNm;
    body["custId"] = m_authService->custId();
    body["cateId"] = cateId;       // 后端要字符串雪花 ID
    body["cateNm"] = cateNm;
    body["enable"] = true;          // 创建后立即启用

    QByteArray payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    qInfo() << "[UserIngr] 创建食材, payload:" << payload;

    QNetworkReply *reply = m_networkMgr->post(request, payload);
    reply->setProperty("requestType", "userIngrCreate");
    reply->setProperty("pendingName", ingrNm);   // 成功回调用
}

void UserIngredientService::onNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();

    // 区分请求类型
    QString requestType = reply->property("requestType").toString();

    // 食材图片下载回复（非 JSON，独立处理）
    if (requestType == "ingrImage") {
        processImageReply(reply);
        return;
    }

    if (reply->error() != QNetworkReply::NoError) {
        m_loading = false;
        Q_EMIT loadingChanged();

        // === 401/403 自动刷新重试 ===
        if (AuthService::isUnauthorizedError(reply) && m_authService) {
            qDebug() << "[UserIngr] 收到 401/403 未授权，触发 Token 刷新并重试"
                     << "requestType=" << requestType;
            // 将当前请求类型重新入队等待重试
            PendingRequest pending{PendingRequestType::Fetch};
            if (requestType == "userIngrCreate") {
                pending.type = PendingRequestType::Create;
                pending.createName = reply->property("pendingName").toString();
            }
            m_pendingRequests.enqueue(pending);
            if (!m_refreshing && !m_authService->isRefreshingToken()) {
                m_refreshing = true;
                m_authService->requestTokenRefresh();
            }
            return;
        }

        qWarning() << "[UserIngr] 网络错误:" << reply->errorString()
                   << "requestType=" << requestType;
        if (requestType == "userIngrCreate") {
            Q_EMIT createFailed(reply->errorString());
        } else {
            Q_EMIT fetchFailed(reply->errorString());
        }
        return;
    }

    QByteArray data = reply->readAll();
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(data, &err);

    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        m_loading = false;
        Q_EMIT loadingChanged();
        qWarning() << "[UserIngr] JSON 解析失败, requestType=" << requestType;
        if (requestType == "userIngrCreate") {
            Q_EMIT createFailed("JSON 解析失败");
        } else {
            Q_EMIT fetchFailed("JSON 解析失败");
        }
        return;
    }

    QJsonObject root = doc.object();

    // ========== 创建食材回复 ==========
    if (requestType == "userIngrCreate") {
        m_loading = false;
        Q_EMIT loadingChanged();

        bool success = root.value("success").toBool(false);
        if (!success) {
            QString msg = root.value("message").toString("创建失败");
            qWarning() << "[UserIngr] 创建食材失败:" << msg;
            Q_EMIT createFailed(msg);
            return;
        }

        QJsonObject dataObj = root.value("data").toObject();
        QString ingrId   = dataObj.value("ingrId").toVariant().toString();
        QString ingrCd   = dataObj.value("ingrCd").toString().toLower();
        QString ingrNm   = dataObj.value("ingrNm").toString();
        QString newCateId  = dataObj.value("cateId").toVariant().toString();
        QString newCateNm  = dataObj.value("cateNm").toString();
        bool enableBool = dataObj.value("enable").toBool(false);
        QString enable  = enableBool ? QStringLiteral("true") : QStringLiteral("false");

        qInfo() << "[UserIngr] 创建食材成功: ingrId=" << ingrId << "ingrCd=" << ingrCd << "ingrNm=" << ingrNm;

        // 追加到本地列表（避免立即重新拉取）
        QVariantMap item;
        item["en"]     = ingrCd;
        item["cn"]     = ingrNm;
        item["id"]     = ingrId;
        item["cateId"] = newCateId;
        item["cateNm"] = newCateNm;
        item["emsId"]  = "0";
        item["emsCd"]  = "";
        item["enable"] = enable;
        m_items.append(item);

        m_ingrMap[ingrCd] = ingrId;
        m_ingrNameMap[ingrNm] = ingrId;

        rebuildCategories();
        saveToCache();
        FoodTranslator::instance()->updateFromApi(m_items);

        Q_EMIT itemsChanged();
        Q_EMIT createSuccess(ingrId, ingrNm);
        return;
    }

    // ========== 拉取食材列表回复 (userIngrFetch) ==========

    // 查找 items 数组: data.items 或 items
    QJsonArray items;
    QJsonObject dataObj = root.value("data").toObject();
    if (dataObj.contains("items")) {
        items = dataObj.value("items").toArray();
    } else if (root.contains("items")) {
        items = root.value("items").toArray();
    }

    if (items.isEmpty()) {
        m_loading = false;
        Q_EMIT loadingChanged();
        qWarning() << "[UserIngr] 返回数据为空";
        Q_EMIT fetchFailed("食材列表为空");
        return;
    }

    m_items.clear();
    m_ingrMap.clear();
    m_ingrNameMap.clear();
    m_emsMap.clear();

    for (const QJsonValue &val : items) {
        QJsonObject obj = val.toObject();
        QString ingrId = obj.value("ingrId").toVariant().toString();
        QString ingrCd = obj.value("ingrCd").toString().toLower();
        QString ingrNm = obj.value("ingrNm").toString();

        // 分类与电子秤绑定信息
        QString cateId  = obj.value("cateId").toVariant().toString();
        QString cateNm  = obj.value("cateNm").toString();
        QString emsId   = obj.value("emsId").toVariant().toString();
        QString emsCd   = obj.value("emsCd").toString().toLower();
        // enable: 后端为 boolean，统一转成 "true"/"false" 字符串便于 QML 比较
        bool enableBool = obj.value("enable").toBool(false);
        QString enable  = enableBool ? QStringLiteral("true") : QStringLiteral("false");

        // 食材图片 URL（完整地址，可能为空）
        QString imgUrl  = obj.value("img").toString().trimmed();

        QVariantMap item;
        item["en"]     = ingrCd;
        item["cn"]     = ingrNm;
        item["id"]     = ingrId;
        item["cateId"] = cateId;
        item["cateNm"] = cateNm;
        item["emsId"]  = emsId;
        item["emsCd"]  = emsCd;
        item["enable"] = enable;
        item["img"]    = imgUrl;
        item["imgLocal"] = QString();   // 本地缓存路径，下载完成后填充
        m_items.append(item);

        if (!ingrId.isEmpty() && !ingrCd.isEmpty()) {
            m_ingrMap[ingrCd] = ingrId;
        }
        if (!ingrId.isEmpty() && !ingrNm.isEmpty()) {
            m_ingrNameMap[ingrNm] = ingrId;
        }
        if (!ingrId.isEmpty() && !emsCd.isEmpty()) {
            m_emsMap[emsCd] = ingrId;
        }
    }

    rebuildCategories();

    m_loading = false;
    Q_EMIT loadingChanged();
    Q_EMIT itemsChanged();

    qInfo() << "[UserIngr] 成功加载" << m_items.size() << "个食材";

    // 写入本地缓存 (新结构: 分类 + 食材)
    saveToCache();

    // 额外保存一份接口原始响应 (未解析)
    saveRawResponse(data);

    // 下载食材图片到本地缓存（异步，完成后刷新 UI 并落盘）
    downloadIngredientImages();

    // 更新翻译器内存字典 (ingrCd/emsCd → ingrNm)，翻译器不再自行写缓存
    FoodTranslator::instance()->updateFromApi(m_items);

    Q_EMIT fetchSuccess();
}

QString UserIngredientService::getIngrId(const QString &ingrCd) const
{
    // 先按英文编码查
    QString id = m_ingrMap.value(ingrCd.toLower());
    if (!id.isEmpty()) return id;
    // 再按电子秤编码查
    id = m_emsMap.value(ingrCd.toLower());
    if (!id.isEmpty()) return id;
    // fallback: 按中文名查
    return m_ingrNameMap.value(ingrCd, QStringLiteral("0"));
}

QVariantMap UserIngredientService::findByEmsCd(const QString &emsCd) const
{
    QString key = emsCd.trimmed().toLower();
    for (const QVariant &v : m_items) {
        QVariantMap m = v.toMap();
        if (m.value("emsCd").toString().toLower() == key)
            return m;
    }
    return QVariantMap();
}

void UserIngredientService::rebuildCategories()
{
    m_categories.clear();
    // 按 cateId 分组，保持首次出现顺序
    QMap<QString, QVariantMap> catMap;       // cateId → {cateId,cateNm,items}
    QStringList order;
    for (const QVariant &v : m_items) {
        QVariantMap item = v.toMap();
        QString cateId = item.value("cateId").toString();
        if (cateId.isEmpty()) cateId = QStringLiteral("0");
        if (!catMap.contains(cateId)) {
            QVariantMap cat;
            cat["cateId"] = cateId;
            cat["cateNm"] = item.value("cateNm").toString();
            cat["items"]  = QVariantList();
            catMap.insert(cateId, cat);
            order.append(cateId);
        }
        QVariantMap cat = catMap.value(cateId);
        QVariantList itemList = cat.value("items").toList();
        itemList.append(item);
        cat["items"] = itemList;
        catMap.insert(cateId, cat);
    }
    for (const QString &cid : order)
        m_categories.append(catMap.value(cid));
}

// ============================================================
//  本地 JSON 缓存 (新结构: 分类 + 食材)
// ============================================================
QString UserIngredientService::cacheFilePath()
{
    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    return dir + "/ingredients.json";
}

QString UserIngredientService::rawCacheFilePath()
{
    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    return dir + "/ingredients_raw.json";
}

void UserIngredientService::saveRawResponse(const QByteArray &data)
{
    QString path = rawCacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[UserIngr] 无法写入原始响应缓存文件:" << path;
        return;
    }
    file.write(data);
    file.close();
    qInfo() << "[UserIngr] 原始响应已写入:" << path << "(" << data.size() << "字节)";
}

// ============================================================
//  食材图片缓存 (下载到 ~/.cache/smartscale/ingr_images/)
// ============================================================
QString UserIngredientService::imageCacheDir() const
{
    QString dir = QDir::homePath() + "/.cache/smartscale/ingr_images";
    QDir().mkpath(dir);
    return dir;
}

QString UserIngredientService::localImagePathFor(const QString &imgUrl) const
{
    QByteArray hash = QCryptographicHash::hash(imgUrl.toUtf8(),
                                              QCryptographicHash::Md5).toHex();
    QString ext = ".img";
    QString path = QUrl(imgUrl).path();
    int dot = path.lastIndexOf('.');
    if (dot >= 0) {
        QString e = path.mid(dot).toLower();
        if (e == ".jpg" || e == ".jpeg" || e == ".png" || e == ".gif"
            || e == ".webp" || e == ".bmp")
            ext = e;
    }
    return imageCacheDir() + "/" + QString::fromLatin1(hash) + ext;
}

QNetworkRequest UserIngredientService::buildImageRequest(const QString &imgUrl)
{
    QNetworkRequest request{QUrl(imgUrl)};

    // S3 预签名 URL（含 X-Amz-Signature）自带查询串认证。
    // 注意：AWS S3 规定一旦请求带有 Authorization 头，便会忽略查询串签名、
    // 改用头签名验证；而 Bearer token 不是合法的 AWS SigV4 签名，会导致 403。
    // 因此预签名 URL 绝不能附加 Bearer 头，仅对非预签名地址才携带 token。
    bool isS3Presigned = imgUrl.contains("X-Amz-Signature", Qt::CaseInsensitive)
                         || imgUrl.contains("X-Amz-Algorithm", Qt::CaseInsensitive);
    if (!isS3Presigned) {
        QString token = m_authService ? m_authService->token() : QString();
        if (!token.isEmpty())
            request.setRawHeader("Authorization", QByteArray("Bearer ") + token.toUtf8());
    }

    // 与 NetworkUtils 一致的 SSL 配置（IP+HTTPS 跳过证书验证）
    QSslConfiguration sslConf = request.sslConfiguration();
    sslConf.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConf.setProtocol(QSsl::TlsV1_2OrLater);
    request.setSslConfiguration(sslConf);
    // 强制 HTTP/1.1
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    return request;
}

void UserIngredientService::downloadIngredientImages()
{
    // 未登录（无 token）时无法携带认证头，跳过下载；下次 fetch 会重新触发
    if (!m_authService || m_authService->token().isEmpty())
        return;

    for (const QVariant &v : m_items) {
        QVariantMap m = v.toMap();
        QString imgUrl = m.value("img").toString();
        QString ingrId = m.value("id").toString();
        if (imgUrl.isEmpty() || ingrId.isEmpty())
            continue;

        // 已有本地缓存且文件仍存在则跳过
        QString local = m.value("imgLocal").toString();
        if (!local.isEmpty() && QFile::exists(local))
            continue;
        // 正在下载中则跳过，避免重复请求
        if (m_imgDownloading.contains(imgUrl))
            continue;

        cacheIngredientImage(ingrId, imgUrl);
    }
}

void UserIngredientService::cacheIngredientImage(const QString &ingrId, const QString &imgUrl)
{
    m_imgDownloading.insert(imgUrl);
    QNetworkRequest request = buildImageRequest(imgUrl);
    QNetworkReply *reply = m_networkMgr->get(request);
    reply->setProperty("requestType", "ingrImage");
    reply->setProperty("ingrId", ingrId);
    reply->setProperty("imgUrl", imgUrl);
    qDebug() << "[UserIngr] 发起食材图片下载:" << ingrId << imgUrl.left(80);
}

void UserIngredientService::processImageReply(QNetworkReply *reply)
{
    QString ingrId = reply->property("ingrId").toString();
    QString imgUrl = reply->property("imgUrl").toString();
    m_imgDownloading.remove(imgUrl);

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "[UserIngr] 图片下载失败:" << imgUrl << reply->errorString();
        return;
    }

    QByteArray imgData = reply->readAll();
    if (imgData.isEmpty()) {
        qWarning() << "[UserIngr] 图片下载为空:" << imgUrl;
        return;
    }

    QString localPath = localImagePathFor(imgUrl);
    QFile f(localPath);
    if (!f.open(QIODevice::WriteOnly)) {
        qWarning() << "[UserIngr] 图片缓存写入失败:" << localPath;
        return;
    }
    f.write(imgData);
    f.close();
    qInfo() << "[UserIngr] 食材图片已缓存:" << ingrId << "->" << localPath;

    setItemLocalImage(ingrId, localPath);
    saveToCache();   // 持久化 imgLocal，下次启动无需重新下载
}

void UserIngredientService::setItemLocalImage(const QString &ingrId, const QString &localPath)
{
    for (int i = 0; i < m_items.size(); ++i) {
        QVariantMap m = m_items[i].toMap();
        if (m.value("id").toString() == ingrId) {
            m["imgLocal"] = localPath;
            m_items[i] = m;
            break;
        }
    }
    rebuildCategories();
    Q_EMIT itemsChanged();
}

void UserIngredientService::loadFromCache()
{
    QString path = cacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qInfo() << "[UserIngr] 无本地缓存，等待登录后拉取";
        return;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        qWarning() << "[UserIngr] 缓存 JSON 格式错误，忽略";
        return;
    }

    QJsonObject root = doc.object();

    // 旧结构 (扁平字典 en→cn) 直接删除，登录后重建为新结构
    if (!root.contains("categories")) {
        qInfo() << "[UserIngr] 检测到旧格式缓存，删除后等待重新拉取:" << path;
        QFile::remove(path);
        return;
    }

    QJsonArray cats = root.value("categories").toArray();
    m_items.clear();
    m_ingrMap.clear();
    m_ingrNameMap.clear();
    m_emsMap.clear();

    for (const QJsonValue &cv : cats) {
        QJsonObject cat = cv.toObject();
        QJsonArray items = cat.value("items").toArray();
        for (const QJsonValue &iv : items) {
            QJsonObject obj = iv.toObject();
            QVariantMap item;
            item["en"]     = obj.value("ingrCd").toString().toLower();
            item["cn"]     = obj.value("ingrNm").toString();
            item["id"]     = obj.value("ingrId").toVariant().toString();
            item["cateId"] = obj.value("cateId").toVariant().toString();
            item["cateNm"] = obj.value("cateNm").toString();
            item["emsId"]  = obj.value("emsId").toVariant().toString();
            item["emsCd"]  = obj.value("emsCd").toString().toLower();
            item["enable"] = obj.value("enable").toString();
            item["img"]    = obj.value("img").toString();
            item["imgLocal"] = obj.value("imgLocal").toString();
            m_items.append(item);

            QString ingrId = item["id"].toString();
            if (!ingrId.isEmpty()) {
                if (!item["en"].toString().isEmpty())
                    m_ingrMap[item["en"].toString()] = ingrId;
                if (!item["cn"].toString().isEmpty())
                    m_ingrNameMap[item["cn"].toString()] = ingrId;
                if (!item["emsCd"].toString().isEmpty())
                    m_emsMap[item["emsCd"].toString()] = ingrId;
            }
        }
    }

    rebuildCategories();

    if (!m_items.isEmpty())
        Q_EMIT itemsChanged();

    qInfo() << "[UserIngr] 从缓存加载了" << m_items.size() << "个食材:" << path;

    // 启动时若已有 token（如已登录态恢复），补下载缺失的图片缓存
    downloadIngredientImages();
}

void UserIngredientService::saveToCache()
{
    QJsonObject root;
    root["version"] = 1;
    root["fetchedAt"] = QDateTime::currentDateTime().toString(Qt::ISODate);

    QJsonArray cats;
    for (const QVariant &cv : m_categories) {
        QVariantMap cat = cv.toMap();
        QJsonObject catObj;
        catObj["cateId"] = cat.value("cateId").toString();
        catObj["cateNm"] = cat.value("cateNm").toString();
        QJsonArray itemArr;
        for (const QVariant &iv : cat.value("items").toList()) {
            QVariantMap m = iv.toMap();
            QJsonObject itemObj;
            itemObj["ingrId"] = m.value("id").toString();
            itemObj["ingrCd"] = m.value("en").toString();
            itemObj["ingrNm"] = m.value("cn").toString();
            itemObj["cateId"] = m.value("cateId").toString();
            itemObj["cateNm"] = m.value("cateNm").toString();
            itemObj["emsId"]  = m.value("emsId").toString();
            itemObj["emsCd"]  = m.value("emsCd").toString();
            itemObj["enable"] = m.value("enable").toString();
            itemObj["img"]    = m.value("img").toString();
            itemObj["imgLocal"] = m.value("imgLocal").toString();
            itemArr.append(itemObj);
        }
        catObj["items"] = itemArr;
        cats.append(catObj);
    }
    root["categories"] = cats;

    QString path = cacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[UserIngr] 无法写入缓存文件:" << path;
        return;
    }
    file.write(QJsonDocument(root).toJson(QJsonDocument::Compact));
    file.close();

    qInfo() << "[UserIngr] 缓存已写入:" << path
            << "(" << m_items.size() << "个食材," << m_categories.size() << "个分类)";
}

// ==========================================================================
//  Token 刷新完成回调 — 重发排队请求
// ==========================================================================

void UserIngredientService::onTokenRefreshCompleted(bool success, const QString &errMsg)
{
    m_refreshing = false;

    if (!success) {
        qWarning() << "[UserIngr] Token 刷新失败，丢弃" << m_pendingRequests.size() << "条排队请求";
        while (!m_pendingRequests.isEmpty()) {
            PendingRequest req = m_pendingRequests.dequeue();
            if (req.type == PendingRequestType::Create) {
                Q_EMIT createFailed("Token 刷新失败: " + errMsg);
            } else {
                Q_EMIT fetchFailed("Token 刷新失败: " + errMsg);
            }
        }
        return;
    }

    qDebug() << "[UserIngr] Token 刷新成功，重发" << m_pendingRequests.size() << "条排队请求";

    while (!m_pendingRequests.isEmpty()) {
        PendingRequest req = m_pendingRequests.dequeue();
        if (req.type == PendingRequestType::Fetch) {
            fetchIngredients();
        } else if (req.type == PendingRequestType::Create) {
            createIngredient(req.createName, req.createCateId, req.createCateNm);
        }
    }
}
