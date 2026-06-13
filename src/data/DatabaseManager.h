#ifndef DATABASEMANAGER_H
#define DATABASEMANAGER_H

#include <QString>
#include <QSqlDatabase>
#include <QMutex>

class DatabaseManager
{
public:
    // 单例访问入口
    static DatabaseManager& instance();

    // 禁止拷贝和赋值
    DatabaseManager(const DatabaseManager&) = delete;
    DatabaseManager& operator=(const DatabaseManager&) = delete;

    /**
     * @brief 初始化数据库连接并执行迁移
     * @param dbPath 数据库文件路径 (如 "data/smartscale.db")
     * @return 成功返回 true
     */
    bool initialize(const QString &dbPath);

    /**
     * @brief 获取数据库连接 (线程安全)
     */
    QSqlDatabase database();

    /**
     * @brief 关闭数据库连接 (程序退出时调用)
     */
    void close();

private:
    DatabaseManager() = default;
    ~DatabaseManager() = default;

    // === 迁移系统 ===
    int currentVersion();
    void setVersion(int version);
    void migrate();                    // 主迁移入口，按版本号递增执行
    void createTables();               // v1: 建表

    // 建表 SQL
    void createSchemaVersionTable();
    void createWeightRecordsTable();
    void createUsersTable();
    void createHardwareConfigTable();

    // 辅助：确保默认管理员存在
    void ensureDefaultUser();

    // 辅助：确保 data/ 目录存在
    static QString ensureDataDir(const QString &dbPath);

    QSqlDatabase m_db;
    QMutex m_mutex;
    bool m_initialized = false;
};

#endif // DATABASEMANAGER_H
