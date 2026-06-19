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
 * @brief 用户域食材服务 — 从 /api/user/Ingr/paged 拉取食材，提供 ingrCd→ingrId 映射
 *
 * QML 用法:
 *   UserIngredientService.fetchIngredients()   // 拉取
 *   UserIngredientService.items                 // QVariantList，可直接绑定 ListView
 *   UserIngredientService.getIngrId("dabaicai") // → "1"
 */
class UserIngredientService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList items READ items NOTIFY itemsChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    explicit UserIngredientService(QObject *parent = nullptr);

    void setAuthService(AuthService *auth);

    QVariantList items() const { return m_items; }
    bool loading() const { return m_loading; }

    /** @brief 从云端拉取食材列表 */
    Q_INVOKABLE void fetchIngredients();

    /** @brief 根据 ingrCd 获取 ingrId，未找到返回 "0" */
    Q_INVOKABLE QString getIngrId(const QString &ingrCd) const;

Q_SIGNALS:
    void itemsChanged();
    void loadingChanged();
    void fetchSuccess();
    void fetchFailed(const QString &errorMsg);

private Q_SLOTS:
    void onNetworkReply(QNetworkReply *reply);

private:
    AuthService *m_authService = nullptr;
    QNetworkAccessManager *m_networkMgr = nullptr;
    bool m_loading = false;

    QVariantList m_items;                     // [{en, cn, id}, ...]
    QMap<QString, QString> m_ingrMap;         // ingrCd → ingrId
    QMap<QString, QString> m_ingrNameMap;     // ingrNm(中文) → ingrId
};

#endif // USERINGREDIENTSERVICE_H
