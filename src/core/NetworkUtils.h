#ifndef NETWORKUTILS_H
#define NETWORKUTILS_H

#include <QNetworkRequest>
#include <QString>

/**
 * @brief 网络请求工具类 — 统一 SSL 配置、Content-Type、Authorization 等样板逻辑
 *
 * 用法:
 *   auto req = NetworkUtils::createApiRequest("https://example.com", "/api/foo", token);
 */
namespace NetworkUtils {

    // === 全局常量 ===
    inline constexpr const char *API_BASE_URL = "https://api.shxgs.cn:5196";

    // === API 路径（集中管理，新增接口在此处添加）===
    namespace Api {
        inline constexpr const char *LOGIN          = "/api/Auth/login";
        inline constexpr const char *REFRESH_TOKEN  = "/api/Auth/refresh-token";
        inline constexpr const char *WEIGHT_CREATE  = "/api/ems/WeightRecord/create";
        inline constexpr const char *CATEGORY_LIST  = "/api/ems/Ingr/paged";  // 品类列表
    }

    /**
     * @brief 创建统一配置的 API 请求（自动拼接 API_BASE_URL）
     * @param apiPath   API 路径，如 Api::LOGIN
     * @param token     可选的 Bearer Token
     */
    QNetworkRequest createApiRequest(const char *apiPath,
                                     const QString &token = QString());

    /**
     * @brief 创建统一配置的 API 请求（指定 baseUrl）
     * @param baseUrl   基础 URL，如 "https://192.168.3.33:7223"
     * @param apiPath   API 路径，如 "/api/Auth/login"
     * @param token     可选的 Bearer Token，空则不设置 Authorization 头
     * @return 配置好的 QNetworkRequest（SSL VerifyNone + JSON Content-Type）
     */
    QNetworkRequest createApiRequest(const QString &baseUrl,
                                     const QString &apiPath,
                                     const QString &token = QString());

} // namespace NetworkUtils

#endif // NETWORKUTILS_H
