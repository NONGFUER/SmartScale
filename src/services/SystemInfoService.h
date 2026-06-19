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

public:
    explicit SystemInfoService(QObject *parent = nullptr);

    int    bootCount()        const { return m_bootCount; }
    int    shutdownCount()    const { return m_shutdownCount; }
    QString lastBootTime()     const { return m_lastBootTime; }
    QString lastShutdownTime() const { return m_lastShutdownTime; }
    QString currentBootTime()  const { return m_currentBootTime; }
    QString appVersion()       const { return m_appVersion; }

private:
    static constexpr const char *kLogFile = "/var/log/power_monitor.log";

    void parseLog();

    int     m_bootCount     = 0;
    int     m_shutdownCount = 0;
    QString m_lastBootTime;
    QString m_lastShutdownTime;
    QString m_currentBootTime;
    QString m_appVersion;
};
