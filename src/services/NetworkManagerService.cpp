#include "NetworkManagerService.h"
#include <QCoreApplication>
#include <QThread>
#include <QRegularExpression>
#include <QDebug>
#include <QFile>
#include <QNetworkInterface>
#include <QHostAddress>

// ============================================================
// 常量定义
// ============================================================
static const int    kStatusPollIntervalMs = 3000;   // 状态轮询间隔
static const int    kScanTimeoutMs        = 15000;   // 扫描超时
static const int    kConnectTimeoutMs     = 30000;   // 连接超时

// nmcli 路径（按优先级搜索，兼容不同 Linux 发行版）
static const char *kNmcliPaths[] = {
    "/usr/bin/nmcli",
    "/usr/sbin/nmcli",
    "/bin/nmcli",
    nullptr
};

// sudo 路径（4G ip link set 需要 root，走 sudo -n 免密）
static const char *kSudoPaths[] = {
    "/usr/bin/sudo",
    "/bin/sudo",
    "/usr/sbin/sudo",
    nullptr
};

// ip 命令路径（iproute2，用于 4G 接口 up/down 强制控制）
static const char *kIpPaths[] = {
    "/usr/sbin/ip",
    "/sbin/ip",
    "/usr/bin/ip",
    "/bin/ip",
    nullptr
};

// ============================================================
// 构造 / 析构
// ============================================================
NetworkManagerService::NetworkManagerService(QObject *parent)
    : QObject(parent)
{
    // 兼容性：从候选列表中解析实际工具路径
    m_nmcliPath = findExecutable(kNmcliPaths);
    m_sudoPath  = findExecutable(kSudoPaths);
    m_ipPath    = findExecutable(kIpPaths);

    qDebug() << "[NetworkManager] 工具路径: nmcli=" << m_nmcliPath
             << "sudo=" << (m_sudoPath.isEmpty() ? "(未找到)" : m_sudoPath)
             << "ip=" << (m_ipPath.isEmpty() ? "(未找到)" : m_ipPath);

    m_process = new QProcess(this);
    m_process->setProcessChannelMode(QProcess::MergedChannels);

    // 状态轮询定时器
    m_statusPollTimer = new QTimer(this);
    connect(m_statusPollTimer, &QTimer::timeout, this, &NetworkManagerService::onStatusPollTimer);
    m_statusPollTimer->start(kStatusPollIntervalMs);

    // 启动时立即刷新状态
    QTimer::singleShot(1000, this, [this]() {
        refreshWifiStatus();
        refreshCellularStatus();
    });
}

// ============================================================
// 权限检查
// ============================================================
bool NetworkManagerService::checkPermissions()
{
    m_lastError.clear();

    if (!hasNetworkManager()) {
        setLastError(QStringLiteral("未找到 NetworkManager (nmcli)，请先安装: sudo apt install network-manager"));
        qWarning() << "[NetworkManager]" << m_lastError;
        return false;
    }

    // 尝试执行一个无副作用的 nmcli 命令来验证权限
    QProcess testProc;
    testProc.start(m_nmcliPath, QStringList() << "-t" << "-f" << "RUNNING" << "general" << "status");
    if (!testProc.waitForFinished(3000)) {
        setLastError(QStringLiteral("nmcli 权限不足或无响应，请确认用户在 networkmanager 组或有 sudo 免密权限"));
        qWarning() << "[NetworkManager]" << m_lastError;
        return false;
    }

    return true;
}

bool NetworkManagerService::hasNetworkManager() const
{
    return !m_nmcliPath.isEmpty();
}

QString NetworkManagerService::findExecutable(const char *paths[])
{
    for (int i = 0; paths[i] != nullptr; ++i) {
        if (QFile::exists(QString::fromUtf8(paths[i]))) {
            return QString::fromUtf8(paths[i]);
        }
    }
    return QString();
}

QString NetworkManagerService::discoverWifiDevice() const
{
    // 原生发现：遍历 QNetworkInterface（getifaddrs），微秒级、无外部进程
    const auto ifaces = QNetworkInterface::allInterfaces();
    // 优先常见无线命名（wlan0/wlp2s0/mlan0 等）
    for (const auto &iface : ifaces) {
        const QString n = iface.name();
        if (n.startsWith(QStringLiteral("wlan")) ||
            n.startsWith(QStringLiteral("wlp"))  ||
            n.startsWith(QStringLiteral("mlan"))) {
            return n;
        }
    }
    // 兜底：/sys/class/net/<name>/wireless 存在即为无线网卡
    for (const auto &iface : ifaces) {
        if (QFile::exists(QStringLiteral("/sys/class/net/") + iface.name() + QStringLiteral("/wireless"))) {
            return iface.name();
        }
    }
    return QString();
}

// ============================================================
// Wi-Fi 操作实现
// ============================================================

void NetworkManagerService::scanWifiNetworks()
{
    if (!checkPermissions()) {
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    if (m_isScanning) return;

    m_isScanning = true;
    Q_EMIT scanningChanged(true);
    m_availableNetworks.clear();

    qDebug() << "[NetworkManager] 开始扫描 Wi-Fi 网络...";

    QStringList args;
    args << "device" << "wifi" << "rescan";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiScanFinished);

    m_process->start(m_nmcliPath, args);

    // 设置超时保护
    QTimer::singleShot(kScanTimeoutMs + 2000, this, [this]() {
        if (m_isScanning) {
            m_isScanning = false;
            Q_EMIT scanningChanged(false);
            qWarning() << "[NetworkManager] Wi-Fi 扫描超时";
            fetchWifiList();
        }
    });
}

void NetworkManagerService::fetchWifiList()
{
    // 扫描请求完成后，获取可用网络列表
    QProcess listProc;
    listProc.start(m_nmcliPath, QStringList()
                   << "-t" << "-f" << "SSID,SIGNAL,FREQ,SECURITY,BSSID"
                   << "device" << "wifi" << "list"
                   << "--rescan" << "no");

    if (listProc.waitForFinished(5000)) {
        parseWifiScanOutput(listProc.readAllStandardOutput());
    } else {
        qWarning() << "[NetworkManager] 获取 Wi-Fi 列表超时";
    }

    m_isScanning = false;
    Q_EMIT scanningChanged(false);
    Q_EMIT networksUpdated();
}

void NetworkManagerService::onWifiScanFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode != 0) {
        QString errOutput = m_process->readAllStandardOutput();
        qWarning() << "[NetworkManager] 扫描失败:" << exitCode << errOutput;
        setLastError(QStringLiteral("Wi-Fi 扫描失败: %1").arg(QString(errOutput).trimmed()));
    }

    fetchWifiList();
}

void NetworkManagerService::parseWifiScanOutput(const QString &output)
{
    m_availableNetworks.clear();

    // 临时用 QMap 按 SSID 去重：同一 SSID 只保留信号最强的那条
    // key=SSID (lowercase), value=QVariantMap(最佳网络信息)
    QMap<QString, QVariantMap> bestNetworks;

    const auto lines = output.split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        // 格式: SSID:SIGNAL:FREQ:SECURITY:BSSID
        const auto fields = line.split(':');
        if (fields.size() >= 3) {
            QString ssid       = fields[0].trimmed();
            QString signalStr  = fields.size() > 1 ? fields[1].trimmed() : QStringLiteral("0");
            QString freqStr    = fields.size() > 2 ? fields[2].trimmed() : QStringLiteral("0");
            QString security   = fields.size() > 3 ? fields[3].trimmed() : QString();
            QString bssid      = fields.size() > 4 ? fields[4].trimmed() : QString();

            if (ssid.isEmpty()) continue;

            bool isSecured = !security.isEmpty() && security != QStringLiteral("--");
            int signal     = signalQualityToPercent(signalStr);
            int freq       = freqStr.toInt();  // MHz, e.g. 2412 or 5180

            QString key = ssid.toLower().trimmed();  // 不区分大小写去重

            if (!bestNetworks.contains(key) || signal > bestNetworks[key]["signal"].toInt()) {
                QVariantMap network;
                network["ssid"]         = ssid;
                network["signal"]       = signal;
                network["freq"]         = freq;
                network["secured"]      = isSecured;
                network["bssid"]        = bssid;
                network["securityType"] = security;
                bestNetworks[key] = network;
            }
        }
    }

    // 转换回 QVariantList（已连接的网络排第一，其余按信号强度降序）
    QList<QVariantMap> sorted;
    for (auto it = bestNetworks.constBegin(); it != bestNetworks.constEnd(); ++it) {
        sorted.append(it.value());
    }
    std::sort(sorted.begin(), sorted.end(),
              [this](const QVariantMap &a, const QVariantMap &b) {
                  // 已连接的排第一
                  bool aConnected = (a["ssid"].toString() == m_wifiSsid);
                  bool bConnected = (b["ssid"].toString() == m_wifiSsid);
                  if (aConnected != bConnected)
                      return aConnected;
                  // 其余按信号强度降序
                  return a["signal"].toInt() > b["signal"].toInt();
              });
    for (const auto &n : sorted) {
        m_availableNetworks.append(n);
    }
}

void NetworkManagerService::connectWifi(const QString &ssid, const QString &password)
{
    if (!checkPermissions()) {
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    if (ssid.isEmpty()) {
        setLastError(QStringLiteral("SSID 不能为空"));
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 正在连接到 Wi-Fi:" << ssid
             << "加密:" << !password.isEmpty();

    m_pendingSsid = ssid;
    m_pendingPassword = password;   // 缓存密码，用于失败时自动重建连接
    m_pendingConnectionName.clear();

    // 动态发现 WiFi 设备名
    QString wifiDevice = discoverWifiDevice();
    if (wifiDevice.isEmpty()) {
        setLastError(QStringLiteral("未找到 Wi-Fi 设备"));
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    setWifiStatus(WifiStatus::Connecting);

    // ★ 先检查是否已存在该 SSID 的连接配置，避免重复创建导致重名问题
    QString existingConn = findExistingConnection(ssid);
    if (!existingConn.isEmpty()) {
        qDebug() << "[NetworkManager] 找到已有连接配置:" << existingConn << "，尝试直接复用激活";

        m_pendingConnectionName = existingConn;

        // 直接激活已有连接（跳过 connection add 步骤）
        QStringList args;
        args << "connection" << "up" << existingConn;

        disconnect(m_process, nullptr, this, nullptr);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &NetworkManagerService::onWifiConnectFinished);

        m_process->start(m_nmcliPath, args);

        // 连接超时保护
        QTimer::singleShot(kConnectTimeoutMs, this, [this]() {
            if (m_wifiStatus == WifiStatus::Connecting) {
                m_process->kill();
                setLastError(QStringLiteral("连接超时"));
                setWifiStatus(WifiStatus::Error);
                Q_EMIT wifiConnectionFailed(m_lastError);
            }
        });

        return;  // ← 提前返回，不创建新连接（失败时会进入 onWifiConnectFinished 处理）
    }

    // 两步法：先创建连接配置（connection add），再激活（connection up）
    // 比 "device wifi connect" 更可靠，能正确处理 key-mgmt 属性
    QStringList args;
    args << "connection" << "add"
         << "type"     << "wifi"
         << "con-name" << sanitizeConnectionName(ssid)
         << "ifname"   << wifiDevice
         << "ssid"     << ssid;

    if (!password.isEmpty()) {
        // 显式指定 WPA-PSK 安全方式，避免 "key-mgmt: 缺少属性" 错误
        args << "wifi-sec.key-mgmt"  << "wpa-psk"
             << "wifi-sec.psk"       << password;
    }

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiConnectionAdded);

    m_process->start(m_nmcliPath, args);

    // 创建连接配置超时保护
    QTimer::singleShot(10000, this, [this, ssid]() {
        if (m_wifiStatus == WifiStatus::Connecting) {
            m_process->kill();
            setLastError(QStringLiteral("创建连接配置超时 (%1)").arg(ssid));
            setWifiStatus(WifiStatus::Error);
            Q_EMIT wifiConnectionFailed(m_lastError);
        }
    });
}

void NetworkManagerService::onWifiConnectionAdded(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode != 0) {
        QString errOutput = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        qWarning() << "[NetworkManager] 创建连接配置失败:" << exitCode << errOutput;

        setLastError(QStringLiteral("创建连接失败: %1").arg(errOutput.left(60)));
        setWifiStatus(WifiStatus::Error);
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    // 第一步成功 → 第二步：激活连接
    qDebug() << "[NetworkManager] 连接配置创建成功，正在激活...";

    // 从输出中提取连接名称（格式：<hash>-<ssid> 或直接用 con-name）
    QString output = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
    QStringList outputLines = output.split('\n', Qt::SkipEmptyParts);

    // nmcli connection add 成功时输出: 'Connection '<name>' (<uuid>) added.'
    QString connName;
    QRegularExpression reConn("'([^']+)'");
    for (const auto &line : outputLines) {
        auto match = reConn.match(line);
        if (match.hasMatch()) {
            connName = match.captured(1);
            break;
        }
    }

    if (connName.isEmpty()) {
        // fallback: 用 SSID 作为连接名
        connName = sanitizeConnectionName(m_pendingSsid);
    }

    m_pendingConnectionName = connName;

    // 激活连接
    QStringList args;
    args << "connection" << "up" << connName;

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiConnectFinished);

    m_process->start(m_nmcliPath, args);

    // 连接超时保护
    QTimer::singleShot(kConnectTimeoutMs - 10000, this, [this]() {
        if (m_wifiStatus == WifiStatus::Connecting) {
            m_process->kill();
            setLastError(QStringLiteral("连接超时"));
            setWifiStatus(WifiStatus::Error);
            Q_EMIT wifiConnectionFailed(m_lastError);
        }
    });
}

QString NetworkManagerService::sanitizeConnectionName(const QString &ssid) const
{
    // 移除 SSID 中可能导致 nmcli 命令解析问题的特殊字符
    QString name = ssid;
    name.replace(QRegularExpression(QStringLiteral("[^\\w\\-\\s]")), QStringLiteral(""));
    name = name.trimmed();
    if (name.isEmpty())
        name = QStringLiteral("WiFi");
    return name;
}

QString NetworkManagerService::extractSsidValue(const QString &rawOutput)
{
    // nmcli -t 输出格式: "field.name:value"，取冒号后的部分
    QString s = rawOutput.trimmed();
    int idx = s.indexOf(':');
    return (idx >= 0) ? s.mid(idx + 1).trimmed() : s;
}

QString NetworkManagerService::findExistingConnection(const QString &ssid) const
{
    QProcess proc;
    proc.start(m_nmcliPath, QStringList()
               << "-t"
               << "-f" << "NAME,TYPE,802-11-wireless.ssid"
               << "connection" << "show");

    if (!proc.waitForFinished(3000)) {
        qWarning() << "[NetworkManager] findExistingConnection: nmcli 查询超时";
        return QString();
    }

    const auto lines = QString::fromUtf8(proc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        auto parts = line.split(':');
        if (parts.size() >= 3) {
            QString connName = parts[0].trimmed();
            QString connType = parts[1].trimmed().toLower();
            QString connSsid = parts[2].trimmed();

            // 只匹配 wifi 类型的连接，且 SSID 一致
            if (connType == QStringLiteral("wifi") && connSsid == ssid) {
                qDebug() << "[NetworkManager] 找到已有连接配置:" << connName << "(SSID:" << ssid << ")";
                return connName;
            }
        }
    }

    qDebug() << "[NetworkManager] 未找到 SSID" << ssid << "的现有连接配置";
    return QString();  // 未找到
}

void NetworkManagerService::deleteConnection(const QString &connName)
{
    qDebug() << "[NetworkManager] 删除旧连接配置:" << connName;

    QProcess proc;
    proc.start(m_nmcliPath, QStringList()
               << "connection" << "delete" << connName);

    if (proc.waitForFinished(5000)) {
        if (proc.exitCode() == 0) {
            qDebug() << "[NetworkManager] 已成功删除连接:" << connName;
        } else {
            qWarning() << "[NetworkManager] 删除连接失败:"
                       << QString::fromUtf8(proc.readAllStandardOutput()).trimmed();
        }
    } else {
        qWarning() << "[NetworkManager] 删除连接超时:" << connName;
        proc.kill();
    }
}

void NetworkManagerService::onWifiConnectFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode == 0) {
        qDebug() << "[NetworkManager] Wi-Fi 连接成功";
        // 批量更新：设置 SSID + 统一发射一次信号
        QString successSsid = m_pendingSsid.isEmpty() ? m_wifiSsid : m_pendingSsid;
        runOnMainThread([this, successSsid]() {
            m_lastError.clear();
            m_wifiSsid = successSsid;
            m_wifiStatus = WifiStatus::Connected;
            Q_EMIT wifiStatusChanged();
        });
        Q_EMIT wifiConnectionSuccess(successSsid);
        refreshWifiStatus();
    } else {
        QString errOutput = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        qWarning() << "[NetworkManager] Wi-Fi 连接失败:" << errOutput;

        if (errOutput.contains(QStringLiteral("Secrets were required")) ||
            errOutput.contains("no valid connections")) {
            setLastError(QStringLiteral("密码错误或认证失败"));

            // ★ 如果是复用旧连接导致的认证失败，删除旧连接并重新创建
            if (!m_pendingConnectionName.isEmpty()) {
                qDebug() << "[NetworkManager] 检测到认证失败，删除旧连接配置并重建:"
                         << m_pendingConnectionName;
                deleteConnection(m_pendingConnectionName);

                // 延迟重新触发连接（给 nmcli 时间清理）
                QTimer::singleShot(500, this, [this]() {
                    if (!m_pendingSsid.isEmpty()) {
                        qDebug() << "[NetworkManager] 使用缓存的密码重新创建连接:"
                                 << m_pendingSsid;
                        connectWifi(m_pendingSsid, m_pendingPassword);
                    }
                });
                return;  // 提前返回，等待后续重连
            }

        } else if (errOutput.contains(QStringLiteral("not found"))) {
            setLastError(QStringLiteral("找不到该网络 (%1)").arg(m_wifiSsid));
        } else if (errOutput.contains("timeout")) {
            setLastError(QStringLiteral("连接超时，请检查信号强度"));
        } else {
            setLastError(QStringLiteral("连接失败: %1").arg(errOutput.left(50)));
        }

        setWifiStatus(WifiStatus::Error);
        Q_EMIT wifiConnectionFailed(m_lastError);
    }
}

void NetworkManagerService::disconnectWifi()
{
    if (!checkPermissions()) {
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    // 动态发现 WiFi 设备名（兼容不同系统命名：wlan0/wlp2s0/mlan0 等）
    QString wifiDevice = discoverWifiDevice();
    if (wifiDevice.isEmpty()) {
        setLastError(QStringLiteral("未找到 Wi-Fi 设备，无法断开"));
        qWarning() << "[NetworkManager]" << m_lastError;
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 断开 Wi-Fi, 设备:" << wifiDevice;

    QStringList args;
    args << "device" << "disconnect" << wifiDevice;

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiDisconnectFinished);

    m_process->start(m_nmcliPath, args);
}

void NetworkManagerService::setWifiEnabled(bool enabled)
{
    if (m_nmcliPath.isEmpty()) {
        setLastError(QStringLiteral("未找到 nmcli，无法切换 Wi-Fi 射频开关"));
        qWarning() << "[NetworkManager]" << m_lastError;
        return;
    }

    qInfo() << "[NetworkManager] 切换 Wi-Fi 射频:" << (enabled ? "on" : "off");

    // 射频开关为无副作用命令，使用独立一次性进程，结束后刷新状态
    QProcess *proc = new QProcess(this);
    connect(proc, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this, proc](int exitCode, QProcess::ExitStatus) {
        Q_UNUSED(exitCode)
        proc->deleteLater();
        refreshWifiStatus();
    });
    proc->start(m_nmcliPath, QStringList() << "radio" << "wifi" << (enabled ? "on" : "off"));
}

// ============================================================
// 网络模式（四选一）实现
// ============================================================

void NetworkManagerService::setNetworkMode(NetworkMode mode)
{
    bool wifiOn = (mode == NetworkMode::WifiOnly
                   || mode == NetworkMode::AllWifiPriority
                   || mode == NetworkMode::AllCellularPriority);
    bool cellOn = (mode == NetworkMode::CellularOnly
                   || mode == NetworkMode::AllWifiPriority
                   || mode == NetworkMode::AllCellularPriority);

    qInfo() << "[NetworkManager] 设置网络模式:" << static_cast<int>(mode)
            << "wifiOn=" << wifiOn << "cellOn=" << cellOn;

    // 1) 开关 Wi-Fi 射频 / 4G
    setWifiEnabled(wifiOn);
    if (cellOn) enableCellular();
    else disableCellular();

    // 2) 全开模式下设置路由优先级（优先接口走默认路由）
    if (mode == NetworkMode::AllWifiPriority || mode == NetworkMode::AllCellularPriority) {
        bool preferWifi = (mode == NetworkMode::AllWifiPriority);
        // 延迟 8s 应用：等两个接口都起来后再设置 metric 并重新激活优先连接，
        // 使低 metric 默认路由立即生效；连接配置已持久化，后续重连也会沿用。
        QTimer::singleShot(8000, this, [this, preferWifi]() {
            applyRoutePriority(preferWifi);
        });
    }

    // 3) 更新当前模式（供 UI 高亮）
    if (m_networkMode != static_cast<int>(mode)) {
        m_networkMode = static_cast<int>(mode);
        Q_EMIT networkModeChanged();
    }
}

QString NetworkManagerService::findActiveWifiConnection() const
{
    if (m_nmcliPath.isEmpty()) return QString();
    QString dev = discoverWifiDevice();
    if (dev.isEmpty()) return QString();

    QProcess p;
    p.start(m_nmcliPath, QStringList() << "-t" << "-f" << "GENERAL.CONNECTION"
                                       << "device" << "show" << dev);
    if (!p.waitForFinished(3000)) return QString();

    const auto lines = QString::fromUtf8(p.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        // 格式: GENERAL.CONNECTION:<connname>（未连接时为 --）
        QString v = line.split(':', Qt::SkipEmptyParts).value(1).trimmed();
        if (!v.isEmpty() && v != QStringLiteral("--"))
            return v;
    }
    return QString();
}

QString NetworkManagerService::findCellularConnection() const
{
    if (m_nmcliPath.isEmpty()) return QString();

    QString cellDev = m_cellularDeviceName.isEmpty()
                      ? discoverCellularDevice()
                      : m_cellularDeviceName;

    QProcess p;
    p.start(m_nmcliPath, QStringList() << "-t" << "-f" << "NAME,TYPE,DEVICE"
                                       << "connection" << "show");
    if (!p.waitForFinished(3000)) return QString();

    const auto lines = QString::fromUtf8(p.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        auto parts = line.split(':');
        if (parts.size() < 3) continue;
        QString name = parts[0].trimmed();
        QString type = parts[1].trimmed().toLower();
        QString dev  = parts[2].trimmed();

        // modem 模式：gsm/mobile/cellular 类型连接
        if (type.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
            type.contains(QStringLiteral("mobile"), Qt::CaseInsensitive) ||
            type.contains(QStringLiteral("cellular"), Qt::CaseInsensitive)) {
            return name;
        }
        // 接口模式：连接绑定到 4G 网络接口设备
        if (!cellDev.isEmpty() && dev == cellDev) {
            return name;
        }
    }
    return QString();
}

void NetworkManagerService::setConnectionRouteMetric(const QString &conn, int metric)
{
    if (conn.isEmpty() || m_nmcliPath.isEmpty()) return;

    QProcess p;
    p.start(m_nmcliPath, QStringList() << "connection" << "modify" << conn
             << "ipv4.route-metric" << QString::number(metric)
             << "ipv6.route-metric" << QString::number(metric));
    if (!p.waitForFinished(5000)) {
        qWarning() << "[NetworkManager] 设置路由优先级超时:" << conn;
        return;
    }
    if (p.exitCode() != 0) {
        qWarning() << "[NetworkManager] 设置路由优先级失败:" << conn
                   << QString::fromUtf8(p.readAllStandardError()).trimmed();
    } else {
        qInfo() << "[NetworkManager] 已设置连接" << conn << "路由优先级 metric=" << metric;
    }
}

void NetworkManagerService::reactivateConnection(const QString &conn)
{
    if (conn.isEmpty() || m_nmcliPath.isEmpty()) return;

    QProcess p;
    p.start(m_nmcliPath, QStringList() << "connection" << "up" << conn
             << "--wait-connect-timeout" << "20");
    if (!p.waitForFinished(25000)) {
        qWarning() << "[NetworkManager] 重新激活连接超时:" << conn;
    }
}

void NetworkManagerService::applyRoutePriority(bool preferWifi)
{
    QString wifiConn = findActiveWifiConnection();
    QString cellConn = findCellularConnection();

    int wifiMetric = preferWifi ? 10  : 300;
    int cellMetric = preferWifi ? 300 : 10;

    if (!wifiConn.isEmpty()) setConnectionRouteMetric(wifiConn, wifiMetric);
    if (!cellConn.isEmpty()) setConnectionRouteMetric(cellConn, cellMetric);

    // 重新激活"优先"连接，使其低 metric 默认路由立即生效
    QString preferred = preferWifi ? wifiConn : cellConn;
    if (!preferred.isEmpty()) reactivateConnection(preferred);

    qInfo() << "[NetworkManager] 应用路由优先级 preferWifi=" << preferWifi
            << "wifiConn=" << (wifiConn.isEmpty() ? "<none>" : wifiConn)
            << "cellConn=" << (cellConn.isEmpty() ? "<none>" : cellConn);
}

void NetworkManagerService::onWifiDisconnectFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode == 0) {
        qDebug() << "[NetworkManager] Wi-Fi 已断开";

        // 批量更新：清空所有 WiFi 属性 + 统一发射一次信号
        runOnMainThread([this]() {
            m_wifiSsid.clear();
            m_wifiIpAddress.clear();
            m_wifiSignal = 0;
            m_wifiStatus = WifiStatus::Disconnected;
            Q_EMIT wifiStatusChanged();
        });
    } else {
        qWarning() << "[NetworkManager] 断开 Wi-Fi 失败:"
                    << QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        refreshWifiStatus();
    }
}

// ============================================================
// Wi-Fi 状态检测（原生 QNetworkInterface，零外部进程）
// ============================================================

bool NetworkManagerService::hasGlobalIPv4(const QNetworkInterface &iface, QString *ipOut)
{
    // 接口 DOWN 时 IP 可能残留（ip link set down 不立即清除地址），
    // 直接读内核 operstate 检测是否为 "down"
    const QString operstatePath = QStringLiteral("/sys/class/net/%1/operstate")
                                     .arg(iface.name());
    QFile operstateFile(operstatePath);
    if (operstateFile.open(QIODevice::ReadOnly)) {
        const auto state = QString::fromUtf8(operstateFile.readAll()).trimmed();
        if (state == QLatin1String("down"))
            return false;
    }

    const auto entries = iface.addressEntries();
    for (const auto &entry : entries) {
        const QHostAddress ip = entry.ip();
        // 排除环回与 link-local（169.254.x.x，DHCP 失败的自分配地址不算联网）
        if (ip.protocol() == QAbstractSocket::IPv4Protocol
            && !ip.isLoopback() && !ip.isLinkLocal()) {
            if (ipOut) *ipOut = ip.toString();
            return true;
        }
    }
    return false;
}

int NetworkManagerService::readWifiSignalFromProc(const QString &wifiDevice)
{
    // /proc/net/wireless 行格式: "wlan0: 0000   70.  -30.  -256 ..."
    QFile wirelessFile(QStringLiteral("/proc/net/wireless"));
    if (!wirelessFile.open(QIODevice::ReadOnly))
        return 0;
    const auto lines = QString::fromUtf8(wirelessFile.readAll()).split('\n');
    for (const auto &line : lines) {
        if (line.contains(wifiDevice + QStringLiteral(":"))) {
            const auto parts = line.simplified().split(' ');
            if (parts.size() >= 3) {
                bool ok = false;
                const double link = parts[2].toDouble(&ok);
                if (ok) return qBound(0, static_cast<int>(link), 100);
            }
            break;
        }
    }
    return 0;
}

QString NetworkManagerService::fetchCurrentWifiSsid(const QString &wifiDevice) const
{
    // 两步反查：device show 取活动连接名 → connection show 取真实 SSID
    // 仅在已连接且 SSID 缓存为空时调用（稳态轮询零进程）
    if (m_nmcliPath.isEmpty()) return QString();

    QProcess devProc;
    devProc.start(m_nmcliPath, QStringList()
                  << "-t" << "-f" << "GENERAL.CONNECTION"
                  << "device" << "show" << wifiDevice);
    if (!devProc.waitForFinished(3000)) return QString();

    const QString connName = extractSsidValue(
        QString::fromUtf8(devProc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts).value(0));
    if (connName.isEmpty() || connName == QStringLiteral("--")) return QString();

    QProcess ssidProc;
    ssidProc.start(m_nmcliPath, QStringList()
                   << "-t" << "-f" << "802-11-wireless.ssid"
                   << "connection" << "show" << connName);
    if (!ssidProc.waitForFinished(3000)) return QString();

    const QString ssid = extractSsidValue(
        QString::fromUtf8(ssidProc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts).value(0));
    return (ssid == QStringLiteral("--")) ? QString() : ssid;
}

void NetworkManagerService::refreshWifiStatus()
{
    // 原生检测：接口缺失/未启用 → Disabled（射频关闭时接口 down）；
    // IsUp + 全局 IPv4 → Connected；IsUp 无 IP → Disconnected（连接窗口内保持 Connecting）
    const QString wifiDevice = discoverWifiDevice();

    WifiStatus newStatus;
    QString ipAddress;
    if (wifiDevice.isEmpty()) {
        newStatus = WifiStatus::Disabled;
    } else {
        const QNetworkInterface iface = QNetworkInterface::interfaceFromName(wifiDevice);
        if (!iface.isValid() || !iface.flags().testFlag(QNetworkInterface::IsUp)) {
            newStatus = WifiStatus::Disabled;
        } else if (hasGlobalIPv4(iface, &ipAddress)) {
            newStatus = WifiStatus::Connected;
        } else {
            newStatus = (m_wifiStatus == WifiStatus::Connecting)
                        ? WifiStatus::Connecting     // 连接进行窗口：DHCP 未就绪不误判断开
                        : WifiStatus::Disconnected;
        }
    }

    // SSID 原生接口取不到：沿用缓存（连接/断开路径会写入）；仅 Connected 且缓存为空时 nmcli 反查一次
    QString ssid;
    int signal = 0;
    if (newStatus == WifiStatus::Connected) {
        ssid = m_wifiSsid.isEmpty() ? fetchCurrentWifiSsid(wifiDevice) : m_wifiSsid;
        signal = readWifiSignalFromProc(wifiDevice);
    }

    bool changed = false;
    if (m_wifiStatus != newStatus)     { m_wifiStatus = newStatus;     changed = true; }
    if (m_wifiSsid != ssid)            { m_wifiSsid = ssid;            changed = true; }
    if (m_wifiIpAddress != ipAddress)  { m_wifiIpAddress = ipAddress;  changed = true; }
    if (m_wifiSignal != signal)        { m_wifiSignal = signal;        changed = true; }

    if (changed) {
        qDebug() << "[NetworkManager] WiFi 状态(原生): status=" << static_cast<int>(m_wifiStatus)
                 << "ssid=" << m_wifiSsid << "ip=" << m_wifiIpAddress
                 << "signal=" << m_wifiSignal;
        Q_EMIT wifiStatusChanged();
        deriveNetworkModeFromState();
    }
}

// ============================================================
// 线程安全辅助
// ============================================================

template<typename Func>
inline void NetworkManagerService::runOnMainThread(Func&& func)
{
    if (QThread::currentThread() == thread()) {
        // 已在主线程（QObject 所属线程），直接执行
        std::forward<Func>(func)();
    } else {
        // 在工作线程，投递到主线程事件循环（QueuedConnection 保证串行）
        QMetaObject::invokeMethod(this, [f = std::forward<Func>(func)]() mutable { f(); },
                                  Qt::QueuedConnection);
    }
}

void NetworkManagerService::setWifiStatus(WifiStatus status)
{
    runOnMainThread([this, status]() {
        if (m_wifiStatus != status) {
            m_wifiStatus = status;
            Q_EMIT wifiStatusChanged();
            deriveNetworkModeFromState();
        }
    });
}

// ============================================================
// 4G 操作实现（控制层：sudo ip link set；状态由原生轮询落定）
// ============================================================

void NetworkManagerService::enableCellular()
{
    qDebug() << "[NetworkManager] 开启 4G 移动数据...";
    m_cellularDisablePending = false;         // 清除可能的关闭残留
    m_cellularEnablePending = true;    // 开启挂起窗口：未拿到 IP 前保持 CellSearching
    setCellularStatus(CellularStatus::CellSearching);
    enableCellularViaDevice();
    // 命令后密集原生刷新，抓住 DHCP/拨号完成瞬间（原生检测微秒级，代价可忽略）
    for (int ms : {500, 1500, 3000, 6000}) {
        QTimer::singleShot(ms, this, &NetworkManagerService::refreshCellularStatus);
    }
}

void NetworkManagerService::enableCellularViaDevice()
{
    QString cellDevice = discoverCellularDevice();
    m_cellularDeviceName = cellDevice;

    if (cellDevice.isEmpty()) {
        setLastError(QStringLiteral("未检测到 4G 网络接口设备"));
        qWarning() << "[NetworkManager]" << m_lastError;
        m_cellularEnablePending = false;   // 提前失败，关闭挂起窗口让轮询落定
        // 无硬件保持 Disabled，不触发 Error
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    // 必须有 sudo + ip 才能提权执行 ip link set up
    if (m_sudoPath.isEmpty() || m_ipPath.isEmpty()) {
        setLastError(QStringLiteral("缺少 sudo 或 ip 命令，无法控制 4G 接口"));
        qWarning() << "[NetworkManager]" << m_lastError
                   << "sudo=" << m_sudoPath << "ip=" << m_ipPath;
        m_cellularEnablePending = false;   // 提前失败，关闭挂起窗口让轮询落定
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 通过 sudo ip link set 启用 4G 接口:" << cellDevice;

    // sudo -n: 非交互模式，无免密权限时立即失败而非卡住等密码
    QStringList args;
    args << "-n" << m_ipPath << "link" << "set" << cellDevice << "up";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(m_sudoPath, args);
    m_pendingCellularOp = true;

    // ip link up 后 NetworkManager 需重新拨号/DHCP，预留较长恢复时间
    QTimer::singleShot(30000, this, [this]() {
        if (m_cellularStatus == CellularStatus::CellSearching) {
            m_process->kill();
            m_cellularEnablePending = false;   // 挂起窗口关闭，落定 Error
            setLastError(QStringLiteral("4G 启用超时"));
            setCellularStatus(CellularStatus::CellError);
            Q_EMIT cellularOperationFailed(m_lastError);
        }
    });
}

void NetworkManagerService::disableCellular()
{
    qDebug() << "[NetworkManager] 关闭 4G 移动数据...";
    m_cellularEnablePending = false;   // 关闭方向：无 IP 即落定 Disabled
    m_cellularDisablePending = true;          // 开启关闭挂起窗口
    setCellularStatus(CellularStatus::CellDisabling);   // 使用新过渡态，QML 开关立即显示关
    disableCellularViaDevice();
    // 命令后密集原生刷新，抓住 IP 消失瞬间
    for (int ms : {500, 1500, 3000}) {
        QTimer::singleShot(ms, this, &NetworkManagerService::refreshCellularStatus);
    }
}

void NetworkManagerService::disableCellularViaDevice()
{
    // 优先使用缓存的设备名（如果有），否则重新发现
    QString cellDevice = m_cellularDeviceName.isEmpty()
                         ? discoverCellularDevice()
                         : m_cellularDeviceName;

    if (cellDevice.isEmpty()) {
        // 没有检测到设备，直接标记为禁用
        qDebug() << "[NetworkManager] 未检测到 4G 接口设备，直接标记为禁用";
        m_cellularOperator.clear();
        m_cellularIpAddress.clear();
        m_cellularSignal = 0;
        setCellularStatus(CellularStatus::CellDisabled);
        Q_EMIT cellularDisabled();
        return;
    }

    // 必须有 sudo + ip 才能提权执行 ip link set down
    if (m_sudoPath.isEmpty() || m_ipPath.isEmpty()) {
        setLastError(QStringLiteral("缺少 sudo 或 ip 命令，无法控制 4G 接口"));
        qWarning() << "[NetworkManager]" << m_lastError
                   << "sudo=" << m_sudoPath << "ip=" << m_ipPath;
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 通过 sudo ip link set 断开 4G 接口:" << cellDevice;

    // sudo -n: 非交互模式，无免密权限时立即失败而非卡住等密码
    QStringList args;
    args << "-n" << m_ipPath << "link" << "set" << cellDevice << "down";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(m_sudoPath, args);
    m_pendingCellularOp = false;

    QTimer::singleShot(15000, this, [this]() {
        if (m_cellularStatus == CellularStatus::CellDisabling) {
            m_process->kill();
            qDebug() << "[NetworkManager] ip link set down 4G 接口超时，强制标记为禁用";
            m_cellularOperator.clear();
            m_cellularIpAddress.clear();
            m_cellularSignal = 0;
            m_cellularDisablePending = false;      // 超时也清除挂起窗口
            setCellularStatus(CellularStatus::CellDisabled);
            Q_EMIT cellularDisabled();
        }
    });
}

// ============================================================
// 4G 设备发现（原生 QNetworkInterface）
// ============================================================

QString NetworkManagerService::discoverCellularDevice() const
{
    const auto ifaces = QNetworkInterface::allInterfaces();

    // 优先已知候选接口名（4G 网棒/模块典型命名）
    static const char *kCandidateIfaces[] = {"eth1", "usb0", "wwan0", "ppp0"};
    for (const char *candidate : kCandidateIfaces) {
        for (const auto &iface : ifaces) {
            if (iface.name() == QLatin1String(candidate))
                return iface.name();
        }
    }
    // 兜底：enx*/usb* 前缀是 USB 以太网设备（4G 模块常见），
    // lo/eth0/wlan* 天然不匹配这些前缀，无需显式排除
    for (const auto &iface : ifaces) {
        const QString n = iface.name();
        if (n.startsWith(QStringLiteral("enx")) || n.startsWith(QStringLiteral("usb")))
            return n;
    }
    return QString();
}

void NetworkManagerService::onCellularOpFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode == 0) {
        if (m_pendingCellularOp) {
            qDebug() << "[NetworkManager] 4G 已启用";
            Q_EMIT cellularEnabled();
        } else {
            qDebug() << "[NetworkManager] 4G 已禁用";
            m_cellularOperator.clear();
            m_cellularIpAddress.clear();
            m_cellularSignal = 0;
            m_cellularDisablePending = false;      // 命令成功完成，关闭挂起窗口
            setCellularStatus(CellularStatus::CellDisabled);
            Q_EMIT cellularDisabled();
        }
        refreshCellularStatus();      // 命令一返回立即原生刷新（微秒级）
    } else {
        // sudo 的报错（如"a password is required"）走 stderr，合并读取 stdout+stderr 定位根因
        QString err = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        const QString errErr = QString::fromUtf8(m_process->readAllStandardError()).trimmed();
        if (!errErr.isEmpty())
            err += (err.isEmpty() ? QString() : QStringLiteral(" ")) + errErr;
        qWarning() << "[NetworkManager] 4G 操作失败:" << err;

        if (err.contains(QStringLiteral("password is required"), Qt::CaseInsensitive) ||
            err.contains(QStringLiteral("a terminal is required"), Qt::CaseInsensitive)) {
            // sudoers 免密未配置（最常见）
            setLastError(QStringLiteral("4G 控制权限不足，请配置 sudoers 免密"));
        } else if (err.contains(QStringLiteral("not found"))) {
            setLastError(QStringLiteral("4G 模块未就绪或 SIM 卡未插入"));
        } else if (err.contains(QStringLiteral("SIM PIN"))) {
            setLastError(QStringLiteral("SIM 卡需要 PIN 码解锁"));
        } else {
            setLastError(QStringLiteral("4G 操作失败: %1").arg(err.left(50)));
        }

        setCellularStatus(CellularStatus::CellError);
        Q_EMIT cellularOperationFailed(m_lastError);
    }
}

void NetworkManagerService::refreshCellularStatus()
{
    // 原生检测：4G 接口存在即硬件在（RNDIS 网棒拔出节点即消失，内核事实无需去抖）；
    // 有全局 IPv4 即数据已通（不受 LOWER_UP 载波标志干扰，比接口 flags 可靠）
    const QString cellDevice = discoverCellularDevice();
    m_cellularDeviceName = cellDevice;  // 缓存供控制路径使用

    if (cellDevice.isEmpty()) {
        updateHasCellularHardware(false);
        m_cellularEnablePending = false;
        bool changed = false;
        if (m_cellularStatus != CellularStatus::CellDisabled) { m_cellularStatus = CellularStatus::CellDisabled; changed = true; }
        if (!m_cellularIpAddress.isEmpty()) { m_cellularIpAddress.clear(); changed = true; }
        if (!m_cellularOperator.isEmpty())  { m_cellularOperator.clear();  changed = true; }
        if (m_cellularSignal != 0)          { m_cellularSignal = 0;        changed = true; }
        if (changed) {
            qDebug() << "[NetworkManager] 4G 状态(原生): 未检测到接口 -> Disabled/无硬件";
            Q_EMIT cellularStatusChanged();
            deriveNetworkModeFromState();
        }
        return;
    }

    updateHasCellularHardware(true);

    QString ipAddress;
    const QNetworkInterface iface = QNetworkInterface::interfaceFromName(cellDevice);
    const bool hasIp = iface.isValid() && hasGlobalIPv4(iface, &ipAddress);

    CellularStatus newStatus;
    if (hasIp) {
        newStatus = CellularStatus::CellConnected;
        m_cellularEnablePending = false;   // 已落定
        m_cellularDisablePending = false;  // 有 IP 说明关闭未成功，清除挂起窗口
    } else if (m_cellularEnablePending) {
        newStatus = CellularStatus::CellSearching;  // 开启挂起窗口：DHCP/拨号中，不误判 Disabled
        ipAddress.clear();
    } else if (m_cellularDisablePending) {       // 关闭挂起窗口：命令完成前保持 Disabling
        newStatus = CellularStatus::CellDisabling;
        ipAddress.clear();
    } else {
        newStatus = CellularStatus::CellDisabled;
        ipAddress.clear();
    }

    bool changed = false;
    if (m_cellularStatus != newStatus)    { m_cellularStatus = newStatus;   changed = true; }
    if (m_cellularIpAddress != ipAddress) { m_cellularIpAddress = ipAddress; changed = true; }

    if (changed) {
        qDebug() << "[NetworkManager] 4G 状态(原生): dev=" << cellDevice
                 << "status=" << static_cast<int>(m_cellularStatus)
                 << "ip=" << m_cellularIpAddress;
        Q_EMIT cellularStatusChanged();
        deriveNetworkModeFromState();
    }
}

void NetworkManagerService::setCellularSignal(int percent)
{
    percent = qBound(0, percent, 100);
    qInfo() << "[NetworkManager] setCellularSignal:" << percent
            << "(was:" << m_cellularSignal << ")";
    if (m_cellularSignal != percent) {
        m_cellularSignal = percent;
        Q_EMIT cellularStatusChanged();
    }
}

void NetworkManagerService::setCellularOperator(const QString &name)
{
    if (!name.isEmpty() && m_cellularOperator != name) {
        m_cellularOperator = name;
        Q_EMIT cellularStatusChanged();
    }
}

void NetworkManagerService::deriveNetworkModeFromState()
{
    // 过渡态跳过：等 WiFi/4G 都落定后再派生，防止开关切换中间态造成模式抖动
    if (m_wifiStatus == WifiStatus::Unknown || m_wifiStatus == WifiStatus::Connecting)
        return;
    if (m_cellularStatus == CellularStatus::CellUnknown || m_cellularStatus == CellularStatus::CellSearching)
        return;

    // wifiOn = 射频开（接口启用：未连接/已连接）；cellOn = 4G 数据在（注册/连接/漫游）
    const bool wifiOn = (m_wifiStatus == WifiStatus::Disconnected ||
                         m_wifiStatus == WifiStatus::Connected);
    const bool cellOn = (m_cellularStatus == CellularStatus::CellRegistered ||
                         m_cellularStatus == CellularStatus::CellConnected ||
                         m_cellularStatus == CellularStatus::CellRoaming);

    int derived;
    if (!wifiOn && !cellOn) {
        derived = static_cast<int>(NetworkMode::AllCellularPriority);   // 双关：默认全开优先4G
    } else if (wifiOn && !cellOn) {
        derived = static_cast<int>(NetworkMode::WifiOnly);
    } else if (!wifiOn && cellOn) {
        derived = static_cast<int>(NetworkMode::CellularOnly);
    } else {
        // 双开：保留当前"全开"优先级偏好；当前不是全开模式时默认全开优先4G
        derived = (m_networkMode == static_cast<int>(NetworkMode::AllWifiPriority))
                  ? static_cast<int>(NetworkMode::AllWifiPriority)
                  : static_cast<int>(NetworkMode::AllCellularPriority);
    }

    if (m_networkMode != derived) {
        m_networkMode = derived;
        qInfo() << "[NetworkManager] 网络状态落定，派生网络模式:" << derived;
        Q_EMIT networkModeChanged();
    }
}

void NetworkManagerService::setCellularStatus(CellularStatus status)
{
    runOnMainThread([this, status]() {
        if (m_cellularStatus != status) {
            m_cellularStatus = status;
            Q_EMIT cellularStatusChanged();
            deriveNetworkModeFromState();
        }
    });
}

void NetworkManagerService::setLastError(const QString &error)
{
    runOnMainThread([this, error]() {
        if (m_lastError != error) {
            m_lastError = error;
            Q_EMIT lastErrorChanged();
        }
    });
}

// ============================================================
// 状态轮询
// ============================================================

void NetworkManagerService::onStatusPollTimer()
{
    // 原生检测为微秒级同步调用（getifaddrs + 小文件读取），直接主线程执行，无需工作线程
    refreshWifiStatus();
    refreshCellularStatus();
}

// ============================================================
// 工具方法
// ============================================================

int NetworkManagerService::signalQualityToPercent(const QString &qualityStr) const
{
    bool ok = false;
    int val = qualityStr.trimmed().toInt(&ok);
    if (!ok) return 0;

    if (val > 0) {
        return qBound(0, val, 100);
    } else {
        return qBound(0, static_cast<int>((val + 90) * 100 / 60), 100);
    }
}

void NetworkManagerService::updateHasCellularHardware(bool hasHardware)
{
    runOnMainThread([this, hasHardware]() {
        if (m_hasCellularHardware != hasHardware) {
            m_hasCellularHardware = hasHardware;
            qDebug() << "[NetworkManager] hasCellularHardware 变化:" << hasHardware;
            Q_EMIT cellularHardwareChanged(hasHardware);
        }
    });
}
