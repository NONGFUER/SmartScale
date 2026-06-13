#ifndef WEIGHTSENSORWORKER_H
#define WEIGHTSENSORWORKER_H

#include <QObject>
#include <QTimer>
#include <QSerialPort>
#include <QByteArray>
#include <QThread>

/**
 * @brief 串口 I/O 工作线程 — 承载所有阻塞式 Modbus 通信
 *
 * 运行在独立 QThread 中, 通过信号与 GUI 线程的 WeightSensor 通信:
 *   GUI → Worker:  requestTare()
 *   Worker → GUI:  weightDataReady(int32_t weight_g, uint16_t status, int32_t adc)
 *                 tareDone(bool ok)
 *                 errorOccurred(const QString &msg)
 */
class WeightSensorWorker : public QObject
{
    Q_OBJECT

public:
    explicit WeightSensorWorker(QObject *parent = nullptr);
    ~WeightSensorWorker();

    /** 启动轮询定时器 (必须在 Worker 线程中调用) */
    void startPolling();

public Q_SLOTS:
    /** 去皮请求 (来自 GUI 线程的 QueuedConnection) */
    void doTare();

Q_SIGNALS:
    /** 称重数据就绪 (跨线程 → GUI) */
    void weightDataReady(int32_t weight_g, uint16_t status, int32_t adc_raw);
    /** 去皮完成 (跨线程 → GUI) */
    void tareDone(bool ok);
    /** 错误通知 (跨线程 → GUI) */
    void errorOccurred(const QString &msg);

private Q_SLOTS:
    /** 定时轮询槽 (由内部 QTimer 驱动) */
    void poll();

private:
    // ==================== Modbus RTU 协议 ====================
    static uint16_t crc16Modbus(const uint8_t *data, uint16_t len);
    static int32_t  beToInt32(const uint8_t *p);
    static uint16_t beToUint16(const uint8_t *p);
    static int32_t  leToInt32(const uint8_t *p);
    static float    leToFloat(const uint8_t *p);
    static int16_t  beToInt16(const uint8_t *p);

    /** 功能码03: 读取净重+状态+ADC */
    int modbusReadWeight(int32_t *weight_g, uint16_t *status, int32_t *adc_raw);
    /** 功能码06: 写单个寄存器 (去皮) */
    int modbusWriteCmd(uint16_t regAddr, uint16_t value);

    // ==================== 串口 ====================
    QSerialPort *m_serial;
    bool initSerial();

    // ==================== 定时器 (Worker 线程内驱动) ====================
    QTimer *m_pollTimer;

    // ==================== Modbus 常量 ====================
    static constexpr uint8_t  SLAVE_ADDR     = 0x01;
    static constexpr uint8_t  FUNC_READ      = 0x03;
    static constexpr uint8_t  FUNC_WRITE     = 0x06;
    static constexpr uint16_t REG_DATA_ADDR  = 0x0010;
    static constexpr uint16_t REG_DATA_COUNT = 9;
    static constexpr uint16_t REG_CMD_ADDR   = 0x0010;
    static constexpr uint16_t CMD_TARE       = 1;
    static constexpr uint16_t CMD_CALIBRATE  = 2;

    // ==================== 超时参数 ====================
    static constexpr int POLL_INTERVAL_MS  = 50;    // 轮询间隔 (降低延迟)
    static constexpr int READ_TIMEOUT_MS   = 1000;  // 读取总超时 (Worker线程中阻塞无压力!)
    static constexpr int SINGLE_WAIT_MS    = 30;    // 单次 waitForReadyRead
};

#endif // WEIGHTSENSORWORKER_H
