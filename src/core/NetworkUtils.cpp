#include "NetworkUtils.h"

#include <QSslConfiguration>
#include <QSslSocket>
#include <QDebug>

// 传输超时（毫秒）：防止网络不可达时请求永久挂起导致 UI 一直转圈。
// 设为 15s，覆盖 DNS 解析 / TCP 握手 / 服务器无响应等挂起场景。
inline constexpr int kRequestTimeoutMs = 15000;

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

    // 传输超时：网络不可达 / 握手无响应时，超时后 reply 触发 finished 并带 TimeoutError，
    // 调用方据此关闭转圈并提示"网络连接失败"。
    request.setTransferTimeout(kRequestTimeoutMs);

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

    // 传输超时（与 createApiRequest 保持一致）
    request.setTransferTimeout(kRequestTimeoutMs);

    qInfo() << "[HTTP] === Multipart POST ===";
    qInfo() << "[HTTP] URL:" << url.toString();
    if (!token.isEmpty()) {
        qInfo() << "[HTTP]   Authorization: Bearer ***";
    }
    qInfo() << "[HTTP]   Content-Type (body):" << contentType;
    qInfo() << "[HTTP] =========================";

    return request;
}

QNetworkRequest NetworkUtils::createUserApiRequest(const char *apiPath,
                                                    const QString &token)
{
    return createApiRequest(USER_BASE_URL, apiPath, token);
}

QNetworkRequest NetworkUtils::createUpdateApiRequest(const char *apiPath,
                                                      const QString &token)
{
    return createApiRequest(UPDATE_BASE_URL, apiPath, token);
}
