#include "SystemInfoService.h"
#include "version.h"

#include <QFile>
#include <QTextStream>
#include <QDebug>

// ============================================================================
// 构造 — 解析系统日志，一次性统计
// ============================================================================

SystemInfoService::SystemInfoService(QObject *parent)
    : QObject(parent)
{
    m_appVersion = QString("v%1_%2").arg(APP_VERSION_FULL).arg(APP_BUILD_DATE);
    parseLog();

    qDebug() << "[SystemInfo] 日志解析完成:"
             << "\n  开机次数:"   << m_bootCount
             << "\n  关机次数:"   << m_shutdownCount
             << "\n  本次开机:"   << m_currentBootTime
             << "\n  上次开机:"   << m_lastBootTime
             << "\n  上次关机:"   << m_lastShutdownTime;
}

// ============================================================================
// 核心解析：逐行扫描 /var/log/power_monitor.log
// ============================================================================

void SystemInfoService::parseLog()
{
    QFile file(kLogFile);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[SystemInfo] 无法打开日志:" << file.errorString();
        return;
    }

    QStringList bootTimes;
    QString lastShutdown;

    QTextStream in(&file);
    while (!in.atEnd()) {
        QString line = in.readLine().trimmed();
        if (line.isEmpty())
            continue;

        if (line.startsWith("[BOOT]")) {
            // 格式: [BOOT] System Started at: 2026-06-18 21:56:09
            static const QString tag("at: ");
            int tagIdx = line.indexOf(tag);
            if (tagIdx >= 0)
                bootTimes.append(line.mid(tagIdx + tag.length()).trimmed());

        } else if (line.startsWith("[SHUTDOWN]")) {
            // 格式: [SHUTDOWN] System Shutting down at: 2026-06-18 22:01:58
            static const QString tag("at: ");
            int tagIdx = line.indexOf(tag);
            if (tagIdx >= 0)
                lastShutdown = line.mid(tagIdx + tag.length()).trimmed();
        }
    }
    file.close();

    // ---- 统计 ----
    m_bootCount = bootTimes.size();

    // 连续两个 BOOT 之间没有 SHUTDOWN → 异常关机（断电/硬重启）
    // 如果日志中存在 SHUTDOWN 记录，说明最后一次是正常关机，异常关机数为 0
    // 否则异常关机数 = BOOT 数 - 1（第一次开机不算异常）
    m_shutdownCount = lastShutdown.isEmpty() ? qMax(0, m_bootCount - 1) : 0;

    // ---- 时间回填 ----
    if (bootTimes.size() >= 2) {
        m_currentBootTime = bootTimes.last();
        m_lastBootTime    = bootTimes[bootTimes.size() - 2];
    } else if (bootTimes.size() == 1) {
        m_currentBootTime = bootTimes.first();
    }

    m_lastShutdownTime = lastShutdown.isEmpty() ? "--" : lastShutdown;
    if (m_lastBootTime.isEmpty())     m_lastBootTime     = "--";
    if (m_currentBootTime.isEmpty())  m_currentBootTime  = "--";
}
