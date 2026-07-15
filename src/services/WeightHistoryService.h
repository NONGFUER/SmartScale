#ifndef WEIGHTHISTORYSERVICE_H
#define WEIGHTHISTORYSERVICE_H

#include <QObject>
#include <QVariantList>
#include <QDate>

// 前向声明
class WeightRecordRepo;
class AuthService;
class UserIngredientService;
class QNetworkAccessManager;
class QNetworkReply;

#include "data/models/WeightRecord.h"
#include <QQueue>

class WeightHistoryService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList historyEntries READ historyEntries NOTIFY historyChanged)
    Q_PROPERTY(int todayCount READ todayCount NOTIFY statsChanged)
    Q_PROPERTY(double todayWeight READ todayWeight NOTIFY statsChanged)
    Q_PROPERTY(double totalWeight READ totalWeight NOTIFY statsChanged)

public:
    explicit WeightHistoryService(WeightRecordRepo *repo,
                                  QObject *parent = nullptr);

    QVariantList historyEntries() const;
    int todayCount() const;
    int totalCount() const;
    double todayWeight() const;
    double totalWeight() const;

    /**
     * @brief 新增称重记录 (写入 SQLite + 更新内存)
     */
    Q_INVOKABLE void addRecord(double weight,
                               const QString &categoryName,
                               const QString &operatorName = QString(),
                               const QString &mainImagePath = QString(),
                               const QString &subImagePath = QString(),
                               const QString &ingrId = QString(),
                               bool aiDetected = false,
                               double unitPrice = 0.0);

    /** @brief 删除记录 (按列表索引) */
    Q_INVOKABLE void removeRecord(int index);

    /** @brief 从数据库重新加载全部记录 */
    Q_INVOKABLE void reload();

    // === 云同步（手动触发）===
    /** @brief 注入 AuthService，用于获取 token 和 userId */
    Q_INVOKABLE void setAuthService(AuthService *authSvc);

    /** @brief 同步单条记录到云端 (index=-1 同步所有未同步记录) */
    Q_INVOKABLE void syncToCloud(int index = -1);

    /** @brief 同步所有未同步记录到云端 */
    Q_INVOKABLE void syncAllToCloud();

    // === USER 域接口 ===
    /** @brief 注入 UserIngredientService（用于获取 ingrId） */
    Q_INVOKABLE void setUserIngredientService(UserIngredientService *svc);

    /** @brief 创建用户域称重记录 (POST /api/user/WeightRecord/create) */
    Q_INVOKABLE void createUserWeightRecord(const QString &ingrCd,
                                             double weightKg,
                                             bool aiDetected);

    /** @brief 撤回称重记录 (软删除 + POST /api/user/WeightRecord/revoke) */
    Q_INVOKABLE void revokeRecord(int recordId, qint64 custId, const QString &cloudRecordId);

    // === 云端分页查询 ===
    /**
     * @brief 分页查询云端称重记录 (POST /api/user/WeightRecord/paged)
     * @param page     页码（从 1 开始）
     * @param pageSize 每页条数
     * @param keyword  关键字（按食材名称/单号过滤，空=不过滤）
     * @param dateS    起始时间（ISO 8601，空=不限制）
     * @param dateE    结束时间（ISO 8601，空=不限制）
     *
     * 结果通过 pagedRecordsReady 信号返回。custId/devId/userId 自动从 AuthService 取。
     */
    Q_INVOKABLE void fetchPagedRecords(int page, int pageSize,
                                       const QString &keyword = QString(),
                                       const QString &dateS = QString(),
                                       const QString &dateE = QString());

    // === 重复称重检测 ===
    /**
     * @brief 检测重复称重记录（相同食材 + 重量相近）
     * @param categoryName 食材名称
     * @param weight 重量(kg)
     * @param tolerance 重量容差(kg)，默认 0.05kg
     * @return QVariantMap: { "duplicate": bool, "categoryName": QString, "weight": double, "recordTime": QString }
     */
    Q_INVOKABLE QVariantMap checkDuplicate(const QString &categoryName, double weight, double tolerance = 0.05);

Q_SIGNALS:
    void historyChanged();
    void statsChanged();
    void cloudSyncSuccess(int localId);
    void cloudSyncFailed(int localId, const QString &errorMsg);
    void cloudSyncProgress(int done, int total);
    void userRecordCreated(bool success, const QString &msg);
    void recordRevoked(bool success, const QString &errorMsg);  // 撤回结果通知
    void pagedRecordsReady(bool success, int total,
                           const QVariantList &items,
                           const QString &errorMsg);  // 分页查询结果

private Q_SLOTS:
    void onCloudReply(QNetworkReply *reply);
    void onTokenReadyForUpload();  // Token 刷新完成后，重发待上传记录

private:
    void refreshFromDb();
    void recalcStats();
    QByteArray buildUploadJson(const WeightRecord &record);
    void uploadSingleRecord(const WeightRecord &record);
    void updateRecordImage(qint64 custId, const QString &recordId, const QString &imagePath);

    WeightRecordRepo *m_repo;
    QVariantList m_historyEntries;
    int m_todayCount;
    int m_totalCount;
    double m_todayWeight;
    double m_totalWeight;

    // 云同步相关
    AuthService *m_authService = nullptr;
    UserIngredientService *m_ingredientSvc = nullptr;
    QNetworkAccessManager *m_networkMgr = nullptr;
    int m_syncTotal = 0;      // 当前批次总待同步数
    int m_syncDone = 0;       // 当前批次已完成数

    // Token 预检相关
    QQueue<WeightRecord> m_pendingUploadQueue;  // 等待 Token 刷新后上传的记录
    bool m_refreshingToken = false;                  // 是否正在刷新 Token

    // 分页查询 Token 刷新重试缓存
    struct PagedParams {
        int page = 1;
        int pageSize = 10;
        QString keyword;
        QString dateS;
        QString dateE;
    };
    PagedParams m_pendingPagedParams;  // 401 重试时缓存的请求参数
};

#endif // WEIGHTHISTORYSERVICE_H
