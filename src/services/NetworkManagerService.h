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
    /** @brief 用户对 4G 的意图状态（点击即置位，不等待真实命令）。UI 开关/信号图标据此即时反馈 */
    Q_PROPERTY(bool           cellularUiActive READ cellularUiActive NOTIFY cellularUiActiveChanged)
    Q_PROPERTY(int            cellularSignal   READ cellularSignal   NOTIFY cellularStatusChanged)
    Q_PROPERTY(QString        cellularOperator READ cellularOperator NOTIFY cellularStatusChanged)
    Q_PROPERTY(QString        cellularIpAddress READ cellularIpAddr  NOTIFY cellularStatusChanged)
    /** @brief 是否检测到任何 4G 硬件（modem 或网络接口模式） */
    Q_PROPERTY(bool            hasCellularHardware READ hasCellularHardware NOTIFY cellularHardwareChanged)
    /** @brief 最后的错误信息（QML 可绑定） */
    Q_PROPERTY(QString         lastError           READ lastError           NOTIFY lastErrorChanged)
    /** @brief 当前网络模式（NetworkMode 枚举值，-1 表示未知/未通过本接口设置） */
    Q_PROPERTY(int             networkMode         READ networkMode         NOTIFY networkModeChanged)

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

    /** @brief 网络模式（设备信息弹窗四选一控制） */
    enum class NetworkMode {
        WifiOnly          = 0,  // 仅开启 WIFI，关闭 4G
        CellularOnly      = 1,  // 仅开启 4G，关闭 WIFI
        AllWifiPriority   = 2,  // WIFI + 4G 全开，优先 WIFI（默认路由走 WIFI）
        AllCellularPriority = 3 // WIFI + 4G 全开，优先 4G（默认路由走 4G）
    };
    Q_ENUM(NetworkMode)

    explicit NetworkManagerService(QObject *parent = nullptr);

    // === Getter ===
    WifiStatus     wifiStatus()       const { return m_wifiStatus; }
    QString        wifiSsid()         const { return m_wifiSsid; }
    int            wifiSignal()       const { return m_wifiSignal; }
    QString        wifiIpAddress()    const { return m_wifiIpAddress; }
    QVariantList  availableNetworks() const { return m_availableNetworks; }
    bool           isScanning()       const { return m_isScanning; }

    CellularStatus cellularStatus()   const { return m_cellularStatus; }
    bool           cellularUiActive() const { return m_cellularUiActive; }
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

    /** @brief 开启/关闭 Wi-Fi 射频（nmcli radio wifi on/off） */
    Q_INVOKABLE void setWifiEnabled(bool enabled);

    /** @brief 设置网络模式（四选一：仅WIFI/仅4G/全开优先WIFI/全开优先4G） */
    Q_INVOKABLE void setNetworkMode(NetworkMode mode);

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
    void cellularUiActiveChanged();
    void cellularEnabled();
    void cellularDisabled();
    void cellularOperationFailed(const QString &errorMsg);
    /** @brief 4G 硬件检测状态变化（用于 UI 更新开关可用状态） */
    void cellularHardwareChanged(bool hasHardware);
    /** @brief 错误信息变化（用于 QML 绑定刷新） */
    void lastErrorChanged();
    /** @brief 网络模式变化（用于 UI 高亮当前选中按钮） */
    void networkModeChanged();

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

    /** @brief 快速刷新 4G 状态：用 ip a 读接口 UP/DOWN，毫秒级，不等 mmcli */
    void refreshCellularStatusFast();

    /** @brief 用 ip a 快速发现 4G 网络接口（候选 eth1/usb0/wwan0/ppp0/enx*） */
    QString findCellularInterfaceFast() const;

    /** @brief 命令发出后启动短定时快速刷新（500/1500/2500ms），快速脱离 CellSearching */
    void scheduleFastCellularRefresh();

    /** @brief 内部设置 Wi-Fi 状态（触发信号） */
    void setWifiStatus(WifiStatus status);
    /** @brief 内部设置 4G 状态（触发信号） */
    void setCellularStatus(CellularStatus status);

    /** @brief 内部设置错误信息（触发信号，供 QML 绑定） */
    void setLastError(const QString &error);

    /** @brief 当前网络模式读取（供 QML 绑定高亮） */
    int networkMode() const { return m_networkMode; }

    // === 网络模式（路由优先级）辅助 ===
    /** @brief 查找当前已连接的 Wi-Fi 连接配置名（用于设置路由 metric） */
    QString findActiveWifiConnection() const;
    /** @brief 查找 4G 连接配置名（modem 模式的 gsm 连接 / 接口模式的设备连接） */
    QString findCellularConnection() const;
    /** @brief 设置指定连接的 IPv4/IPv6 路由 metric（值越小优先级越高） */
    void setConnectionRouteMetric(const QString &conn, int metric);
    /** @brief 重新激活指定连接，使新的路由 metric 立即生效 */
    void reactivateConnection(const QString &conn);
    /** @brief 应用路由优先级：优先接口走低 metric，非优先走高 metric 并重新激活优先连接 */
    void applyRoutePriority(bool preferWifi);

    /** @brief 更新 4G 硬件检测状态（仅在值变化时发射信号） */
    void updateHasCellularHardware(bool hasHardware);

    /** @brief 清理 SSID 中的特殊字符，生成合法的 nmcli 连接名 */
    QString sanitizeConnectionName(const QString &ssid) const;

    /** @brief 从 nmcli -t 输出中提取纯 SSID（剥离 "field.name:" 前缀） */
    static QString extractSsidValue(const QString &rawOutput);

    /** @brief 查找指定 SSID 的现有 nmcli 连接名，返回连接名（空串表示不存在） */
    QString findExistingConnection(const QString &ssid) const;

    /** @brief 删除指定的 nmcli 连接配置 */
    void deleteConnection(const QString &connName);

    // === 成员变量 ===
    WifiStatus     m_wifiStatus      = WifiStatus::Unknown;
    QString        m_wifiSsid;
    int            m_wifiSignal      = 0;          // 0-100
    QString        m_wifiIpAddress;
    QVariantList  m_availableNetworks; // [{ssid, signal, secured, bssid}, ...]
    bool           m_isScanning       = false;

    CellularStatus m_cellularStatus  = CellularStatus::CellUnknown;
    bool           m_cellularUiActive = false;     // 用户对 4G 的意图（点击即置位，供 UI 即时反馈）
    int            m_cellularSignal  = 0;          // 0-100
    QString        m_cellularOperator;
    QString        m_cellularIpAddress;

    /**
     * @brief 连续"未检测到 4G 设备"的轮询次数（去抖计数）。
     * 偶发 1~2 次 mmcli/nmcli 查询超时或 modem 暂不可见，不代表 4G 真断网；
     * 只有连续达到 kCellLostThreshold 次才判定为断网，避免状态栏 4G 图标闪 Signal0。
     */
    int            m_cellLostStreak = 0;
    static constexpr int kCellLostThreshold = 2;   // 连续 2 次（约 16s）才判断网

    /** @brief 检测到的 4G 网络接口设备名（如 "eth1"），用于以太网模式的 4G 模块 */
    mutable QString m_cellularDeviceName;

    /** @brief 是否检测到任何 4G 硬件（modem 或网络接口模式） */
    bool           m_hasCellularHardware = false;

    QString        m_lastError;
    bool           m_pendingCellularOp = false;  // true=启用, false=禁用
    bool           m_fastExpectEnable = false;   // 快速刷新方向：true=正在开启(无IP也保持Searching), false=正在关闭(无IP即Disabled)

    /** @brief 当前网络模式（NetworkMode 枚举值，-1 未知） */
    int            m_networkMode = -1;

    // 两步连接法：创建配置 → 激活 之间的中间状态
    QString        m_pendingSsid;                 // 正在连接的 SSID
    QString        m_pendingConnectionName;       // 已创建但尚未激活的连接名称
    QString        m_pendingPassword;              // 缓存正在连接的 WiFi 密码（用于失败时自动重建）

    // 用户主动断开 WiFi 后的防回退保护（防止轮询定时器读取 nmcli 缓存状态刷回 Connected）
    QElapsedTimer  m_disconnectTime;              // 断开操作成功时记录时间点，无效表示未处于保护窗口

    // 异步进程（每次操作复用）
    QProcess      *m_process         = nullptr;

    // 工具实际路径（构造时从候选列表中解析，兼容不同发行版）
    QString        m_nmcliPath;
    QString        m_mmcliPath;
    QString        m_sudoPath;   // sudo（4G ip link set 提权用）
    QString        m_ipPath;     // ip（iproute2，4G 接口强制 up/down）

    // 状态轮询定时器（每 10 秒刷新一次状态）
    QTimer        *m_statusPollTimer = nullptr;
};
