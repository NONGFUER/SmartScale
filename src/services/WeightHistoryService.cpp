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
#include <QUuid>

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
                                     const QString &subImagePath)
{
    if (!m_repo) {
        qWarning() << "[WHS] Repository 未设置，无法添加记录";
        return;
    }

    // 构建模型对象
    WeightRecord model(weight, categoryName, operatorName,
                       QString(), mainImagePath, subImagePath);

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
        // 一次性连接：Token 刷新成功 → 重发待上传队列
        connect(m_authService, &AuthService::tokenRefreshed,
                this, &WeightHistoryService::onTokenReadyForUpload, Qt::UniqueConnection);
        // Token 刷新失败 → 清空队列并报错
        connect(m_authService, &AuthService::tokenRefreshFailed,
                this, [this](const QString &errMsg) {
            qWarning() << "[WHS] Token 刷新失败，待上传队列丢弃:" << errMsg;
            while (!m_pendingUploadQueue.isEmpty()) {
                WeightRecord r = m_pendingUploadQueue.dequeue();
                Q_EMIT cloudSyncFailed(r.id, "Token 刷新失败: " + errMsg);
            }
            m_refreshingToken = false;
        }, Qt::UniqueConnection);
    }
}

QByteArray WeightHistoryService::buildUploadJson(const WeightRecord &record)
{
    QJsonObject json;
    json["ingrId"] = m_ingredientSvc ? m_ingredientSvc->getIngrId(record.categoryName).toInt() : 0;
    json["custId"] = m_authService ? m_authService->custId() : 0;
    json["devId"]  = 2;//m_authService ? m_authService->devId() : 0;
    json["val"]    = static_cast<int>(record.weight * 1000);
    json["aiDet"]  = !record.categoryName.isEmpty();
    //json["img"]    = record.mainImagePath;
    json["userId"] = m_authService ? m_authService->userId() : -1;
    json["bill"]   = static_cast<int>(qHash(QUuid::createUuid()));

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
            qDebug() << "[WHS] 发起 Token 刷新请求...";
            m_authService->refreshToken();
        }
        return;
    }

    QNetworkRequest request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_WEIGHT_CREATE, token);

    QByteArray payload = buildUploadJson(record);

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

void WeightHistoryService::onCloudReply(QNetworkReply *reply)
{
    // 只处理云同步回复（带 localId 的），跳过用户记录创建等请求
    if (!reply->property("localId").isValid()) {
        return;
    }

    int localId = reply->property("localId").toInt();

    if (reply->error() != QNetworkReply::NoError) {
        QByteArray errData = reply->readAll();
        QString errMsg = reply->errorString();
        qCritical() << "[WHS] 上传失败 id=" << localId
                    << "error:" << errMsg
                    << "body:" << errData;
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

    // 更新数据库：标记为已同步
    if (m_repo) {
        WeightRecord model = m_repo->findById(localId);
        if (model.id > 0) {
            model.synced = true;
            m_repo->update(model);
            qDebug() << "[WHS] 记录 id=" << localId << "已标记为已同步";
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

    if (m_pendingUploadQueue.isEmpty()) {
        qDebug() << "[WHS] Token 刷新完成，无待上传记录";
        return;
    }

    qDebug() << "[WHS] Token 刷新成功，开始重发" << m_pendingUploadQueue.size() << "条待上传记录";

    while (!m_pendingUploadQueue.isEmpty()) {
        WeightRecord r = m_pendingUploadQueue.dequeue();
        uploadSingleRecord(r);
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
    json["ingrId"] = m_ingredientSvc->getIngrId(ingrCd).toInt();
    json["custId"] = m_authService->custId();
    json["devId"]  = m_authService->devId();
    json["val"]    = static_cast<int>(weightKg * 1000);
    json["aiDet"]  = aiDetected;
    json["img"]    = QString();
    json["userId"] = m_authService->userId();
    json["bill"]   = static_cast<int>(qHash(QUuid::createUuid()));

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
