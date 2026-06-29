#ifndef USERINGREDIENTSERVICE_H
#define USERINGREDIENTSERVICE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QMap>

class AuthService;
class QNetworkAccessManager;
class QNetworkReply;

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
    static QString cacheFilePath();

    AuthService *m_authService = nullptr;
    QNetworkAccessManager *m_networkMgr = nullptr;
    bool m_loading = false;

    QVariantList m_items;                     // [{en,cn,id,cateId,cateNm,emsId,emsCd,enable}, ...]
    QVariantList m_categories;                // [{cateId,cateNm,items:[...]}, ...]
    QMap<QString, QString> m_ingrMap;         // ingrCd → ingrId
    QMap<QString, QString> m_ingrNameMap;     // ingrNm(中文) → ingrId
    QMap<QString, QString> m_emsMap;          // emsCd → ingrId
};

#endif // USERINGREDIENTSERVICE_H
