#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QSerialPort>
#include <QTimer>

/**
 * @brief 蜂窝模组 CCID(ICCID) 获取服务
 *
 * 方案：Udev 自动加载驱动产生 /dev/ttyUSB* 设备 → Qt QSerialPort 异步读写 AT 指令。
 *
 * 工作流程（纯异步状态机，不阻塞 UI）：
 *   1. 枚举 /dev/ttyUSB*（或按 ASR VID 0x2ECC 过滤）作为候选 AT 端口；
 *   2. 依次打开候选端口、发送 "AT\r"，收到 "OK" 即确认是调制解调器 AT 接口；
 *   3. 命中后依次发送 "AT+ICCID\r" 与 "AT+CIMI\r"，
 *      在 readyRead 中累积缓冲、按 "+ICCID:" 提取 18~20 位 ICCID、按 14~15 位数字提取 IMSI；
 *   4. 成功 → 暴露 ccid()/imsi() 并通过 ccidChanged/imsiChanged 信号通知；失败/超时 → 保持空串并自动重试。
 *
 * 已确认真机参数（ASR ML307B）：
 *   - 模组型号：ASR ML307B，AT 端口实测为 ttyUSB2（但本服务动态探测，不写死）；
 *   - USB VID/PID：0x2ECC / 0x3012；
 *   - 程序以普通用户(sjwu)运行，已加入 dialout 组 + udev MODE="0666" 放行串口；
 *   - SIM 已插卡并联网(eth1 正常)；AT+ICCID 返回 ERROR 时做兜底保持空串。
 *
 * QML 绑定名：App.Backend::CellularModem
 */
class CellularModemService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString ccid         READ ccid         NOTIFY ccidChanged)
    Q_PROPERTY(QString imsi         READ imsi         NOTIFY imsiChanged)
    Q_PROPERTY(QString operatorName READ operatorName NOTIFY operatorNameChanged)
    Q_PROPERTY(bool    available    READ available    NOTIFY availableChanged)

public:
    explicit CellularModemService(QObject *parent = nullptr);
    ~CellularModemService();

    QString ccid() const { return m_ccid; }
    QString imsi() const { return m_imsi; }
    QString operatorName() const { return m_operatorName; }
    bool    available() const { return m_available; }

    /** 启动 CCID/IMSI/运营商 获取：遍历候选端口动态探测 AT 接口并依次读取 +ICCID / +CIMI / +COPS?（已在进行中或已完成则忽略） */
    Q_INVOKABLE void start();

Q_SIGNALS:
    /** CCID(ICCID) 获取成功（非空串），或后续被刷新时触发 */
    void ccidChanged(const QString &ccid);
    /** IMSI(CIMI) 获取成功（非空串），或后续被刷新时触发 */
    void imsiChanged(const QString &imsi);
    /** 运营商名称(AT+COPS?) 获取成功（非空串），或后续被刷新时触发 */
    void operatorNameChanged(const QString &operatorName);
    /** 模组可用性变化（探测到 AT 接口且成功解析为 true） */
    void availableChanged(bool available);

private Q_SLOTS:
    void onReadyRead();
    void onProbeTimeout();
    void onQueryTimeout();
    void onRetryTimeout();

private:
    enum class State { Idle, Probing, Querying, QueryingImsi, QueryingOperator, Done, Failed };

    void probeNext();
    void beginQuery();
    void beginQueryImsi();
    void beginQueryOperator();
    void finishWithAll();

    /** 运营商名中文化：长字母名/短字母名/数字 PLMN 码 统一映射为"中国移动"等中文 */
    static QString normalizeOperatorName(const QString &raw);
    void fail(const QString &reason);
    void cleanupSerial();

    QSerialPort *m_serial      = nullptr;
    QTimer     *m_probeTimer   = nullptr;   // 单端口 AT 探测超时
    QTimer     *m_queryTimer   = nullptr;   // AT+ICCID / AT+CIMI / AT+COPS? 查询超时
    QTimer     *m_retryTimer   = nullptr;   // 整体重试间隔

    QStringList m_candidates;              // 候选 AT 端口 systemLocation 列表
    int         m_candidateIndex = 0;
    State       m_state = State::Idle;
    QString     m_ccid;
    QString     m_imsi;
    QString     m_operatorName;            // 运营商名称（AT+COPS? 第3个字段，如 "CHINA MOBILE"）
    bool        m_available = false;
    QByteArray  m_buffer;                   // readyRead 累积缓冲
    int         m_retries = 0;              // 已重试次数

    static constexpr int    kMaxRetries         = 3;
    static constexpr int    kProbeTimeoutMs     = 1500;  // 单端口探测 AT 响应超时
    static constexpr int    kQueryTimeoutMs     = 3000;  // AT+ICCID 查询超时
    static constexpr int    kRetryDelayMs       = 5000;  // 前几次快速重试间隔
    static constexpr int    kSlowRetryDelayMs   = 10000; // 持续低速重试间隔
    static constexpr qint32 kModemBaud          = 115200;
    static constexpr quint16 kAsrVendorId       = 0x2ECC; // ASR ML307B
};
