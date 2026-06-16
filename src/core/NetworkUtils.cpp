#include "NetworkUtils.h"

#include <QSslConfiguration>
#include <QSslSocket>
#include <QDebug>

QNetworkRequest NetworkUtils::createApiRequest(const char *apiPath,
                                                const QString &token)
{
    return createApiRequest(API_BASE_URL, apiPath, token);
}

QNetworkRequest NetworkUtils::createApiRequest(const QString &baseUrl,
                                                const QString &apiPath,
                                                const QString &token)
{
    QUrl url(QString("%1%2").arg(baseUrl, apiPath));
    QNetworkRequest request(url);

    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");

    if (!token.isEmpty()) {
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + token.toUtf8());
    }

    // IP + HTTPS 环境需跳过证书验证
    QSslConfiguration sslConf = request.sslConfiguration();
    sslConf.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConf.setProtocol(QSsl::TlsV1_2OrLater);
    request.setSslConfiguration(sslConf);

    // 强制使用 HTTP/1.1，避免 HTTP/2 导致 "Host requires authentication" 错误
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    // 打印请求报文
    qInfo() << "[HTTP] === 请求报文 ===";
    qInfo() << "[HTTP] URL:" << url.toString();
    qInfo() << "[HTTP] Method: POST";
    qInfo() << "[HTTP] Headers:";
    qInfo() << "[HTTP]   Content-Type:" << request.header(QNetworkRequest::ContentTypeHeader).toString();
    if (!token.isEmpty()) {
        qInfo() << "[HTTP]   Authorization: Bearer ***";
    }
    qInfo() << "[HTTP] =================";

    return request;
}

QNetworkRequest NetworkUtils::createMultipartApiRequest(const char *apiPath,
                                                         const QString &token,
                                                         const QString &contentType)
{
    QUrl url(QString("%1%2").arg(API_BASE_URL, apiPath));
    QNetworkRequest request(url);

    // multipart 不设 Content-Type header（QHttpMultiPart 会自动带 boundary）
    // 手动设置会导致后端无法解析 boundary

    if (!token.isEmpty()) {
        request.setRawHeader("Authorization",
                             QByteArray("Bearer ") + token.toUtf8());
    }

    // SSL 配置（与 createApiRequest 一致）
    QSslConfiguration sslConf = request.sslConfiguration();
    sslConf.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConf.setProtocol(QSsl::TlsV1_2OrLater);
    request.setSslConfiguration(sslConf);

    // 强制 HTTP/1.1
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);

    qInfo() << "[HTTP] === Multipart POST ===";
    qInfo() << "[HTTP] URL:" << url.toString();
    if (!token.isEmpty()) {
        qInfo() << "[HTTP]   Authorization: Bearer ***";
    }
    qInfo() << "[HTTP]   Content-Type (body):" << contentType;
    qInfo() << "[HTTP] =========================";

    return request;
}
