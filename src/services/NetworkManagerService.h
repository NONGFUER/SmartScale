#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>
#include <QRegularExpression>

/**
 * @brief 网络管理服务 — 统一管理 Wi-Fi 和 4G 网络
 *
 * 技术方案（Linux 嵌入式环境）：
 *   - Wi-Fi: 通过 nmcli (NetworkManager CLI) 控制
 *   - 4G:    通过 mmcli (ModemManager CLI) 控制
 *   - 权限:  需要 sudo 或用户在 networkmanager/plugdev 组
 *
 * QML 绑定名: App.Backend::NetworkManager
 */
class NetworkManagerService : public QObject
{
    Q_OBJECT

    // ===== Wi-Fi 属性 (QML 可绑定) =====
    Q_PROPERTY(WifiStatus     wifiStatus       READ wifiStatus       NOTIFY wifiStatusChanged)
    Q_PROPERTY(QString        wifiSsid         READ wifiSsid         NOTIFY wifiStatusChanged)
    Q_PROPERTY(int            wifiSignal       READ wifiSignal       NOTIFY wifiStatusChanged)
    Q_PROPERTY(QString        wifiIpAddress    READ wifiIpAddress    NOTIFY wifiStatusChanged)
    Q_PROPERTY(QVariantList  availableNetworks READ availableNetworks NOTIFY networksUpdated)
    Q_PROPERTY(bool           isScanning       READ isScanning       NOTIFY scanningChanged)

    // ===== 4G 属性 (QML 可绑定) =====
    Q_PROPERTY(CellularStatus cellularStatus   READ cellularStatus   NOTIFY cellularStatusChanged)
    Q_PROPERTY(int            cellularSignal   READ cellularSignal   NOTIFY cellularStatusChanged)
    Q_PROPERTY(QString        cellularOperator READ cellularOperator NOTIFY cellularStatusChanged)
    Q_PROPERTY(QString        cellularIpAddress READ cellularIpAddr  NOTIFY cellularStatusChanged)

public:
    enum class WifiStatus {
        Unknown     = 0,
        Disabled    = 1,
        Disconnected= 2,
        Connecting  = 3,
        Connected   = 4,
        Error       = 5
    };
    Q_ENUM(WifiStatus)

    enum class CellularStatus {
        Unknown     = 0,
        Disabled    = 1,
        Searching   = 2,
        Registered  = 3,
        Connected   = 4,
        Roaming     = 5,
        Error       = 6
    };
    Q_ENUM(CellularStatus)

    explicit NetworkManagerService(QObject *parent = nullptr);

    // === Getter ===
    WifiStatus     wifiStatus()       const { return m_wifiStatus; }
    QString        wifiSsid()         const { return m_wifiSsid; }
    int            wifiSignal()       const { return m_wifiSignal; }
    QString        wifiIpAddress()    const { return m_wifiIpAddress; }
    QVariantList  availableNetworks() const { return m_availableNetworks; }
    bool           isScanning()       const { return m_isScanning; }

    CellularStatus cellularStatus()   const { return m_cellularStatus; }
    int            cellularSignal()   const { return m_cellularSignal; }
    QString        cellularOperator() const { return m_cellularOperator; }
    QString        cellularIpAddr()   const { return m_cellularIpAddress; }

    // ===== Wi-Fi 操作 =====
    /** @brief 扫描可用 Wi-Fi 网络（异步，结果通过 networksUpdated 信号通知） */
    Q_INVOKABLE void scanWifiNetworks();

    /**
     * @brief 连接到指定 Wi-Fi
     * @param ssid 服务集标识符（网络名称）
     * @param password 密码（开放网络传空字符串）
     */
    Q_INVOKABLE void connectWifi(const QString &ssid, const QString &password = QString());

    /** @brief 断开当前 Wi-Fi 连接 */
    Q_INVOKABLE void disconnectWifi();

    /** @brief 刷新当前 Wi-Fi 状态 */
    Q_INVOKABLE void refreshWifiStatus();

    // ===== 4G 操作 =====
    /** @brief 开启 4G 移动数据 */
    Q_INVOKABLE void enableCellular();

    /** @brief 关闭 4G 移动数据 */
    Q_INVOKABLE void disableCellular();

    /** @brief 刷新 4G 状态 */
    Q_INVOKABLE void refreshCellularStatus();

    // ===== 权限检查 =====
    /** @brief 检查是否有足够的权限执行网络操作 */
    Q_INVOKABLE bool checkPermissions();

    /** @brief 获取最后的错误信息 */
    Q_INVOKABLE QString lastError() const { return m_lastError; }

Q_SIGNALS:
    // Wi-Fi 信号
    void wifiStatusChanged();
    void networksUpdated();
    void scanningChanged(bool isScanning);
    void wifiConnectionSuccess(const QString &ssid);
    void wifiConnectionFailed(const QString &errorMsg);

    // 4G 信号
    void cellularStatusChanged();
    void cellularEnabled();
    void cellularDisabled();
    void cellularOperationFailed(const QString &errorMsg);

private Q_SLOTS:
    void onWifiScanFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiConnectionAdded(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiConnectFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiDisconnectFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onCellularOpFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStatusPollTimer();

private:
    // === 内部方法 ===
    bool hasNetworkManager() const;
    bool hasModemManager() const;

    void parseWifiScanOutput(const QString &output);
    void updateCellularStatusFromMmcli(const QString &output);

    int signalQualityToPercent(const QString &qualityStr) const;

    /** @brief 获取 Wi-Fi 列表（扫描完成后调用） */
    void fetchWifiList();

    /** @brief 通过 mmcli 启用 4G */
    void enableCellularViaModem();
    /** @brief 通过 mmcli 禁用 4G */
    void disableCellularViaModem();

    /** @brief 内部设置 Wi-Fi 状态（触发信号） */
    void setWifiStatus(WifiStatus status);
    /** @brief 内部设置 4G 状态（触发信号） */
    void setCellularStatus(CellularStatus status);

    /** @brief 清理 SSID 中的特殊字符，生成合法的 nmcli 连接名 */
    QString sanitizeConnectionName(const QString &ssid) const;

    /** @brief 从 nmcli -t 输出中提取纯 SSID（剥离 "field.name:" 前缀） */
    static QString extractSsidValue(const QString &rawOutput);

    // === 成员变量 ===
    WifiStatus     m_wifiStatus      = WifiStatus::Unknown;
    QString        m_wifiSsid;
    int            m_wifiSignal      = 0;          // 0-100
    QString        m_wifiIpAddress;
    QVariantList  m_availableNetworks; // [{ssid, signal, secured, bssid}, ...]
    bool           m_isScanning       = false;

    CellularStatus m_cellularStatus  = CellularStatus::Unknown;
    int            m_cellularSignal  = 0;          // 0-100
    QString        m_cellularOperator;
    QString        m_cellularIpAddress;

    QString        m_lastError;
    bool           m_pendingCellularOp = false;  // true=启用, false=禁用

    // 两步连接法：创建配置 → 激活 之间的中间状态
    QString        m_pendingSsid;                 // 正在连接的 SSID
    QString        m_pendingConnectionName;       // 已创建但尚未激活的连接名称

    // 异步进程（每次操作复用）
    QProcess      *m_process         = nullptr;

    // 状态轮询定时器（每 10 秒刷新一次状态）
    QTimer        *m_statusPollTimer = nullptr;
};
