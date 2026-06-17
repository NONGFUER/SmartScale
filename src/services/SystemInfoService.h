#pragma once

#include <QObject>
#include <QString>

/**
 * @brief 系统信息服务 — 记录主机开机关机次数与时间（测试阶段调试用）
 *
 * 设计思路：
 *   - 每次"开机"（程序启动）追加一条 boot 事件到 JSON
 *   - 每次"关机"（aboutToQuit / 析构）追加一条 shutdown 事件
 *   - 重启次数 = 累计 boot 事件数
 *   - 上次开机/关机 = 从事件列表倒序取值
 *
 * 持久化：data/system_info.json
 */
class SystemInfoService : public QObject
{
    Q_OBJECT
    // ---- QML 可读属性 ----
    Q_PROPERTY(int    restartCount     READ restartCount     CONSTANT)
    Q_PROPERTY(QString lastBootTime     READ lastBootTime     CONSTANT)
    Q_PROPERTY(QString lastShutdownTime READ lastShutdownTime CONSTANT)
    Q_PROPERTY(QString currentBootTime  READ currentBootTime  CONSTANT)

public:
    explicit SystemInfoService(QObject *parent = nullptr);
    ~SystemInfoService() override;

    SystemInfoService(const SystemInfoService &) = delete;
    SystemInfoService &operator=(const SystemInfoService &) = delete;

    int    restartCount()     const { return m_restartCount; }
    QString lastBootTime()     const { return m_lastBootTime; }
    QString lastShutdownTime() const { return m_lastShutdownTime; }
    QString currentBootTime()  const { return m_currentBootTime; }

public Q_SLOTS:
    /** 记录一次关机事件并写入文件 */
    void recordShutdown();

private:
    static constexpr const char *kDataFile = "data/system_info.json";

    void loadFromFile();
    void saveToFile();

    int     m_restartCount     = 0;
    QString m_lastBootTime;
    QString m_lastShutdownTime;
    QString m_currentBootTime;

    /** 内存中的事件列表: [{"type":"boot"/"shutdown","time":"2026-06-17 20:01:00"}, ...] */
    QList<QJsonObject> m_events;
};
