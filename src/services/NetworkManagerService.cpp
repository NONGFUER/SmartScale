#include "NetworkManagerService.h"
#include <QCoreApplication>
#include <QRegularExpression>
#include <QDebug>
#include <QtConcurrent/QtConcurrent>

// ============================================================
// 常量定义
// ============================================================
static const int    kStatusPollIntervalMs = 10000;  // 状态轮询间隔
static const int    kScanTimeoutMs        = 15000;   // 扫描超时
static const int    kConnectTimeoutMs     = 30000;   // 连接超时

// nmcli 路径（按优先级搜索，兼容不同 Linux 发行版）
static const char *kNmcliPaths[] = {
    "/usr/bin/nmcli",
    "/usr/sbin/nmcli",
    "/bin/nmcli",
    nullptr
};

// mmcli 路径（按优先级搜索）
static const char *kMmcliPaths[] = {
    "/usr/bin/mmcli",
    "/usr/sbin/mmcli",
    "/bin/mmcli",
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
    m_mmcliPath = findExecutable(kMmcliPaths);

    qDebug() << "[NetworkManager] 工具路径: nmcli=" << m_nmcliPath
             << "mmcli=" << (m_mmcliPath.isEmpty() ? "(未找到)" : m_mmcliPath);

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

bool NetworkManagerService::hasModemManager() const
{
    return !m_mmcliPath.isEmpty();
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
    QProcess proc;
    proc.start(m_nmcliPath, QStringList() << "-t" << "-f" << "DEVICE,TYPE" << "device");
    if (!proc.waitForFinished(3000)) return QString();

    const auto lines = QString::fromUtf8(proc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        auto parts = line.split(':');
        if (parts.size() >= 2 && parts[1].trimmed().contains("wifi", Qt::CaseInsensitive)) {
            return parts[0].trimmed();
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
    m_pendingConnectionName.clear();

    // 动态发现 WiFi 设备名
    QString wifiDevice = discoverWifiDevice();
    if (wifiDevice.isEmpty()) {
        setLastError(QStringLiteral("未找到 Wi-Fi 设备"));
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    setWifiStatus(WifiStatus::Connecting);

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

void NetworkManagerService::onWifiConnectFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode == 0) {
        qDebug() << "[NetworkManager] Wi-Fi 连接成功";
        m_lastError.clear();
        // 优先使用 m_pendingSsid（用户主动连接的目标），这是最准确的
        QString successSsid = m_pendingSsid.isEmpty() ? m_wifiSsid : m_pendingSsid;
        m_wifiSsid = successSsid;
        setWifiStatus(WifiStatus::Connected);
        Q_EMIT wifiConnectionSuccess(successSsid);
        refreshWifiStatus();
    } else {
        QString errOutput = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        qWarning() << "[NetworkManager] Wi-Fi 连接失败:" << errOutput;

        if (errOutput.contains(QStringLiteral("Secrets were required")) ||
            errOutput.contains("no valid connections")) {
            setLastError(QStringLiteral("密码错误或认证失败"));
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

void NetworkManagerService::onWifiDisconnectFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (exitCode == 0) {
        qDebug() << "[NetworkManager] Wi-Fi 已断开";
        m_wifiSsid.clear();
        m_wifiIpAddress.clear();
        m_wifiSignal = 0;
        setWifiStatus(WifiStatus::Disconnected);
    } else {
        qWarning() << "[NetworkManager] 断开 Wi-Fi 失败:"
                    << QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        refreshWifiStatus();
    }
}

void NetworkManagerService::refreshWifiStatus()
{
    qDebug() << "[NetworkManager] refreshWifiStatus() 开始";

    if (!hasNetworkManager()) {
        setWifiStatus(WifiStatus::Disabled);
        return;
    }

    // 第一步：动态查找 Wi-Fi 设备名
    QString wifiDevice = discoverWifiDevice();

    if (wifiDevice.isEmpty()) {
        qWarning() << "[NetworkManager] refreshWifiStatus: 未找到 WiFi 设备";
        setWifiStatus(WifiStatus::Disabled);
        return;
    }

    qDebug() << "[NetworkManager] 找到 WiFi 设备:" << wifiDevice;

    // 第二步：查询设备状态（获取 GENERAL.STATE 和 GENERAL.CONNECTION）
    QProcess proc;
    proc.start(m_nmcliPath, QStringList()
               << "-t"
               << "-f" << "GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS"
               << "device" << "show" << wifiDevice);

    if (!proc.waitForFinished(3000)) {
        qWarning() << "[NetworkManager] refreshWifiStatus: nmcli 超时";
        return;
    }

    QString output = QString::fromUtf8(proc.readAllStandardOutput());
    int exitCode = proc.exitCode();
    QString errOutput = QString::fromUtf8(proc.readAllStandardError());
    qDebug() << "[NetworkManager] nmcli device show" << wifiDevice
             << "exitCode=" << exitCode << "stderr=" << errOutput;
    qDebug() << "[NetworkManager] nmcli device show 原始输出:\n" << output;

    // 解析状态和连接名
    QString stateStr;
    QString connName;   // nmcli 连接配置名（可能被 sanitize 过，不等于真实 SSID）
    for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
        auto pair = line.split(':', Qt::SkipEmptyParts);
        if (pair.size() < 2) continue;
        QString key   = pair[0].trimmed().toLower();
        QString value = pair[1].trimmed();

        if (key.contains("state")) {
            stateStr = value;
        } else if (key.contains("general.connection")) {
            connName = value;
        } else if (key.contains("ip4.address") && !value.isEmpty()) {
            m_wifiIpAddress = value.split('/').first();
        }
    }

    // 第三步：如果已连接，通过连接配置名反查真实 SSID
    // GENERAL.CONNECTION 返回的是连接 profile 名（可能经 sanitize 截断），
    // 不是原始 SSID（如 "吴赛杰的iPhone" → 可能变成 "iPhone"）
    if (!connName.isEmpty() && connName != QStringLiteral("--")) {
        QProcess ssidProc;
        ssidProc.start(m_nmcliPath, QStringList()
                       << "-t" << "-f" << "802-11-wireless.ssid"
                       << "connection" << "show" << connName);

        if (ssidProc.waitForFinished(3000)) {
            QString rawOutput = QString::fromUtf8(ssidProc.readAllStandardOutput()).trimmed();
            qDebug() << "[NetworkManager] 连接" << connName << "的 SSID 原始输出:" << rawOutput;

            // 只取第一行（nmcli 可能返回多行重复值，如多个 profile）
            QString firstLine = rawOutput.split('\n', Qt::SkipEmptyParts).value(0);
            QString realSsid = extractSsidValue(firstLine);
            qDebug() << "[NetworkManager] 解析后的真实 SSID:" << realSsid;
            if (!realSsid.isEmpty() && realSsid != QStringLiteral("--")) {
                m_wifiSsid = realSsid;
            }
        } else {
            qWarning() << "[NetworkManager] 查询 SSID 超时，使用连接名作为 fallback:" << connName;
            m_wifiSsid = connName;
        }
    } else {
        m_wifiSsid.clear();
    }

    // 解析状态枚举
    WifiStatus newStatus = WifiStatus::Unknown;
    if (stateStr.contains("connected", Qt::CaseInsensitive)) {
        newStatus = WifiStatus::Connected;
    } else if (stateStr.contains("connecting", Qt::CaseInsensitive)) {
        newStatus = WifiStatus::Connecting;
    } else if (stateStr.contains("disconnected", Qt::CaseInsensitive) ||
               stateStr.contains("unavailable", Qt::CaseInsensitive)) {
        newStatus = WifiStatus::Disconnected;
    } else if (stateStr.contains("unmanaged", Qt::CaseInsensitive)) {
        newStatus = WifiStatus::Disabled;
    }

    qDebug() << "[NetworkManager] refreshWifiStatus 结果:"
             << "state=" << stateStr << "(" << static_cast<int>(newStatus) << ")"
             << "connName=" << connName
             << "realSsid=" << m_wifiSsid
             << "ip=" << m_wifiIpAddress;

    setWifiStatus(newStatus);
}

void NetworkManagerService::setWifiStatus(WifiStatus status)
{
    if (m_wifiStatus != status) {
        m_wifiStatus = status;
        Q_EMIT wifiStatusChanged();
    }
}

// ============================================================
// 4G 操作实现
// ============================================================

void NetworkManagerService::enableCellular()
{
    qDebug() << "[NetworkManager] 开启 4G 移动数据...";
    setCellularStatus(CellularStatus::Searching);

    // ===== 模式1：ModemManager (mmcli) — 传统 4G 模块控制 =====
    if (hasModemManager()) {
        QString modemIdx = discoverModemIndex();
        if (!modemIdx.isEmpty()) {
            qDebug() << "[NetworkManager] 使用 ModemManager 模式启用 4G";
            // 有 modem 设备，走原有的 mmcli/nmcli GSM 逻辑
            // ... 原有代码 ...
            if (hasNetworkManager()) {
                QProcess findProc;
                findProc.start(m_nmcliPath, QStringList()
                               << "-t" << "-f" << "NAME,TYPE"
                               << "connection" << "show");

                if (findProc.waitForFinished(3000)) {
                    const QString output = QString::fromUtf8(findProc.readAllStandardOutput());
                    QString gsmConnName;

                    for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
                        if (line.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
                            line.contains(QStringLiteral("mobile"), Qt::CaseInsensitive)) {
                            gsmConnName = line.split(':').first().trimmed();
                            qDebug() << "[NetworkManager] 找到已有 GSM 连接配置:" << gsmConnName;
                            break;
                        }
                    }

                    if (!gsmConnName.isEmpty()) {
                        qDebug() << "[NetworkManager] 通过 nmcli 激活连接:" << gsmConnName;
                        QStringList args;
                        args << "connection" << "up" << gsmConnName
                             << "--wait-connect-timeout" << "30";

                        disconnect(m_process, nullptr, this, nullptr);
                        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                                this, &NetworkManagerService::onCellularOpFinished);

                        m_process->start(m_nmcliPath, args);
                        m_pendingCellularOp = true;

                        QTimer::singleShot(35000, this, [this]() {
                            if (m_cellularStatus == CellularStatus::Searching) {
                                m_process->kill();
                                setLastError(QStringLiteral("4G 启用超时"));
                                qWarning() << "[NetworkManager]" << m_lastError;
                                setCellularStatus(CellularStatus::Error);
                                Q_EMIT cellularOperationFailed(m_lastError);
                            }
                        });
                        return;
                    }
                }
            }

            // fallback: mmcli --simple-connect
            enableCellularViaModem();
            return;
        }
    }

    // ===== 模式2：网络接口模式 (nmcli) — 4G 以太网模块 / USB dongle =====
    qDebug() << "[NetworkManager] 尝试使用网络接口模式启用 4G";
    enableCellularViaDevice();
}

void NetworkManagerService::enableCellularViaDevice()
{
    QString cellDevice = discoverCellularDevice();
    m_cellularDeviceName = cellDevice;

    if (cellDevice.isEmpty()) {
        setLastError(QStringLiteral("未检测到 4G 网络接口设备"));
        qWarning() << "[NetworkManager]" << m_lastError;
        // 无硬件保持 Disabled，不触发 Error
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 通过 nmcli 启用 4G 接口:" << cellDevice;

    // 策略：查找与该设备关联的 GSM/cellular 连接配置并激活
    if (hasNetworkManager()) {
        QProcess findProc;
        findProc.start(m_nmcliPath, QStringList()
                       << "-t" << "-f" << "NAME,TYPE,DEVICE"
                       << "connection" << "show");

        if (findProc.waitForFinished(3000)) {
            const QString output = QString::fromUtf8(findProc.readAllStandardOutput());
            QString targetConn;

            for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
                auto parts = line.split(':');
                if (parts.size() >= 3 && parts[2].trimmed() == cellDevice) {
                    QString connType = parts[1].trimmed().toLower();
                    // 找到绑定到该设备的任意连接配置
                    targetConn = parts[0].trimmed();
                    qDebug() << "[NetworkManager] 找到设备" << cellDevice << "的连接配置:" << targetConn;
                    break;
                }
            }

            if (!targetConn.isEmpty()) {
                QStringList args;
                args << "connection" << "up" << targetConn
                     << "--wait-connect-timeout" << "30";

                disconnect(m_process, nullptr, this, nullptr);
                connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                        this, &NetworkManagerService::onCellularOpFinished);

                m_process->start(m_nmcliPath, args);
                m_pendingCellularOp = true;

                QTimer::singleShot(35000, this, [this]() {
                    if (m_cellularStatus == CellularStatus::Searching) {
                        m_process->kill();
                        setLastError(QStringLiteral("4G 启用超时"));
                        setCellularStatus(CellularStatus::Error);
                        Q_EMIT cellularOperationFailed(m_lastError);
                    }
                });
                return;
            }
        }

        // 如果没找到现成连接，尝试直接让设备重新连接（nmcli device connect）
        qWarning() << "[NetworkManager] 未找到" << cellDevice << "的连接配置，尝试 device connect";
        QStringList args;
        args << "device" << "connect" << cellDevice;

        disconnect(m_process, nullptr, this, nullptr);
        connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                this, &NetworkManagerService::onCellularOpFinished);

        m_process->start(m_nmcliPath, args);
        m_pendingCellularOp = true;

        QTimer::singleShot(30000, this, [this]() {
            if (m_cellularStatus == CellularStatus::Searching) {
                m_process->kill();
                setLastError(QStringLiteral("4G 接口连接超时"));
                setCellularStatus(CellularStatus::Error);
                Q_EMIT cellularOperationFailed(m_lastError);
            }
        });
        return;
    }

    // 没有 nmcli 的情况
    setLastError(QStringLiteral("无 NetworkManager，无法控制 4G 接口"));
    Q_EMIT cellularOperationFailed(m_lastError);
}

void NetworkManagerService::enableCellularViaModem()
{
    QString modemIdx = discoverModemIndex();
    if (modemIdx.isEmpty()) {
        // 无硬件不是"错误"，保持 Disabled 状态，仅记录原因供 UI 展示
        setLastError(QStringLiteral("未检测到 4G 模块（请检查硬件连接或驱动）"));
        qWarning() << "[NetworkManager]" << m_lastError;
        // 保持 Disabled 状态不变，不触发 Error 状态切换
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 使用调制解调器" << modemIdx << "启用 4G (--simple-connect)...";

    // 使用 mmcli --simple-connect 让 modem 直接建立数据承载
    // apn=internet 是通用默认值，不同运营商可能需要调整
    QStringList args;
    args << "-m" << modemIdx << "--simple-connect" << "apn=internet";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(m_mmcliPath, args);
    m_pendingCellularOp = true;

    // 超时保护
    QTimer::singleShot(35000, this, [this]() {
        if (m_cellularStatus == CellularStatus::Searching) {
            m_process->kill();
            setLastError(QStringLiteral("4G 启用超时 (mmcli)"));
            qWarning() << "[NetworkManager]" << m_lastError;
            setCellularStatus(CellularStatus::Error);
            Q_EMIT cellularOperationFailed(m_lastError);
        }
    });
}

void NetworkManagerService::disableCellular()
{
    qDebug() << "[NetworkManager] 关闭 4G 移动数据...";
    setCellularStatus(CellularStatus::Searching);

    // ===== 模式1：ModemManager (mmcli) — 传统 4G 模块控制 =====
    if (hasModemManager()) {
        QString modemIdx = discoverModemIndex();
        if (!modemIdx.isEmpty()) {
            qDebug() << "[NetworkManager] 使用 ModemManager 模式禁用 4G";

            // 原有逻辑：先尝试 nmcli 断开 GSM 连接
            if (hasNetworkManager()) {
                QProcess findProc;
                findProc.start(m_nmcliPath, QStringList()
                               << "-t" << "-f" << "NAME,TYPE,DEVICE"
                               << "connection" << "show" << "--active");

                if (findProc.waitForFinished(3000)) {
                    const QString output = QString::fromUtf8(findProc.readAllStandardOutput());
                    for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
                        if (line.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
                            line.contains(QStringLiteral("mobile"), Qt::CaseInsensitive)) {
                            auto parts = line.split(':');
                            if (parts.size() >= 3) {
                                QString device = parts[2].trimmed();
                                qDebug() << "[NetworkManager] 通过 nmcli 断开设备:" << device;

                                QStringList args;
                                args << "device" << "disconnect" << device;

                                disconnect(m_process, nullptr, this, nullptr);
                                connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                                        this, &NetworkManagerService::onCellularOpFinished);

                                m_process->start(m_nmcliPath, args);
                                m_pendingCellularOp = false;

                                QTimer::singleShot(15000, this, [this]() {
                                    if (m_cellularStatus == CellularStatus::Searching) {
                                        m_process->kill();
                                        disableCellularViaModem();
                                    }
                                });
                                return;
                            }
                        }
                    }
                    qDebug() << "[NetworkManager] 未找到活跃的 GSM 连接，尝试 mmcli";
                }
            }

            disableCellularViaModem();
            return;
        }
    }

    // ===== 模式2：网络接口模式 (nmcli) — 4G 以太网模块 / USB dongle =====
    qDebug() << "[NetworkManager] 尝试使用网络接口模式禁用 4G";
    disableCellularViaDevice();
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
        setCellularStatus(CellularStatus::Disabled);
        Q_EMIT cellularDisabled();
        return;
    }

    qDebug() << "[NetworkManager] 通过 nmcli 断开 4G 接口:" << cellDevice;

    QStringList args;
    args << "device" << "disconnect" << cellDevice;

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(m_nmcliPath, args);
    m_pendingCellularOp = false;

    QTimer::singleShot(15000, this, [this]() {
        if (m_cellularStatus == CellularStatus::Searching) {
            m_process->kill();
            qDebug() << "[NetworkManager] nmcli 断开 4G 接口超时，强制标记为禁用";
            m_cellularOperator.clear();
            m_cellularIpAddress.clear();
            m_cellularSignal = 0;
            setCellularStatus(CellularStatus::Disabled);
            Q_EMIT cellularDisabled();
        }
    });
}

void NetworkManagerService::disableCellularViaModem()
{
    QString modemIdx = discoverModemIndex();
    if (modemIdx.isEmpty()) {
        // 没有检测到 modem，直接标记为禁用
        qDebug() << "[NetworkManager] 未检测到调制解调器，直接标记 4G 为已禁用";
        m_cellularOperator.clear();
        m_cellularIpAddress.clear();
        m_cellularSignal = 0;
        setCellularStatus(CellularStatus::Disabled);
        Q_EMIT cellularDisabled();
        return;
    }

    qDebug() << "[NetworkManager] 使用调制解调器" << modemIdx << "禁用 4G (--simple-disconnect)...";

    QStringList args;
    args << "-m" << modemIdx << "--simple-disconnect";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(m_mmcliPath, args);
    m_pendingCellularOp = false;

    // 超时保护
    QTimer::singleShot(15000, this, [this]() {
        if (m_cellularStatus == CellularStatus::Searching) {
            m_process->kill();
            qDebug() << "[NetworkManager] mmcli 断开超时，强制标记为禁用";
            m_cellularOperator.clear();
            m_cellularIpAddress.clear();
            m_cellularSignal = 0;
            setCellularStatus(CellularStatus::Disabled);
            Q_EMIT cellularDisabled();
        }
    });
}

// ============================================================
// 4G 设备发现（以太网模式）
// ============================================================

QString NetworkManagerService::discoverCellularDevice() const
{
    if (!hasNetworkManager()) return QString();

    // 策略1：遍历所有设备，查找 ethernet 类型且连接配置含 gsm/mobile/cellular 关键字的设备
    QProcess devProc;
    devProc.start(m_nmcliPath, QStringList()
                  << "-t" << "-f" << "DEVICE,TYPE,STATE,CONNECTION"
                  << "device");

    if (devProc.waitForFinished(3000)) {
        QString output = QString::fromUtf8(devProc.readAllStandardOutput());
        qDebug() << "[NetworkManager] discoverCellularDevice: 设备列表:\n" << output;

        // 先尝试精确匹配：检查连接配置名是否包含 4G 相关关键字
        QProcess connProc;
        connProc.start(m_nmcliPath, QStringList()
                       << "-t" << "-f" << "NAME,TYPE,DEVICE"
                       << "connection" << "show");

        if (connProc.waitForFinished(3000)) {
            const auto lines = QString::fromUtf8(connProc.readAllStandardOutput()).split('\n', Qt::SkipEmptyParts);
            for (const auto &line : lines) {
                // 格式: 连接名:类型:设备
                if (line.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
                    line.contains(QStringLiteral("mobile"), Qt::CaseInsensitive) ||
                    line.contains(QStringLiteral("cellular"), Qt::CaseInsensitive) ||
                    line.contains(QStringLiteral("4g"), Qt::CaseInsensitive)) {
                    auto parts = line.split(':');
                    if (parts.size() >= 3) {
                        QString device = parts[2].trimmed();
                        if (!device.isEmpty()) {
                            qDebug() << "[NetworkManager] discoverCellularDevice: 通过连接配置找到 4G 设备:" << device;
                            return device;
                        }
                    }
                }
            }
        }

        // 策略2：fallback — 检查常见 4G 接口名的设备状态
        // 某些 4G USB 模块会被命名为 eth1, usb0, enx* 等
        static const QVector<QString> kCandidateIfaces = {
            QStringLiteral("eth1"),
            QStringLiteral("usb0"),
            QStringLiteral("ppp0")
        };

        for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
            auto parts = line.split(':');
            if (parts.size() < 2) continue;
            QString device = parts[0].trimmed();
            QString type   = parts[1].trimmed().toLower();

            // 只看 ethernet 类型（排除 wifi、loopback 等）
            if (type != QStringLiteral("ethernet")) continue;

            // 检查是否是已知候选接口名
            for (const auto &candidate : kCandidateIfaces) {
                if (device == candidate) {
                    qDebug() << "[NetworkManager] discoverCellularDevice: 通过候选列表找到 4G 设备:" << device;
                    return device;
                }
            }

            // 策略3：enx* 开头的通常是 USB 网络设备（可能是 4G 模块）
            if (device.startsWith(QStringLiteral("enx"))) {
                qDebug() << "[NetworkManager] discoverCellularDevice: 找到 USB 以太网设备（可能为 4G）:" << device;
                return device;
            }
        }
    }

    qWarning() << "[NetworkManager] discoverCellularDevice: 未检测到 4G 网络接口设备";
    return QString();
}

// ============================================================
// 调制解调器发现 (mmcli 模式)
// ============================================================

QString NetworkManagerService::discoverModemIndex() const
{
    QProcess modemListProc;
    modemListProc.start(m_mmcliPath, QStringList() << "-L");

    if (!modemListProc.waitForFinished(5000)) {
        qWarning() << "[NetworkManager] discoverModemIndex: mmcli -L 超时";
        return QString();
    }

    QString output = QString::fromUtf8(modemListProc.readAllStandardOutput());
    qDebug() << "[NetworkManager] discoverModemIndex: mmcli -L 输出:\n" << output;

    // mmcli -L 输出格式示例：
    //   /org/freedesktop/ModemManager1/Modem/0 [QUECTEL Mobile Broadband Device] ...
    // 匹配路径末尾的数字索引
    QRegularExpression reModem(QStringLiteral("Modem/(\\d+)\\s"));
    QRegularExpressionMatch match = reModem.match(output);

    if (match.hasMatch()) {
        QString idx = match.captured(1);
        qDebug() << "[NetworkManager] discoverModemIndex: 找到调制解调器索引 =" << idx;
        return idx;
    }

    // 兼容 fallback：尝试更宽松的匹配（某些版本输出格式不同）
    QRegularExpression reFallback(QStringLiteral("/(\\d+)\\]"));
    match = reFallback.match(output);
    if (match.hasMatch()) {
        QString idx = match.captured(1);
        qDebug() << "[NetworkManager] discoverModemIndex: (fallback) 找到调制解调器索引 =" << idx;
        return idx;
    }

    qWarning() << "[NetworkManager] discoverModemIndex: 未检测到任何调制解调器设备";
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
            setCellularStatus(CellularStatus::Disabled);
            Q_EMIT cellularDisabled();
        }
        QTimer::singleShot(1000, this, &NetworkManagerService::refreshCellularStatus);
    } else {
        QString err = QString::fromUtf8(m_process->readAllStandardOutput()).trimmed();
        qWarning() << "[NetworkManager] 4G 操作失败:" << err;

        if (err.contains(QStringLiteral("not found"))) {
            setLastError(QStringLiteral("4G 模块未就绪或 SIM 卡未插入"));
        } else if (err.contains(QStringLiteral("SIM PIN"))) {
            setLastError(QStringLiteral("SIM 卡需要 PIN 码解锁"));
        } else {
            setLastError(QStringLiteral("4G 操作失败: %1").arg(err.left(50)));
        }

        setCellularStatus(CellularStatus::Error);
        Q_EMIT cellularOperationFailed(m_lastError);
    }
}

void NetworkManagerService::refreshCellularStatus()
{
    // ===== 模式1：ModemManager (mmcli) — 传统 4G 模块控制 =====
    if (hasModemManager()) {
        QString modemIdx = discoverModemIndex();
        if (!modemIdx.isEmpty()) {
            // 有 modem 设备，使用 mmcli 查询状态（原有逻辑）
            qDebug() << "[NetworkManager] refreshCellularStatus: 使用 ModemManager 模式 (modem=" << modemIdx << ")";
            updateHasCellularHardware(true);

            QProcess proc;
            proc.start(m_mmcliPath, QStringList() << "-m" << modemIdx << "--output-keyvalue");

            if (proc.waitForFinished(5000)) {
                updateCellularStatusFromMmcli(proc.readAllStandardOutput());
                return;  // 成功获取，直接返回
            }
            qWarning() << "[NetworkManager] refreshCellularStatus: mmcli 查询超时";
            // 超时不返回，继续尝试模式2
        } else {
            qDebug() << "[NetworkManager] refreshCellularStatus: 有 ModemManager 但未找到 modem，尝试接口模式";
        }
    }

    // ===== 模式2：网络接口模式 (nmcli) — 4G 以太网模块 / USB dongle =====
    QString cellDevice = discoverCellularDevice();
    m_cellularDeviceName = cellDevice;  // 缓存供后续操作使用

    if (!cellDevice.isEmpty()) {
        qDebug() << "[NetworkManager] refreshCellularStatus: 使用网络接口模式 (device=" << cellDevice << ")";
        updateHasCellularHardware(true);

        QProcess proc;
        proc.start(m_nmcliPath, QStringList()
                   << "-t" << "-f" << "GENERAL.STATE,IP4.ADDRESS,GENERAL.CONNECTION"
                   << "device" << "show" << cellDevice);

        if (proc.waitForFinished(3000)) {
            updateCellularStatusFromNmcli(proc.readAllStandardOutput(), cellDevice);
            return;
        }
        qWarning() << "[NetworkManager] refreshCellularStatus: nmcli 查询超时 (device=" << cellDevice << ")";
    }

    // ===== 都失败：标记为 Disabled + 无硬件 =====
    qDebug() << "[NetworkManager] refreshCellularStatus: 未检测到任何 4G 设备（mmcli 或 网络接口）";
    updateHasCellularHardware(false);
    if (m_cellularStatus != CellularStatus::Disabled) {
        setCellularStatus(CellularStatus::Disabled);
    }
}

void NetworkManagerService::updateCellularStatusFromNmcli(const QString &output, const QString &device)
{
    const auto lines = output.split('\n', Qt::SkipEmptyParts);

    QString stateStr;
    QString connName;

    for (const auto &line : lines) {
        auto pair = line.split(':', Qt::SkipEmptyParts);
        if (pair.size() < 2) continue;

        QString key   = pair[0].trimmed().toLower();
        QString value = pair[1].trimmed();

        if (key.contains("state")) {
            stateStr = value;
        } else if (key.contains("general.connection") && value != QStringLiteral("--")) {
            connName = value;
        } else if (key.contains("ip4.address") && !value.isEmpty()) {
            m_cellularIpAddress = value.split('/').first();
        }
    }

    // 使用连接名作为运营商标识（4G 接口模式下无法获取真实运营商）
    if (!connName.isEmpty()) {
        m_cellularOperator = connName;
    }

    // 从设备名推断信号强度（接口模式通常无法获取真实信号，使用启发式）
    // 如果是 connected 状态，给一个默认中等信号值
    CellularStatus newStatus = CellularStatus::Unknown;
    if (stateStr.contains("connected", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Connected;
        m_cellularSignal = 65;  // 默认中等信号（接口模式无法获取真实值）
    } else if (stateStr.contains("connecting", Qt::CaseInsensitive) ||
               stateStr.contains("activating", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Searching;
        m_cellularSignal = 30;
    } else if (stateStr.contains("disconnected", Qt::CaseInsensitive) ||
               stateStr.contains("unavailable", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Disabled;
        m_cellularSignal = 0;
        m_cellularIpAddress.clear();
    } else if (stateStr.contains("unmanaged", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Disabled;
        m_cellularSignal = 0;
    }

    qDebug() << "[NetworkManager] refreshCellularStatus [接口模式]:"
             << "device=" << device
             << "state=" << stateStr << "(" << static_cast<int>(newStatus) << ")"
             << "conn=" << connName
             << "ip=" << m_cellularIpAddress;

    setCellularStatus(newStatus);
}

void NetworkManagerService::updateCellularStatusFromMmcli(const QString &output)
{
    const auto lines = output.split('\n', Qt::SkipEmptyParts);

    QString accessState;
    QString signalQuality;
    QString operatorName;

    for (const auto &line : lines) {
        auto pair = line.split('=', Qt::SkipEmptyParts);
        if (pair.size() < 2) continue;

        QString key   = pair[0].trimmed().toLower();
        QString value = pair[1].trimmed();

        if (key.contains("state") || key.contains("accessstate")) {
            accessState = value;
        } else if (key.contains("signal")) {
            signalQuality = value.remove('%');
        } else if (key.contains("operator")) {
            operatorName = value;
        } else if (key.contains("ip")) {
            if (value.contains('.')) {
                m_cellularIpAddress = value;
            }
        }
    }

    if (!operatorName.isEmpty())
        m_cellularOperator = operatorName;
    if (!signalQuality.isEmpty())
        m_cellularSignal = signalQuality.toInt();

    CellularStatus newStatus = CellularStatus::Unknown;
    if (accessState.contains("connected", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Connected;
    } else if (accessState.contains("searching", Qt::CaseInsensitive) ||
             accessState.contains("registering", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Searching;
    } else if (accessState.contains("registered", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Registered;
    } else if (accessState.contains("roaming", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Roaming;
    } else if (accessState.contains("disabled", Qt::CaseInsensitive) ||
             accessState.contains("empty", Qt::CaseInsensitive)) {
        newStatus = CellularStatus::Disabled;
    }

    if (newStatus != m_cellularStatus) {
        setCellularStatus(newStatus);
    }
}

void NetworkManagerService::setCellularStatus(CellularStatus status)
{
    if (m_cellularStatus != status) {
        m_cellularStatus = status;
        Q_EMIT cellularStatusChanged();
    }
}

void NetworkManagerService::setLastError(const QString &error)
{
    if (m_lastError != error) {
        m_lastError = error;
        Q_EMIT lastErrorChanged();
    }
}

// ============================================================
// 状态轮询
// ============================================================

void NetworkManagerService::onStatusPollTimer()
{
    Q_UNUSED(QtConcurrent::run([this]() -> void {
        refreshWifiStatus();
        refreshCellularStatus();
    }));
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
    if (m_hasCellularHardware != hasHardware) {
        m_hasCellularHardware = hasHardware;
        qDebug() << "[NetworkManager] hasCellularHardware 变化:" << hasHardware;
        Q_EMIT cellularHardwareChanged(hasHardware);
    }
}
