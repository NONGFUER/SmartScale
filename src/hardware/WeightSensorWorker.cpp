#include "WeightSensorWorker.h"
#include <QDebug>
#include <QElapsedTimer>

// ============================================================================
// 构造 / 析构
// ============================================================================

WeightSensorWorker::WeightSensorWorker(QObject *parent)
    : QObject(parent)
    , m_serial(nullptr)
    , m_pollTimer(new QTimer(this))
{
    m_pollTimer->setSingleShot(false);

    if (!initSerial()) {
        qWarning() << "[WeightSensorWorker] 串口初始化失败，将在无数据模式下运行";
    }

    qDebug() << "[WeightSensorWorker] 初始化完成, 串口:"
             << (m_serial ? m_serial->portName() : "(无)")
             << "thread:" << QThread::currentThread();
}

WeightSensorWorker::~WeightSensorWorker()
{
    if (m_serial && m_serial->isOpen()) {
        m_serial->close();
    }
}

// ============================================================================
// 启动轮询
// ============================================================================

void WeightSensorWorker::startPolling()
{
    connect(m_pollTimer, &QTimer::timeout, this, &WeightSensorWorker::poll);
    m_pollTimer->start(POLL_INTERVAL_MS);
    qDebug() << "[WeightSensorWorker] 轮询已启动, interval=" << POLL_INTERVAL_MS << "ms";
}

// ============================================================================
// 串口初始化
// ============================================================================

bool WeightSensorWorker::initSerial()
{
    QString portName = QStringLiteral("/dev/ttyAMA0");

    m_serial = new QSerialPort(this);
    m_serial->setPortName(portName);
    m_serial->setBaudRate(QSerialPort::Baud9600);
    m_serial->setDataBits(QSerialPort::Data8);
    m_serial->setParity(QSerialPort::NoParity);
    m_serial->setStopBits(QSerialPort::OneStop);
    m_serial->setFlowControl(QSerialPort::NoFlowControl);

    if (!m_serial->open(QIODevice::ReadWrite)) {
        qWarning() << "[WeightSensorWorker] 无法打开串口"
                   << portName << "-" << m_serial->errorString();
        delete m_serial;
        m_serial = nullptr;
        return false;
    }

    qDebug() << "[WeightSensorWorker] 串口已打开:" << portName << "@9600 8N1";
    return true;
}

// ============================================================================
// 定时轮询 — 在 Worker 线程中执行, 阻塞 I/O 不影响 UI
// ============================================================================

void WeightSensorWorker::poll()
{
    int32_t weightG = 0;
    uint16_t statusWord = 0;
    int32_t adcRaw = 0;

    int ret = modbusReadWeight(&weightG, &statusWord, &adcRaw);

    if (ret == 0) {
        Q_EMIT weightDataReady(weightG, statusWord, adcRaw);
    }
    // ret != 0 时静默丢弃, 不打扰 UI (连续失败可后续加计数告警)
}

// ============================================================================
// 去皮 — 在 Worker 线程中执行
// ============================================================================

void WeightSensorWorker::doTare()
{
    if (!m_serial || !m_serial->isOpen()) {
        qWarning() << "[WeightSensorWorker] 去皮失败: 串口未打开";
        Q_EMIT tareDone(false);
        return;
    }

    qDebug() << "[WeightSensorWorker] >>> 发送去皮命令...";
    int ret = modbusWriteCmd(REG_CMD_ADDR, CMD_TARE);
    if (ret == 0) {
        qDebug() << "[WeightSensorWorker] 去皮成功";
        Q_EMIT tareDone(true);
    } else {
        qWarning() << "[WeightSensorWorker] 去皮失败, err=" << ret;
        Q_EMIT tareDone(false);
    }
}

// ============================================================================
// Modbus CRC-16
// ============================================================================

uint16_t WeightSensorWorker::crc16Modbus(const uint8_t *data, uint16_t len)
{
    uint16_t crc = 0xFFFF;
    for (uint16_t i = 0; i < len; i++) {
        crc ^= (uint16_t)data[i];
        for (int j = 0; j < 8; j++) {
            if ((crc & 0x0001))
                { crc >>= 1; crc ^= 0xA001; }
            else
                { crc >>= 1; }
        }
    }
    return crc;
}

// ============================================================================
// 字节序转换
// ============================================================================

int32_t WeightSensorWorker::beToInt32(const uint8_t *p)
{
    return (int32_t)((uint32_t)p[0] << 24 |
                     (uint32_t)p[1] << 16 |
                     (uint32_t)p[2] << 8  |
                     (uint32_t)p[3]);
}

uint16_t WeightSensorWorker::beToUint16(const uint8_t *p)
{
    return ((uint16_t)p[0] << 8) | p[1];
}

int32_t WeightSensorWorker::leToInt32(const uint8_t *p)
{
    return (int32_t)((uint32_t)p[0] |
                     (uint32_t)p[1] << 8  |
                     (uint32_t)p[2] << 16 |
                     (uint32_t)p[3] << 24);
}

float WeightSensorWorker::leToFloat(const uint8_t *p)
{
    uint32_t u = (uint32_t)p[0]  |
                 (uint32_t)p[1] << 8  |
                 (uint32_t)p[2] << 16 |
                 (uint32_t)p[3] << 24;
    float f;
    memcpy(&f, &u, sizeof(f));
    return f;
}

int16_t WeightSensorWorker::beToInt16(const uint8_t *p)
{
    return (int16_t)(((uint16_t)p[0] << 8) | p[1]);
}

// ============================================================================
// 功能码 06: 写单个寄存器 (去皮/校准)
// 返回: 0=OK  -1=写/读失败  -2=CRC错  -3=异常响应
// ============================================================================

int WeightSensorWorker::modbusWriteCmd(uint16_t regAddr, uint16_t value)
{
    if (!m_serial || !m_serial->isOpen()) return -1;

    // 组帧
    uint8_t tx[8];
    tx[0] = SLAVE_ADDR;
    tx[1] = FUNC_WRITE;
    tx[2] = (regAddr >> 8) & 0xFF;
    tx[3] = regAddr & 0xFF;
    tx[4] = (value >> 8) & 0xFF;
    tx[5] = value & 0xFF;

    uint16_t crc = crc16Modbus(tx, 6);
    tx[6] = crc & 0xFF;
    tx[7] = (crc >> 8) & 0xFF;

    // 打印 TX
    QByteArray txHex;
    for (int i = 0; i < 8; i++) txHex.append(QString("%1 ").arg(tx[i], 2, 16, QChar('0')).toUpper().toUtf8());
    //qDebug().nospace() << "[Modbus] TX WRITE: " << txHex.trimmed();

    // 发送前清空接收缓冲区
    m_serial->clear(QSerialPort::Input);

    // 发送
    qint64 written = m_serial->write((const char *)tx, 8);
    if (written != 8) {
        qWarning() << "[Modbus] 写入失败, expected=8 actual=" << written;
        return -1;
    }
    if (!m_serial->flush()) {
        qWarning() << "[Modbus] flush 失败";
        return -1;
    }

    // 等待确认帧回显 (功能码06的响应 = 请求原样回显, 固定8B)
    if (!m_serial->waitForReadyRead(500)) {
        qWarning() << "[Modbus] 等待确认帧超时";
        return -1;
    }
    QThread::msleep(30);

    QByteArray rx = m_serial->readAll();
    if (rx.size() < 8) {
        QByteArray rxHex;
        for (int i = 0; i < rx.size(); i++) rxHex.append(QString("%1 ").arg((uint8_t)rx[i], 2, 16, QChar('0')).toUpper().toUtf8());
        qWarning() << "[Modbus] 确认帧长度不足:" << rx.size() << "bytes -" << rxHex.trimmed();
        return -1;
    }

    // 打印 RX
    QByteArray rxHex;
    for (int i = 0; i < rx.size(); i++) rxHex.append(QString("%1 ").arg((uint8_t)rx[i], 2, 16, QChar('0')).toUpper().toUtf8());
    qDebug().nospace() << "[Modbus] RX ACK(" << rx.size() << "B): " << rxHex.trimmed();

    // CRC 校验
    uint16_t calcCrc = crc16Modbus((const uint8_t *)rx.data(), 6);
    uint16_t recvCrc = ((uint8_t)rx[6]) | (((uint8_t)rx[7]) << 8);
    if (calcCrc != recvCrc) {
        qWarning() << "[Modbus] CRC错误: calc=0x" << QString::number(calcCrc, 16)
                   << "recv=0x" << QString::number(recvCrc, 16);
        return -2;
    }

    // 异常检查
    if ((uint8_t)rx[1] & 0x80) {
        qWarning() << "[Modbus] 异常响应: 错误码=0x"
                   << QString::number((uint8_t)rx[2], 16);
        return -3;
    }

    qDebug() << "[Modbus] [OK] 从站确认成功";
    return 0;
}

// ============================================================================
// 功能码 03: 读保持寄存器 (净重+状态+ADC)
// 返回: 0=OK  -1=通信失败  -2=CRC错  -3=异常响应
//
// 关键改进: 超时设为 READ_TIMEOUT_MS(1000ms), 因为运行在 Worker 线程中,
//           长时间阻塞不会影响 UI 响应!
// ============================================================================

int WeightSensorWorker::modbusReadWeight(int32_t *weight_g, uint16_t *status, int32_t *adc_raw)
{
    if (!m_serial || !m_serial->isOpen()) return -1;

    // 组帧
    uint8_t tx[8];
    tx[0] = SLAVE_ADDR;
    tx[1] = FUNC_READ;
    tx[2] = (REG_DATA_ADDR >> 8) & 0xFF;
    tx[3] = REG_DATA_ADDR & 0xFF;
    tx[4] = (REG_DATA_COUNT >> 8) & 0xFF;
    tx[5] = REG_DATA_COUNT & 0xFF;

    uint16_t crc = crc16Modbus(tx, 6);
    tx[6] = crc & 0xFF;
    tx[7] = (crc >> 8) & 0xFF;

    // 打印 TX
    QByteArray txHex;
    for (int i = 0; i < 8; i++) txHex.append(QString("%1 ").arg(tx[i], 2, 16, QChar('0')).toUpper().toUtf8());
    //qDebug().nospace() << "[Modbus] TX(8B): " << txHex.trimmed();

    // 发送前清空接收缓冲区
    m_serial->clear(QSerialPort::Input);

    // 发送
    qint64 written = m_serial->write((const char *)tx, 8);
    if (written != 8) {
        qWarning() << "[Modbus] 写入失败, expected=8 actual=" << written;
        return -1;
    }
    if (!m_serial->flush()) return -1;

    // 循环等待响应，直至收满23字节或总超时
    // 9600bps: 23B × 11bit / 9600 ≈ 26ms + 从站处理时间
    // 超时 1000ms 对 UI 无影响 (Worker 线程)
    const int FRAME_LEN = 23;  // V2.0协议: 地址+功能码+字节数(18)+数据+CRC = 23B

    QElapsedTimer timer;
    timer.start();

    QByteArray rxBuf;
    while (rxBuf.size() < FRAME_LEN && timer.elapsed() < READ_TIMEOUT_MS) {
        if (m_serial->waitForReadyRead(SINGLE_WAIT_MS)) {
            rxBuf += m_serial->readAll();
        }
    }

    if (rxBuf.isEmpty()) {
        qDebug() << "[Modbus] 无响应 (等待" << timer.elapsed() << "ms)";
        return -1;
    }

    // 打印 RX
    QByteArray rxHex;
    for (int i = 0; i < rxBuf.size(); i++) rxHex.append(QString("%1 ").arg((uint8_t)rxBuf[i], 2, 16, QChar('0')).toUpper().toUtf8());

    if (rxBuf.size() < FRAME_LEN) {
        qWarning() << "[Modbus] 数据不足: 期望" << FRAME_LEN << "B 实际" << rxBuf.size() << "B -" << rxHex.trimmed();
        return -1;
    }
    if (rxBuf.size() > FRAME_LEN) {
        qDebug() << "[Modbus] 收到" << rxBuf.size() << "B, 仅使用前" << FRAME_LEN << "B (粘包)";
    }

    // 打印完整 RX 帧
    QByteArray rxFullHex;
    for (int i = 0; i < rxBuf.size(); i++) rxFullHex.append(QString("%1 ").arg((uint8_t)rxBuf[i], 2, 16, QChar('0')).toUpper().toUtf8());
    //qDebug().nospace() << "[Modbus] RX(" << rxBuf.size() << "B): " << rxFullHex.trimmed();

    // CRC 校验
    uint16_t calcCrc = crc16Modbus((const uint8_t *)rxBuf.data(), FRAME_LEN - 2);
    uint16_t recvCrc = ((uint8_t)rxBuf[FRAME_LEN - 2]) | (((uint8_t)rxBuf[FRAME_LEN - 1]) << 8);
    if (calcCrc != recvCrc) {
        qWarning() << "[Modbus] CRC错误: calc=0x" << QString::number(calcCrc, 16)
                   << "recv=0x" << QString::number(recvCrc, 16);
        return -2;
    }

    // 异常检查
    if ((uint8_t)rxBuf[1] & 0x80) {
        qWarning() << "[Modbus] 异常响应: 错误码=0x"
                   << QString::number((uint8_t)rxBuf[2], 16);
        return -3;
    }

    // 解析数据区 (V2.0 协议, 18字节):
    //   +0  ADC_Value      (int32, 小端)
    //   +4  EmptyLoad_Value (int32, 小端)
    //   +8  SCALE1          (float, 小端 IEEE754)
    //   +12 WEIGHT          (int32, 大端, 单位 g)  如 01 02 03 00 → 0x01020300
    //   +16 ContAndStatus   (uint16, 大端)
    const uint8_t *d = (const uint8_t *)rxBuf.data() + 3;

    // 打印原始数据区
    QByteArray dataHex;
    for (int i = 0; i < 18; i++) dataHex.append(QString("%1 ").arg(d[i], 2, 16, QChar('0')).toUpper().toUtf8());
    //qDebug().nospace() << "[Modbus] 原始数据(18B): " << dataHex.trimmed();

    *adc_raw   = leToInt32(d + 0);
    int32_t emptyLoad = leToInt32(d + 4);
    float scale1 = leToFloat(d + 8);
    *weight_g = leToInt32(d + 12);
    *status   = beToUint16(d + 16);

    qDebug().nospace() << "[Modbus] 解析: ADC=" << *adc_raw
                       << " EmptyLoad=" << emptyLoad
                       << " SCALE1=" << scale1
                       << " WEIGHT=" << *weight_g << "g"
                       << QString(" Status=0x%1").arg(*status, 4, 16, QChar('0'));

    return 0;
}
