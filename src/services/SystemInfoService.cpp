#include "SystemInfoService.h"

#include <QCoreApplication>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

// ============================================================================
// 构造 — 记录开机事件
// ============================================================================

SystemInfoService::SystemInfoService(QObject *parent)
    : QObject(parent)
{
    loadFromFile();

    // ---- 检测异常关机：如果最后一条是 boot（无配对 shutdown），补录 shutdown ----
    if (!m_events.isEmpty() && m_events.last()["type"].toString() == "boot") {
        // 上次是非正常退出（kill/断电/reboot），用最后一条 boot 时间作为近似关机时间
        QJsonObject emergencySd;
        emergencySd["type"] = "shutdown";
        emergencySd["time"] = m_events.last()["time"].toString();
        emergencySd["abnormal"] = true;
        m_events.append(emergencySd);
        qDebug() << "[SystemInfo] 检测到异常关机，已补录 shutdown 记录";
    }

    // ---- 本次开机：追加 boot 事件 ----
    m_currentBootTime = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
    QJsonObject bootEvent;
    bootEvent["type"] = "boot";
    bootEvent["time"] = m_currentBootTime;
    m_events.append(bootEvent);

    // ---- 统计与回填 ----
    int bootCount = 0;
    for (const auto &ev : m_events) {
        if (ev["type"].toString() == "boot") ++bootCount;
    }
    m_restartCount = bootCount;

    // 从事件列表倒序找上次开机(倒数第2个boot)、上次关机(最后一个shutdown)
    QString prevBoot, lastShutdown;
    bool foundCurrentBoot = false;  // 跳过刚加入的当前开机
    for (int i = m_events.size() - 1; i >= 0; --i) {
        const auto &ev = m_events[i];
        if (!foundCurrentBoot && ev["type"].toString() == "boot") {
            foundCurrentBoot = true;  // 当前这次，跳过
            continue;
        }
        if (prevBoot.isEmpty() && ev["type"].toString() == "boot") {
            prevBoot = ev["time"].toString();
        }
        if (lastShutdown.isEmpty() && ev["type"].toString() == "shutdown") {
            lastShutdown = ev["time"].toString();
        }
        if (!prevBoot.isEmpty() && !lastShutdown.isEmpty()) break;
    }
    m_lastBootTime     = prevBoot.isEmpty()     ? "--" : prevBoot;
    m_lastShutdownTime = lastShutdown.isEmpty() ? "--" : lastShutdown;

    saveToFile();

    qDebug() << "[SystemInfo] 开机事件已记录:"
             << "\n  累计开机:" << m_restartCount << "次"
             << "\n  本次开机:" << m_currentBootTime
             << "\n  上次开机:" << m_lastBootTime
             << "\n  上次关机:" << m_lastShutdownTime;
}

// ============================================================================
// 析构 — 记录关机事件
// ============================================================================

SystemInfoService::~SystemInfoService()
{
    recordShutdown();
}

// ============================================================================
// 公共槽
// ============================================================================

void SystemInfoService::recordShutdown()
{
    QJsonObject sdEvent;
    sdEvent["type"] = "shutdown";
    sdEvent["time"] = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
    m_events.append(sdEvent);
    saveToFile();
    qDebug() << "[SystemInfo] 关机事件已记录:" << sdEvent["time"];
}

// ============================================================================
// 持久化
// ============================================================================

void SystemInfoService::loadFromFile()
{
    QFile file(kDataFile);
    if (!file.exists()) {
        qInfo() << "[SystemInfo] 首次运行，无历史数据";
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "[SystemInfo] 无法读取:" << file.errorString();
        return;
    }
    QJsonParseError err;
    QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &err);
    file.close();
    if (err.error != QJsonParseError::NoError || !doc.isArray()) {
        qWarning() << "[SystemInfo] JSON 格式异常:" << err.errorString();
        return;
    }

    QJsonArray arr = doc.array();
    m_events.clear();
    m_events.reserve(arr.size());
    for (const QJsonValue &v : arr) {
        if (v.isObject())
            m_events.append(v.toObject());
    }
}

void SystemInfoService::saveToFile()
{
    QDir dir(QFileInfo(kDataFile).absolutePath());
    if (!dir.exists()) dir.mkpath(".");

    QFile file(kDataFile);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qCritical() << "[SystemInfo] 无法写入:" << file.errorString();
        return;
    }
    QJsonArray arr;
    for (const auto &ev : m_events)
        arr.append(ev);
    file.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    file.close();
}
