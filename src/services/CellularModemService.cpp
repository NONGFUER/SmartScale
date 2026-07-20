#include "CellularModemService.h"

#include <QSerialPortInfo>
#include <QRegularExpression>
#include <QDir>
#include <QDebug>

// ============================================================================
// 构造 / 析构
// ============================================================================

CellularModemService::CellularModemService(QObject *parent)
    : QObject(parent)
{
    m_probeTimer = new QTimer(this);
    m_probeTimer->setSingleShot(true);
    connect(m_probeTimer, &QTimer::timeout, this, &CellularModemService::onProbeTimeout);

    m_queryTimer = new QTimer(this);
    m_queryTimer->setSingleShot(true);
    connect(m_queryTimer, &QTimer::timeout, this, &CellularModemService::onQueryTimeout);

    m_retryTimer = new QTimer(this);
    m_retryTimer->setSingleShot(true);
    connect(m_retryTimer, &QTimer::timeout, this, &CellularModemService::onRetryTimeout);
}

CellularModemService::~CellularModemService()
{
    cleanupSerial();
}

// ============================================================================
// 启动
// ============================================================================

void CellularModemService::start()
{
    // 已在进行中（探测/任一查询阶段）则忽略重复调用
    if (m_state == State::Probing || m_state == State::Querying
        || m_state == State::QueryingImsi || m_state == State::QueryingOperator)
        return;
    // 已成功获取过 CCID 则无需再来一遍
    if (m_state == State::Done && !m_ccid.isEmpty())
        return;

    qInfo() << "[CellularModem] 启动 CCID 获取（遍历 /dev/ttyUSB* 动态确认 AT 端口）";
    m_retryTimer->stop();   // 取消旧的重试定时器，避免外部触发与内部重试并发
    m_retries = 0;
    m_candidates.clear();
    m_candidateIndex = 0;
    m_state = State::Idle;
    m_buffer.clear();
    probeNext();
}

// ============================================================================
// 端口探测：遍历候选，发 AT 收到 OK 即命中
// ============================================================================

void CellularModemService::probeNext()
{
    // 首次进入（或重试重置后）构建候选列表
    if (m_candidates.isEmpty()) {
        // 环境变量强制指定端口（调试/单测用）：SMARTSCALE_MODEM_PORT=/dev/ttyUSB2
        QByteArray forced = qgetenv("SMARTSCALE_MODEM_PORT");
        if (!forced.isEmpty()) {
            m_candidates << QString::fromLocal8Bit(forced);
            qInfo() << "[CellularModem] 使用环境变量强制端口:" << m_candidates.first();
        } else {
            const QList<QSerialPortInfo> ports = QSerialPortInfo::availablePorts();
            for (const QSerialPortInfo &info : ports) {
                const QString name = info.portName();
                // 遍历 /dev/ttyUSB* 动态确认；同时支持按 ASR VID 0x2ECC 过滤（兼容非 ttyUSB 命名）
                const bool isUsbTty = name.startsWith(QStringLiteral("ttyUSB"))
                                   || info.systemLocation().contains(QStringLiteral("ttyUSB"));
                const bool isAsr    = (info.vendorIdentifier() == kAsrVendorId);
                if (isUsbTty || isAsr) {
                    m_candidates << info.systemLocation();
                    qDebug().nospace() << "[CellularModem] 候选 AT 端口: "
                                       << info.systemLocation()
                                       << " vid=0x" << QString::number(info.vendorIdentifier(), 16)
                                       << " pid=0x" << QString::number(info.productIdentifier(), 16);
                }
            }
        }
        // Fallback：某些驱动/系统下 QSerialPortInfo 不列出节点，直接扫 /dev/ttyUSB* 与 /dev/ttyACM*
        QDir devDir(QStringLiteral("/dev"));
        const QStringList direct = devDir.entryList(QStringList()
                                                        << QStringLiteral("ttyUSB*")
                                                        << QStringLiteral("ttyACM*"),
                                                    QDir::System | QDir::NoDotAndDotDot,
                                                    QDir::Name);
        for (const QString &name : direct) {
            const QString path = devDir.absoluteFilePath(name);
            if (!m_candidates.contains(path)) {
                m_candidates << path;
                qDebug() << "[CellularModem] /dev 直接扫描补充候选:" << path;
            }
        }

        m_candidateIndex = 0;
        if (m_candidates.isEmpty()) {
            qWarning() << "[CellularModem] 未发现任何 /dev/ttyUSB* 候选端口";
            fail(QStringLiteral("无候选串口"));
            return;
        }
        qInfo() << "[CellularModem] 共" << m_candidates.size() << "个候选端口，开始探测 AT 接口";
    }

    // 所有候选都试过 → 本轮失败，进入重试/放弃流程
    if (m_candidateIndex >= m_candidates.size()) {
        fail(QStringLiteral("所有候选端口均无 AT 响应"));
        return;
    }

    const QString portName = m_candidates.at(m_candidateIndex++);
    qDebug() << "[CellularModem] 探测端口:" << portName;

    cleanupSerial();
    m_serial = new QSerialPort(this);
    m_serial->setPortName(portName);
    m_serial->setBaudRate(kModemBaud);
    m_serial->setDataBits(QSerialPort::Data8);
    m_serial->setParity(QSerialPort::NoParity);
    m_serial->setStopBits(QSerialPort::OneStop);
    m_serial->setFlowControl(QSerialPort::NoFlowControl);

    if (!m_serial->open(QIODevice::ReadWrite)) {
        qWarning() << "[CellularModem] 无法打开" << portName << "-" << m_serial->errorString();
        delete m_serial;
        m_serial = nullptr;
        probeNext();   // 立刻试下一个候选
        return;
    }

    connect(m_serial, &QSerialPort::readyRead, this, &CellularModemService::onReadyRead);

    m_state = State::Probing;
    m_buffer.clear();
    m_serial->write("AT\r");
    m_serial->flush();
    m_probeTimer->start(kProbeTimeoutMs);
}

// ============================================================================
// 命中 AT 端口 → 依次查询 ICCID、IMSI
// ============================================================================

void CellularModemService::beginQuery()
{
    m_state = State::Querying;
    m_buffer.clear();
    m_serial->write("AT+ICCID\r");
    m_serial->flush();
    m_queryTimer->start(kQueryTimeoutMs);
}

// 拿到 ICCID 后继续查询 IMSI（AT+CIMI）
void CellularModemService::beginQueryImsi()
{
    m_state = State::QueryingImsi;
    m_buffer.clear();
    m_serial->write("AT+CIMI\r");
    m_serial->flush();
    m_queryTimer->start(kQueryTimeoutMs);
}

// 拿到 IMSI 后继续查询运营商（AT+COPS?）
void CellularModemService::beginQueryOperator()
{
    m_state = State::QueryingOperator;
    m_buffer.clear();
    m_serial->write("AT+COPS?\r");
    m_serial->flush();
    m_queryTimer->start(kQueryTimeoutMs);
}

// ============================================================================
// 接收处理
// ============================================================================

void CellularModemService::onReadyRead()
{
    if (!m_serial)
        return;
    m_buffer += m_serial->readAll();

    if (m_state == State::Probing) {
        // 收到 OK 即确认是 AT 端口（缓冲含 "AT\r\r\nOK\r\n"）
        if (m_buffer.contains("OK")) {
            m_probeTimer->stop();
            qInfo() << "[CellularModem] 端口" << m_serial->portName()
                    << "响应 AT → 确认为调制解调器 AT 接口，开始查询 ICCID";
            beginQuery();
        }
        // 仅认 OK；个别模组可能先回 ERROR 再回 OK，故不在此处因 ERROR 退出
    } else if (m_state == State::Querying) {
        // 解析 +ICCID: 响应，缓冲示例:
        //   "AT+ICCID\r\r\n+ICCID: 898600...\r\n\r\nOK\r\n"
        const int idx = m_buffer.indexOf("+ICCID:");
        if (idx >= 0) {
            const QByteArray tail = m_buffer.mid(idx);
            // 提取 +ICCID: 之后 18~20 位数字/十六进制字符（兼容部分 ICCID 含 A-F 校验位）
            QRegularExpression re("\\+ICCID:\\s*([0-9A-F]{18,20})");
            const QRegularExpressionMatch m = re.match(QString::fromLatin1(tail));
            if (m.hasMatch()) {
                m_ccid = m.captured(1);
                qInfo() << "[CellularModem] 已获取 CCID(ICCID):" << m_ccid
                        << "，继续查询 IMSI(AT+CIMI)";
                beginQueryImsi();
                return;
            }
        }
        // 明确 ERROR（SIM 未就绪/无卡）→ 提前结束本轮重试
        if (m_buffer.contains("ERROR")) {
            qWarning() << "[CellularModem] AT+ICCID 返回 ERROR（SIM 可能未就绪/无卡），缓冲:"
                       << m_buffer;
            m_queryTimer->stop();
            fail(QStringLiteral("AT+ICCID ERROR"));
        }
    } else if (m_state == State::QueryingImsi) {
        // 解析 IMSI：ML307B 的 AT+CIMI 直接回 IMSI 数字（如 "460001234567890"），
        // 也可能带 "+CIMI:" 前缀。缓冲示例:
        //   "AT+CIMI\r\r\n460001234567890\r\n\r\nOK\r\n"
        //   "AT+CIMI\r\r\n+CIMI: 460001234567890\r\n\r\nOK\r\n"
        QRegularExpression re("(?:\\+CIMI:\\s*)?([0-9]{14,15})");
        const QRegularExpressionMatch m = re.match(QString::fromLatin1(m_buffer));
        if (m.hasMatch()) {
            m_imsi = m.captured(1);
            qInfo() << "[CellularModem] 已获取 IMSI:" << m_imsi
                    << "，继续查询运营商(AT+COPS?)";
            beginQueryOperator();
            return;
        }
        // 已收到 OK 但仍未解析出 IMSI（或明确 ERROR）→ 跳过 IMSI 直接查运营商
        if (m_buffer.contains("OK") || m_buffer.contains("ERROR")) {
            qWarning() << "[CellularModem] 未能解析 IMSI（缓冲:" << m_buffer
                       << "），跳过继续查询运营商";
            beginQueryOperator();
        }
    } else if (m_state == State::QueryingOperator) {
        // 解析 +COPS: 响应，缓冲示例:
        //   "AT+COPS?\r\r\n+COPS: 0,0,\"CHINA MOBILE\",7\r\n\r\nOK\r\n"
        //   "AT+COPS?\r\r\n+COPS: 0,2,\"46000\",7\r\n\r\nOK\r\n"（数字模式，第2字段=2 时第3字段是 PLMN 数字）
        // 提取第 3 个逗号分隔字段的引号内字符串作为运营商名（长格式字母名优先）
        QRegularExpression re("\\+COPS:\\s*\\d+\\s*,\\s*\\d+\\s*,\\s*\"([^\"]*)\"");
        const QRegularExpressionMatch m = re.match(QString::fromLatin1(m_buffer));
        if (m.hasMatch()) {
            m_operatorName = normalizeOperatorName(m.captured(1));
            finishWithAll();
            return;
        }
        // 已收到 OK 但仍未解析出运营商（或未注册: +COPS: 0 / ERROR）→ 以已获取结果收尾，运营商留空
        if (m_buffer.contains("OK") || m_buffer.contains("ERROR")) {
            qWarning() << "[CellularModem] 未能解析运营商（缓冲:" << m_buffer
                       << "），以 CCID/IMSI 收尾";
            finishWithAll();
        }
    }
}

// ============================================================================
// 超时处理
// ============================================================================

void CellularModemService::onProbeTimeout()
{
    if (m_state != State::Probing || !m_serial)
        return;
    qDebug() << "[CellularModem] 端口" << m_serial->portName() << "探测超时（无 AT 响应）";
    cleanupSerial();
    probeNext();   // 试下一个候选
}

void CellularModemService::onQueryTimeout()
{
    if (m_state == State::QueryingImsi) {
        // IMSI 查询超时：仍保有 CCID，跳过直接查运营商
        qWarning() << "[CellularModem] AT+CIMI 查询超时，跳过继续查询运营商，缓冲:" << m_buffer;
        beginQueryOperator();
        return;
    }
    if (m_state == State::QueryingOperator) {
        // 运营商查询超时：以已获取的 CCID/IMSI 收尾
        qWarning() << "[CellularModem] AT+COPS? 查询超时，以 CCID/IMSI 收尾，缓冲:" << m_buffer;
        finishWithAll();
        return;
    }
    if (m_state != State::Querying)
        return;
    qWarning() << "[CellularModem] AT+ICCID 查询超时，缓冲:" << m_buffer;
    fail(QStringLiteral("AT+ICCID 超时"));
}

void CellularModemService::onRetryTimeout()
{
    qInfo() << "[CellularModem] 重试触发（第" << m_retries << "次）";
    m_state = State::Idle;
    probeNext();
}

// ============================================================================
// 运营商名中文化映射
// ============================================================================

QString CellularModemService::normalizeOperatorName(const QString &raw)
{
    const QString s = raw.trimmed();
    if (s.isEmpty())
        return s;

    // 1) 数字 PLMN 码（AT+COPS? 第2字段=2 时返回，如 "46000"）
    static const QHash<QString, QString> plmnMap = {
        // 中国移动
        { "46000", "中国移动" }, { "46002", "中国移动" }, { "46004", "中国移动" },
        { "46007", "中国移动" }, { "46008", "中国移动" },
        // 中国联通
        { "46001", "中国联通" }, { "46006", "中国联通" }, { "46009", "中国联通" },
        // 中国电信
        { "46003", "中国电信" }, { "46005", "中国电信" }, { "46011", "中国电信" },
        // 中国广电
        { "46015", "中国广电" },
        // 中国铁通（已并入移动）
        { "46020", "中国移动" },
    };
    if (plmnMap.contains(s))
        return plmnMap.value(s);

    // 2) 字母名（长格式 format=0 / 短格式 format=1，忽略大小写）
    const QString upper = s.toUpper();
    static const QHash<QString, QString> nameMap = {
        // 中国移动
        { "CHINA MOBILE", "中国移动" }, { "CMCC", "中国移动" }, { "CHN-CMCC", "中国移动" },
        { "CHN-CM", "中国移动" }, { "CM", "中国移动" },
        // 中国联通
        { "CHINA UNICOM", "中国联通" }, { "CUCC", "中国联通" }, { "CHN-UNICOM", "中国联通" },
        { "CHN-CU", "中国联通" }, { "CU", "中国联通" },
        // 中国电信
        { "CHINA TELECOM", "中国电信" }, { "CT", "中国电信" }, { "CHN-CT", "中国电信" },
        { "CHN-CUCC", "中国电信" },
        // 中国广电
        { "CHINA BROADNET", "中国广电" }, { "CBN", "中国广电" }, { "CHN-CBN", "中国广电" },
    };
    if (nameMap.contains(upper))
        return nameMap.value(upper);

    // 3) 未知则原样返回（如虚拟运营商或境外运营商）
    return s;
}

// ============================================================================
// 收尾 / 失败 / 重试
// ============================================================================

void CellularModemService::finishWithAll()
{
    m_queryTimer->stop();
    m_state = State::Done;
    m_available = !m_ccid.isEmpty() || !m_imsi.isEmpty() || !m_operatorName.isEmpty();
    cleanupSerial();
    qInfo() << "[CellularModem] 成功获取 CCID(ICCID):" << m_ccid
            << " IMSI:" << m_imsi
            << " 运营商:" << m_operatorName;
    Q_EMIT availableChanged(m_available);
    Q_EMIT ccidChanged(m_ccid);
    Q_EMIT imsiChanged(m_imsi);
    Q_EMIT operatorNameChanged(m_operatorName);
}

void CellularModemService::fail(const QString &reason)
{
    qWarning() << "[CellularModem] 获取 CCID 失败:" << reason;
    cleanupSerial();
    m_state = State::Failed;

    m_retries++;
    m_candidates.clear();   // 重置以便重试时重新枚举（设备可能刚插入/刚加载驱动）

    if (m_retries <= kMaxRetries) {
        qInfo() << "[CellularModem] 将在" << kRetryDelayMs << "ms 后重试 ("
                << m_retries << "/" << kMaxRetries << ")";
        m_retryTimer->start(kRetryDelayMs);
    } else {
        // 快速重试耗尽后改为低速无限重试：设备驱动/节点可能稍后才会出现
        if (m_retries % 6 == 0) {   // 约每 60s 记一次 info，避免日志刷屏
            qInfo() << "[CellularModem] 持续低速重试获取 CCID（第" << m_retries
                    << "次），原因:" << reason;
        } else {
            qDebug() << "[CellularModem] 低速重试中（第" << m_retries << "次）";
        }
        m_retryTimer->start(kSlowRetryDelayMs);
    }
}

void CellularModemService::cleanupSerial()
{
    m_probeTimer->stop();
    m_queryTimer->stop();
    if (m_serial) {
        disconnect(m_serial, &QSerialPort::readyRead, this, &CellularModemService::onReadyRead);
        if (m_serial->isOpen())
            m_serial->close();
        delete m_serial;
        m_serial = nullptr;
    }
    m_buffer.clear();
}
