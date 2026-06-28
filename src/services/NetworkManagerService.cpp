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

// nmcli 路径（大多数 Linux 发行版标准路径）
static const char *kNmcliPath  = "/usr/bin/nmcli";
static const char *kMmcliPath  = "/usr/bin/mmcli";

// ============================================================
// 构造 / 析构
// ============================================================
NetworkManagerService::NetworkManagerService(QObject *parent)
    : QObject(parent)
{
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
        m_lastError = QStringLiteral("未找到 NetworkManager (nmcli)，请先安装: sudo apt install network-manager");
        qWarning() << "[NetworkManager]" << m_lastError;
        return false;
    }

    // 尝试执行一个无副作用的 nmcli 命令来验证权限
    QProcess testProc;
    testProc.start(kNmcliPath, QStringList() << "-t" << "-f" << "RUNNING" << "general" << "status");
    if (!testProc.waitForFinished(3000)) {
        m_lastError = QStringLiteral("nmcli 权限不足或无响应，请确认用户在 networkmanager 组或有 sudo 免密权限");
        qWarning() << "[NetworkManager]" << m_lastError;
        return false;
    }

    return true;
}

bool NetworkManagerService::hasNetworkManager() const
{
    return QFile::exists(kNmcliPath);
}

bool NetworkManagerService::hasModemManager() const
{
    return QFile::exists(kMmcliPath);
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

    m_process->start(kNmcliPath, args);

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
    listProc.start(kNmcliPath, QStringList()
                   << "-t" << "-f" << "SSID,SIGNAL,SECURITY,BSSID"
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
        m_lastError = QStringLiteral("Wi-Fi 扫描失败: %1").arg(QString(errOutput).trimmed());
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
        // 格式: SSID:SIGNAL:SECURITY:BSSID
        const auto fields = line.split(':');
        if (fields.size() >= 3) {
            QString ssid       = fields[0].trimmed();
            QString signalStr  = fields.size() > 1 ? fields[1].trimmed() : QStringLiteral("0");
            QString security   = fields.size() > 2 ? fields[2].trimmed() : QString();
            QString bssid      = fields.size() > 3 ? fields[3].trimmed() : QString();

            if (ssid.isEmpty()) continue;

            bool isSecured = !security.isEmpty() && security != QStringLiteral("--");
            int signal     = signalQualityToPercent(signalStr);

            QString key = ssid.toLower();  // 不区分大小写去重

            if (!bestNetworks.contains(key) || signal > bestNetworks[key]["signal"].toInt()) {
                QVariantMap network;
                network["ssid"]         = ssid;
                network["signal"]       = signal;
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

    qDebug() << "[NetworkManager] 扫描完成，找到" << m_availableNetworks.size() << "个网络（已去重）";
}

void NetworkManagerService::connectWifi(const QString &ssid, const QString &password)
{
    if (!checkPermissions()) {
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    if (ssid.isEmpty()) {
        m_lastError = QStringLiteral("SSID 不能为空");
        Q_EMIT wifiConnectionFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 正在连接到 Wi-Fi:" << ssid
             << "加密:" << !password.isEmpty();

    m_pendingSsid = ssid;
    m_pendingConnectionName.clear();

    setWifiStatus(WifiStatus::Connecting);

    // 两步法：先创建连接配置（connection add），再激活（connection up）
    // 比 "device wifi connect" 更可靠，能正确处理 key-mgmt 属性

    QStringList args;
    args << "connection" << "add"
         << "type"     << "wifi"
         << "con-name" << sanitizeConnectionName(ssid)
         << "ifname"   << "wlan0"
         << "ssid"     << ssid;

    if (!password.isEmpty()) {
        // 显式指定 WPA-PSK 安全方式，避免 "key-mgmt: 缺少属性" 错误
        args << "wifi-sec.key-mgmt"  << "wpa-psk"
             << "wifi-sec.psk"       << password;
    }

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiConnectionAdded);

    m_process->start(kNmcliPath, args);

    // 创建连接配置超时保护
    QTimer::singleShot(10000, this, [this, ssid]() {
        if (m_wifiStatus == WifiStatus::Connecting) {
            m_process->kill();
            m_lastError = QStringLiteral("创建连接配置超时 (%1)").arg(ssid);
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

        m_lastError = QStringLiteral("创建连接失败: %1").arg(errOutput.left(60));
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

    m_process->start(kNmcliPath, args);

    // 连接超时保护
    QTimer::singleShot(kConnectTimeoutMs - 10000, this, [this]() {
        if (m_wifiStatus == WifiStatus::Connecting) {
            m_process->kill();
            m_lastError = QStringLiteral("连接超时");
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
            m_lastError = QStringLiteral("密码错误或认证失败");
        } else if (errOutput.contains(QStringLiteral("not found"))) {
            m_lastError = QStringLiteral("找不到该网络 (%1)").arg(m_wifiSsid);
        } else if (errOutput.contains("timeout")) {
            m_lastError = QStringLiteral("连接超时，请检查信号强度");
        } else {
            m_lastError = QStringLiteral("连接失败: %1").arg(errOutput.left(50));
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

    qDebug() << "[NetworkManager] 断开 Wi-Fi";

    QStringList args;
    args << "device" << "disconnect" << "wlan0";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onWifiDisconnectFinished);

    m_process->start(kNmcliPath, args);
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

    // 第一步：查找 Wi-Fi 设备名
    QProcess devProc;
    devProc.start(kNmcliPath, QStringList() << "-t" << "-f" << "DEVICE,TYPE" << "device");
    if (!devProc.waitForFinished(3000)) {
        qWarning() << "[NetworkManager] refreshWifiStatus: 查询设备列表超时";
        return;
    }

    QString devOutput = QString::fromUtf8(devProc.readAllStandardOutput());
    qDebug() << "[NetworkManager] 设备列表:\n" << devOutput;

    QString wifiDevice;
    const auto lines = devOutput.split('\n', Qt::SkipEmptyParts);
    for (const auto &line : lines) {
        auto parts = line.split(':');
        if (parts.size() >= 2 && parts[1].trimmed().contains("wifi", Qt::CaseInsensitive)) {
            wifiDevice = parts[0].trimmed();
            qDebug() << "[NetworkManager] 找到 WiFi 设备:" << wifiDevice;
            break;
        }
    }

    if (wifiDevice.isEmpty()) {
        qWarning() << "[NetworkManager] 未找到 WiFi 设备";
        setWifiStatus(WifiStatus::Disabled);
        return;
    }

    // 第二步：查询设备状态（获取 GENERAL.STATE 和 GENERAL.CONNECTION）
    QProcess proc;
    proc.start(kNmcliPath, QStringList()
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
        ssidProc.start(kNmcliPath, QStringList()
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
    if (!hasModemManager()) {
        m_lastError = QStringLiteral("未找到 ModemManager (mmcli)，请先安装并确保有 4G 模块");
        qWarning() << "[NetworkManager]" << m_lastError;
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 开启 4G 移动数据...";

    QStringList args;
    args << "connection" << "up" << "--wait-connect-timeout" << "30";

    QProcess findProc;
    findProc.start(kNmcliPath, QStringList()
                   << "-t" << "-f" << "NAME,TYPE"
                   << "connection" << "show" << "--active");

    if (findProc.waitForFinished(3000)) {
        const QString output = QString::fromUtf8(findProc.readAllStandardOutput());
        bool foundMobileConn = false;

        for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
            if (line.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
                line.contains(QStringLiteral("mobile"), Qt::CaseInsensitive)) {
                QString connName = line.split(':').first().trimmed();
                args.append(connName);
                foundMobileConn = true;
                break;
            }
        }

        if (!foundMobileConn) {
            enableCellularViaModem();
            return;
        }
    }

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(kNmcliPath, args);
    m_pendingCellularOp = true;
}

void NetworkManagerService::enableCellularViaModem()
{
    QProcess modemListProc;
    modemListProc.start(kMmcliPath, QStringList() << "-L");

    if (!modemListProc.waitForFinished(5000)) {
        m_lastError = QStringLiteral("无法列出 4G 调制解调器设备");
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    QString output = modemListProc.readAllStandardOutput();
    QRegularExpression reModem("/\\d+/");
    QRegularExpressionMatch match = reModem.match(output);

    if (!match.hasMatch()) {
        m_lastError = QStringLiteral("未检测到 4G 调制解调器模块");
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    QString modemIdx = match.captured().remove('/');

    qDebug() << "[NetworkManager] 使用调制解调器:" << modemIdx << "启用 4G...";

    QStringList args;
    args << "-m" << modemIdx << "--simple-connect" << "apn=internet";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(kMmcliPath, args);
    m_pendingCellularOp = true;
}

void NetworkManagerService::disableCellular()
{
    if (!hasModemManager()) {
        m_lastError = QStringLiteral("未找到 ModemManager");
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    qDebug() << "[NetworkManager] 关闭 4G 移动数据...";

    QProcess findProc;
    findProc.start(kNmcliPath, QStringList()
                   << "-t" << "-f" << "NAME,TYPE,DEVICE"
                   << "connection" << "show" << "--active");

    if (findProc.waitForFinished(3000)) {
        const QString output = QString::fromUtf8(findProc.readAllStandardOutput());
        for (const auto &line : output.split('\n', Qt::SkipEmptyParts)) {
            if (line.contains(QStringLiteral("gsm"), Qt::CaseInsensitive) ||
                line.contains(QStringLiteral("mobile"), Qt::CaseInsensitive)) {
                QString device = line.split(':')[2].trimmed();

                QStringList args;
                args << "device" << "disconnect" << device;

                disconnect(m_process, nullptr, this, nullptr);
                connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
                        this, &NetworkManagerService::onCellularOpFinished);

                m_process->start(kNmcliPath, args);
                m_pendingCellularOp = false;
                return;
            }
        }
    }

    disableCellularViaModem();
}

void NetworkManagerService::disableCellularViaModem()
{
    QProcess modemListProc;
    modemListProc.start(kMmcliPath, QStringList() << "-L");

    if (!modemListProc.waitForFinished(5000)) {
        m_lastError = QStringLiteral("无法访问调制解调器");
        Q_EMIT cellularOperationFailed(m_lastError);
        return;
    }

    QString output = modemListProc.readAllStandardOutput();
    QRegularExpression reModem("/\\d+/");
    QRegularExpressionMatch match = reModem.match(output);

    if (!match.hasMatch()) {
        m_cellularOperator.clear();
        m_cellularIpAddress.clear();
        m_cellularSignal = 0;
        setCellularStatus(CellularStatus::Disabled);
        Q_EMIT cellularDisabled();
        return;
    }

    QString modemIdx = match.captured().remove('/');
    qDebug() << "[NetworkManager] 使用调制解调器:" << modemIdx << "禁用 4G...";

    QStringList args;
    args << "-m" << modemIdx << "--simple-disconnect";

    disconnect(m_process, nullptr, this, nullptr);
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &NetworkManagerService::onCellularOpFinished);

    m_process->start(kMmcliPath, args);
    m_pendingCellularOp = false;
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
            m_lastError = QStringLiteral("4G 模块未就绪或 SIM 卡未插入");
        } else if (err.contains(QStringLiteral("SIM PIN"))) {
            m_lastError = QStringLiteral("SIM 卡需要 PIN 码解锁");
        } else {
            m_lastError = QStringLiteral("4G 操作失败: %1").arg(err.left(50));
        }

        setCellularStatus(CellularStatus::Error);
        Q_EMIT cellularOperationFailed(m_lastError);
    }
}

void NetworkManagerService::refreshCellularStatus()
{
    if (!hasModemManager()) {
        if (m_cellularStatus != CellularStatus::Disabled) {
            setCellularStatus(CellularStatus::Disabled);
        }
        return;
    }

    QProcess proc;
    proc.start(kMmcliPath, QStringList() << "-m" << "0" << "--output-keyvalue");

    if (proc.waitForFinished(5000)) {
        updateCellularStatusFromMmcli(proc.readAllStandardOutput());
    }
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
