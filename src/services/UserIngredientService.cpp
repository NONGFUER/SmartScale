#include "UserIngredientService.h"
#include "AuthService.h"
#include "core/NetworkUtils.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QDebug>

UserIngredientService::UserIngredientService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
    connect(m_networkMgr, &QNetworkAccessManager::finished,
            this, &UserIngredientService::onNetworkReply);
}

void UserIngredientService::setAuthService(AuthService *auth)
{
    m_authService = auth;
}

void UserIngredientService::fetchIngredients()
{
    if (m_loading) return;
    if (!m_authService || m_authService->token().isEmpty()) {
        qWarning() << "[UserIngr] 未登录，无法拉取食材列表";
        return;
    }

    m_loading = true;
    Q_EMIT loadingChanged();

    auto request = NetworkUtils::createUserApiRequest(
        NetworkUtils::Api::USER_INGR_PAGED, m_authService->token());

    QJsonObject body;
    body["page"]      = 1;
    body["pageSize"]  = 100;
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

void UserIngredientService::onNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();

    if (reply->error() != QNetworkReply::NoError) {
        m_loading = false;
        Q_EMIT loadingChanged();
        qWarning() << "[UserIngr] 网络错误:" << reply->errorString();
        Q_EMIT fetchFailed(reply->errorString());
        return;
    }

    QByteArray data = reply->readAll();
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(data, &err);

    if (err.error != QJsonParseError::NoError || !doc.isObject()) {
        m_loading = false;
        Q_EMIT loadingChanged();
        qWarning() << "[UserIngr] JSON 解析失败";
        Q_EMIT fetchFailed("JSON 解析失败");
        return;
    }

    QJsonObject root = doc.object();

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

    for (const QJsonValue &val : items) {
        QJsonObject obj = val.toObject();
        QString ingrId = obj.value("ingrId").toVariant().toString();
        QString ingrCd = obj.value("ingrCd").toString().toLower();
        QString ingrNm = obj.value("ingrNm").toString();

        QVariantMap item;
        item["en"] = ingrCd;
        item["cn"] = ingrNm;
        item["id"] = ingrId;
        m_items.append(item);

        if (!ingrId.isEmpty() && !ingrCd.isEmpty()) {
            m_ingrMap[ingrCd] = ingrId;
        }
        if (!ingrId.isEmpty() && !ingrNm.isEmpty()) {
            m_ingrNameMap[ingrNm] = ingrId;
        }
    }

    m_loading = false;
    Q_EMIT loadingChanged();
    Q_EMIT itemsChanged();

    qInfo() << "[UserIngr] 成功加载" << m_items.size() << "个食材";
    Q_EMIT fetchSuccess();
}

QString UserIngredientService::getIngrId(const QString &ingrCd) const
{
    // 先按英文编码查
    QString id = m_ingrMap.value(ingrCd.toLower());
    if (!id.isEmpty()) return id;
    // fallback: 按中文名查
    return m_ingrNameMap.value(ingrCd, QStringLiteral("0"));
}
