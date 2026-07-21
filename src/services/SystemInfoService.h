#pragma once

#include <QObject>
#include <QString>

/**
 * @brief 系统信息服务 — 纯读取 /var/log/power_monitor.log 统计开机关机
 *
 * 数据源：系统级 power-monitor.service 写入的日志文件
 * 解析规则：
 *   - [BOOT] 行数       = 开机次数
 *   - 连续两个 [BOOT] 之间无 [SHUTDOWN] = 异常关机/断电次数
 *   - 最后一条 [SHUTDOWN] = 最近正常关机时间
 */
class SystemInfoService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int    bootCount        READ bootCount        CONSTANT)
    Q_PROPERTY(int    shutdownCount    READ shutdownCount    CONSTANT)
    Q_PROPERTY(QString lastBootTime     READ lastBootTime     CONSTANT)
    Q_PROPERTY(QString lastShutdownTime READ lastShutdownTime CONSTANT)
    Q_PROPERTY(QString currentBootTime  READ currentBootTime  CONSTANT)
    Q_PROPERTY(QString appVersion       READ appVersion       CONSTANT)
    Q_PROPERTY(QString hardModel        READ hardModel        CONSTANT)
    Q_PROPERTY(QString hardRevision     READ hardRevision     CONSTANT)
    Q_PROPERTY(QString hardSerial       READ hardSerial       CONSTANT)
    Q_PROPERTY(QString memTotal         READ memTotal         CONSTANT)

public:
    explicit SystemInfoService(QObject *parent = nullptr);

    int    bootCount()        const { return m_bootCount; }
    int    shutdownCount()    const { return m_shutdownCount; }
    QString lastBootTime()     const { return m_lastBootTime; }
    QString lastShutdownTime() const { return m_lastShutdownTime; }
    QString currentBootTime()  const { return m_currentBootTime; }
    QString appVersion()       const { return m_appVersion; }
    QString hardModel()    const { return m_hardModel; }
    QString hardRevision() const { return m_hardRevision; }
    QString hardSerial()   const { return m_hardSerial; }
    QString memTotal()       const { return m_memTotal; }

private:
    static constexpr const char *kLogFile = "/var/log/power_monitor.log";

    void parseLog();
    /** @brief 读取 /proc/cpuinfo 解析树莓派 Model/Revision/Serial（开机后不变，构造时读一次） */
    void parseCpuInfo();
    /** @brief 读取 /proc/meminfo 解析内存信息（构造时读一次） */
    void parseMemInfo();

    int     m_bootCount     = 0;
    int     m_shutdownCount = 0;
    QString m_lastBootTime;
    QString m_lastShutdownTime;
    QString m_currentBootTime;
    QString m_appVersion;
    QString m_hardModel;     // /proc/cpuinfo Model   → MQTT hardver
    QString m_hardRevision;  // /proc/cpuinfo Revision → MQTT revision
    QString m_hardSerial;    // /proc/cpuinfo Serial   → MQTT serial

    // 内存信息（/proc/meminfo）
    QString m_memTotal;  // "2GB" 或 "4GB"
};
