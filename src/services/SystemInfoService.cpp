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
    parseCpuInfo();

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

// ============================================================================
// 硬件信息：解析 /proc/cpuinfo（树莓派全局字段，精确匹配键名）
// ============================================================================
void SystemInfoService::parseCpuInfo()
{
    QFile file("/proc/cpuinfo");
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qWarning() << "[SystemInfo] 无法打开 /proc/cpuinfo:" << file.errorString();
        return;
    }

    qInfo() << "[SystemInfo] 开始读取 /proc/cpuinfo";

    QTextStream in(&file);
    // 注意：/proc/cpuinfo 是虚拟文件，内核上报 size=0，
    // 用 atEnd() 可能一开始就返回 true 导致循环不执行，
    // 故改用 readLine() 返回值是否为 null 判断 EOF。
    QString line;
    while (!(line = in.readLine()).isNull()) {
        int sep = line.indexOf(':');
        if (sep < 0) continue;

        QString key = line.left(sep).trimmed();
        QString val = line.mid(sep + 1).trimmed().remove(QChar('\0'));

        qInfo().noquote() << "[SystemInfo] cpuinfo key=" << key << "value=" << val;

        if (key.compare(QStringLiteral("Model"), Qt::CaseInsensitive) == 0)
            m_hardModel = val;
        else if (key.compare(QStringLiteral("Revision"), Qt::CaseInsensitive) == 0)
            m_hardRevision = val;
        else if (key.compare(QStringLiteral("Serial"), Qt::CaseInsensitive) == 0)
            m_hardSerial = val;
    }
    file.close();

    qInfo() << "[SystemInfo] 硬件信息解析结果:"
            << "hardModel="    << m_hardModel
            << "hardRevision=" << m_hardRevision
            << "hardSerial="   << m_hardSerial;
}
