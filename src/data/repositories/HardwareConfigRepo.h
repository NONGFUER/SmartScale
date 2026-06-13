#ifndef HARDWARECONFIGREPO_H
#define HARDWARECONFIGREPO_H

#include <QObject>
#include <QList>
#include <QSqlQuery>
#include "data/models/HardwareConfig.h"

class DatabaseManager;

class HardwareConfigRepo : public QObject
{
    Q_OBJECT

public:
    explicit HardwareConfigRepo(DatabaseManager &dbMgr, QObject *parent = nullptr);

    // === CRUD ===
    int insert(const HardwareConfig &config);
    bool update(const HardwareConfig &config);
    bool remove(int id);
    bool removeByKey(const QString &key);

    // === 查询 ===
    HardwareConfig findById(int id);
    HardwareConfig findByKey(const QString &key);         // 按 key 查找
    QList<HardwareConfig> queryAll();

    // === 便捷访问 (带默认值) ===
    QString getValue(const QString &key, const QString &defaultValue = QString());
    int getIntValue(const QString &key, int defaultValue = 0);
    double getDoubleValue(const QString &key, double defaultValue = 0.0);
    bool getBoolValue(const QString &key, bool defaultValue = false);

    // === 快捷设置 (upsert: 存在则更新, 不存在则插入) ===
    bool setValue(const QString &key, const QString &value);
    bool setIntValue(const QString &key, int value);
    bool setDoubleValue(const QString &key, double value);
    bool setBoolValue(const QString &key, bool value);

private:
    HardwareConfig fromQuery(QSqlQuery &q);
    DatabaseManager &m_db;
};

#endif // HARDWARECONFIGREPO_H
