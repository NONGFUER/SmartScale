#include "UpdateService.h"
#include "core/NetworkUtils.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QDebug>

// 请求 payload 写死（JSON 字符串 "User_Dzc"）
static const QByteArray kUpdatePayload = R"("User_Dzc")";

UpdateService::UpdateService(QObject *parent)
    : QObject(parent)
    , m_networkMgr(new QNetworkAccessManager(this))
{
}

void UpdateService::checkUpdate()
{
    if (m_checking) {
        qDebug() << "[UpdateService] 查询进行中，跳过重复请求";
        return;
    }
    m_checking = true;
    Q_EMIT checkingChanged();

    QNetworkRequest request = NetworkUtils::createUpdateApiRequest(
        NetworkUtils::Api::UPDATE_INFO_LATEST);

    qInfo() << "[UpdateService] 正在查询最新版本信息, payload:" << kUpdatePayload;

    QNetworkReply *reply = m_networkMgr->post(request, kUpdatePayload);
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        m_checking = false;
        Q_EMIT checkingChanged();

        const QByteArray body = reply->readAll();

        // === 打印响应报文（无论成败，格式化 JSON 便于阅读；解析失败则打原文）===
        const QJsonDocument printDoc = QJsonDocument::fromJson(body);
        qInfo().noquote() << "[UpdateService] === 响应报文 ===\n"
                          << (printDoc.isNull()
                                  ? QString::fromUtf8(body)
                                  : QString::fromUtf8(printDoc.toJson(QJsonDocument::Indented)));

        if (reply->error() != QNetworkReply::NoError) {
            qWarning() << "[UpdateService] 查询失败:" << reply->errorString();
            Q_EMIT checkFinished(false, reply->errorString());
            return;
        }

        // === 解析响应 ===
        QJsonParseError parseErr;
        const QJsonDocument doc = QJsonDocument::fromJson(body, &parseErr);
        if (parseErr.error != QJsonParseError::NoError || !doc.isObject()) {
            qWarning() << "[UpdateService] 响应 JSON 解析失败:" << parseErr.errorString();
            Q_EMIT checkFinished(false, QStringLiteral("响应格式错误"));
            return;
        }

        const QJsonObject root = doc.object();
        if (!root.value(QStringLiteral("success")).toBool()) {
            const QString msg = root.value(QStringLiteral("message")).toString();
            qWarning() << "[UpdateService] 服务端返回失败:" << msg;
            Q_EMIT checkFinished(false, msg.isEmpty() ? QStringLiteral("服务端返回失败") : msg);
            return;
        }

        const QJsonObject data = root.value(QStringLiteral("data")).toObject();
        // 注意: data 内数字字段均为字符串形式（"325"），用 toVariant() 兼容字符串/数字
        m_updateId     = data.value(QStringLiteral("id")).toString();
        m_version      = data.value(QStringLiteral("version")).toString();
        m_verCode      = data.value(QStringLiteral("verCode")).toVariant().toInt();
        m_fileName     = data.value(QStringLiteral("fileName")).toString();
        m_force        = data.value(QStringLiteral("force")).toBool();
        m_size         = data.value(QStringLiteral("size")).toVariant().toLongLong();
        m_differential = data.value(QStringLiteral("differential")).toBool();
        m_verCodeMax   = data.value(QStringLiteral("verCodeMax")).toVariant().toInt();
        m_verCodeMin   = data.value(QStringLiteral("verCodeMin")).toVariant().toInt();
        m_hash         = data.value(QStringLiteral("hash")).toString();

        // pubTime 为秒级时间戳，格式化为本地时间
        const qint64 pubSecs = data.value(QStringLiteral("pubTime")).toVariant().toLongLong();
        m_pubTime = QDateTime::fromSecsSinceEpoch(pubSecs).toString(QStringLiteral("yyyy-MM-dd HH:mm:ss"));

        // url 为相对路径，拼接完整下载地址
        const QString relUrl = data.value(QStringLiteral("url")).toString();
        m_downloadUrl = relUrl.startsWith(QStringLiteral("http"))
                            ? relUrl
                            : QString::fromLatin1(NetworkUtils::UPDATE_BASE_URL) + relUrl;

        m_hasInfo = true;
        Q_EMIT infoChanged();

        qInfo() << "[UpdateService] 最新版本:" << m_version
                << "verCode=" << m_verCode
                << "force=" << m_force
                << "size=" << m_size
                << "url=" << m_downloadUrl;
        Q_EMIT checkFinished(true, m_version);
    });
}
