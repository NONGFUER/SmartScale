#ifndef AUTHSERVICE_H
#define AUTHSERVICE_H

#include <QObject>
#include <QString>
#include <QDateTime>
#include <QNetworkAccessManager>
#include <QNetworkReply>

class UserRepo;

class AuthService : public QObject
{
    Q_OBJECT
    // === 会话属性 (QML 可绑定) ===
    Q_PROPERTY(QString token READ token NOTIFY tokenChanged)
    Q_PROPERTY(qint64 userId READ userId NOTIFY userInfoChanged)
    Q_PROPERTY(QString role READ role NOTIFY userInfoChanged)
    Q_PROPERTY(bool isOnlineMode READ isOnlineMode NOTIFY modeChanged)
    Q_PROPERTY(QString currentUser READ currentUser NOTIFY currentUserChanged)
    Q_PROPERTY(qint64 custId READ custId NOTIFY userInfoChanged)
    Q_PROPERTY(qint64 devId READ devId NOTIFY userInfoChanged)
    Q_PROPERTY(QString productId READ productId NOTIFY productIdChanged)
    Q_PROPERTY(QString avatarUrl READ avatarUrl NOTIFY avatarChanged)
    Q_PROPERTY(QString custNm READ custNm NOTIFY custNmChanged)
    Q_PROPERTY(QString deviceSn READ deviceSn NOTIFY deviceSnChanged)
    Q_PROPERTY(bool rememberLogin READ rememberLogin WRITE setRememberLogin NOTIFY rememberLoginChanged)
    Q_PROPERTY(QString lastUserCode READ lastUserCode NOTIFY lastLoginChanged)
    Q_PROPERTY(bool hasSavedLogin READ hasSavedLogin NOTIFY lastLoginChanged)

public:
    explicit AuthService(QObject *parent = nullptr);
    ~AuthService();

    /** @brief 登录 */
    Q_INVOKABLE void login(const QString &userCode, const QString &password);

    /** @brief 刷新 Token */
    Q_INVOKABLE void refreshToken();

    /**
     * @brief 统一 Token 刷新入口（带并发锁）
     *
     * 所有 Service 应调用此方法而非直接调用 refreshToken()。
     * 内部维护刷新锁，防止多个调用方同时触发多次刷新请求。
     * 刷新完成后通过 tokenRefreshCompleted 信号通知所有等待者。
     */
    Q_INVOKABLE void requestTokenRefresh();

    /** @brief 查询是否正在执行 Token 刷新（供调用方判断是否需排队） */
    bool isRefreshingToken() const;

    /**
     * @brief 检查 HTTP 回复是否为 401 Unauthorized
     * @return true 表示 Token 过期需触发刷新
     */
    static bool isUnauthorizedError(QNetworkReply *reply);

    /** @brief 退出登录 */
    Q_INVOKABLE void logout();

    // === Token 预检 ===
    /** @brief Token 是否即将过期（默认 5 分钟内） */
    bool isTokenExpiringSoon(int thresholdSeconds = 300) const;

    /** @brief Token 是否有效（非空且未过期） */
    bool isTokenValid() const;

    // === 离线登录支持 ===
    void setUserRepo(UserRepo *repo);

    // === Getter ===
    QString token() const { return m_token; }
    qint64 userId() const { return m_userId; }
    QString role() const { return m_role; }
    bool isOnlineMode() const { return m_isOnlineMode; }
    QString currentUser() const { return m_currentUser; }
    qint64 custId() const { return m_custId; }
    qint64 devId() const { return m_devId; }
    /** @brief 产品 ID（登录后由 /api/ems/Product/by-sn 返回，缓存到本地） */
    QString productId() const { return m_productId; }
    /** @brief 用户头像 URL（登录后由 /api/ems/User/by-id 返回） */
    QString avatarUrl() const { return m_avatarUrl; }
    /** @brief 客户名称（登录后由 /api/ems/User/by-id 返回） */
    QString custNm() const { return m_custNm; }

    // === 设备序列号（由 WeightSensor 注入）===
    void setDeviceSn(const QString &sn);
    QString deviceSn() const { return m_deviceSn; }

    // === 记住登录功能 ===
    bool rememberLogin() const { return m_rememberLogin; }
    void setRememberLogin(bool remember);
    QString lastUserCode() const { return m_lastUserCode; }
    bool hasSavedLogin() const;
    Q_INVOKABLE void autoLogin();  // 使用保存的凭据自动登录
    Q_INVOKABLE void clearSavedLogin();  // 清除记住的登录信息

Q_SIGNALS:
    void loginSuccess();
    void loginFailed(const QString &errorMsg);
    void tokenRefreshed(const QString &newToken);
    void tokenRefreshFailed(const QString &errorMsg);
    /**
     * @brief Token 刷新完成通知（统一信号，替代分散的 tokenRefreshed/Failed）
     *
     * 所有通过 requestTokenRefresh() 触发的刷新，无论成功失败都会发射此信号。
     * 各 Service 应连接此信号以重发被拦截的请求。
     *
     * @param success  刷新是否成功
     * @param errorMsg 失败原因（成功时为空字符串）
     */
    void tokenRefreshCompleted(bool success, const QString &errorMsg);
    void currentUserChanged();
    void logoutCompleted();
    void tokenChanged();
    void userInfoChanged();
    void modeChanged();
    void productIdChanged();
    void avatarChanged();
    void custNmChanged();
    void deviceSnChanged();
    void rememberLoginChanged();
    void lastLoginChanged();

private Q_SLOTS:
    /** @brief 处理网络回复 */
    void onNetworkReply(QNetworkReply *reply);

private:
    // === 在线登录 ===
    void tryOnlineLogin(const QString &userCode, const QString &password);

    // === 离线降级 ===
    void tryOfflineLogin(const QString &userCode, const QString &password);

    // === 刷新 Token ===
    void tryRefreshToken();

    // === 根据 SN 获取产品（登录后调用，提取 productId 缓存） ===
    void tryFetchProductBySn();

    // === 获取用户信息（头像等，登录成功后调用）===
    void tryFetchUserInfo();

    // === 统一处理登录/刷新成功 ===
    void handleAuthSuccess(const QString &username,
                           qint64 userId,
                           const QString &token,
                           const QString &refreshToken,
                           const QDateTime &expiresAt,
                           const QString &role,
                           bool online,
                           bool isInitialLogin = true);

    // === 网络请求辅助（消除 SSL/Header 样板重复） ===
    QNetworkRequest createApiRequest(const QString &apiPath,
                                     const QString &token = QString()) const;

    // === 认证响应解析（登录 / 刷新共用） ===
    /** @return 解析是否成功，失败时 errMsg 填写原因 */
    bool parseAuthResponse(const QByteArray &data,
                           QString &outToken,
                           QString &outRefreshToken,
                           QDateTime &outExpiresAt,
                           qint64 &outUserId,
                           QString &outUserName,
                           QString &outErrMsg);

    // === productId 本地缓存读写 ===
    void loadProductFromCache();
    void saveProductToCache() const;

    // === 记住登录本地缓存读写 ===
    void loadLastLogin();
    void saveLastLogin();
    void clearSavedLoginData();

    // === 成员变量 ===
    QNetworkAccessManager *m_networkMgr;
    UserRepo *m_userRepo = nullptr;

    QString m_pendingUserCode;    // 待认证的用户名（离线降级时复用）
    QString m_pendingPassword;    // 待认证的密码（离线降级时复用）

    QString m_currentUser;
    QString m_token;
    QString m_refreshToken;
    QDateTime m_tokenExpiresAt;
    qint64 m_userId = -1;
    QString m_role;
    bool m_isOnlineMode = false;
    qint64 m_custId = 0;
    qint64 m_devId = 0;
    QString m_productId;          // 产品 ID（来自 /api/ems/Product/by-sn）
    QString m_avatarUrl;           // 用户头像 URL（来自 /api/ems/User/by-id）
    QString m_custNm;              // 客户名称（来自 /api/ems/User/by-id）
    QString m_deviceSn;            // 从 WeightSensor 读取的真实设备 SN

    // === 记住登录 ===
    bool m_rememberLogin = false;
    QString m_lastUserCode;        // 保存的用户名
    QString m_lastPassword;        // 保存的密码

    // === Token 刷新协调器（无感刷新核心） ===
    bool   m_isRefreshing = false;       // 全局刷新锁：防止并发重复请求
    int    m_refreshFailCount = 0;       // 连续刷新失败计数，超过阈值建议重新登录
    static constexpr int kMaxRefreshFailures = 2;  // 连续失败阈值
};

#endif // AUTHSERVICE_H
