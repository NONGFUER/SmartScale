#include "WeightHistoryService.h"
#include "data/repositories/WeightRecordRepo.h"
#include "data/models/WeightRecord.h"
#include "services/AuthService.h"
#include "services/UserIngredientService.h"
#include "core/NetworkUtils.h"

#include <QDateTime>
#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkRequest>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUuid>
#include <QHttpMultiPart>
#include <QHttpPart>
#include <QFile>
#include <QFileInfo>
#include <QUrlQuery>
#include <QSslSocket>

WeightHistoryService::WeightHistoryService(WeightRecordRepo *repo, QObject *parent)
    : QObject(parent)
    , m_repo(repo)
    , m_todayCount(0)
    , m_totalCount(0)
    , m_todayWeight(0.0)
    , m_totalWeight(0.0)
{
    m_networkMgr = new QNetworkAccessManager(this);
    connect(m_networkMgr, &QNetworkAccessManager::finished,
            this, &WeightHistoryService::onCloudReply);

    refreshFromDb();
}

void WeightHistoryService::refreshFromDb()
{
    m_historyEntries.clear();

    if (!m_repo) {
        qWarning() << "[WHS] Repository 未设置，无法加载数据";
        return;
    }

    QList<WeightRecord> records = m_repo->queryAll();
    for (const auto &r : records) {
        m_historyEntries.append(r.toMap());
    }

    recalcStats();
    qDebug() << "[WHS] 从数据库加载了" << m_historyEntries.size() << "条记录";
}

void WeightHistoryService::recalcStats()
{
    QDate today = QDate::currentDate();
    m_todayCount = 0;
    m_totalCount = m_historyEntries.size();
    m_todayWeight = 0.0;
    m_totalWeight = 0.0;

    for (const auto &entry : std::as_const(m_historyEntries)) {
        QVariantMap map = entry.toMap();
        double w = map.value("weight", 0.0).toDouble();
        m_totalWeight += w;

        // 判断是否是今天的记录
        QString timeStr = map.value("recordTime").toString();
        QDate recordDate = QDateTime::fromString(timeStr, "yyyy-MM-dd HH:mm:ss").date();
        if (recordDate.isNull()) {
            recordDate = QDateTime::fromString(timeStr, Qt::ISODate).date();
        }
        if (recordDate == today) {
            m_todayCount++;
            m_todayWeight += w;
        }
    }
}

QVariantList WeightHistoryService::historyEntries() const
{
    return m_historyEntries;
}

int WeightHistoryService::todayCount() const { return m_todayCount; }
int WeightHistoryService::totalCount() const { return m_totalCount; }
double WeightHistoryService::todayWeight() const { return m_todayWeight; }
double WeightHistoryService::totalWeight() const { return m_totalWeight; }

void WeightHistoryService::addRecord(double weight,
                                     const QString &categoryName,
                                     const QString &operatorName,
                                     const QString &mainImagePath,
                                     const QString &subImagePath,
                                     const QString &ingrId,
                                     bool aiDetected,
                                     double unitPrice)
{
    if (!m_repo) {
        qWarning() << "[WHS] Repository 未设置，无法添加记录";
        return;
    }

    // 构建模型对象
    WeightRecord model(weight, categoryName, operatorName,
                       QString(), mainImagePath, subImagePath);
    model.ingrId = ingrId;
    model.aiDetected = aiDetected;
    model.unitPrice = unitPrice;
    // 金额基于舍入后两位小数的 weight 和 price 计算，避免传感器原始精度影响
    double wRounded = qRound(weight * 100.0) / 100.0;
    double pRounded = qRound(unitPrice * 100.0) / 100.0;
    model.amount = qRound(wRounded * pRounded * 100.0) / 100.0;

    // 1. 写入数据库
    int newId = m_repo->insert(model);
    if (newId <= 0) {
        qCritical() << "[WHS] 插入数据库失败";
        return;
    }
    model.id = newId;

    // 2. 插入内存缓存顶部 (最新记录在前)
    m_historyEntries.prepend(model.toMap());

    // 3. 更新统计
    m_totalCount++;
    m_todayCount++;
    m_totalWeight += weight;
    m_todayWeight += weight;

    qDebug() << "[WHS] 记录已添加:" << categoryName << weight << "kg id=" << newId;

    // 4. 上传云端
    uploadSingleRecord(model);

    Q_EMIT historyChanged();
    Q_EMIT statsChanged();
}

void WeightHistoryService::removeRecord(int index)
{
    if (index < 0 || index >= m_historyEntries.size()) return;

    QVariantMap map = m_historyEntries.at(index).toMap();
    int dbId = map.value("id", -1).toInt();
    double removedWeight = map.value("weight", 0.0).toDouble();

    // 1. 从数据库删除
    if (m_repo && dbId > 0) {
        if (!m_repo->remove(dbId)) {
            qCritical() << "[WHS] 删除数据库记录失败, id=" << dbId;
            return;  // DB 操作失败则不更新内存，保持一致
        }
    }

    // 2. 从内存移除
    m_historyEntries.removeAt(index);
    m_totalCount--;

    // 简化处理: 被删的记录默认从今日统计扣除 (精确场景可从日期判断)
    if (m_todayCount > 0) m_todayCount--;
    m_todayWeight = qMax(0.0, m_todayWeight - removedWeight);
    m_totalWeight = qMax(0.0, m_totalWeight - removedWeight);

    qDebug() << "[WHS] 记录已删除, index=" << index << "dbId=" << dbId;

    Q_EMIT historyChanged();
    Q_EMIT statsChanged();
}

void WeightHistoryService::reload()
{
    refreshFromDb();
    Q_EMIT historyChanged();
    Q_EMIT statsChanged();
}

// ============================================================
// 云同步（手动触发）
// ============================================================

void WeightHistoryService::setAuthService(AuthService *authSvc)
{
    m_authService = authSvc;
    if (m_authService) {
        // 旧信号：保持向后兼容（内部仍用 onTokenReadyForUpload 重发队列）
        connect(m_authService, &AuthService::tokenRefreshed,
                this, &WeightHistoryService::onTokenReadyForUpload, Qt::UniqueConnection);
        connect(m_authService, &AuthService::tokenRefreshFailed,
                this, [this](const QString &errMsg) {
            qWarning() << "[WHS] Token 刷新失败，待上传队列丢弃:" << errMsg;
            while (!m_pendingUploadQueue.isEmpty()) {
                WeightRecord r = m_pendingUploadQueue.dequeue();
                Q_EMIT cloudSyncFailed(r.id, "Token 刷新失败: " + errMsg);
            }
            m_refreshingToken = false;
        }, Qt::UniqueConnection);

        // 新统一信号：刷新完成后（成功或失败），重发所有排队请求
        connect(m_authService, &AuthService::tokenRefreshCompleted,
                this, [this](bool success, const QString &errMsg) {
            if (success) {
                qDebug() << "[WHS] 统一刷新完成，开始重发待上传记录"
                         << m_pendingUploadQueue.size() << "条";
                while (!m_pendingUploadQueue.isEmpty()) {
                    WeightRecord r = m_pendingUploadQueue.dequeue();
                    uploadSingleRecord(r);
                }
            } else {
                qWarning() << "[WHS] 统一刷新失败，丢弃" 
                           << m_pendingUploadQueue.size() << "条待上传记录";
                while (!m_pendingUploadQueue.isEmpty()) {
                    WeightRecord r = m_pendingUploadQueue.dequeue();
                    Q_EMIT cloudSyncFailed(r.id, "Token 刷新失败: " + errMsg);
                }
            }
            m_refreshingToken = false;
        }, Qt::UniqueConnection);
    }
}

QByteArray WeightHistoryService::buildUploadJson(const WeightRecord &record)
{
    QJsonObject json;
    // ingrId 为雪花 ID（64-bit），用 toLongLong 避免 int(32-bit) 溢出
    bool ok;
    qint64 ingrIdVal = record.ingrId.toLongLong(&ok);
    if (!ok || ingrIdVal <= 0) {
        qWarning() << "[WHS] ingrId 无效，上传将携带 ingrId=0, record.id=" << record.id
                   << "ingrId=" << record.ingrId << "food=" << record.categoryName;
    }
    json["ingrId"] = ok ? QJsonValue(qlonglong(ingrIdVal)) : 0;
    json["custId"] = m_authService ? m_authService->custId() : 0;
    json["devId"] = m_authService ? m_authService->productId() : QString();
    // 保留两位小数，用 qRound 避免浮点精度导致舍入不可控（如 0.6396→0.65）
    json["val"]    = qRound(record.weight * 100.0)   / 100.0;
    json["price"]  = qRound(record.unitPrice * 100.0)  / 100.0;
    json["amount"] = qRound(record.amount * 100.0)     / 100.0;
    json["aiDet"]  = record.aiDetected;
    //json["img"]    = record.mainImagePath;
    json["userId"] = m_authService ? QJsonValue(qlonglong(m_authService->userId())) : -1;
    json["bill"]   = static_cast<int>((qHash(QUuid::createUuid()) & 0x7FFFFFFFu) + 1);

    return QJsonDocument(json).toJson(QJsonDocument::Compact);
}

void WeightHistoryService::uploadSingleRecord(const WeightRecord &record)
{
    if (!m_networkMgr || !m_authService) {
        qWarning() << "[WHS] 网络或认证未初始化";
        Q_EMIT cloudSyncFailed(record.id, "网络或认证未初始化");
        return;
    }

    QString token = m_authService->token();
    if (token.isEmpty()) {
        qWarning() << "[WHS] 未登录，无法上传";
        Q_EMIT cloudSyncFailed(record.id, "未登录");
        return;
    }

    // === Token 预检：即将过期则先刷新，记录入队等待 ===
    if (m_authService->isTokenExpiringSoon()) {
        qDebug() << "[WHS] Token 即将过期，入队等待刷新 id=" << record.id;
        m_pendingUploadQueue.enqueue(record);

        if (!m_refreshingToken) {
            m_refreshingToken = true;
            qDebug() << "[WHS] 发起 Token 刷新请求（通过协调器）...";
            m_authService->requestTokenRefresh();
        }
        return;
    }

    QNetworkRequest request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_WEIGHT_CREATE, token);

    QByteArray payload = buildUploadJson(record);

    // === 诊断打印：排查 403 Forbidden ===
    qDebug() << "[WHS-DIAG] ========== 上传诊断开始 id=" << record.id << "==========";
    qDebug() << "[WHS-DIAG] URL   :" << request.url().toString();
    qDebug() << "[WHS-DIAG] Token长度:" << token.length()
             << " 前10字符:" << (token.length() > 10 ? token.left(10) : token)
             << " 后6字符:" << (token.length() > 6 ? token.right(6) : token);
    qDebug() << "[WHS-DIAG] Auth头:" << request.rawHeader("Authorization");
    qDebug() << "[WHS-DIAG] ContentType:" << request.rawHeader("Content-Type");
    qDebug() << "[WHS-DIAG] Payload:" << payload;
    qDebug() << "[WHS-DIAG] Token是否即将过期:" << m_authService->isTokenExpiringSoon();
    qDebug() << "[WHS-DIAG] ==========================================";
    // === 诊断结束 ===

    qDebug() << "[WHS] 请求体 id=" << record.id << "payload:" << payload;

    // 将 localId 存入 reply 的 property，以便回调中识别
    QNetworkReply *reply = m_networkMgr->post(request, payload);
    reply->setProperty("localId", record.id);

    qDebug() << "[WHS] 正在上传记录 id=" << record.id
             << "weight=" << record.weight << "food=" << record.categoryName;
}

void WeightHistoryService::syncToCloud(int index)
{
    QList<WeightRecord> records;

    if (index >= 0) {
        // 同步指定索引的记录（需要先从内存取到 dbId）
        if (index < m_historyEntries.size()) {
            QVariantMap map = m_historyEntries.at(index).toMap();
            int dbId = map.value("id", -1).toInt();
            if (dbId > 0 && m_repo) {
                WeightRecord r = m_repo->findById(dbId);
                if (r.id > 0) records.append(r);
            }
        }
    } else {
        // 同步所有未同步记录
        if (m_repo) records = m_repo->queryUnsynced();
    }

    if (records.isEmpty()) {
        qDebug() << "[WHS] 没有需要同步的记录";
        return;
    }

    m_syncTotal = records.size();
    m_syncDone = 0;

    qDebug() << "[WHS] 开始同步" << m_syncTotal << "条记录到云端";

    for (const auto &r : records) {
        uploadSingleRecord(r);
    }

    Q_EMIT cloudSyncProgress(0, m_syncTotal);
}

void WeightHistoryService::syncAllToCloud()
{
    syncToCloud(-1);
}

// ============================================================
//  撤回称重记录（软删除 + 云端 API 调用）
// ============================================================

void WeightHistoryService::revokeRecord(int recordId, qint64 custId, const QString &cloudRecordId)
{
    qDebug() << "[WHS] 撤回记录请求: localId=" << recordId
             << "custId=" << custId << "cloudId=" << cloudRecordId;

    // 1. 先本地软删除（立即生效，无论网络是否成功）
    if (m_repo && recordId > 0) {
        m_repo->softDelete(recordId);
    }

    // 2. 刷新本地数据
    refreshFromDb();
    Q_EMIT historyChanged();
    recalcStats();
    Q_EMIT statsChanged();

    // 3. 如果有云端 ID 且在线模式，调用远程撤回 API
    if (m_authService && !m_authService->token().isEmpty()
        && custId > 0 && !cloudRecordId.isEmpty()) {
        QString token = m_authService->token();
        QNetworkRequest request = NetworkUtils::createUserApiRequest(
            NetworkUtils::Api::USER_WEIGHT_REVOKE, token);

        // Body: { "pam1": custId, "pam2": cloudRecordId }
        QJsonObject bodyObj;
        bodyObj["pam1"] = custId;
        bodyObj["pam2"] = cloudRecordId;
        QByteArray bodyData = QJsonDocument(bodyObj).toJson(QJsonDocument::Compact);

        qInfo() << "[WHS] 发送撤回请求到云端:" << bodyData;

        QNetworkReply *reply = m_networkMgr->post(request, bodyData);
        reply->setProperty("_isRevoke", true);
        reply->setProperty("_localRecordId", recordId);
    } else {
        // 离线或无云端 ID：仅本地撤回完成
        qDebug() << "[WHS] 仅本地撤回完成（离线模式或无云端ID）";
        Q_EMIT recordRevoked(true, QString());
    }
}

// ============================================================
//  云端分页查询称重记录 (POST /api/user/WeightRecord/paged)
// ============================================================

void WeightHistoryService::fetchPagedRecords(int page, int pageSize,
                                             const QString &keyword,
                                             const QString &dateS,
                                             const QString &dateE)
{
    if (!m_authService || m_authService->token().isEmpty()) {
        qWarning() << "[WHS] 分页查询失败：未登录或无 Token";
        Q_EMIT pagedRecordsReady(false, 0, {}, QStringLiteral("未登录，请先登录"));
        return;
    }

    // 缓存参数供 401 重试使用
    m_pendingPagedParams.page = page;
    m_pendingPagedParams.pageSize = pageSize;
    m_pendingPagedParams.keyword = keyword;
    m_pendingPagedParams.dateS = dateS;
    m_pendingPagedParams.dateE = dateE;

    QString token = m_authService->token();
    QNetworkRequest request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_WEIGHT_PAGED, token);

    // 构造请求体 — custId/devId/userId 从 AuthService 取（雪花 ID 用 qint64）
    QJsonObject bodyObj;
    bodyObj["page"] = page;
    bodyObj["pageSize"] = pageSize;
    bodyObj["keyword"] = keyword;
    bodyObj["custId"] = m_authService ? QJsonValue(qlonglong(m_authService->custId())) : QJsonValue(qlonglong(0));
    bodyObj["userId"] = m_authService ? QJsonValue(qlonglong(m_authService->userId())) : QJsonValue(qlonglong(0));
    bodyObj["devId"] = m_authService ? QJsonValue(qlonglong(m_authService->devId())) : QJsonValue(qlonglong(0));
    bodyObj["ingrId"] = QJsonValue(qlonglong(0));  // 0 = 不按食材过滤
    bodyObj["del"] = QStringLiteral("All");
    bodyObj["dateS"] = dateS;
    bodyObj["dateE"] = dateE;

    QByteArray bodyData = QJsonDocument(bodyObj).toJson(QJsonDocument::Compact);
    qInfo() << "[WHS] 分页查询称重记录 page=" << page << "pageSize=" << pageSize
            << "keyword=" << keyword;

    QNetworkReply *reply = m_networkMgr->post(request, bodyData);
    reply->setProperty("_isPaged", true);
}

void WeightHistoryService::onCloudReply(QNetworkReply *reply)
{
    // === 处理分页查询回复 ===
    if (reply->property("_isPaged").isValid() && reply->property("_isPaged").toBool()) {
        if (reply->error() != QNetworkReply::NoError) {
            // 401/403 自动刷新重试
            if (AuthService::isUnauthorizedError(reply) && m_authService) {
                qDebug() << "[WHS] 分页查询收到 401，触发 Token 刷新并重试";
                if (!m_refreshingToken && !m_authService->isRefreshingToken()) {
                    m_refreshingToken = true;
                    m_authService->requestTokenRefresh();
                }
                reply->deleteLater();
                return;
            }
            qWarning() << "[WHS] 分页查询失败:" << reply->errorString()
                       << "HTTP=" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
            Q_EMIT pagedRecordsReady(false, 0, {}, reply->errorString());
            reply->deleteLater();
            return;
        }

        QByteArray data = reply->readAll();
        QJsonParseError parseErr;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);
        if (parseErr.error != QJsonParseError::NoError) {
            qCritical() << "[WHS] 分页查询响应 JSON 解析错误:" << parseErr.errorString();
            Q_EMIT pagedRecordsReady(false, 0, {}, QStringLiteral("响应解析失败"));
            reply->deleteLater();
            return;
        }

        QJsonObject rootObj = doc.object();
        QJsonObject dataObj = rootObj.value("data").toObject();

        // total 是字符串，兼容 string/number
        int total = 0;
        QJsonValue totalVal = dataObj.value("total");
        if (totalVal.isString())
            total = totalVal.toString().toInt();
        else
            total = totalVal.toInt();

        // 解析 items 数组 — 雪花 ID 字段全部保持 QString，禁止 toInt()
        QVariantList items;
        QJsonArray itemsArr = dataObj.value("items").toArray();
        for (const QJsonValue &v : itemsArr) {
            QJsonObject obj = v.toObject();
            QVariantMap item;
            // 雪花 ID 字段：用 toVariant().toString() 兼容 string/number
            item["recoId"] = obj.value("recoId").toVariant().toString();
            item["ingrId"] = obj.value("ingrId").toVariant().toString();
            item["custId"] = obj.value("custId").toVariant().toString();
            item["devId"] = obj.value("devId").toVariant().toString();
            item["userId"] = obj.value("userId").toVariant().toString();
            // 业务字段
            item["val"] = obj.value("val").toVariant().toString();
            item["price"] = obj.value("price").toVariant().toString();
            item["amount"] = obj.value("amount").toVariant().toString();
            item["aiDet"] = obj.value("aiDet").toBool(false);
            item["img"] = obj.value("img").toVariant().toString();
            item["crdAt"] = obj.value("crdAt").toVariant().toString();
            item["del"] = obj.value("del").toBool(false);
            item["bill"] = obj.value("bill").toVariant().toString();
            item["custNm"] = obj.value("custNm").toVariant().toString();
            item["ingrNm"] = obj.value("ingrNm").toVariant().toString();
            item["userNm"] = obj.value("userNm").toVariant().toString();
            item["devNm"] = obj.value("devNm").toVariant().toString();
            items.append(item);
        }

        qInfo() << "[WHS] 分页查询成功: total=" << total << "返回条数=" << items.size();
        Q_EMIT pagedRecordsReady(true, total, items, QString());
        reply->deleteLater();
        return;
    }

    // === 处理撤回回复 ===
    if (reply->property("_isRevoke").isValid() && reply->property("_isRevoke").toBool()) {
        int localRecordId = reply->property("_localRecordId").toInt();
        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[WHS] 撤回云端请求失败:" << reply->errorString()
                       << "localId=" << localRecordId;
            Q_EMIT recordRevoked(false, reply->errorString());
        } else {
            qInfo() << "[WHS] 撤回云端成功, localId=" << localRecordId
                    << "响应:" << reply->readAll();
            Q_EMIT recordRevoked(true, QString());
        }
        reply->deleteLater();
        return;
    }

    // 只处理云同步回复（带 localId 的），跳过用户记录创建等请求
    if (!reply->property("localId").isValid()) {
        return;
    }

    int localId = reply->property("localId").toInt();

    if (reply->error() != QNetworkReply::NoError) {
        QByteArray errData = reply->readAll();
        QString errMsg = reply->errorString();

        // === 401/403 自动刷新重试 ===
        if (AuthService::isUnauthorizedError(reply) && m_authService) {
            qDebug() << "[WHS] 收到 401/401 未授权，触发 Token 刷新并重试 id=" << localId;
            // 重新构造原始记录用于重试
            if (m_repo) {
                WeightRecord retryRec = m_repo->findById(localId);
                if (retryRec.id > 0) {
                    m_pendingUploadQueue.enqueue(retryRec);
                }
            }
            if (!m_refreshingToken && !m_authService->isRefreshingToken()) {
                m_refreshingToken = true;
                m_authService->requestTokenRefresh();
            }
            reply->deleteLater();
            return;
        }

        // === 诊断打印：其他错误详情 ===
        qCritical() << "[WHS-DIAG-ERR] ========== 上传失败诊断 id=" << localId << "==========";
        qCritical() << "[WHS-DIAG-ERR] HTTP状态码:" << reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        qCritical() << "[WHS-DIAG-ERR] 错误枚举:" << reply->error() << errMsg;
        qCritical() << "[WHS-DIAG-ERR] 响应Body:" << errData;
        // 打印所有响应头
        for (const auto &h : reply->rawHeaderList()) {
            qCritical() << "[WHS-DIAG-ERR] RespHeader:" << h << "=" << reply->rawHeader(h);
        }
        qCritical() << "[WHS-DIAG-ERR] ==========================================";
        // === 诊断结束 ===

        Q_EMIT cloudSyncFailed(localId, errMsg);
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    QJsonParseError parseErr;
    QJsonDocument doc = QJsonDocument::fromJson(data, &parseErr);

    if (parseErr.error != QJsonParseError::NoError) {
        qCritical() << "[WHS] 响应JSON解析错误 id=" << localId << parseErr.errorString();
        Q_EMIT cloudSyncFailed(localId, "响应解析失败");
        reply->deleteLater();
        return;
    }

    qDebug() << "[WHS] 上传成功 id=" << localId
             << "response:" << qUtf8Printable(doc.toJson(QJsonDocument::Indented));

    // 更新数据库：标记为已同步，保存云端记录 ID
    if (m_repo) {
        WeightRecord model = m_repo->findById(localId);
        if (model.id > 0) {
            model.synced = true;

            // 解析服务器返回的 recordId 和 custId（用于后续图片上传）
            QJsonValue dataVal = doc.object().value("data");
            qDebug() << "[WHS] 服务器返回 data:" << dataVal;

            qint64 custId = 0;
            QString remoteRecoId;  // 雪花 ID，全程保持 QString

            if (dataVal.isObject()) {
                QJsonObject dataObj = dataVal.toObject();
                qDebug() << "[WHS] data keys:" << dataObj.keys();

                // recoId 是雪花 ID（17位），保持 QString，禁止转 int
                QJsonValue r = dataObj.value("recoId");
                if (r.isString()) {
                    remoteRecoId = r.toString();
                } else {
                    remoteRecoId = r.toVariant().toString();
                }
                qDebug() << "[WHS] 解析 recoId 原始值:" << r << "→ 转换后:" << remoteRecoId;

                // custId 是雪花 ID（17位），用 toLongLong 避免 int 溢出
                QJsonValue c = dataObj.value("custId");
                custId = c.isString() ? c.toString().toLongLong() : c.toVariant().toLongLong();

                // fallback: custId 为空时尝试 userId
                if (custId <= 0) {
                    QJsonValue u = dataObj.value("userId");
                    qint64 uid = u.isString() ? u.toString().toLongLong() : u.toVariant().toLongLong();
                    if (uid > 0) {
                        qDebug() << "[WHS] custId为空，fallback到userId=" << uid;
                        custId = uid;
                    }
                }
            } else if (dataVal.isDouble()) {
                remoteRecoId = dataVal.toVariant().toString();
            }

            if (!remoteRecoId.isEmpty()) {
                model.cloudId = remoteRecoId;
            }

            m_repo->update(model);

            // 同步更新内存缓存（QML 直接读取此数据）
            for (int i = 0; i < m_historyEntries.size(); ++i) {
                QVariantMap entry = m_historyEntries.at(i).toMap();
                if (entry.value("id").toInt() == localId) {
                    if (!remoteRecoId.isEmpty()) {
                        entry["cloudId"] = remoteRecoId;
                    }
                    entry["synced"] = true;
                    m_historyEntries[i] = entry;
                    break;
                }
            }
            Q_EMIT historyChanged();

            qDebug() << "[WHS] 记录 id=" << localId << "已标记为已同步, remoteRecoId=" << remoteRecoId << "custId=" << custId;

            // 如果有图片，上传到服务器
            qDebug() << "[WHS] 图片上传条件检查:"
                     << "remoteRecoId=" << remoteRecoId
                     << "custId=" << custId
                     << "mainImagePath=" << model.mainImagePath
                     << "mainImagePath.isEmpty=" << model.mainImagePath.isEmpty()
                     << "exists=" << QFileInfo::exists(model.mainImagePath);
            if (!remoteRecoId.isEmpty() && custId > 0
                && !model.mainImagePath.isEmpty()
                && QFileInfo::exists(model.mainImagePath)) {
                updateRecordImage(custId, remoteRecoId, model.mainImagePath);
            } else {
                qWarning() << "[WHS] 跳过图片上传，条件不满足";
            }
        }
    }

    m_syncDone++;
    Q_EMIT cloudSyncSuccess(localId);
    Q_EMIT cloudSyncProgress(m_syncDone, m_syncTotal);

    reply->deleteLater();
}

void WeightHistoryService::onTokenReadyForUpload()
{
    m_refreshingToken = false;

    // 重发待上传记录
    if (!m_pendingUploadQueue.isEmpty()) {
        qDebug() << "[WHS] Token 刷新成功，开始重发" << m_pendingUploadQueue.size() << "条待上传记录";
        while (!m_pendingUploadQueue.isEmpty()) {
            WeightRecord r = m_pendingUploadQueue.dequeue();
            uploadSingleRecord(r);
        }
    }

    // 重发待重试的分页查询（如果有缓存的有效参数）
    if (m_pendingPagedParams.pageSize > 0) {
        qDebug() << "[WHS] Token 刷新成功，重发分页查询 page=" << m_pendingPagedParams.page;
        fetchPagedRecords(m_pendingPagedParams.page,
                          m_pendingPagedParams.pageSize,
                          m_pendingPagedParams.keyword,
                          m_pendingPagedParams.dateS,
                          m_pendingPagedParams.dateE);
        m_pendingPagedParams = {};  // 清空缓存
    }

    if (m_pendingUploadQueue.isEmpty() && m_pendingPagedParams.pageSize == 0) {
        qDebug() << "[WHS] Token 刷新完成，无待处理请求";
    }
}

// ============================================================
// USER 域接口
// ============================================================

void WeightHistoryService::setUserIngredientService(UserIngredientService *svc)
{
    m_ingredientSvc = svc;
}

void WeightHistoryService::createUserWeightRecord(const QString &ingrCd,
                                                    double weightKg,
                                                    bool aiDetected)
{
    if (!m_networkMgr || !m_authService || !m_ingredientSvc) {
        qWarning() << "[WHS] 依赖服务未初始化";
        Q_EMIT userRecordCreated(false, "依赖服务未初始化");
        return;
    }

    QString token = m_authService->token();
    if (token.isEmpty()) {
        Q_EMIT userRecordCreated(false, "未登录");
        return;
    }

    QJsonObject json;
    // ingrId 为雪花 ID（64-bit），用 toLongLong 避免 int 溢出
    bool ok;
    qint64 ingrIdVal = m_ingredientSvc->getIngrId(ingrCd).toLongLong(&ok);
    json["ingrId"] = ok ? QJsonValue(qlonglong(ingrIdVal)) : 0;
    json["custId"] = m_authService->custId();
    json["devId"] = m_authService->productId();
    json["val"]    = static_cast<int>(weightKg * 1000);
    json["aiDet"]  = aiDetected;
    json["img"]    = QString();
    json["userId"] = QJsonValue(qlonglong(m_authService->userId()));
    json["bill"]   = static_cast<int>((qHash(QUuid::createUuid()) & 0x7FFFFFFFu) + 1);

    QByteArray payload = QJsonDocument(json).toJson(QJsonDocument::Compact);

    auto request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_WEIGHT_CREATE, token);

    qInfo() << "[WHS] 创建用户记录, payload:" << payload;

    QNetworkReply *reply = m_networkMgr->post(request, payload);

    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            qCritical() << "[WHS] 用户记录创建失败:" << reply->errorString();
            Q_EMIT userRecordCreated(false, reply->errorString());
            return;
        }

        QByteArray respData = reply->readAll();
        qInfo() << "[WHS] 用户记录创建成功, response:" << respData;
        Q_EMIT userRecordCreated(true, "成功");
    });
}

// ============================================================
// 图片上传 (multipart/form-data)
// POST /api/user/WeightRecord/update-img
// Body: CustId(int64) + RecoId(int64) + File(binary) 均为 form-data 字段
// ============================================================

// ============================================================
//  重复称重检测
// ============================================================

QVariantMap WeightHistoryService::checkDuplicate(const QString &categoryName, double weight, double tolerance)
{
    QVariantMap result;
    result["duplicate"] = false;
    result["categoryName"] = QString();
    result["weight"] = 0.0;
    result["recordTime"] = QString();

    if (categoryName.isEmpty() || weight <= 0 || m_historyEntries.isEmpty()) {
        return result;
    }

    // 只与最近一条记录（索引 0，最新保存的）比较，不跨记录全局查找
    QVariantMap lastEntry = m_historyEntries.first().toMap();
    if (lastEntry.value("categoryName").toString() != categoryName) {
        return result;  // 前一条是不同食材，不判重
    }

    // 前一条是同食材，判定重量是否在容差范围内
    double existingWeight = lastEntry.value("weight", 0.0).toDouble();
    if (qAbs(existingWeight - weight) <= tolerance) {
        result["duplicate"] = true;
        result["categoryName"] = categoryName;
        result["weight"] = existingWeight;
        result["recordTime"] = lastEntry.value("recordTime").toString();
        qDebug() << "[WHS] 检测到重复称重:" << categoryName
                 << "重量:" << weight << "vs" << existingWeight
                 << "时间:" << result["recordTime"].toString();
    }

    return result;
}

void WeightHistoryService::updateRecordImage(qint64 custId, const QString &recordId, const QString &imagePath)
{
    if (!m_networkMgr || !m_authService) return;

    QString token = m_authService->token();
    if (token.isEmpty()) return;

    // 注意: CustId 和 RecoId 是 form-data body 字段（非 URL query）,
    // 与 Swagger 定义一致: CustId($int64), RecoId($int64), File($binary)
    QUrl url(QString("%1%2").arg(NetworkUtils::USER_BASE_URL,
                                  NetworkUtils::Api::USER_WEIGHT_UPDATE_IMG));

    QNetworkRequest request(url);
    request.setRawHeader("Authorization", QByteArray("Bearer ") + token.toUtf8());
    QSslConfiguration sslConf = request.sslConfiguration();
    sslConf.setPeerVerifyMode(QSslSocket::VerifyNone);
    request.setSslConfiguration(sslConf);
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    QFile *file = new QFile(imagePath);
    if (!file->open(QIODevice::ReadOnly)) {
        qWarning() << "[WHS] 无法打开图片:" << imagePath;
        delete file;
        return;
    }

    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    // CustId: form-data 文本字段 ($int64)
    QHttpPart custIdPart;
    custIdPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                         QVariant("form-data; name=\"CustId\""));
    custIdPart.setBody(QString::number(custId).toUtf8());
    multiPart->append(custIdPart);

    // RecoId: form-data 文本字段 ($int64), 雪花 ID
    QHttpPart recoIdPart;
    recoIdPart.setHeader(QNetworkRequest::ContentDispositionHeader,
                         QVariant("form-data; name=\"RecoId\""));
    recoIdPart.setBody(recordId.toUtf8());
    multiPart->append(recoIdPart);

    // File: form-data 二进制字段 ($binary)
    QHttpPart imagePart;
    imagePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                        QVariant("form-data; name=\"File\"; filename=\"record.jpg\""));
    imagePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant("image/jpeg"));
    imagePart.setBodyDevice(file);
    file->setParent(multiPart);
    multiPart->append(imagePart);

    QNetworkReply *reply = m_networkMgr->post(request, multiPart);
    multiPart->setParent(reply);

    qDebug() << "[WHS-IMG-DIAG] ========== 图片上传诊断开始 ==========";
    qDebug() << "[WHS-IMG-DIAG] URL     :" << request.url().toString();
    qDebug() << "[WHS-IMG-DIAG] CustId  :" << custId;
    qDebug() << "[WHS-IMG-DIAG] RecoId  :" << recordId;
    qDebug() << "[WHS-IMG-DIAG] Token长度:" << token.length()
             << " 前10字符:" << (token.length() > 10 ? token.left(10) : token)
             << " 后6字符:" << (token.length() > 6 ? token.right(6) : token);
    qDebug() << "[WHS-IMG-DIAG] Auth头  :" << request.rawHeader("Authorization");
    qDebug() << "[WHS-IMG-DIAG] 文件路径:" << imagePath;
    qDebug() << "[WHS-IMG-DIAG] 文件大小:" << file->size() << "bytes";
    qDebug() << "[WHS-IMG-DIAG] Token即将过期:" << m_authService->isTokenExpiringSoon();
    qDebug() << "[WHS-IMG-DIAG] ======================================";

    connect(reply, &QNetworkReply::finished, this, [reply, recordId, custId]() {
        int httpCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QByteArray respBody = reply->readAll();

        if (reply->error() != QNetworkReply::NoError) {
            qCritical() << "[WHS-IMG-DIAG-ERR] ========== 图片上传失败诊断 ==========";
            qCritical() << "[WHS-IMG-DIAG-ERR] RecoId     :" << recordId;
            qCritical() << "[WHS-IMG-DIAG-ERR] HTTP状态码 :" << httpCode;
            qCritical() << "[WHS-IMG-DIAG-ERR] 错误枚举   :" << reply->error() << reply->errorString();
            qCritical() << "[WHS-IMG-DIAG-ERR] 响应Body   :" << respBody;
            for (const auto &h : reply->rawHeaderList()) {
                qCritical() << "[WHS-IMG-DIAG-ERR] RespHeader :" << h << "=" << reply->rawHeader(h);
            }
            qCritical() << "[WHS-IMG-DIAG-ERR] ===========================================";
        } else {
            qDebug() << "[WHS-IMG-DIAG] ========== 图片上传成功 ==========";
            qDebug() << "[WHS-IMG-DIAG] RecoId    :" << recordId;
            qDebug() << "[WHS-IMG-DIAG] HTTP状态码:" << httpCode;
            qDebug() << "[WHS-IMG-DIAG] 响应Body  :" << respBody;
            qDebug() << "[WHS-IMG-DIAG] =====================================";
        }
        reply->deleteLater();
    });
}
