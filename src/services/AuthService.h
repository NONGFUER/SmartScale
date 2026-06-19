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
    Q_PROPERTY(int userId READ userId NOTIFY userInfoChanged)
    Q_PROPERTY(QString role READ role NOTIFY userInfoChanged)
    Q_PROPERTY(bool isOnlineMode READ isOnlineMode NOTIFY modeChanged)
    Q_PROPERTY(QString currentUser READ currentUser NOTIFY currentUserChanged)
    Q_PROPERTY(int custId READ custId NOTIFY userInfoChanged)
    Q_PROPERTY(int devId READ devId NOTIFY userInfoChanged)

public:
    explicit AuthService(QObject *parent = nullptr);
    ~AuthService();

    /** @brief 登录 */
    Q_INVOKABLE void login(const QString &userCode, const QString &password);

    /** @brief 刷新 Token */
    Q_INVOKABLE void refreshToken();

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
    int userId() const { return m_userId; }
    QString role() const { return m_role; }
    bool isOnlineMode() const { return m_isOnlineMode; }
    QString currentUser() const { return m_currentUser; }
    int custId() const { return m_custId; }
    int devId() const { return m_devId; }

Q_SIGNALS:
    void loginSuccess();
    void loginFailed(const QString &errorMsg);
    void tokenRefreshed(const QString &newToken);
    void tokenRefreshFailed(const QString &errorMsg);
    void currentUserChanged();
    void logoutCompleted();
    void tokenChanged();
    void userInfoChanged();
    void modeChanged();

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

    // === 统一处理登录/刷新成功 ===
    void handleAuthSuccess(const QString &username,
                           int userId,
                           const QString &token,
                           const QString &refreshToken,
                           const QDateTime &expiresAt,
                           const QString &role,
                           bool online);

    // === 网络请求辅助（消除 SSL/Header 样板重复） ===
    QNetworkRequest createApiRequest(const QString &apiPath,
                                     const QString &token = QString()) const;

    // === 认证响应解析（登录 / 刷新共用） ===
    /** @return 解析是否成功，失败时 errMsg 填写原因 */
    bool parseAuthResponse(const QByteArray &data,
                           QString &outToken,
                           QString &outRefreshToken,
                           QDateTime &outExpiresAt,
                           int &outUserId,
                           QString &outUserName,
                           QString &outErrMsg);

    // === 成员变量 ===
    QNetworkAccessManager *m_networkMgr;
    UserRepo *m_userRepo = nullptr;

    QString m_pendingUserCode;    // 待认证的用户名（离线降级时复用）
    QString m_pendingPassword;    // 待认证的密码（离线降级时复用）

    QString m_currentUser;
    QString m_token;
    QString m_refreshToken;
    QDateTime m_tokenExpiresAt;
    int m_userId = -1;
    QString m_role;
    bool m_isOnlineMode = false;
    int m_custId = 0;
    int m_devId = 0;
};

#endif // AUTHSERVICE_H
