#include "CategoryService.h"
#include "AuthService.h"
#include "core/NetworkUtils.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QDebug>

CategoryService::CategoryService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
    // 先加载离线数据作为兜底
    buildFallbackData();
}

void CategoryService::setAuthService(AuthService *auth)
{
    m_authService = auth;
}

void CategoryService::fetchCategories()
{
    if (m_loading) return;
    m_loading = true;
    Q_EMIT loadingChanged();
    m_errorText.clear();
    Q_EMIT errorTextChanged();

    QString token = m_authService ? m_authService->token() : QString();
    auto request = NetworkUtils::createApiRequest(NetworkUtils::Api::CATEGORY_LIST, token);
    // GET 请求
    qInfo() << "[CategoryService] 正在请求品类列表...";

    m_networkMgr->get(request);
}

void CategoryService::onNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();

    m_loading = false;
    Q_EMIT loadingChanged();

    if (reply->error() != QNetworkReply::NoError) {
        QString errMsg = QString("网络错误: %1").arg(reply->errorString());
        qWarning() << "[CategoryService]" << errMsg;
        m_errorText = errMsg;
        Q_EMIT errorTextChanged();
        Q_EMIT fetchFailed(errMsg);
        return;
    }

    int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    QByteArray data = reply->readAll();

    qInfo() << "[CategoryService] HTTP" << statusCode << "响应长度:" << data.size();

    if (statusCode != 200) {
        QString errMsg = QString("服务器错误(HTTP %1)").arg(statusCode);
        m_errorText = errMsg;
        Q_EMIT errorTextChanged();
        Q_EMIT fetchFailed(errMsg);
        return;
    }

    if (parseCategoryResponse(data)) {
        Q_EMIT fetchSuccess();
    } else {
        Q_EMIT fetchFailed("数据解析失败");
    }
}

bool CategoryService::parseCategoryResponse(const QByteArray &data)
{
    QJsonDocument doc = QJsonDocument::fromJson(data);
    QJsonArray catArray;

    // 支持两种顶层格式：JSON 对象 {...} 或数组 [...]
    if (doc.isArray()) {
        // 格式B: 顶层就是数组 [{name:"...", items:[...]}, ...]
        catArray = doc.array();
        qInfo() << "[CategoryService] 检测到数组格式响应";
    } else if (!doc.isObject()) {
        qWarning() << "[CategoryService] JSON 格式错误，使用离线数据";
        return false;
    }

    QJsonObject root = doc.object();

    if (!catArray.isEmpty()) {
        // 已从数组格式获取，直接跳到解析
    } else if (root.contains("code") && root["code"].isDouble()) {
        // 格式A: { code:0, data: [...] }
        if (root["code"].toInt() == 0 && root.contains("data")) {
            catArray = root["data"].toArray();
        } else {
            QString msg = root.contains("message") ? root["message"].toString() : "未知错误";
            qWarning() << "[CategoryService] 服务端返回错误:" << msg;
            m_errorText = msg;
            Q_EMIT errorTextChanged();
            return false;
        }
    } else if (root.contains("categories")) {
        catArray = root["categories"].toArray();
    }

    if (catArray.isEmpty()) {
        qWarning() << "[CategoryService] 返回数据为空，使用离线兜底";
        return false;
    }

    QVariantList result;

    for (const QJsonValue &catVal : catArray) {
        QJsonObject catObj = catVal.toObject();
        QVariantMap categoryMap;
        categoryMap["name"] = catObj.value("name").toString(catObj.value("categoryName").toString());
        categoryMap["color"] = catObj.value("color").toString("#409EFF");

        QVariantList itemList;
        QJsonArray items = catObj.value("items").toArray();
        for (const QJsonValue &itemVal : items) {
            QJsonObject itemObj = itemVal.toObject();
            QVariantMap itemMap;
            itemMap["en"]  = itemObj.value("en").toString(itemObj.value("englishName").toString());
            itemMap["cn"]  = itemObj.value("cn").toString(itemObj.value("chineseName").toString(itemObj.value("name").toString()));
            itemList.append(itemMap);
        }

        categoryMap["items"] = itemList;
        result.append(categoryMap);
    }

    m_categories = result;
    Q_EMIT categoriesChanged();

    qInfo() << "[CategoryService] 成功解析" << result.size() << "个分类";
    return true;
}

void CategoryService::buildFallbackData()
{
    m_categories = QVariantList{
        QVariantMap{
            {"name", QStringLiteral("叶子类")},
            {"color", QStringLiteral("#67C23A")},
            {"items", QVariantList{
                QVariantMap{{"en","qingcai"},      {"cn","青菜"}},
                QVariantMap{{"en","bocai"},         {"cn","菠菜"}},
                QVariantMap{{"en","dabaicai"},      {"cn","大白菜"}},
                QVariantMap{{"en","baoxincai"},     {"cn","包心菜"}},
                QVariantMap{{"en","youmaicai"},     {"cn","油麦菜"}},
            }}
        },
        QVariantMap{
            {"name", QStringLiteral("根茎类")},
            {"color", QStringLiteral("#E6A23C")},
            {"items", QVariantList{
                QVariantMap{{"en","huluobo"},       {"cn","胡萝卜"}},
                QVariantMap{{"en","luobo"},         {"cn","萝卜"}},
                QVariantMap{{"en","bailuobo"},      {"cn","白萝卜"}},
                QVariantMap{{"en","tudou"},          {"cn","土豆"}},
                QVariantMap{{"en","jiang"},          {"cn","姜"}},
            }}
        },
        QVariantMap{
            {"name", QStringLiteral("肉类")},
            {"color", QStringLiteral("#F56C6C")},
            {"items", QVariantList{
                QVariantMap{{"en","zhurou"},        {"cn","猪肉"}},
                QVariantMap{{"en","jirou"},         {"cn","鸡肉"}},
                QVariantMap{{"en","niurou"},        {"cn","牛肉"}},
            }}
        },
        QVariantMap{
            {"name", QStringLiteral("水果")},
            {"color", QStringLiteral("#909399")},
            {"items", QVariantList{
                QVariantMap{{"en","pingguo"},       {"cn","苹果"}},
                QVariantMap{{"en","xiangjiao"},     {"cn","香蕉"}},
                QVariantMap{{"en","juzi"},          {"cn","橘子"}},
            }}
        },
        QVariantMap{
            {"name", QStringLiteral("更多")},
            {"color", QStringLiteral("#9C27B0")},
            {"items", QVariantList{
                QVariantMap{{"en","doulei"},        {"cn","豆类"}},
                QVariantMap{{"en","mugua"},         {"cn","木瓜"}},
                QVariantMap{{"en","nangua"},        {"cn","南瓜"}},
                QVariantMap{{"en","huanggua"},      {"cn","黄瓜"}},
                QVariantMap{{"en","fanqie"},        {"cn","番茄"}},
                QVariantMap{{"en","qinzie"},        {"cn","茄子"}},
            }}
        },
    };

    Q_EMIT categoriesChanged();
}

QVariantList CategoryService::getItemsByCategory(const QString &categoryName) const
{
    if (categoryName.isEmpty()) {
        // 返回全部品项（扁平）
        QVariantList all;
        for (const auto &cat : m_categories) {
            all.append(cat.toMap()["items"].toList());
        }
        return all;
    }

    for (const auto &cat : m_categories) {
        if (cat.toMap()["name"].toString() == categoryName) {
            return cat.toMap()["items"].toList();
        }
    }
    return {};
}
