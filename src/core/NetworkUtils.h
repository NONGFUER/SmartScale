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
    inline constexpr const char *API_BASE_URL  = "https://api.shxgs.cn:5196";
    inline constexpr const char *USER_BASE_URL = "https://user.shxgs.cn:5196";

    // === API 路径（集中管理，新增接口在此处添加）===
    namespace Api {
        inline constexpr const char *LOGIN          = "/api/Auth/login";
        inline constexpr const char *REFRESH_TOKEN  = "/api/Auth/refresh-token";
        // inline constexpr const char *WEIGHT_CREATE  = "/api/ems/WeightRecord/create";  // 已废弃，统一走 USER 域
        inline constexpr const char *CATEGORY_LIST  = "/api/ems/Ingr/paged";  // 品类列表
        inline constexpr const char *AI_RECOGNIZE_FILE  = "/api/ems/AiDet/recognize-ingr/file";  // 识别食材
        inline constexpr const char *PRODUCT_BY_SN      = "/api/ems/Product/by-sn";  // 根据 SN 获取产品
        inline constexpr const char *USER_BY_ID          = "/api/ems/User/by-id";    // 获取当前登录用户信息（头像等）

        // === USER 域接口（user.shxgs.cn:5196）===
        inline constexpr const char *USER_WEIGHT_CREATE     = "/api/user/WeightRecord/create";
        inline constexpr const char *USER_WEIGHT_UPDATE_IMG = "/api/user/WeightRecord/update-img";
        inline constexpr const char *USER_WEIGHT_REVOKE     = "/api/user/WeightRecord/revoke";
        inline constexpr const char *USER_INGR_PAGED        = "/api/user/UserIngr/paged";
        inline constexpr const char *USER_INGR_CREATE       = "/api/user/UserIngr/create";
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

    /**
     * @brief 创建 multipart/form-data API 请求（文件上传专用）
     * @param apiPath       API 路径，如 Api::AI_RECOGNIZE_FILE
     * @param token         可选的 Bearer Token
     * @param contentType   上传文件的 MIME 类型，默认 "image/jpeg"
     *
     * 注意：multipart 请求不手动设置 Content-Type（让 QHttpMultiPart 自动带 boundary）
     */
    QNetworkRequest createMultipartApiRequest(const char *apiPath,
                                              const QString &token = QString(),
                                              const QString &contentType = "image/jpeg");

    /**
     * @brief 创建 USER 域 API 请求（使用 USER_BASE_URL: user.shxgs.cn:5196）
     */
    QNetworkRequest createUserApiRequest(const char *apiPath,
                                         const QString &token = QString());

} // namespace NetworkUtils

#endif // NETWORKUTILS_H
