#include "HardwareConfigRepo.h"
#include "data/DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

HardwareConfigRepo::HardwareConfigRepo(DatabaseManager &dbMgr, QObject *parent)
    : QObject(parent)
    , m_db(dbMgr)
{
}

int HardwareConfigRepo::insert(const HardwareConfig &config)
{
    QSqlQuery q(m_db.database());
    q.prepare("INSERT INTO hardware_config (config_key, config_value) VALUES (?, ?)");
    q.addBindValue(config.key);
    q.addBindValue(config.value);

    if (!q.exec()) {
        qCritical() << "[HWConfigRepo] 插入失败:" << q.lastError().text();
        return -1;
    }
    return q.lastInsertId().toInt();
}

bool HardwareConfigRepo::update(const HardwareConfig &config)
{
    if (config.id <= 0) return false;

    QSqlQuery q(m_db.database());
    q.prepare(R"(
        UPDATE hardware_config SET config_key = ?, config_value = ?,
               updated_at = datetime('now','localtime') WHERE id = ?
    )");
    q.addBindValue(config.key);
    q.addBindValue(config.value);
    q.addBindValue(config.id);

    if (!q.exec()) {
        qCritical() << "[HWConfigRepo] 更新失败:" << q.lastError().text();
        return false;
    }
    return true;
}

bool HardwareConfigRepo::remove(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("DELETE FROM hardware_config WHERE id = ?");
    q.addBindValue(id);
    return q.exec();
}

bool HardwareConfigRepo::removeByKey(const QString &key)
{
    QSqlQuery q(m_db.database());
    q.prepare("DELETE FROM hardware_config WHERE config_key = ?");
    q.addBindValue(key);
    return q.exec();
}

HardwareConfig HardwareConfigRepo::findById(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("SELECT * FROM hardware_config WHERE id = ?");
    q.addBindValue(id);
    return q.next() ? fromQuery(q) : HardwareConfig();
}

HardwareConfig HardwareConfigRepo::findByKey(const QString &key)
{
    QSqlQuery q(m_db.database());
    q.prepare("SELECT * FROM hardware_config WHERE config_key = ?");
    q.addBindValue(key);
    return q.next() ? fromQuery(q) : HardwareConfig();
}

QList<HardwareConfig> HardwareConfigRepo::queryAll()
{
    QList<HardwareConfig> list;
    QSqlQuery q(m_db.database());
    q.exec("SELECT * FROM hardware_config ORDER BY id");

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

QString HardwareConfigRepo::getValue(const QString &key, const QString &defaultValue)
{
    auto cfg = findByKey(key);
    return cfg.id > 0 ? cfg.value : defaultValue;
}

int HardwareConfigRepo::getIntValue(const QString &key, int defaultValue)
{
    auto cfg = findByKey(key);
    return cfg.id > 0 ? cfg.valueInt(defaultValue) : defaultValue;
}

double HardwareConfigRepo::getDoubleValue(const QString &key, double defaultValue)
{
    auto cfg = findByKey(key);
    return cfg.id > 0 ? cfg.valueDouble(defaultValue) : defaultValue;
}

bool HardwareConfigRepo::getBoolValue(const QString &key, bool defaultValue)
{
    auto cfg = findByKey(key);
    return cfg.id > 0 ? cfg.valueBool(defaultValue) : defaultValue;
}

// --- upsert 实现 ---

bool HardwareConfigRepo::setValue(const QString &key, const QString &value)
{
    auto existing = findByKey(key);
    if (existing.id > 0) {
        existing.value = value;
        return update(existing);
    }
    return insert(HardwareConfig(key, value)) > 0;
}

bool HardwareConfigRepo::setIntValue(const QString &key, int value)
{
    return setValue(key, QString::number(value));
}

bool HardwareConfigRepo::setDoubleValue(const QString &key, double value)
{
    return setValue(key, QString::number(value, 'f', 4));
}

bool HardwareConfigRepo::setBoolValue(const QString &key, bool value)
{
    return setValue(key, value ? "true" : "false");
}

HardwareConfig HardwareConfigRepo::fromQuery(QSqlQuery &q)
{
    HardwareConfig c;
    c.id     = q.value("id").toInt();
    c.key    = q.value("config_key").toString();
    c.value  = q.value("config_value").toString();
    c.updatedAt = QDateTime::fromString(q.value("updated_at").toString(), Qt::ISODate);
    return c;
}
