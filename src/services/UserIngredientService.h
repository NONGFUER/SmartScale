#ifndef USERINGREDIENTSERVICE_H
#define USERINGREDIENTSERVICE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QMap>
#include <QQueue>

class AuthService;
class QNetworkAccessManager;
class QNetworkReply;
class QNetworkRequest;

/**
 * @brief 用户域食材服务 — 从 /api/user/UserIngr/paged 拉取食材，缓存到本地 ingredients.json
 *
 * 缓存结构 (含分类和食材):
 *   { "version":1, "categories":[ { "cateId":"1", "cateNm":"叶菜类",
 *       "items":[ {ingrId,ingrCd,ingrNm,emsId,emsCd,enable}, ... ] } ] }
 *
 * QML 用法:
 *   UserIngredientService.fetchIngredients()        // 拉取并缓存
 *   UserIngredientService.categories                 // 按分类分组，渲染选择弹窗
 *   UserIngredientService.findByEmsCd("bocai")      // AI 场景: emsCd → {ingrId,ingrNm,...}
 */
class UserIngredientService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(QVariantList categories READ categories NOTIFY itemsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    explicit UserIngredientService(QObject *parent = nullptr);

    void setAuthService(AuthService *auth);

    QVariantList items() const { return m_items; }
    QVariantList categories() const { return m_categories; }
    bool loading() const { return m_loading; }

    /** @brief 从云端拉取食材列表并写入本地缓存 */
    Q_INVOKABLE void fetchIngredients();

    /** @brief 根据 ingrCd 获取 ingrId，未找到返回 "0" (兼容旧调用) */
    Q_INVOKABLE QString getIngrId(const QString &ingrCd) const;

    /** @brief AI 场景: 按电子秤编码 emsCd 查找食材，返回 {ingrId,ingrNm,emsId,...} */
    Q_INVOKABLE QVariantMap findByEmsCd(const QString &emsCd) const;

    /** @brief 创建新食材（ingrCd 用随机编码），成功后自动刷新本地列表 */
    Q_INVOKABLE void createIngredient(const QString &ingrNm, const QString &cateId, const QString &cateNm);

Q_SIGNALS:
    void itemsChanged();
    void loadingChanged();
    void fetchSuccess();
    void fetchFailed(const QString &errorMsg);
    void createSuccess(const QString &ingrId, const QString &ingrNm);
    void createFailed(const QString &errorMsg);

private Q_SLOTS:
    void onNetworkReply(QNetworkReply *reply);

private:
    void rebuildCategories();                 // 由 m_items 按 cateId 分组生成 m_categories
    void loadFromCache();                     // 启动时从本地 JSON 加载
    void saveToCache();                       // API 返回后写入本地 JSON (新结构)
    void saveRawResponse(const QByteArray &data);  // 保存 /UserIngr/paged 原始响应 (未解析)
    static QString cacheFilePath();
    static QString rawCacheFilePath();        // 原始响应对应的缓存文件绝对路径

    // === 食材图片缓存 ===
    void downloadIngredientImages();          // 遍历 m_items，下载缺失的食材图片到本地
    void cacheIngredientImage(const QString &ingrId, const QString &imgUrl); // 下载单个图片
    void processImageReply(QNetworkReply *reply);  // 图片下载完成回调
    QNetworkRequest buildImageRequest(const QString &imgUrl);  // 构造带认证头的图片请求
    QString imageCacheDir() const;            // 图片缓存目录 (~/.cache/smartscale/ingr_images)
    QString localImagePathFor(const QString &imgUrl) const;  // 由 URL 推导本地文件名
    void setItemLocalImage(const QString &ingrId, const QString &localPath); // 更新某项本地图路径

    /** @brief Token 刷新完成后，重发排队的请求 */
    void onTokenRefreshCompleted(bool success, const QString &errMsg);

    /** @brief 排队等待刷新的请求类型 */
    enum class PendingRequestType { Fetch, Create };
    struct PendingRequest {
        PendingRequestType type;
        QString createName;   // 创建食材时的名称
        QString createCateId; // 创建食材的分类ID
        QString createCateNm; // 创建食材的分类名称
    };

    AuthService *m_authService = nullptr;
    QNetworkAccessManager *m_networkMgr = nullptr;
    bool m_loading = false;

    QVariantList m_items;                     // [{en,cn,id,cateId,cateNm,emsId,emsCd,enable}, ...]
    QVariantList m_categories;                // [{cateId,cateNm,items:[...]}, ...]
    QMap<QString, QString> m_ingrMap;         // ingrCd → ingrId
    QMap<QString, QString> m_ingrNameMap;     // ingrNm(中文) → ingrId
    QMap<QString, QString> m_emsMap;          // emsCd → ingrId

    // === Token 刷新协调 ===
    QQueue<PendingRequest> m_pendingRequests;
    bool m_refreshing = false;

    // === 图片下载去重 ===
    QSet<QString> m_imgDownloading;           // 正在下载的 imgUrl 集合，避免重复请求
};

#endif // USERINGREDIENTSERVICE_H
