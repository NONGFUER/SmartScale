#include "CategoryService.h"
#include "AuthService.h"
#include "core/NetworkUtils.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QNetworkRequest>
#include <QFile>
#include <QDir>
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
    // 接入统一 Token 刷新协调器
    if (m_authService) {
        QObject::connect(m_authService, &AuthService::tokenRefreshCompleted,
                         this, &CategoryService::onTokenRefreshCompleted,
                         Qt::UniqueConnection);
    }
}

void CategoryService::fetchCategories()
{
    if (m_loading) return;

    // === Token 预检 ===
    QString token = m_authService ? m_authService->token() : QString();
    if (!token.isEmpty() && m_authService && m_authService->isTokenExpiringSoon()) {
        qDebug() << "[CategoryService] Token 即将过期，排队等待刷新";
        m_pendingFetchCount++;
        if (!m_refreshing && !m_authService->isRefreshingToken()) {
            m_refreshing = true;
            m_authService->requestTokenRefresh();
        }
        return;
    }

    m_loading = true;
    Q_EMIT loadingChanged();
    m_errorText.clear();
    Q_EMIT errorTextChanged();

    auto request = NetworkUtils::createApiRequest(NetworkUtils::Api::CATEGORY_LIST, token);
    // GET 请求
    qInfo() << "[CategoryService] 正在请求品类列表...";

    m_networkMgr->get(request);
}

// ==========================================================================
//  食材品类全量拉取 (POST /api/user/IngrCate/all?custId=<custId>) + 本地缓存
// ==========================================================================

QString CategoryService::ingrCateCacheFilePath() const
{
    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    return dir + "/ingr_categories.json";
}

void CategoryService::fetchIngrCategories()
{
    QString token = m_authService ? m_authService->token() : QString();
    // custId 是雪花 ID，用 QString 拼接避免溢出
    QString custId = m_authService ? QString::number(m_authService->custId()) : QStringLiteral("0");

    // === Token 预检 ===
    if (!token.isEmpty() && m_authService && m_authService->isTokenExpiringSoon()) {
        qDebug() << "[CategoryService] Token 即将过期，排队等待刷新后拉取食材品类";
        m_pendingIngrCateFetch++;
        if (!m_refreshing && !m_authService->isRefreshingToken()) {
            m_refreshing = true;
            m_authService->requestTokenRefresh();
        }
        return;
    }

    // 拼接 custId 查询参数（USER 域）
    QString apiPath = QString("%1?custId=%2")
                          .arg(QString::fromLatin1(NetworkUtils::Api::USER_INGRCATE_ALL), custId);
    QNetworkRequest request = NetworkUtils::createApiRequest(
        QString::fromLatin1(NetworkUtils::USER_BASE_URL), apiPath, token);

    qInfo() << "[CategoryService] 正在请求食材品类全量, custId=" << custId;

    QNetworkReply *reply = m_networkMgr->post(request, QByteArray());
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();

        if (reply->error() != QNetworkReply::NoError) {
            // === 401/403 自动刷新重试 ===
            if (AuthService::isUnauthorizedError(reply) && m_authService) {
                qDebug() << "[CategoryService] 食材品类收到 401/403，触发 Token 刷新并重试";
                m_pendingIngrCateFetch++;
                if (!m_refreshing && !m_authService->isRefreshingToken()) {
                    m_refreshing = true;
                    m_authService->requestTokenRefresh();
                }
                return;
            }
            QString errMsg = QString("网络错误: %1").arg(reply->errorString());
            qWarning() << "[CategoryService] 食材品类拉取失败:" << errMsg;
            Q_EMIT ingrCategoriesFetchFailed(errMsg);
            return;
        }

        int statusCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        QByteArray data = reply->readAll();
        qInfo() << "[CategoryService] 食材品类 HTTP" << statusCode << "响应长度:" << data.size();

        if (statusCode != 200) {
            QString errMsg = QString("服务器错误(HTTP %1)").arg(statusCode);
            qWarning() << "[CategoryService]" << errMsg;
            Q_EMIT ingrCategoriesFetchFailed(errMsg);
            return;
        }

        saveIngrCateCache(data);
        Q_EMIT ingrCategoriesFetched(ingrCateCacheFilePath());
    });
}

void CategoryService::saveIngrCateCache(const QByteArray &data)
{
    QString path = ingrCateCacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[CategoryService] 无法写入食材品类缓存文件:" << path;
        return;
    }
    file.write(data);
    file.close();
    qInfo() << "[CategoryService] 食材品类缓存已写入:" << path << "(" << data.size() << "字节)";
}

void CategoryService::onNetworkReply(QNetworkReply *reply)
{
    reply->deleteLater();

    m_loading = false;
    Q_EMIT loadingChanged();

    if (reply->error() != QNetworkReply::NoError) {
        // === 401/403 自动刷新重试 ===
        if (AuthService::isUnauthorizedError(reply) && m_authService) {
            qDebug() << "[CategoryService] 收到 401/403 未授权，触发 Token 刷新并重试";
            m_pendingFetchCount++;
            if (!m_refreshing && !m_authService->isRefreshingToken()) {
                m_refreshing = true;
                m_authService->requestTokenRefresh();
            }
            return;
        }

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

// ==========================================================================
//  Token 刷新完成回调 — 重发排队请求
// ==========================================================================

void CategoryService::onTokenRefreshCompleted(bool success, const QString &errMsg)
{
    m_refreshing = false;

    if (!success) {
        qWarning() << "[CategoryService] Token 刷新失败，丢弃" << m_pendingFetchCount
                   << "条品类 +" << m_pendingIngrCateFetch << "条食材品类排队请求";
        if (m_pendingFetchCount > 0) {
            m_errorText = "Token 刷新失败: " + errMsg;
            Q_EMIT errorTextChanged();
            Q_EMIT fetchFailed(m_errorText);
        }
        if (m_pendingIngrCateFetch > 0) {
            Q_EMIT ingrCategoriesFetchFailed("Token 刷新失败: " + errMsg);
        }
        m_pendingFetchCount = 0;
        m_pendingIngrCateFetch = 0;
        return;
    }

    qDebug() << "[CategoryService] Token 刷新成功，重发" << m_pendingFetchCount
             << "条品类 +" << m_pendingIngrCateFetch << "条食材品类排队请求";
    // 只需各重发一次（多次排队合并为一次）
    int count = m_pendingFetchCount;
    int ingrCateCount = m_pendingIngrCateFetch;
    m_pendingFetchCount = 0;
    m_pendingIngrCateFetch = 0;
    if (count > 0) {
        fetchCategories();
    }
    if (ingrCateCount > 0) {
        fetchIngrCategories();
    }
}
