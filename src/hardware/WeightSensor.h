#ifndef WEIGHTSENSOR_H
#define WEIGHTSENSOR_H

#include <QObject>
#include <QQueue>
#include <QThread>
#include <QTimer>

class WeightSensorWorker;

struct WeightSample {
    double weightKg = 0;
    uint16_t statusWord = 0;
    int32_t adcRaw = 0;
};

/**
 * @brief 称重传感器 (GUI 线程薄代理)
 *
 * 职责:
 *   - QML 属性 (netWeight, isStable) + 信号通知
 *   - 滑动窗口滤波 & 稳定检测
 *   - 管理 Worker 线程生命周期
 *
 * 所有阻塞式串口 I/O 已移至 WeightSensorWorker (独立线程)
 */
class WeightSensor : public QObject
{
    Q_OBJECT
    Q_PROPERTY(double netWeight READ netWeight NOTIFY weightChanged)
    Q_PROPERTY(bool isStable READ isStable NOTIFY stableChanged)

public:
    explicit WeightSensor(QObject *parent = nullptr);
    ~WeightSensor();

    double netWeight() const;
    bool isStable() const;

    /** 去皮: 通过信号转发到 Worker 线程 */
    Q_INVOKABLE void tare();
    /** 清零: 软件清零（记录当前为零点偏移） */
    Q_INVOKABLE void zero();

Q_SIGNALS:
    void weightChanged();
    void stableChanged();
    void stableTriggered(); // 重量从"不稳定"刚变为"稳定的瞬间触发"

    /** 内部信号: 向 Worker 线程发送去皮请求 */
    void requestTare();

private Q_SLOTS:
    /** 接收 Worker 的称重数据, 写入缓冲池 */
    void onWeightDataReady(int32_t weight_g, uint16_t status, int32_t adc_raw);
    /** 接收 Worker 的去皮结果 */
    void onTareDone(bool ok);
    /** 消费缓冲池数据 (低频定时器驱动) */
    void consumeBuffer();

private:
    // ==================== 线程管理 ====================
    QThread       *m_workerThread;
    WeightSensorWorker *m_worker;

    // ==================== 称重状态 ====================
    double m_netWeight;     // 净重 (kg)
    bool   m_isStable;
    double m_zeroOffset;    // 软件零点偏移 (kg)
    double m_tareWeight;    // 皮重 (kg)

    // ==================== 滤波 & 稳定检测 ====================
    QQueue<double> m_filterWindow;
    static constexpr int    FILTER_WINDOW_SIZE = 3;          // 滑动窗口大小（3次=150ms）
    static constexpr double STABLE_THRESHOLD_KG = 0.03;      // 极差阈值
    static constexpr int    STABLE_REQUIRED_COUNT = 3;       // 连续稳定次数
    int  m_stableCount  = 0;
    bool m_triggered    = false; // 防止重复触发

    // ==================== 缓冲池 (生产者-消费者) ====================
    WeightSample   m_buffer;                    // 最新数据缓存（覆盖写）
    bool           m_bufferHasData = false;     // 是否有待消费数据
    QTimer        *m_consumeTimer = nullptr;    // 消费定时器
    static constexpr int CONSUME_INTERVAL_MS = 150;  // 消费间隔(ms)
};

#endif // WEIGHTSENSOR_H
