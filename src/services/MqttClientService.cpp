#include "MqttClientService.h"

#include <QMqttClient>
#include <QMqttSubscription>
#include <QMqttTopicName>
#include <QMqttTopicFilter>
#include <QSslKey>              // QSslKey 类型（QSslSocket 不自动包含）
#include <QUuid>
#include <QLoggingCategory>
#include <QFile>
#include <QRandomGenerator>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDateTime>
#include <QNetworkInterface>
#include <QUdpSocket>
#include <QFile>
#include <QDir>
#include <QTextStream>

Q_LOGGING_CATEGORY(lcMqtt, "smartscale.mqtt")

// ============================================================================
// 构造 / 析构
// ============================================================================

MqttClientService::MqttClientService(QObject *parent)
    : QObject(parent)
    , m_client(new QMqttClient(this))
{
    // ---- 绑定 QtMqtt 信号 ----
    connect(m_client, &QMqttClient::connected,
            this,     &MqttClientService::onQMqttConnected);
    connect(m_client, &QMqttClient::disconnected,
            this,     &MqttClientService::onQMqttDisconnected);
    connect(m_client, &QMqttClient::errorChanged,
            this,     [this](QMqttClient::ClientError error) {
                onQMqttErrorOccurred(error);
            });
    // Qt 6.8: messageReceived(const QByteArray &, const QMqttTopicName &)
    connect(m_client, &QMqttClient::messageReceived,
            this,     &MqttClientService::onQMqttMessageReceived);

    // 下行命令过滤：在通用 messageReceived 之外单独解析 down/cmd
    connect(this, &MqttClientService::messageReceived,
            this, &MqttClientService::onCommandMessage);

    // ---- 重连定时器 ----
    m_reconnectTimer = new QTimer(this);
    m_reconnectTimer->setSingleShot(true);
    m_reconnectTimer->setInterval(k_reconnectIntervalMs);
    connect(m_reconnectTimer, &QTimer::timeout,
            this,            &MqttClientService::onReconnectTimerTick);

    // ---- 心跳监控定时器 ----
    m_keepAliveMonitor = new QTimer(this);
    m_keepAliveMonitor->setInterval(5000);
    connect(m_keepAliveMonitor, &QTimer::timeout,
            this,                &MqttClientService::onKeepAliveCheck);

    // ---- 心跳上报定时器 (默认每 3 秒) ----
    m_pingTimer = new QTimer(this);
    m_pingTimer->setInterval(kPingIntervalMs);
    m_pingTimer->setSingleShot(false);
    connect(m_pingTimer, &QTimer::timeout,
            this,          &MqttClientService::onPingTick);

    // ---- 设备状态上报定时器 (默认每 30 秒) ----
    m_statusTimer = new QTimer(this);
    m_statusTimer->setInterval(kStatusIntervalMs);
    m_statusTimer->setSingleShot(false);
    connect(m_statusTimer, &QTimer::timeout,
            this,             &MqttClientService::onStatusTick);

    qCDebug(lcMqtt) << "[Mqtt] MqttClientService 已创建";
}

MqttClientService::~MqttClientService()
{
    disconnectFromBroker(true);
}

// ============================================================================
// 属性 getter / setter (线程安全)
// ============================================================================

void MqttClientService::setHost(const QString &host)
{
    const QMutexLocker lock(&m_mutex);
    if (m_host != host) {
        m_host = host;
        m_client->setHostname(host);   // Qt 6.8: setHostname 非 setHost
        Q_EMIT hostChanged();
    }
}
QString MqttClientService::host() const { const QMutexLocker lock(&m_mutex); return m_host; }

void MqttClientService::setPort(int port)
{
    const QMutexLocker lock(&m_mutex);
    if (m_port != port) {
        m_port = port;
        m_client->setPort(static_cast<quint16>(port));
        Q_EMIT portChanged();
    }
}
int MqttClientService::port() const { const QMutexLocker lock(&m_mutex); return m_port; }

void MqttClientService::setClientId(const QString &clientId)
{
    const QMutexLocker lock(&m_mutex);
    if (m_clientId != clientId) {
        m_clientId = clientId.isEmpty()
                         ? QUuid::createUuid().toString(QUuid::WithoutBraces)
                         : clientId;
        m_client->setClientId(m_clientId);
        Q_EMIT clientIdChanged();
    }
}
QString MqttClientService::clientId() const
{
    const QMutexLocker lock(&m_mutex);
    return m_clientId.isEmpty()
               ? QUuid::createUuid().toString(QUuid::WithoutBraces)
               : m_clientId;
}

void MqttClientService::setProtocolVersion(int version)
{
    switch (version) {
        case 3:  m_client->setProtocolVersion(QMqttClient::MQTT_3_1);   break;
        case 4:  m_client->setProtocolVersion(QMqttClient::MQTT_3_1_1); break;
        case 5:  m_client->setProtocolVersion(QMqttClient::MQTT_5_0);   break;
        default: m_client->setProtocolVersion(QMqttClient::MQTT_3_1_1); break;
    }
}

void MqttClientService::setUsername(const QString &username)
{
    const QMutexLocker lock(&m_mutex);
    if (m_username != username) {
        m_username = username;
        m_client->setUsername(username);
        Q_EMIT usernameChanged();
    }
}
QString MqttClientService::username() const { const QMutexLocker lock(&m_mutex); return m_username; }

void MqttClientService::setPassword(const QString &password)
{
    const QMutexLocker lock(&m_mutex);
    m_password = password;
    m_client->setPassword(password);
}

// ============================================================================
// SSL/TLS 配置（Qt 6.8: 缓存到 m_sslConfig，连接时通过 connectToHostEncrypted 使用）
// ============================================================================

void MqttClientService::enableSsl(bool enabled)
{
    const QMutexLocker lock(&m_mutex);
    if (m_sslEnabled != enabled) {
        m_sslEnabled = enabled;
        if (enabled) {
            m_sslConfig = QSslConfiguration::defaultConfiguration();
        } else {
            m_sslConfig = QSslConfiguration();  // 重置
        }
        Q_EMIT sslEnabledChanged();
    }
}
bool MqttClientService::isSslEnabled() const { const QMutexLocker lock(&m_mutex); return m_sslEnabled; }

void MqttClientService::setCaCertificates(const QList<QSslCertificate> &certs)
{
    const QMutexLocker lock(&m_mutex);
    m_sslConfig.setCaCertificates(certs);
}

bool MqttClientService::loadCaCertificatesFromFile(const QString &pemFilePath)
{
    QFile f(pemFilePath);
    if (!f.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("[Mqtt] 无法打开 CA 证书文件: ") + pemFilePath);
        qCWarning(lcMqtt) << m_lastError;
        return false;
    }
    QList<QSslCertificate> certs = QSslCertificate::fromDevice(&f);
    f.close();

    if (certs.isEmpty()) {
        setError(QStringLiteral("[Mqtt] CA证书文件无有效证书: ") + pemFilePath);
        qCWarning(lcMqtt) << m_lastError;
        return false;
    }

    setCaCertificates(certs);
    qCDebug(lcMqtt) << "[Mqtt] 已加载" << certs.size() << "个 CA 证书";
    return true;
}

void MqttClientService::setLocalCertificate(const QSslCertificate &cert)
{
    const QMutexLocker lock(&m_mutex);
    m_sslConfig.setLocalCertificate(cert);
}
bool MqttClientService::loadLocalCertificateFromFile(const QString &pemFilePath)
{
    QFile f(pemFilePath);
    if (!f.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("[Mqtt] 无法打开客户端证书: ") + pemFilePath);
        return false;
    }
    QSslCertificate cert(&f);
    f.close();
    if (cert.isNull()) {
        setError(QStringLiteral("[Mqtt] 客户端证书无效: ") + pemFilePath);
        return false;
    }
    setLocalCertificate(cert);
    return true;
}

void MqttClientService::setPrivateKey(const QByteArray &keyPem, QSsl::KeyAlgorithm algo)
{
    const QMutexLocker lock(&m_mutex);
    m_sslConfig.setPrivateKey(QSslKey(keyPem, algo));
}
bool MqttClientService::loadPrivateKeyFromFile(const QString &pemFilePath,
                                                const QByteArray &passphrase)
{
    QFile f(pemFilePath);
    if (!f.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("[Mqtt] 无法打开私钥文件: ") + pemFilePath);
        return false;
    }
    QSslKey key(&f, QSsl::Rsa, QSsl::Pem, QSsl::PrivateKey, passphrase);
    f.close();
    if (key.isNull()) {
        setError(QStringLiteral("[Mqtt] 私钥无效: ") + pemFilePath);
        return false;
    }
    setPrivateKey(key.toPem());
    return true;
}

void MqttClientService::setPeerVerifyMode(QSslSocket::PeerVerifyMode mode)
{
    const QMutexLocker lock(&m_mutex);
    m_sslConfig.setPeerVerifyMode(mode);
}

void MqttClientService::setAlpnProtocols(const QStringList &protocols)
{
    const QMutexLocker lock(&m_mutex);
    // Qt 6.8: ALPN 通过 SSL 配置的 protocol 设置（非标准 API）
    // m_sslConfig.setAlpnProtocols(protocols);  // 可能不可用
    Q_UNUSED(protocols);
}

// ============================================================================
// 行为参数配置
// ============================================================================

void MqttClientService::setReconnectIntervalMs(int ms)
{
    const QMutexLocker lock(&m_mutex);
    k_reconnectIntervalMs = qMax(ms, 1000);
    m_reconnectTimer->setInterval(k_reconnectIntervalMs);
}
int MqttClientService::reconnectIntervalMs() const { return k_reconnectIntervalMs; }

void MqttClientService::setKeepAliveSeconds(int seconds)
{
    const QMutexLocker lock(&m_mutex);
    k_keepAliveSeconds = qMax(seconds, 10);
    m_client->setKeepAlive(static_cast<quint16>(k_keepAliveSeconds));
}
int MqttClientService::keepAliveSeconds() const { return k_keepAliveSeconds; }

void MqttClientService::setOfflineQueueEnabled(bool enabled)
{ const QMutexLocker lock(&m_mutex); m_offlineQueueEnabled = enabled; }
bool MqttClientService::isOfflineQueueEnabled() const
{ const QMutexLocker lock(&m_mutex); return m_offlineQueueEnabled; }

void MqttClientService::setMaxQueueSize(int maxSize)
{ const QMutexLocker lock(&m_mutex); m_maxQueueSize = maxSize; }
int MqttClientService::maxQueueSize() const
{ const QMutexLocker lock(&m_mutex); return m_maxQueueSize; }

void MqttClientService::setAutoReconnect(bool enabled)
{ const QMutexLocker lock(&m_mutex); m_autoReconnect = enabled; }
bool MqttClientService::autoReconnect() const
{ const QMutexLocker lock(&m_mutex); return m_autoReconnect; }

void MqttClientService::setMaxReconnectAttempts(int maxAttempts)
{ const QMutexLocker lock(&m_mutex); m_maxReconnectAttempts = maxAttempts; }
int MqttClientService::maxReconnectAttempts() const
{ const QMutexLocker lock(&m_mutex); return m_maxReconnectAttempts; }

void MqttClientService::setWillMessage(const QString &topic,
                                        const QByteArray &message,
                                        QoSLevel qos, bool retain)
{
    const QMutexLocker lock(&m_mutex);
    m_willConfig.topic   = topic;
    m_willConfig.message = message;
    m_willConfig.qos     = qos;
    m_willConfig.retain  = retain;
    m_willConfig.enabled = !topic.isEmpty();
    m_client->setWillMessage(message);
    m_client->setWillTopic(topic);
    m_client->setWillQoS(static_cast<quint8>(qos));
    m_client->setWillRetain(retain);
}
void MqttClientService::clearWillMessage()
{
    const QMutexLocker lock(&m_mutex);
    m_willConfig.enabled = false;
    m_client->setWillMessage(QByteArray());
    m_client->setWillTopic(QString());
}

// ============================================================================
// 状态查询
// ============================================================================

MqttClientService::ConnectionState MqttClientService::connectionState() const
{ const QMutexLocker lock(&m_mutex); return m_connectionState; }

bool MqttClientService::isConnected() const
{ const QMutexLocker lock(&m_mutex); return m_connectionState == ConnectionState::Connected; }

bool MqttClientService::isConnectingOrReconnecting() const
{
    const QMutexLocker lock(&m_mutex);
    return m_connectionState == ConnectionState::Connecting
        || m_connectionState == ConnectionState::Reconnecting;
}

QString MqttClientService::lastError() const
{ const QMutexLocker lock(&m_mutex); return m_lastError; }

int MqttClientService::pendingMessageCount() const
{ const QMutexLocker lock(&m_mutex); return m_pendingMessages.size(); }

void MqttClientService::clearPendingQueue()
{
    const QMutexLocker lock(&m_mutex);
    m_pendingMessages.clear();
}

void MqttClientService::setState(ConnectionState s)
{
    const QMutexLocker lock(&m_mutex);
    if (m_connectionState == s) return;

    auto old = m_connectionState;
    m_previousState = old;
    m_connectionState = s;

    qCInfo(lcMqtt) << "[Mqtt] 状态变更:"
                    << static_cast<int>(old) << "->" << static_cast<int>(s);

    for (auto &cb : m_stateChangeCallbacks)
        cb(old, s);
    Q_EMIT connectionStateChanged();
}

void MqttClientService::setError(const QString &err)
{
    const QMutexLocker lock(&m_mutex);
    if (m_lastError == err) return;
    m_lastError = err;
    Q_EMIT lastErrorChanged();
}

// ============================================================================
// 核心操作：连接管理
// ============================================================================

void MqttClientService::connectToBroker()
{
    QMetaObject::invokeMethod(this, [this]() {
        if (m_host.isEmpty()) {
            setError(QStringLiteral("[Mqtt] Broker 地址未设置，请先调用 setHost()"));
            Q_EMIT errorOccurred(m_lastError);
            return;
        }

        resetReconnectCounter();
        stopReconnectTimer();
        setState(ConnectionState::Connecting);

        bool useSsl;
        {
            const QMutexLocker lock(&m_mutex);
            useSsl = m_sslEnabled;
        }

        qCInfo(lcMqtt) << "[Mqtt] 正在连接到"
                        << (useSsl ? QStringLiteral("mqtts://") : QStringLiteral("mqtt://"))
                        << m_host << ":" << m_port
                        << " clientId=" << m_clientId;

        if (useSsl) {
            // Qt 6.8: 通过 connectToHostEncrypted 传入 QSslConfiguration
            m_client->connectToHostEncrypted(m_sslConfig);
        } else {
            m_client->connectToHost();
        }
    }, Qt::QueuedConnection);
}

void MqttClientService::disconnectFromBroker(bool clearPendingQueue)
{
    QMetaObject::invokeMethod(this, [this, clearPendingQueue]() {
        stopReconnectTimer();
        stopKeepAliveMonitor();
        stopPingTimer();          // 用户主动断开：暂停心跳 (参数保留，重连后自动恢复)
        stopStatusTimer();        // 用户主动断开：暂停状态上报 (参数保留，重连后自动恢复)

        if (clearPendingQueue) {
            const QMutexLocker lock(&m_mutex);
            m_pendingMessages.clear();
            m_pendingSubscriptions.clear();
        }

        setState(ConnectionState::Disconnected);
        m_client->disconnectFromHost();

        for (auto &cb : m_disconnectedCallbacks)
            cb(DisconnectReason::UserInitiated, QString());
        Q_EMIT disconnected(DisconnectReason::UserInitiated);
    }, Qt::QueuedConnection);
}

// ============================================================================
// 核心操作：订阅 / 取消订阅
// ============================================================================

bool MqttClientService::subscribe(const QString &topic, QoSLevel qos)
{
    if (topic.isEmpty()) {
        setError(QStringLiteral("[Mqtt] 订阅主题不能为空"));
        Q_EMIT errorOccurred(m_lastError);
        return false;
    }

    {
        const QMutexLocker lock(&m_mutex);
        if (m_activeSubscriptions.contains(topic)) {
            qCDebug(lcMqtt) << "[Mqtt] 已订阅，跳过:" << topic;
            return true;
        }
        if (m_connectionState != ConnectionState::Connected) {
            if (m_autoReconnect) {
                bool found = false;
                for (const auto &ps : m_pendingSubscriptions) {
                    if (ps.topic == topic) { found = true; break; }
                }
                if (!found) {
                    m_pendingSubscriptions.append({topic, qos});
                    qCDebug(lcMqtt) << "[Mqtt] 未连接，缓存订阅请求:" << topic;
                }
                return true;
            } else {
                setError(QStringLiteral("[Mqtt] 尚未连接且自动重连已禁用"));
                Q_EMIT errorOccurred(m_lastError);
                return false;
            }
        }
    }

    // Qt 6.8: subscribe 接受 QMqttTopicFilter（可隐式转换自 QString）
    auto *sub = m_client->subscribe(QMqttTopicFilter(topic),
                                     static_cast<quint8>(qos));
    if (!sub) {
        setError(QStringLiteral("[Mqtt] 订阅失败: ") + topic);
        Q_EMIT errorOccurred(m_lastError);
        return false;
    }

    connect(sub, &QMqttSubscription::stateChanged,
            this, [this, sub, topic](QMqttSubscription::SubscriptionState state) {
        if (state == QMqttSubscription::Subscribed) {
            {
                const QMutexLocker lock(&m_mutex);
                m_activeSubscriptions.insert(topic, sub);
                if (!m_subscribedTopics.contains(topic))
                    m_subscribedTopics.append(topic);
            }
            Q_EMIT subscribed(topic);
            qCInfo(lcMqtt) << "[Mqtt] 订阅确认:" << topic;
        }
    });

    qCDebug(lcMqtt) << "[Mqtt] 提交订阅:" << topic;
    return true;
}

bool MqttClientService::unsubscribe(const QString &topic)
{
    if (topic.isEmpty()) return false;

    QMqttSubscription *sub = nullptr;
    {
        const QMutexLocker lock(&m_mutex);
        sub = m_activeSubscriptions.take(topic);
        m_subscribedTopics.removeAll(topic);
    }

    if (sub) {
        m_client->unsubscribe(QMqttTopicFilter(sub->topic()));
        Q_EMIT unsubscribed(topic);
        qCDebug(lcMqtt) << "[Mqtt] 取消订阅:" << topic;
        return true;
    }

    {
        const QMutexLocker lock(&m_mutex);
        for (int i = 0; i < m_pendingSubscriptions.size(); ++i) {
            if (m_pendingSubscriptions[i].topic == topic) {
                m_pendingSubscriptions.removeAt(i);
                qCDebug(lcMqtt) << "[Mqtt] 从待订阅队列移除:" << topic;
                return true;
            }
        }
    }

    qCWarning(lcMqtt) << "[Mqtt] 未找到订阅:" << topic;
    return false;
}

QStringList MqttClientService::subscribedTopics() const
{
    const QMutexLocker lock(&m_mutex);
    return m_subscribedTopics;
}
bool MqttClientService::isSubscribed(const QString &topic) const
{
    const QMutexLocker lock(&m_mutex);
    return m_subscribedTopics.contains(topic);
}

// ============================================================================
// 核心操作：发布消息
// ============================================================================

int MqttClientService::publish(const QString &topic,
                                const QByteArray &payload,
                                QoSLevel qos, bool retain)
{
    if (topic.isEmpty()) {
        setError(QStringLiteral("[Mqtt] 发布主题不能为空"));
        Q_EMIT errorOccurred(m_lastError);
        return -1;
    }

    int msgId;
    {
        const QMutexLocker lock(&m_mutex);
        msgId = ++m_nextMessageId;
        if (msgId <= 0) msgId = 1;
    }

    if (m_connectionState == ConnectionState::Connected
        && m_client->state() == QMqttClient::Connected) {

        // Qt 6.8: publish 接受 QMqttTopicName（可隐式转换），返回 qint32
        qint32 pubId = m_client->publish(QMqttTopicName(topic), payload,
                                          static_cast<quint8>(qos), retain);
        if (pubId >= 0 || qos == QoSLevel::AtMostOnce) {
            Q_EMIT messagePublished(msgId, topic);
            qCDebug(lcMqtt) << "[Mqtt] 发布成功 [" << msgId << "]" << topic;
        }
        return msgId;
    }

    // 未连接 → 入队或拒绝
    if (m_offlineQueueEnabled) {
        const QMutexLocker lock(&m_mutex);
        if (m_maxQueueSize > 0 && m_pendingMessages.size() >= m_maxQueueSize) {
            setError(QStringLiteral("[Mqtt] 离线队列已满 (%1/%2)")
                      .arg(m_pendingMessages.size()).arg(m_maxQueueSize));
            Q_EMIT errorOccurred(m_lastError);
            return -1;
        }
        m_pendingMessages.enqueue({topic, payload, qos, retain});
        qCDebug(lcMqtt) << "[Mqtt] 未连接，入队等待 (" << m_pendingMessages.size() << ")"
                        << topic;
        return msgId;
    } else {
        setError(QStringLiteral("[Mqtt] 未连接且离线队列已禁用"));
        Q_EMIT errorOccurred(m_lastError);
        return -1;
    }
}

int MqttClientService::publishString(const QString &topic,
                                      const QString &message,
                                      QoSLevel qos, bool retain)
{
    return publish(topic, message.toUtf8(), qos, retain);
}

// ============================================================================
// 内部辅助方法
// ============================================================================

void MqttClientService::startReconnectTimer()
{
    if (!m_autoReconnect) return;
    if (m_maxReconnectAttempts > 0 && m_reconnectAttempt >= m_maxReconnectAttempts) {
        qCWarning(lcMqtt) << "[Mqtt] 达到最大重连次数:"
                           << m_maxReconnectAttempts << "，停止重试";
        setError(QStringLiteral("[Mqtt] 达到最大重连次数 (%1)").arg(m_maxReconnectAttempts));
        Q_EMIT errorOccurred(m_lastError);
        setState(ConnectionState::Disconnected);
        return;
    }
    m_reconnectTimer->start();
}

void MqttClientService::stopReconnectTimer()
{
    if (m_reconnectTimer) m_reconnectTimer->stop();
}

void MqttClientService::startKeepAliveMonitor()
{
    if (k_keepAliveSeconds > 0 && !m_keepAliveMonitor->isActive())
        m_keepAliveMonitor->start();
}

void MqttClientService::stopKeepAliveMonitor()
{
    if (m_keepAliveMonitor) m_keepAliveMonitor->stop();
}

void MqttClientService::flushPendingMessages()
{
    QQueue<PendingPublish> queue;
    {
        const QMutexLocker lock(&m_mutex);
        std::swap(queue, m_pendingMessages);
    }

    while (!queue.isEmpty()) {
        auto item = queue.dequeue();
        if (m_connectionState == ConnectionState::Connected) {
            publish(item.topic, item.payload, item.qos, item.retain);
        }
    }
}

void MqttClientService::flushPendingSubscriptions()
{
    QList<PendingSubscription> subs;
    {
        const QMutexLocker lock(&m_mutex);
        std::swap(subs, m_pendingSubscriptions);
    }

    for (const auto &item : subs) {
        subscribe(item.topic, item.qos);
    }
}

void MqttClientService::resetReconnectCounter()
{
    const QMutexLocker lock(&m_mutex);
    m_reconnectAttempt = 0;
}

// ============================================================================
// QtMqtt 事件槽（适配 Qt 6.8 API）
// ============================================================================

void MqttClientService::onQMqttConnected()
{
    stopReconnectTimer();
    resetReconnectCounter();
    setState(ConnectionState::Connected);
    startKeepAliveMonitor();

    qCInfo(lcMqtt) << "[Mqtt] 已连接至 Broker";

    for (auto &cb : m_connectedCallbacks) cb();
    Q_EMIT connected();

    flushPendingSubscriptions();
    flushPendingMessages();

    // ---- 连接成功后，若已配置心跳则启动（并立即发一次）----
    if (!m_heartbeatSn.isEmpty()) {
        startPingTimer();
        onPingTick();
    }

    // ---- 连接成功后，若已配置状态上报则启动（并立即发一次）----
    if (!m_statusSn.isEmpty()) {
        startStatusTimer();
        onStatusTick();
    }
}

void MqttClientService::onQMqttDisconnected()
{
    stopKeepAliveMonitor();
    stopPingTimer();          // 断连：暂停心跳 (参数保留，重连后自动恢复)
    stopStatusTimer();        // 断连：暂停状态上报 (参数保留，重连后自动恢复)

    DisconnectReason reason = DisconnectReason::Unknown;
    auto clientErr = m_client->error();
    // Qt 6.8 枚举值: NoError, InvalidProtocolVersion, IdRejected,
    //                 ServerUnavailable, BadUserNameOrPassword, NotAuthorized,
    //                 TransportInvalid, ProtocolViolation, UnknownError, Mqtt5SpecificError
    switch (clientErr) {
        case QMqttClient::NoError:
            reason = DisconnectReason::UserInitiated; break;
        case QMqttClient::BadUsernameOrPassword:   // = 4
        case QMqttClient::NotAuthorized:           // = 5
            reason = DisconnectReason::AuthFailed; break;
        case QMqttClient::InvalidProtocolVersion:  // = 1
        case QMqttClient::IdRejected:              // = 2
        case QMqttClient::ServerUnavailable:       // = 3
        case QMqttClient::ProtocolViolation:       // = 257
        case QMqttClient::Mqtt5SpecificError:      // = 260
            reason = DisconnectReason::ProtocolError; break;
        case QMqttClient::TransportInvalid:        // = 256
            reason = DisconnectReason::NetworkError; break;
        default:
            reason = DisconnectReason::Unknown; break;
    }

    QString errMsg = (clientErr != QMqttClient::NoError)
                         ? QStringLiteral("[%1]").arg(static_cast<int>(clientErr))
                         : QString();

    bool wasConnected = (m_previousState == ConnectionState::Connected);
    if (reason != DisconnectReason::UserInitiated && m_autoReconnect) {
        {
            const QMutexLocker lock(&m_mutex);
            ++m_reconnectAttempt;
        }
        setState(ConnectionState::Reconnecting);
        Q_EMIT reconnecting(m_reconnectAttempt);
        qCWarning(lcMqtt) << "[Mqtt] 连接断开 (原因="
                           << static_cast<int>(reason)
                           << ")，第" << m_reconnectAttempt << "次重连...";
        startReconnectTimer();
    } else {
        setState(ConnectionState::Disconnected);
    }

    {
        const QMutexLocker lock(&m_mutex);
        m_activeSubscriptions.clear();
    }

    for (auto &cb : m_disconnectedCallbacks) cb(reason, errMsg);
    Q_EMIT disconnected(reason);
}

void MqttClientService::onQMqttErrorOccurred(QMqttClient::ClientError error)
{
    if (error == QMqttClient::NoError) return;

    QString desc;
    switch (error) {
        case QMqttClient::InvalidProtocolVersion:  desc = QStringLiteral("无效的协议版本"); break;
        case QMqttClient::IdRejected:              desc = QStringLiteral("客户端标识符被拒"); break;
        case QMqttClient::ServerUnavailable:       desc = QStringLiteral("服务端不可用"); break;
        // 注意: BadUsernameOrPassword (=4) 在 GCC 14 + QtMqtt 下有已知解析问题
        // 使用 static_cast 绕过
        case 4:  desc = QStringLiteral("用户名或密码错误"); break;
        case QMqttClient::NotAuthorized:            desc = QStringLiteral("未授权"); break;           // = 5
        case QMqttClient::TransportInvalid:        desc = QStringLiteral("传输层错误"); break;       // = 256
        case QMqttClient::ProtocolViolation:       desc = QStringLiteral("协议违规"); break;          // = 257
        case QMqttClient::UnknownError:            desc = QStringLiteral("未知错误"); break;           // = 258
        case QMqttClient::Mqtt5SpecificError:      desc = QStringLiteral("MQTT 5 特定错误"); break;    // = 260
        default: desc = QStringLiteral("错误码 (") + QString::number(static_cast<int>(error)) + QStringLiteral(")"); break;
    }

    QString fullMsg = QStringLiteral("[Mqtt] 错误: ") + desc;
    setError(fullMsg);
    qCWarning(lcMqtt) << fullMsg;
    Q_EMIT errorOccurred(fullMsg);
}

// Qt 6.8: messageReceived(const QByteArray &message, const QMqttTopicName &topic)
// 注意：参数顺序是 (payload, topic)，不是 (topic, payload)!
void MqttClientService::onQMqttMessageReceived(const QByteArray &message,
                                                 const QMqttTopicName &topic)
{
    QString topicStr = topic.name();

    qCDebug(lcMqtt) << "[Mqtt] 收到消息:" << topicStr
                     << "size=" << message.size();

    for (auto &cb : m_messageCallbacks)
        cb(topicStr, message);
    Q_EMIT messageReceived(topicStr, message);
}

void MqttClientService::onReconnectTimerTick()
{
    if (m_connectionState != ConnectionState::Disconnected
        && m_connectionState != ConnectionState::Reconnecting) {
        return;
    }

    setState(ConnectionState::Connecting);
    qCInfo(lcMqtt) << "[Mqtt] 自动重连... (第"
                   << (m_reconnectAttempt + 1) << "次)";

    bool useSsl;
    {
        const QMutexLocker lock(&m_mutex);
        useSsl = m_sslEnabled;
    }

    if (useSsl) {
        m_client->connectToHostEncrypted(m_sslConfig);
    } else {
        m_client->connectToHost();
    }
}

void MqttClientService::onKeepAliveCheck()
{
    if (m_connectionState == ConnectionState::Connected) {
        qCDebug(lcMqtt) << "[Mqtt] 心跳正常 (keepAlive="
                        << k_keepAliveSeconds << "s)";
    }
}

// ============================================================================
// 设备心跳上报：每隔 kPingIntervalMs 向 cust/{custId}/device/{sn}/up/ping 发送
// ============================================================================

void MqttClientService::startPingTimer()
{
    if (m_pingTimer && !m_pingTimer->isActive())
        m_pingTimer->start();
}

void MqttClientService::stopPingTimer()
{
    if (m_pingTimer) m_pingTimer->stop();
}

void MqttClientService::startHeartbeat(const QString &sn, qint64 custId)
{
    if (sn.isEmpty()) {
        qCWarning(lcMqtt) << "[Mqtt] startHeartbeat 失败: SN 为空";
        return;
    }

    {
        const QMutexLocker lock(&m_mutex);
        m_heartbeatSn     = sn;
        m_heartbeatCustId = custId;
    }

    qCInfo(lcMqtt) << "[Mqtt] 启动心跳上报 (间隔" << kPingIntervalMs << "ms) ->"
                   << buildPingTopic(custId, sn);

    // 已连接则立即启动并先发一次；未连接仅保存参数，待 onQMqttConnected 时启动
    if (isConnected()) {
        startPingTimer();
        onPingTick();
    }
}

void MqttClientService::stopHeartbeat()
{
    stopPingTimer();
    const QMutexLocker lock(&m_mutex);
    m_heartbeatSn.clear();
    m_heartbeatCustId = 0;
    qCInfo(lcMqtt) << "[Mqtt] 心跳上报已停止";
}

QString MqttClientService::buildPingTopic(qint64 custId, const QString &sn)
{
    return QString("cust/%1/device/%2/up/ping").arg(custId).arg(sn);
}

QByteArray MqttClientService::buildPingPayload()
{
    // 心跳仅用于保活，主题已含 custId/sn，payload 为空对象
    return QJsonDocument(QJsonObject()).toJson(QJsonDocument::Compact);
}

void MqttClientService::onPingTick()
{
    // 参数异常：停止定时器自我保护
    if (m_heartbeatSn.isEmpty()) {
        stopPingTimer();
        return;
    }

    // 仅在真正连接就绪时发送，避免离线队列堆积心跳
    bool reallyConnected;
    {
        const QMutexLocker lock(&m_mutex);
        reallyConnected = (m_connectionState == ConnectionState::Connected)
                       && (m_client->state() == QMqttClient::Connected);
    }
    if (!reallyConnected) {
        qCDebug(lcMqtt) << "[Mqtt] 心跳跳过 (连接尚未就绪)";
        Q_EMIT heartbeatSkipped();
        return;
    }

    const QString     topic   = buildPingTopic(m_heartbeatCustId, m_heartbeatSn);
    const QByteArray  payload = buildPingPayload();

    try {
        // 心跳用 QoS 0：最多一次，丢失不影响在线判断（下个周期会补）
        const int msgId = publish(topic, payload, QoSLevel::AtMostOnce, false);
        if (msgId >= 0) {
            Q_EMIT heartbeatSent(topic);
            qCDebug(lcMqtt) << "[Mqtt] 心跳已发送:" << topic;
        } else {
            qCWarning(lcMqtt) << "[Mqtt] 心跳发送失败 (publish 返回" << msgId << ")";
        }
    } catch (const std::exception &e) {
        qCWarning(lcMqtt) << "[Mqtt] 心跳发送异常:" << e.what();
        setError(QStringLiteral("[Mqtt] 心跳发送异常: ") + QString::fromUtf8(e.what()));
    } catch (...) {
        qCWarning(lcMqtt) << "[Mqtt] 心跳发送未知异常";
        setError(QStringLiteral("[Mqtt] 心跳发送未知异常"));
    }
}

// ============================================================================
// 设备状态上报：每隔 kStatusIntervalMs 向 cust/{custId}/device/{sn}/up/status 发送
//   参数: temp = 设备温度(℃), ip = 设备当前联网 IP
// ============================================================================

void MqttClientService::startStatusTimer()
{
    if (m_statusTimer && !m_statusTimer->isActive())
        m_statusTimer->start();
}

void MqttClientService::stopStatusTimer()
{
    if (m_statusTimer) m_statusTimer->stop();
}

void MqttClientService::startDeviceStatusReport(const QString &sn,
                                                qint64 custId,
                                                int intervalMs)
{
    if (sn.isEmpty()) {
        qCWarning(lcMqtt) << "[Mqtt] startDeviceStatusReport 失败: SN 为空";
        return;
    }

    {
        const QMutexLocker lock(&m_mutex);
        m_statusSn     = sn;
        m_statusCustId = custId;
        if (intervalMs >= 1000)
            m_statusTimer->setInterval(intervalMs);
    }

    qCInfo(lcMqtt) << "[Mqtt] 启动设备状态上报 (间隔"
                   << m_statusTimer->interval() << "ms) ->"
                   << buildStatusTopic(custId, sn);

    // 已连接则立即启动并先发一次；未连接仅保存参数，待 onQMqttConnected 时启动
    if (isConnected()) {
        startStatusTimer();
        onStatusTick();
    }
}

void MqttClientService::stopDeviceStatusReport()
{
    stopStatusTimer();
    const QMutexLocker lock(&m_mutex);
    m_statusSn.clear();
    m_statusCustId    = 0;
    m_lastReportedIp.clear();
    qCInfo(lcMqtt) << "[Mqtt] 设备状态上报已停止";
}

QString MqttClientService::buildStatusTopic(qint64 custId, const QString &sn)
{
    return QString("cust/%1/device/%2/up/status").arg(custId).arg(sn);
}

QByteArray MqttClientService::buildStatusPayload(double tempCelsius,
                                                 const QString &ip)
{
    QJsonObject obj;
    // temp: 无法读取(-1.0)时记为 null
    if (tempCelsius >= 0.0)
        obj[QStringLiteral("temp")] = tempCelsius;
    else
        obj[QStringLiteral("temp")] = QJsonValue(QJsonValue::Null);
    // ip: 无法获取时记为 null
    if (!ip.isEmpty())
        obj[QStringLiteral("ip")] = ip;
    else
        obj[QStringLiteral("ip")] = QJsonValue(QJsonValue::Null);
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

double MqttClientService::getDeviceTemperatureCelsius()
{
    // 方案: 读取 Linux thermal zone (温度单位为毫摄氏度)
    // 取所有可用 zone 中的最大值（通常代表 CPU/主板温度）
    QDir thermalDir(QStringLiteral("/sys/class/thermal"));
    if (!thermalDir.exists())
        return -1.0;

    const QStringList entries = thermalDir.entryList(
        QStringList() << QStringLiteral("thermal_zone*"),
        QDir::Dirs | QDir::NoDotAndDotDot);
    if (entries.isEmpty())
        return -1.0;

    double maxTemp = -1.0;
    for (const QString &entry : entries) {
        QFile f(thermalDir.filePath(entry) + QStringLiteral("/temp"));
        if (!f.open(QIODevice::ReadOnly))
            continue;
        bool ok = false;
        const qlonglong milli = f.readAll().trimmed().toLongLong(&ok);
        f.close();
        if (ok && milli > 0) {
            const double c = static_cast<double>(milli) / 1000.0;
            if (c > maxTemp) maxTemp = c;
        }
    }
    return maxTemp;   // 无有效读数返回 -1.0
}

QString MqttClientService::getCurrentLocalIp()
{
    // 方案: 通过 UDP "连接" 到一个公网地址（不实际发包），
    //       让操作系统选定出口网卡，从而读取设备当前联网 IP。
    QUdpSocket s;
    s.connectToHost(QStringLiteral("8.8.8.8"), 53, QIODevice::ReadOnly);
    const QHostAddress addr = s.localAddress();
    s.close();
    if (!addr.isNull() && addr != QHostAddress::LocalHost
        && addr.protocol() == QAbstractSocket::IPv4Protocol) {
        return addr.toString();
    }

    // 回退: 遍历所有网卡，取第一个已启用、非回环、非链路本地、有 IPv4 且非 169.254 的地址
    const QList<QNetworkInterface> ifaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : ifaces) {
        if (!(iface.flags() & QNetworkInterface::IsUp)
            || !(iface.flags() & QNetworkInterface::IsRunning)
            || (iface.flags() & QNetworkInterface::IsLoopBack))
            continue;
        for (const QNetworkAddressEntry &entry : iface.addressEntries()) {
            const QHostAddress a = entry.ip();
            if (a.protocol() == QAbstractSocket::IPv4Protocol
                && !a.isLoopback()
                && !a.toString().startsWith(QStringLiteral("169.254."))) {
                return a.toString();
            }
        }
    }
    return QString();
}

void MqttClientService::onStatusTick()
{
    // 参数异常：停止定时器自我保护
    if (m_statusSn.isEmpty()) {
        stopStatusTimer();
        return;
    }

    // 仅在真正连接就绪时发送，避免离线队列堆积状态
    bool reallyConnected;
    {
        const QMutexLocker lock(&m_mutex);
        reallyConnected = (m_connectionState == ConnectionState::Connected)
                       && (m_client->state() == QMqttClient::Connected);
    }
    if (!reallyConnected) {
        qCDebug(lcMqtt) << "[Mqtt] 状态上报跳过 (连接尚未就绪)";
        Q_EMIT statusSkipped();
        return;
    }

    // 采集设备温度与 IP
    const double temp = getDeviceTemperatureCelsius();
    const QString ip   = getCurrentLocalIp();

    {
        const QMutexLocker lock(&m_mutex);
        // IP 未变化且本轮非首次→仍按周期上报；若 IP 变化则记录（下个周期自然带上最新值）
        m_lastReportedIp = ip;
    }

    const QString     topic   = buildStatusTopic(m_statusCustId, m_statusSn);
    const QByteArray  payload = buildStatusPayload(temp, ip);

    try {
        // 状态用 QoS 1：确保平台可靠收到；断连时由 onStatusTick 跳过，不在离线队列堆积
        const int msgId = publish(topic, payload, QoSLevel::AtLeastOnce, false);
        if (msgId >= 0) {
            Q_EMIT statusReported(topic);
            qCInfo(lcMqtt) << "[Mqtt] 状态已上报:" << topic
                           << "temp=" << (temp >= 0.0 ? QString::number(temp, 'f', 1) + "C" : "N/A")
                           << "ip=" << (ip.isEmpty() ? "N/A" : ip);
        } else {
            qCWarning(lcMqtt) << "[Mqtt] 状态上报失败 (publish 返回" << msgId << ")";
        }
    } catch (const std::exception &e) {
        qCWarning(lcMqtt) << "[Mqtt] 状态上报异常:" << e.what();
        setError(QStringLiteral("[Mqtt] 状态上报异常: ") + QString::fromUtf8(e.what()));
    } catch (...) {
        qCWarning(lcMqtt) << "[Mqtt] 状态上报未知异常";
        setError(QStringLiteral("[Mqtt] 状态上报未知异常"));
    }
}

// ============================================================================
// 下行命令监听：订阅 cust/{custId}/device/{sn}/down/cmd
//   命令字: close(预留) / restart(重启) / exituser(退出登录)
//   附带 time 字段: 多少毫秒后执行
// ============================================================================

void MqttClientService::startCommandListener(const QString &sn, qint64 custId)
{
    if (sn.isEmpty()) {
        qCWarning(lcMqtt) << "[Mqtt] startCommandListener 失败: SN 为空";
        return;
    }

    {
        const QMutexLocker lock(&m_mutex);
        m_cmdSn     = sn;
        m_cmdCustId = custId;
        m_cmdTopic  = buildCommandTopic(custId, sn);
    }

    qCInfo(lcMqtt) << "[Mqtt] 启动下行命令监听 ->" << m_cmdTopic;

    // 订阅（未连接时由 subscribe 内部缓存，连接成功后自动执行；
    //       已连接过一次后续重连由 QMqttClient 自动重订阅）
    subscribe(m_cmdTopic, QoSLevel::AtLeastOnce);
}

QString MqttClientService::buildCommandTopic(qint64 custId, const QString &sn)
{
    return QString("cust/%1/device/%2/down/cmd").arg(custId).arg(sn);
}

void MqttClientService::onCommandMessage(const QString &topic, const QByteArray &payload)
{
    // 仅处理本设备下行命令主题
    if (topic != m_cmdTopic)
        return;

    // 解析 JSON 命令
    const QJsonObject obj = QJsonDocument::fromJson(payload).object();
    const QString cmd = obj.value(QStringLiteral("cmd")).toString().trimmed();
    if (cmd.isEmpty()) {
        qCWarning(lcMqtt) << "[Mqtt] 下行命令缺少 cmd 字段:" << payload;
        return;
    }

    // time: 多少毫秒后执行 (缺省/非法 -> 立即执行)
    const QJsonValue timeVal = obj.value(QStringLiteral("time"));
    qint64 timeMs = 0;
    if (timeVal.isDouble())
        timeMs = static_cast<qint64>(timeVal.toDouble());
    else if (timeVal.isString())
        timeMs = timeVal.toString().toLongLong();
    if (timeMs < 0) timeMs = 0;

    qCInfo(lcMqtt) << "[Mqtt] 收到下行命令:" << cmd
                   << "(time=" << timeMs << "ms)";

    // close / restart / exituser 之外的命令字不做特殊处理，原样抛出
    Q_EMIT deviceCommandReceived(cmd, timeMs);
}

// ============================================================================
// 上行告警上报：cust/{custId}/device/{sn}/up/alarm (预留触发点)
//   参数: type(告警类型) / msg(告警信息) / ts(告警时间戳)
// ============================================================================

int MqttClientService::publishAlarm(const QString &type,
                                    const QString &msg,
                                    qint64 ts)
{
    QString sn;
    qint64 custId;
    {
        const QMutexLocker lock(&m_mutex);
        sn     = m_statusSn;
        custId = m_statusCustId;
    }
    if (sn.isEmpty() || custId <= 0) {
        qCWarning(lcMqtt) << "[Mqtt] 告警上报失败: 状态上报参数未配置 (sn/custId)";
        return -1;
    }

    const QString     topic   = buildAlarmTopic(custId, sn);
    const QByteArray  payload = buildAlarmPayload(type, msg, ts);
    return publish(topic, payload, QoSLevel::AtLeastOnce, false);
}

QString MqttClientService::buildAlarmTopic(qint64 custId, const QString &sn)
{
    return QString("cust/%1/device/%2/up/alarm").arg(custId).arg(sn);
}

QByteArray MqttClientService::buildAlarmPayload(const QString &type,
                                               const QString &msg,
                                               qint64 ts)
{
    QJsonObject obj;
    obj[QStringLiteral("type")] = type.isEmpty() ? QJsonValue(QJsonValue::Null) : type;
    obj[QStringLiteral("msg")]  = msg.isEmpty()   ? QJsonValue(QJsonValue::Null) : msg;
    // ts: 缺省(<=0)使用当前时间戳
    const qint64 stamp = (ts > 0) ? ts : QDateTime::currentMSecsSinceEpoch();
    obj[QStringLiteral("ts")] = stamp;
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

// ============================================================================
// 回调注册
// ============================================================================

void MqttClientService::onMessageReceived(MessageCallback cb)
{ const QMutexLocker lock(&m_mutex); m_messageCallbacks.append(cb); }
void MqttClientService::onConnected(ConnectionCallback cb)
{ const QMutexLocker lock(&m_mutex); m_connectedCallbacks.append(cb); }
void MqttClientService::onDisconnected(DisconnectCallback cb)
{ const QMutexLocker lock(&m_mutex); m_disconnectedCallbacks.append(cb); }
void MqttClientService::onStateChanged(StateChangeCallback cb)
{ const QMutexLocker lock(&m_mutex); m_stateChangeCallbacks.append(cb); }

// ============================================================================
// shxgs MQTT Broker 接入（user.shxgs.cn:8888）
// ============================================================================

void MqttClientService::initAndConnect(const QString &sn, qint64 custId)
{
    if (sn.isEmpty()) {
        setError(QStringLiteral("[MqttShxgs] 设备序列号 (SN) 不能为空"));
        Q_EMIT errorOccurred(m_lastError);
        return;
    }

    // ---- 1. 密码管理: 首次生成 / 后续复用 ----
    QSettings settings;
    settings.beginGroup(QLatin1String(kSettingsGroup));
    m_storedPassword = settings.value(
        QLatin1String(kSettingsKeyPwd)).toString();
    settings.endGroup();

    if (m_storedPassword.isEmpty()) {
        m_storedPassword = generateRandomPassword(16);

        settings.beginGroup(QLatin1String(kSettingsGroup));
        settings.setValue(QLatin1String(kSettingsKeyPwd), m_storedPassword);
        settings.endGroup();
        settings.sync();

        qCInfo(lcMqtt) << "[MqttShxgs] 首次连接，已生成随机密码 ("
                       << m_storedPassword.size() << "位) 并持久化";
    } else {
        qCDebug(lcMqtt) << "[MqttShxgs] 使用已存储的密码 ("
                        << m_storedPassword.size() << "位)";
    }

    // ---- 2. 配置 Broker 参数 ----
    setHost(QLatin1String(kShxgsHost));
    setPort(kShxgsPort);                          // 8888
    enableSsl(true);                              // mqtts://
    setClientId(sn);
    setUsername(sn);
    setPassword(m_storedPassword);
    setAutoReconnect(true);
    setReconnectIntervalMs(5000);
    setMaxReconnectAttempts(0);
    setKeepAliveSeconds(60);
    setProtocolVersion(4);                        // MQTT 3.1.1

    // SSL 配置
    setPeerVerifyMode(QSslSocket::VerifyNone);   // 先宽松模式，后续按需调整

    {
        const QMutexLocker lock(&m_mutex);
        m_custId = custId;
    }

    // Last-Will
//     QString willTopic = buildDeviceTopic(custId, sn);
//     QJsonObject willObj;
//     willObj[QStringLiteral("hardver")] = QString();
//     willObj[QStringLiteral("softver")] = QString();
//     willObj[QStringLiteral("sim")]     = QString();
//    // willObj[QStringLiteral("status")]  = QStringLiteral("offline");
//     QByteArray willMsg = QJsonDocument(willObj).toJson(QJsonDocument::Compact);
//     setWillMessage(willTopic, willMsg, QoSLevel::AtLeastOnce, false);

    qCInfo(lcMqtt) << "[MqttShxgs] 初始化完成:"
                    << "\n  Broker:   mqtts://" << kShxgsHost << ":" << kShxgsPort
                    << "\n  ClientId: " << sn
                    << "\n  Username: " << sn
                    << "\n  Password: " << m_storedPassword
                    << "\n  CustId:   " << custId;
                   // << "\n  Will:     " << willTopic;

    // 调试用：方便用外部客户端测试时直接拿到 (SN / Password)
    qInfo().noquote() << "[MqttShxgs-DEBUG] 配置文件:" << settings.fileName()
                       << "\n[MqttShxgs-DEBUG] SN/Username =" << sn
                       << "\n[MqttShxgs-DEBUG] Password     =" << m_storedPassword;

    // ---- 3. 发起连接 ----
    connectToBroker();
}

int MqttClientService::publishDeviceInfo(const QString &sn,
                                          qint64 custId,
                                          const QString &hardVer,
                                          const QString &softVer,
                                          const QString &sim,
                                          const QString &revision,
                                          const QString &serial)
{
    QString topic = buildDeviceTopic(custId, sn);
    QByteArray payload = buildInfoPayload(hardVer, softVer, sim, revision, serial);

    return publish(topic, payload, QoSLevel::AtLeastOnce);
}

QString MqttClientService::buildDeviceTopic(qint64 custId, const QString &sn)
{
    return QString("cust/%1/device/%2/up/info").arg(custId).arg(sn);
}

QByteArray MqttClientService::buildInfoPayload(const QString &hardVer,
                                               const QString &softVer,
                                               const QString &sim,
                                               const QString &revision,
                                               const QString &serial)
{
    QJsonObject obj;
    obj[QStringLiteral("hardver")]   = hardVer.isEmpty()   ? QString() : hardVer;
    obj[QStringLiteral("softver")]   = softVer.isEmpty()   ? QString() : softVer;
    obj[QStringLiteral("sim")]       = sim.isEmpty()       ? QString() : sim;
    obj[QStringLiteral("revision")]  = revision.isEmpty()  ? QString() : revision;
    obj[QStringLiteral("serial")]    = serial.isEmpty()    ? QString() : serial;
    return QJsonDocument(obj).toJson(QJsonDocument::Compact);
}

QString MqttClientService::generateRandomPassword(int length)
{
    static constexpr const char kCharset[] =
        "abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    static constexpr int kCharsetSize = sizeof(kCharset) - 1;

    QString pwd;
    pwd.reserve(length);
    auto *gen = QRandomGenerator::global();
    for (int i = 0; i < length; ++i) {
        pwd.append(kCharset[gen->bounded(kCharsetSize)]);
    }
    return pwd;
}

QString MqttClientService::storedPassword() const
{
    const QMutexLocker lock(&m_mutex);
    return m_storedPassword;
}
