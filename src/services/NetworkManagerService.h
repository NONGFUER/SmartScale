#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QProcess>
#include <QTimer>
#include <QVariantMap>
#include <QRegularExpression>
#include <functional>

class QNetworkInterface;

/**
 * @brief 网络管理服务 — 统一管理 Wi-Fi 和 4G 网络（状态单一数据源）
 *
 * 技术方案（Linux 嵌入式环境）：
 *   - 检测层（原生，零外部进程）：QNetworkInterface 判定 wlan0/eth1 联网与否 + IP；
 *     WiFi 信号读 /proc/net/wireless；4G 信号/运营商由 CellularModemService
 *     AT+CSQ / AT+COPS? 经 setCellularSignal/setCellularOperator 注入
 *   - 控制层：nmcli（WiFi 扫描/连接/射频、路由 metric）+ sudo ip link set（4G up/down）
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
        CellError     = 6,
        CellDisabling = 7          // 正在关闭（命令执行中，QML 开关应显示"关"）
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

public Q_SLOTS:
    /** @brief 注入 4G 信号强度（CellularModemService AT+CSQ，0-100；值变化才 emit） */
    void setCellularSignal(int percent);
    /** @brief 注入 4G 运营商名（CellularModemService AT+COPS?，空串忽略） */
    void setCellularOperator(const QString &name);

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

    /** @brief 动态发现 WiFi 设备名（原生：遍历 QNetworkInterface，兼容 wlan*、wlp*、mlan* 命名） */
    QString discoverWifiDevice() const;

    /** @brief 在多个候选路径中查找第一个存在的可执行文件 */
    static QString findExecutable(const char *paths[]);

    void parseWifiScanOutput(const QString &output);

    int signalQualityToPercent(const QString &qualityStr) const;

    /** @brief 获取 Wi-Fi 列表（扫描完成后调用） */
    void fetchWifiList();

    /** @brief 通过 nmcli 连接启用 4G（以太网模式） */
    void enableCellularViaDevice();

    /** @brief 通过 nmcli 断开禁用 4G（以太网模式） */
    void disableCellularViaDevice();

    /**
     * @brief 发现 4G 网络接口设备名（原生：遍历 QNetworkInterface）
     *
     * 检测策略：优先候选名（eth1/usb0/wwan0/ppp0），兜底 enx*、usb* 前缀
     * （USB 以太网设备，4G 网棒典型命名）。lo/eth0/wifi 天然不匹配。
     * 返回设备名（如 "eth1"），失败返回空串
     */
    QString discoverCellularDevice() const;

    /** @brief 接口是否有全局 IPv4 地址（排除环回/link-local 169.254）；可选输出 IP 字符串 */
    static bool hasGlobalIPv4(const QNetworkInterface &iface, QString *ipOut = nullptr);

    /** @brief 从 /proc/net/wireless 读取指定 WiFi 设备信号（0-100），无该行返回 0 */
    static int readWifiSignalFromProc(const QString &wifiDevice);

    /** @brief nmcli 反查当前连接的 SSID（仅在已连接且缓存为空时调用，稳态零进程） */
    QString fetchCurrentWifiSsid(const QString &wifiDevice) const;

    /** @brief 网络状态落定后派生有效网络模式（networkMode 单一数据源的第二写者，仅变化时 emit） */
    void deriveNetworkModeFromState();

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
    int            m_cellularSignal  = 0;          // 0-100（AT+CSQ 注入，唯一数据源）
    QString        m_cellularOperator;
    QString        m_cellularIpAddress;

    /** @brief 检测到的 4G 网络接口设备名（如 "eth1"），用于以太网模式的 4G 模块 */
    mutable QString m_cellularDeviceName;

    /** @brief 是否检测到任何 4G 硬件（4G 网络接口存在即为真） */
    bool           m_hasCellularHardware = false;

    QString        m_lastError;
    bool           m_pendingCellularOp = false;  // true=启用, false=禁用
    /** @brief 4G 开启挂起窗口：enable 后未拿到 IP 前保持 CellSearching（30s 超时转 Error 时清除） */
    bool           m_cellularEnablePending = false;
    /** @brief 4G 关闭挂起窗口：disable 后命令完成前保持 CellDisabling（防轮询提前判 Disabled 回退） */
    bool           m_cellularDisablePending = false;

    /** @brief 当前网络模式（NetworkMode 枚举值，-1 未知） */
    int            m_networkMode = -1;

    // 两步连接法：创建配置 → 激活 之间的中间状态
    QString        m_pendingSsid;                 // 正在连接的 SSID
    QString        m_pendingConnectionName;       // 已创建但尚未激活的连接名称
    QString        m_pendingPassword;              // 缓存正在连接的 WiFi 密码（用于失败时自动重建）

    // 异步进程（每次操作复用）
    QProcess      *m_process         = nullptr;

    // 工具实际路径（构造时从候选列表中解析，兼容不同发行版）
    QString        m_nmcliPath;
    QString        m_sudoPath;   // sudo（4G ip link set 提权用）
    QString        m_ipPath;     // ip（iproute2，4G 接口强制 up/down）

    // 状态轮询定时器（每 3 秒刷新一次状态，原生检测微秒级）
    QTimer        *m_statusPollTimer = nullptr;
};
