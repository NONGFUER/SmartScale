#ifndef CATEGORYSERVICE_H
#define CATEGORYSERVICE_H

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class AuthService;

/**
 * @brief 品类数据服务 — 从云端 API 获取食材分类列表，支持离线降级
 *
 * QML 用法:
 *   CategoryService.fetchCategories()   // 触发拉取
 *   CategoryService.categories          // QVariantList (绑定到 ListView/Repeater model)
 */
class CategoryService : public QObject
{
    Q_OBJECT
    // === QML 可绑定属性 ===
    Q_PROPERTY(QVariantList categories READ categories NOTIFY categoriesChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)

public:
    explicit CategoryService(QObject *parent = nullptr);

    /** @brief 设置认证服务（用于获取 Token） */
    void setAuthService(AuthService *auth);

    // === Getter ===
    QVariantList categories() const { return m_categories; }
    bool loading() const { return m_loading; }
    QString errorText() const { return m_errorText; }

    /** @brief 从云端拉取品类列表（QML 可调用） */
    Q_INVOKABLE void fetchCategories();

    /**
     * @brief 获取指定分类下的所有品项（扁平列表）
     * @param categoryName 分类名称，空字符串返回全部
     * @return 品项列表 [{name, en, cn, categoryName}, ...]
     */
    Q_INVOKABLE QVariantList getItemsByCategory(const QString &categoryName = QString()) const;

Q_SIGNALS:
    void categoriesChanged();
    void loadingChanged();
    void errorTextChanged();
    void fetchSuccess();
    void fetchFailed(const QString &errorMsg);

private Q_SLOTS:
    void onNetworkReply(QNetworkReply *reply);

private:
    /** @brief 构建离线降级的本地数据 */
    void buildFallbackData();

    /** @brief 解析云端返回的 JSON 数据 */
    bool parseCategoryResponse(const QByteArray &data);

    /** @brief Token 刷新完成后，重发排队请求 */
    void onTokenRefreshCompleted(bool success, const QString &errMsg);

    QNetworkAccessManager *m_networkMgr;
    AuthService *m_authService = nullptr;

    QVariantList m_categories;  // [{name: "叶菜类", items: [{en:"...",cn:"..."}, ...]}, ...]
    bool m_loading = false;
    QString m_errorText;

    // === Token 刷新协调 ===
    bool m_refreshing = false;
    int m_pendingFetchCount = 0;  // 排队等待刷新的 fetchCategories 调用次数
};

#endif // CATEGORYSERVICE_H
