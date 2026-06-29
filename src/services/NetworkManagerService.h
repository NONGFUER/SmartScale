#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QProcess>
#include <QTimer>
#include <QElapsedTimer>
#include <QVariantMap>
#include <QRegularExpression>
#include <functional>

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
    /** @brief 是否检测到任何 4G 硬件（modem 或网络接口模式） */
    Q_PROPERTY(bool            hasCellularHardware READ hasCellularHardware NOTIFY cellularHardwareChanged)
    /** @brief 最后的错误信息（QML 可绑定） */
    Q_PROPERTY(QString         lastError           READ lastError           NOTIFY lastErrorChanged)

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
        CellUnknown   = 0,
        CellDisabled  = 1,
        CellSearching = 2,
        CellRegistered = 3,
        CellConnected = 4,
        CellRoaming   = 5,
        CellError     = 6
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
    bool            hasCellularHardware() const { return m_hasCellularHardware; }

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
    QString lastError() const { return m_lastError; }

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
    /** @brief 4G 硬件检测状态变化（用于 UI 更新开关可用状态） */
    void cellularHardwareChanged(bool hasHardware);
    /** @brief 错误信息变化（用于 QML 绑定刷新） */
    void lastErrorChanged();

private Q_SLOTS:
    void onWifiScanFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiConnectionAdded(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiConnectFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onWifiDisconnectFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onCellularOpFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onStatusPollTimer();

private:
    // === 内部方法 ===
    /**
     * @brief 确保在主线程执行属性更新（跨线程时自动通过 QMetaObject 投递）
     *
     * 解决 QtConcurrent::run 工作线程直接修改 Q_PROPERTY + emit 信号
     * 导致的竞态条件，该竞态会导致 QML 绑定引擎异常、子树渲染崩溃。
     */
    template<typename Func>
    void runOnMainThread(Func&& func);

    bool hasNetworkManager() const;
    bool hasModemManager() const;

    /** @brief 动态发现 WiFi 设备名（兼容 wlan0/wlp2s0/mlan0 等不同命名） */
    QString discoverWifiDevice() const;

    /** @brief 在多个候选路径中查找第一个存在的可执行文件 */
    static QString findExecutable(const char *paths[]);

    void parseWifiScanOutput(const QString &output);
    void updateCellularStatusFromMmcli(const QString &output);
    /** @brief 从 nmcli device show 输出解析 4G 状态（以太网模式） */
    void updateCellularStatusFromNmcli(const QString &output, const QString &device);

    int signalQualityToPercent(const QString &qualityStr) const;

    /** @brief 获取 Wi-Fi 列表（扫描完成后调用） */
    void fetchWifiList();

    /** @brief 通过 mmcli 启用 4G */
    void enableCellularViaModem();
    /** @brief 通过 mmcli 禁用 4G */
    void disableCellularViaModem();

    /** @brief 通过 nmcli 连接启用 4G（以太网模式） */
    void enableCellularViaDevice();

    /** @brief 通过 nmcli 断开禁用 4G（以太网模式） */
    void disableCellularViaDevice();

    /** @brief 动态发现 4G 调制解调器索引，返回字符串（如 "0"），失败返回空串 */
    QString discoverModemIndex() const;

    /**
     * @brief 发现 4G 网络接口设备名（适用于 4G 模块以以太网模式工作的场景）
     *
     * 检测策略（按优先级）：
     *   1. 遍历 nmcli device 列表，查找类型为 ethernet 且连接配置名含 gsm/mobile/cellular 关键字的设备
     *   2. fallback：检查已知常见 4G 接口名（eth1, usb0, enx* 等）
     * 返回设备名（如 "eth1"），失败返回空串
     */
    QString discoverCellularDevice() const;

    /** @brief 内部设置 Wi-Fi 状态（触发信号） */
    void setWifiStatus(WifiStatus status);
    /** @brief 内部设置 4G 状态（触发信号） */
    void setCellularStatus(CellularStatus status);

    /** @brief 内部设置错误信息（触发信号，供 QML 绑定） */
    void setLastError(const QString &error);

    /** @brief 更新 4G 硬件检测状态（仅在值变化时发射信号） */
    void updateHasCellularHardware(bool hasHardware);

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

    CellularStatus m_cellularStatus  = CellularStatus::CellUnknown;
    int            m_cellularSignal  = 0;          // 0-100
    QString        m_cellularOperator;
    QString        m_cellularIpAddress;

    /** @brief 检测到的 4G 网络接口设备名（如 "eth1"），用于以太网模式的 4G 模块 */
    mutable QString m_cellularDeviceName;

    /** @brief 是否检测到任何 4G 硬件（modem 或网络接口模式） */
    bool           m_hasCellularHardware = false;

    QString        m_lastError;
    bool           m_pendingCellularOp = false;  // true=启用, false=禁用

    // 两步连接法：创建配置 → 激活 之间的中间状态
    QString        m_pendingSsid;                 // 正在连接的 SSID
    QString        m_pendingConnectionName;       // 已创建但尚未激活的连接名称

    // 用户主动断开 WiFi 后的防回退保护（防止轮询定时器读取 nmcli 缓存状态刷回 Connected）
    QElapsedTimer  m_disconnectTime;              // 断开操作成功时记录时间点，无效表示未处于保护窗口

    // 异步进程（每次操作复用）
    QProcess      *m_process         = nullptr;

    // 工具实际路径（构造时从候选列表中解析，兼容不同发行版）
    QString        m_nmcliPath;
    QString        m_mmcliPath;

    // 状态轮询定时器（每 10 秒刷新一次状态）
    QTimer        *m_statusPollTimer = nullptr;
};
