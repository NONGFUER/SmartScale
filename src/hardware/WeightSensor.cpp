#include "WeightSensor.h"
#include "WeightSensorWorker.h"
#include <QDebug>
#include <QtMath>
#include <algorithm>

// ============================================================================
// 构造 / 析构 — 创建并启动 Worker 线程
// ============================================================================

WeightSensor::WeightSensor(QObject *parent)
    : QObject(parent)
    , m_workerThread(new QThread(this))
    , m_worker(nullptr)
    , m_netWeight(0.0)
    , m_isStable(false)
    , m_zeroOffset(0.0)
    , m_tareWeight(0.0)
{
    // 创建 Worker 并移到独立线程
    m_worker = new WeightSensorWorker();
    m_worker->moveToThread(m_workerThread);

    // 线程结束时自动清理 Worker
    connect(m_workerThread, &QThread::finished, m_worker, &QObject::deleteLater);

    // Worker → GUI: 数据就绪 (QueuedConnection, 跨线程安全)
    connect(m_worker, &WeightSensorWorker::weightDataReady,
            this,     &WeightSensor::onWeightDataReady);
    // Worker → GUI: 去皮完成
    connect(m_worker, &WeightSensorWorker::tareDone,
            this,     &WeightSensor::onTareDone);

    // GUI → Worker: 去皮请求 (QueuedConnection)
    connect(this, &WeightSensor::requestTare,
            m_worker, &WeightSensorWorker::doTare);

    // 启动线程 → Worker 初始化串口 → 启动轮询定时器
    // 使用 QueuedConnection 确保 startPolling() 在 Worker 线程中执行
    connect(m_workerThread, &QThread::started, m_worker, [this]() {
        m_worker->startPolling();
    }, Qt::QueuedConnection);

    m_workerThread->start();

    qDebug() << "[WeightSensor] 初始化完成, Worker线程已启动";
}

WeightSensor::~WeightSensor()
{
    m_workerThread->quit();
    m_workerThread->wait();
    qDebug() << "[WeightSensor] 已销毁";
}

// ============================================================================
// QML 属性访问器
// ============================================================================

double WeightSensor::netWeight() const
{
    // 负20g以内显示为0.00，不出现负数
    if (m_netWeight > -0.02 && m_netWeight < 0.0) {
        return 0.0;
    }
    return m_netWeight;
}
bool WeightSensor::isStable()  const { return m_isStable; }

// ============================================================================
// Q_INVOKABLE 操作
// ============================================================================

void WeightSensor::tare()
{
    qDebug() << "[WeightSensor] >>> 请求去皮...";
    Q_EMIT requestTare();  // 通过 QueuedConnection 发到 Worker 线程
}

void WeightSensor::zero()
{
    m_zeroOffset = m_netWeight + m_tareWeight;
    m_tareWeight = 0.0;
    qDebug() << "[WeightSensor] 清零, zeroOffset=" << m_zeroOffset << "kg";
    Q_EMIT weightChanged();
}

// ============================================================================
// 接收 Worker 的称重数据 — 在 GUI 线程执行滤波 + 稳定检测 + 属性更新
// ============================================================================

void WeightSensor::onWeightDataReady(int32_t weight_g, uint16_t statusWord, int32_t adcRaw)
{
    // g -> kg 转换
    double rawWeightKg = weight_g / 1000.0;

    // 电子秤硬件稳定标志
    // 0x0001=bit0 去皮, 0x0002=bit1 稳定, 0x0004=bit2 负重
    bool hwStable = (statusWord & 0x02);
    bool hwTared  = (statusWord & 0x01);

    qDebug().nospace() << "[Scale] raw=" << rawWeightKg << "kg"
                       << " ADC=" << adcRaw
                       << QString(" status=0x%1").arg(statusWord, 4, 16, QChar('0'))
                       << (hwStable ? " [HW:稳定]" : " [HW:波动]")
                       << (hwTared  ? " [去皮]" : "")
                       << ((statusWord & 0x04) ? " 负重" : "");

    // === 直接使用原始值，不进行滤波 ===
    double newNetWeight = rawWeightKg - m_zeroOffset - m_tareWeight;

    // 更新稳定状态（直接使用硬件标志）
    if (hwStable != m_isStable) {
        m_isStable = hwStable;
        Q_EMIT stableChanged();
    }

    // 不稳定时重置触发标志（关键：允许重量变化后再次触发）
    if (!hwStable) {
        m_triggered = false;
    }

    // 硬件判定稳定时触发拍照（正负值均可触发）
    if (hwStable && !m_triggered) {
        if (std::abs(newNetWeight) > 0.05) {
            Q_EMIT stableTriggered();
            m_triggered = true;
            qDebug() << "[Scale] *** stableTriggered! *** weight=" << newNetWeight << "kg";
        }
    }

    // 变化量 > 0.001kg 才刷新 UI
    if (std::abs(newNetWeight - m_netWeight) > 0.001) {
        m_netWeight = newNetWeight;  // 允许负值
        Q_EMIT weightChanged();
    }
}

// ============================================================================
// 接收 Worker 的去皮结果
// ============================================================================

void WeightSensor::onTareDone(bool ok)
{
    if (ok) {
        qDebug() << "[WeightSensor]去皮成功 (来自 Worker)";
    } else {
        qWarning() << "[WeightSensor]去皮失败 (来自 Worker)";
    }
}
