#ifndef MQTTCLIENTSERVICE_H
#define MQTTCLIENTSERVICE_H

#include <QObject>
#include <QString>
#include <QByteArray>
#include <QList>
#include <QMap>
#include <QQueue>
#include <QMutex>
#include <QMutexLocker>
#include <QTimer>
#include <QSslCertificate>
#include <QSslSocket>
#include <QSettings>
#include <functional>

#include <QMqttClient>        // MOC 需要 QMqttClient::ClientError/ClientState 完整类型
#include <QMqttSubscription>
#include <QMqttMessage>

/**
 * @brief MQTT 客户端服务类
 *
 * 提供完整的 MQTT 通信能力：
 * - 连接/断开/订阅/发布核心操作
 * - SSL/TLS 安全连接（支持 CA 证书、双向认证、ALPN）
 * - 自动重连与心跳保活
 * - 离线消息队列缓存
 * - 线程安全设计
 * - 回调接口与 Qt Signal 双重通知机制
 *
 * @note 底层依赖 QtMqtt 模块 (Qt6::Mqtt)
 *
 * 使用示例:
 * @code
 *   auto mqtt = new MqttClientService(parent);
 *   mqtt->setHost("user.shxgs.cn");
 *   mqtt->setPort(8888);
 *   mqtt->setClientId("my-client-001");
 *   mqtt->setUsername("user");
 *   mqtt->setPassword("pass");
 *   mqtt->enableSsl(true);              // 启用 mqtts://
 *   mqtt->loadCaCertificatesFromFile("/path/to/ca.crt");
 *
 *   // 注册回调
 *   mqtt->onMessageReceived([](const QString &topic, const QByteArray &payload) {
 *       qDebug() << "收到消息:" << topic << payload;
 *   });
 *   mqtt->onConnected([]() { qDebug() << "已连接"; });
 *
 *   mqtt->connectToBroker();
 * @endcode
 */
class MqttClientService : public QObject {
    Q_OBJECT

    // ==================== QML 可绑定属性 ====================
    Q_PROPERTY(ConnectionState connectionState READ connectionState NOTIFY connectionStateChanged)
    Q_PROPERTY(QString lastError         READ lastError         NOTIFY lastErrorChanged)
    Q_PROPERTY(QString host               READ host WRITE setHost NOTIFY hostChanged)
    Q_PROPERTY(int     port               READ port WRITE setPort NOTIFY portChanged)
    Q_PROPERTY(QString clientId           READ clientId WRITE setClientId NOTIFY clientIdChanged)
    Q_PROPERTY(QString username           READ username WRITE setUsername NOTIFY usernameChanged)
    Q_PROPERTY(bool    sslEnabled         READ isSslEnabled       NOTIFY sslEnabledChanged)

public:
    // ==================== 枚举定义 ====================

    /** 连接状态 */
    enum class ConnectionState {
        Disconnected = 0,
        Connecting,
        Connected,
        Reconnecting
    };
    Q_ENUM(ConnectionState)

    /** MQTT QoS 等级 */
    enum class QoSLevel {
        AtMostOnce  = 0,    ///< QoS 0: 最多投递一次
        AtLeastOnce = 1,    ///< QoS 1: 至少投递一次
        ExactlyOnce = 2     ///< QoS 2: 恰好投递一次
    };
    Q_ENUM(QoSLevel)

    /** 断开原因 */
    enum class DisconnectReason {
        UserInitiated,      ///< 用户主动调用 disconnectFromBroker()
        NetworkError,       ///< 网络层错误
        ProtocolError,      ///< MQTT 协议错误
        ServerDisconnect,   ///< 服务端主动断开
        AuthFailed,         ///< 认证失败
        Timeout,            ///< 连接/响应超时
        Unknown             ///< 未知原因
    };

    // ==================== 回调类型别名 ====================

    using MessageCallback     = std::function<void(const QString &topic, const QByteArray &payload)>;
    using ConnectionCallback  = std::function<void()>;
    using DisconnectCallback  = std::function<void(DisconnectReason reason, const QString &errorMsg)>;
    using StateChangeCallback = std::function<void(ConnectionState oldState, ConnectionState newState)>;

    // ==================== 构造 / 析构 ====================

    explicit MqttClientService(QObject *parent = nullptr);
    ~MqttClientService() override;

    // 禁用拷贝和移动
    MqttClientService(const MqttClientService &)            = delete;
    MqttClientService &operator=(const MqttClientService &) = delete;
    MqttClientService(MqttClientService &&)                 = delete;
    MqttClientService &operator=(MqttClientService &&)      = delete;

    // ==================== Broker 地址配置 ====================

    void setHost(const QString &host);
    QString host() const;

    void setPort(int port);
    int port() const;

    /** 设置客户端 ID；不设置则自动生成 UUID */
    void setClientId(const QString &clientId);
    QString clientId() const;

    /** 设置 MQTT 协议版本: 3=MQTT 3.1, 4=MQTT 3.1.1(默认), 5=MQTT 5.0 */
    void setProtocolVersion(int version);

    // ==================== 认证配置 ====================

    void setUsername(const QString &username);
    QString username() const;

    void setPassword(const QString &password);

    // ==================== SSL/TLS 配置 ====================

    /** 启用/禁用 SSL/TLS (mqtts://) */
    void enableSsl(bool enabled);
    bool isSslEnabled() const;

    /** 设置 CA 证书列表（用于验证服务器证书） */
    void setCaCertificates(const QList<QSslCertificate> &certs);

    /** 从 PEM 文件加载 CA 证书 */
    bool loadCaCertificatesFromFile(const QString &pemFilePath);

    /** 设置客户端本地证书（双向 TLS 认证） */
    void setLocalCertificate(const QSslCertificate &cert);
    bool loadLocalCertificateFromFile(const QString &pemFilePath);

    /** 设置客户端私钥（双向 TLS 认证） */
    void setPrivateKey(const QByteArray &keyPem, QSsl::KeyAlgorithm algo = QSsl::Rsa);
    bool loadPrivateKeyFromFile(const QString &pemFilePath, const QByteArray &passphrase = QByteArray());

    /** 设置对等验证模式（对应界面上的 "SSL Secure" 开关） */
    void setPeerVerifyMode(QSslSocket::PeerVerifyMode mode);

    /** 设置 ALPN 协议列表 */
    void setAlpnProtocols(const QStringList &protocols);

    // ==================== 行为参数配置 ====================

    /** 设置自动重连间隔（毫秒），默认 5000ms */
    void setReconnectIntervalMs(int ms);
    int reconnectIntervalMs() const;

    /** 设置保活时间（秒），默认 60s */
    void setKeepAliveSeconds(int seconds);
    int keepAliveSeconds() const;

    /** 是否在离线时缓存 publish 消息（默认 true） */
    void setOfflineQueueEnabled(bool enabled);
    bool isOfflineQueueEnabled() const;

    /** 离线队列最大容量，0 表示无上限（默认 1000） */
    void setMaxQueueSize(int maxSize);
    int maxQueueSize() const;

    /** 是否自动重连（默认 true） */
    void setAutoReconnect(bool enabled);
    bool autoReconnect() const;

    /** 最大重连尝试次数，0 表示无限重试（默认 0） */
    void setMaxReconnectAttempts(int maxAttempts);
    int maxReconnectAttempts() const;

    /**
     * @brief 设置 Last-Will 消息（异常断开时代发）
     * @param topic   遗嘱主题
     * @param message 遗嘱内容
     * @param qos     遗嘱 QoS
     * @param retain   是否保留
     */
    void setWillMessage(const QString &topic,
                        const QByteArray &message,
                        QoSLevel qos = QoSLevel::AtLeastOnce,
                        bool retain = false);
    void clearWillMessage();

    // ==================== 核心操作：连接管理 ====================

    /** 连接到 Broker（线程安全，可在任意线程调用） */
    Q_INVOKABLE void connectToBroker();

    /** 断开连接（线程安全）
     *  @param clearPendingQueue 是否清空待发送队列（默认 true）
     */
    Q_INVOKABLE void disconnectFromBroker(bool clearPendingQueue = true);

    // ==================== 核心操作：订阅 / 取消订阅 ====================

    /**
     * @brief 订阅主题（支持通配符 + 和 #）
     * @param topic 过滤表达式，如 "sensor/+/temp"、"event/#"
     * @param qos   服务质量等级
     * @return 是否成功提交订阅请求
     *
     * 未连接时若 autoReconnect=true，请求会被缓存，
     * 在下次连接成功后自动执行。
     */
    Q_INVOKABLE bool subscribe(const QString &topic,
                               QoSLevel qos = QoSLevel::AtLeastOnce);

    /**
     * @brief 取消订阅
     * @param topic 与 subscribe 时传入的 topic 一致即可
     */
    Q_INVOKABLE bool unsubscribe(const QString &topic);

    QStringList subscribedTopics() const;
    bool isSubscribed(const QString &topic) const;

    // ==================== 核心操作：发布消息 ====================

    /**
     * @brief 发布消息
     * @return >=0: 消息 ID; -1: 失败（未连接且离线队列禁用/已满）
     *
     * 已连接 → 立即发送
     * 未连接+离线队列启用 → 入队等待
     * 未连接+离线队列禁用 → 返回 -1 并设置 lastError
     */
    Q_INVOKABLE int publish(const QString &topic,
                            const QByteArray &payload,
                            QoSLevel qos = QoSLevel::AtLeastOnce,
                            bool retain = false);

    /** 发布文本消息的便捷方法 */
    Q_INVOKABLE int publishString(const QString &topic,
                                  const QString &message,
                                  QoSLevel qos = QoSLevel::AtLeastOnce,
                                  bool retain = false);

    // ==================== 状态查询 ====================

    ConnectionState connectionState() const;
    bool isConnected() const;
    bool isConnectingOrReconnecting() const;
    QString lastError() const;
    int pendingMessageCount() const;

    /** 手动清空离线待发送队列 */
    void clearPendingQueue();

    // ==================== 设备接入 shxgs MQTT Broker ====================

    /**
     * @brief 初始化并连接到 user.shxgs.cn:8888 (mqtts)
     *
     * 认证规则:
     *   - username = sn (设备序列号)
     *   - password: 首次自动随机生成 18 位以内，持久化后复用
     *   - clientId = sn
     *
     * @param sn      设备序列号（来自 WeightSensor::sn()）
     * @param custId  客户 ID（来自 AuthService::custId()）
     */
    Q_INVOKABLE void initAndConnect(const QString &sn, qint64 custId);

    /**
     * @brief 发布设备信息到 cust/{custId}/device/{sn}/up/info
     * 格式: JSON {"hardver":"xxx","softver":"xxx","sim":"xxx"}
     */
    Q_INVOKABLE int publishDeviceInfo(const QString &sn,
                                      qint64 custId,
                                      const QString &hardVer = QString(),
                                      const QString &softVer = QString(),
                                      const QString &sim       = QString());

    /** 构建设备上报主题: cust/{custId}/device/{sn}/up/info */
    static QString buildDeviceTopic(qint64 custId, const QString &sn);

    /** 构建设备信息 payload (JSON): {"hardver":"xxx","softver":"xxx","sim":"xxx"} */
    static QByteArray buildInfoPayload(const QString &hardVer,
                                       const QString &softVer,
                                       const QString &sim);

    /** 生成随机密码（字母+数字，默认 16 位） */
    static QString generateRandomPassword(int length = 16);

    /** 获取当前存储的 MQTT 密码（空表示尚未初始化） */
    QString storedPassword() const;

    // ==================== 回调注册 ====================

    void onMessageReceived(MessageCallback cb);
    void onConnected(ConnectionCallback cb);
    void onDisconnected(DisconnectCallback cb);
    void onStateChanged(StateChangeCallback cb);

Q_SIGNALS:
    /* --- 属性变更信号 --- */
    void connectionStateChanged();
    void lastErrorChanged();
    void hostChanged();
    void portChanged();
    void clientIdChanged();
    void usernameChanged();
    void sslEnabledChanged();

    /* --- 业务事件信号 --- */
    void connected();                                              ///< 连接建立成功
    void disconnected(DisconnectReason reason);                    ///< 连接断开
    void messageReceived(const QString &topic, const QByteArray &payload);  ///< 收到消息
    void messagePublished(int msgId, const QString &topic);       ///< QoS>0 的发布确认
    void subscribed(const QString &topic);                         ///< 订阅确认
    void unsubscribed(const QString &topic);                       ///< 取消订阅确认
    void errorOccurred(const QString &errorString);                ///< 错误发生
    void reconnecting(int attemptNumber);                          ///< 正在第 N 次重连

private Q_SLOTS:
    void onQMqttConnected();
    void onQMqttDisconnected();
    void onQMqttErrorOccurred(QMqttClient::ClientError error);
    void onQMqttMessageReceived(const QByteArray &message, const QMqttTopicName &topic);
    void onReconnectTimerTick();
    void onKeepAliveCheck();

private:
    // ---- 内部辅助方法 ----

    void setState(ConnectionState s);
    void setError(const QString &err);
    void startReconnectTimer();
    void stopReconnectTimer();
    void startKeepAliveMonitor();
    void stopKeepAliveMonitor();
    void flushPendingMessages();       // 发送所有缓存的 publish
    void flushPendingSubscriptions();  // 执行所有缓存的 subscribe
    void resetReconnectCounter();

    // ---- 内部数据结构 ----

    /** 待发布消息条目 */
    struct PendingPublish {
        QString   topic;
        QByteArray payload;
        QoSLevel  qos;
        bool      retain;
    };

    /** 待订阅主题条目 */
    struct PendingSubscription {
        QString  topic;
        QoSLevel qos;
    };

    /** Last-Will 配置 */
    struct WillConfig {
        QString   topic;
        QByteArray message;
        QoSLevel  qos;
        bool      retain;
        bool      enabled = false;
    };

    // ---- 成员变量 ----

    QMqttClient            *m_client             = nullptr;
    QTimer                 *m_reconnectTimer      = nullptr;   // 重连定时器
    QTimer                 *m_keepAliveMonitor    = nullptr;   // 心跳监控定时器

    mutable QMutex          m_mutex;                         // 保护共享状态的互斥锁

    ConnectionState         m_connectionState   = ConnectionState::Disconnected;
    ConnectionState         m_previousState     = ConnectionState::Disconnected;
    QString                 m_lastError;
    int                     m_reconnectAttempt   = 0;          // 当前重连计数

    // ---- Broker / 认证配置 ----
    QString                 m_host;
    int                     m_port               = 1883;
    QString                 m_clientId;
    QString                 m_username;
    QString                 m_password;
    bool                    m_sslEnabled         = false;
    QSslConfiguration       m_sslConfig;          // 缓存 SSL 配置 (Qt 6.8 无 setSslConfiguration)

    // ---- 行为参数 ----
    int                     k_reconnectIntervalMs = 5000;
    int                     k_keepAliveSeconds    = 60;
    bool                    m_offlineQueueEnabled = true;
    int                     m_maxQueueSize        = 1000;
    bool                    m_autoReconnect       = true;
    int                     m_maxReconnectAttempts = 0;        // 0 = 无限

    // ---- 缓存队列 ----
    QQueue<PendingPublish>      m_pendingMessages;
    QList<PendingSubscription>  m_pendingSubscriptions;

    // ---- 当前活跃订阅（用于去重和查询）----
    QMap<QString, QMqttSubscription *> m_activeSubscriptions;
    QStringList                        m_subscribedTopics;  // 已确认的订阅主题列表

    // ---- Last-Will ----
    WillConfig              m_willConfig;

    // ---- 回调列表（支持多个监听者）----
    QList<MessageCallback>     m_messageCallbacks;
    QList<ConnectionCallback>  m_connectedCallbacks;
    QList<DisconnectCallback>  m_disconnectedCallbacks;
    QList<StateChangeCallback> m_stateChangeCallbacks;

    // ---- 自增消息 ID ----
    int                     m_nextMessageId       = 0;

    // ---- shxgs 设备接入专用字段 ----
    QString                 m_storedPassword;       // 持久化的 MQTT 密码
    qint64                  m_custId              = 0;   // 当前 custId
    static constexpr const char *kSettingsGroup  = "MqttShxgs";
    static constexpr const char *kSettingsKeyPwd = "Password";

    // ---- Broker 常量 (shxgs) ----
    static inline const char *kShxgsHost = "user.shxgs.cn";
    static constexpr int      kShxgsPort = 8888;
};

#endif // MQTTCLIENTSERVICE_H
