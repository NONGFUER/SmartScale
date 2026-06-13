#include "data/DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDir>
#include <QDebug>
#include <QStandardPaths>
#include <QCryptographicHash>

// ============================================================
// 单例
// ============================================================
DatabaseManager& DatabaseManager::instance()
{
    static DatabaseManager instance;
    return instance;
}

// ============================================================
// 初始化
// ============================================================
bool DatabaseManager::initialize(const QString &dbPath)
{
    QMutexLocker locker(&m_mutex);

    if (m_initialized) {
        qWarning() << "[DB] 已初始化，跳过重复初始化";
        return true;
    }

    QString resolvedPath = ensureDataDir(dbPath);
    qDebug() << "[DB] 初始化数据库, 路径:" << resolvedPath;

    m_db = QSqlDatabase::addDatabase("QSQLITE", "smartscale_conn");
    m_db.setDatabaseName(resolvedPath);

    if (!m_db.open()) {
        qCritical() << "[DB] 打开数据库失败:" << m_db.lastError().text();
        return false;
    }

    // SQLite 性能优化
    QSqlQuery query(m_db);
    query.exec("PRAGMA journal_mode=WAL");      // 写时复制, 提升并发读写
    query.exec("PRAGMA synchronous=NORMAL");      // 平衡安全和性能
    query.exec("PRAGMA foreign_keys=ON");         // 启用外键约束

    // 执行版本迁移
    migrate();

    m_initialized = true;
    qDebug() << "[DB] 初始化完成, 当前版本:" << currentVersion();
    return true;
}

// ============================================================
// 数据库连接
// ============================================================
QSqlDatabase DatabaseManager::database()
{
    QMutexLocker locker(&m_mutex);
    if (!m_db.isOpen()) {
        qWarning() << "[DB] 数据库未打开";
    }
    return m_db;
}

void DatabaseManager::close()
{
    QMutexLocker locker(&m_mutex);
    if (m_db.isOpen()) {
        m_db.close();
        qDebug() << "[DB] 连接已关闭";
    }
}

// ============================================================
// 目录保证
// ============================================================
QString DatabaseManager::ensureDataDir(const QString &dbPath)
{
    QDir dir = QFileInfo(dbPath).absoluteDir();
    if (!dir.exists()) {
        bool ok = dir.mkpath(".");
        if (ok) {
            qDebug() << "[DB] 创建数据目录:" << dir.absolutePath();
        } else {
            qCritical() << "[DB] 创建数据目录失败:" << dir.absolutePath();
        }
    }
    return dbPath;
}

// ============================================================
// 版本管理
// ============================================================
int DatabaseManager::currentVersion()
{
    QSqlQuery query(m_db);
    query.exec("SELECT version FROM schema_version ORDER BY version DESC LIMIT 1");
    if (query.next()) {
        return query.value(0).toInt();
    }
    return 0;  // 未初始化
}

void DatabaseManager::setVersion(int version)
{
    QSqlQuery query(m_db);
    query.prepare("INSERT OR IGNORE INTO schema_version (version) VALUES (?)");
    query.addBindValue(version);
    if (!query.exec()) {
        qCritical() << "[DB] 设置版本失败:" << query.lastError().text();
    }
}

// ============================================================
// 迁移主流程
// ============================================================
void DatabaseManager::migrate()
{
    int version = currentVersion();
    qDebug() << "[DB] 当前数据库版本:" << version;

    // v1: 初始建表
    if (version < 1) {
        qDebug() << "[DB] 执行迁移 v1: 创建所有表";
        createTables();
        ensureDefaultUser();
        setVersion(1);
    }

    // 未来新增迁移在此追加:
    // if (version < 2) { ... setVersion(2); }
    // if (version < 3) { ... setVersion(3); }
}

void DatabaseManager::createTables()
{
    createSchemaVersionTable();
    createUsersTable();
    createWeightRecordsTable();
    createHardwareConfigTable();
}

// ============================================================
// 各表 DDL
// ============================================================

void DatabaseManager::createSchemaVersionTable()
{
    QSqlQuery query(m_db);
    bool ok = query.exec(R"(
        CREATE TABLE IF NOT EXISTS schema_version (
            version INTEGER PRIMARY KEY
        )
    )");
    if (!ok)
        qCritical() << "[DB] 建表 schema_version 失败:" << query.lastError().text();
}

void DatabaseManager::createUsersTable()
{
    QSqlQuery query(m_db);
    bool ok = query.exec(R"(
        CREATE TABLE IF NOT EXISTS users (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            username        TEXT    UNIQUE NOT NULL,
            password_hash   TEXT    NOT NULL,
            display_name    TEXT    DEFAULT '',
            is_active       INTEGER DEFAULT 1,
            created_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
        )
    )");
    if (!ok)
        qCritical() << "[DB] 建表 users 失败:" << query.lastError().text();
    else
        qDebug() << "[DB] 表 users 就绪";
}

void DatabaseManager::createWeightRecordsTable()
{
    QSqlQuery query(m_db);
    bool ok = query.exec(R"(
        CREATE TABLE IF NOT EXISTS weight_records (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,

            -- 核心业务字段
            weight          REAL    NOT NULL CHECK(weight >= 0),
            category_name   TEXT    NOT NULL,
            record_time     TEXT    NOT NULL,
            operator_name   TEXT    DEFAULT '',

            -- 双摄像头图片
            has_main_image  INTEGER DEFAULT 0,
            main_image_path TEXT    DEFAULT '',
            has_sub_image   INTEGER DEFAULT 0,
            sub_image_path  TEXT    DEFAULT '',

            -- 同步预留字段
            synced          INTEGER DEFAULT 0,
            cloud_id        TEXT    DEFAULT '',

            -- 内部时间戳
            created_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime')),
            updated_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
        )
    )");
    if (!ok)
        qCritical() << "[DB] 建表 weight_records 失败:" << query.lastError().text();
    else
        qDebug() << "[DB] 表 weight_records 就绪";

    // 索引: 按称重时间查询加速
    query.exec("CREATE INDEX IF NOT EXISTS idx_record_time ON weight_records(record_time)");
    // 索引: 按类别统计加速
    query.exec("CREATE INDEX IF NOT EXISTS idx_category ON weight_records(category_name)");
    // 索引: 同步状态查询加速
    query.exec("CREATE INDEX IF NOT EXISTS idx_synced ON weight_records(synced)");
}

void DatabaseManager::createHardwareConfigTable()
{
    QSqlQuery query(m_db);
    bool ok = query.exec(R"(
        CREATE TABLE IF NOT EXISTS hardware_config (
            id              INTEGER PRIMARY KEY AUTOINCREMENT,
            config_key      TEXT    UNIQUE NOT NULL,
            config_value    TEXT    NOT NULL,
            updated_at      TEXT    NOT NULL DEFAULT (datetime('now','localtime'))
        )
    )");
    if (!ok)
        qCritical() << "[DB] 建表 hardware_config 失败:" << query.lastError().text();
    else
        qDebug() << "[DB] 表 hardware_config 就绪";
}

void DatabaseManager::ensureDefaultUser()
{
    QSqlQuery query(m_db);
    query.exec("SELECT COUNT(*) FROM users");
    if (query.next() && query.value(0).toInt() > 0) {
        return; // 已有用户，跳过
    }

    QString hash = QCryptographicHash::hash(
        QByteArray("123456"),
        QCryptographicHash::Sha256
    ).toHex();

    query.prepare(R"(
        INSERT INTO users (username, password_hash, display_name, is_active)
        VALUES (?, ?, ?, ?)
    )");
    query.addBindValue("admin");
    query.addBindValue(hash);
    query.addBindValue("管理员");
    query.addBindValue(1);
    if (query.exec()) {
        qDebug() << "[DB] 默认管理员已创建: admin / 123456";
    } else {
        qCritical() << "[DB] 创建默认管理员失败:" << query.lastError().text();
    }
}
