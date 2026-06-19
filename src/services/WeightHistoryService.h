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
                               const QString &subImagePath = QString());

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

Q_SIGNALS:
    void historyChanged();
    void statsChanged();
    void cloudSyncSuccess(int localId);
    void cloudSyncFailed(int localId, const QString &errorMsg);
    void cloudSyncProgress(int done, int total);
    void userRecordCreated(bool success, const QString &msg);

private Q_SLOTS:
    void onCloudReply(QNetworkReply *reply);
    void onTokenReadyForUpload();  // Token 刷新完成后，重发待上传记录

private:
    void refreshFromDb();
    void recalcStats();
    QByteArray buildUploadJson(const WeightRecord &record);
    void uploadSingleRecord(const WeightRecord &record);
    void updateRecordImage(int custId, int recordId, const QString &imagePath);

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
};

#endif // WEIGHTHISTORYSERVICE_H
