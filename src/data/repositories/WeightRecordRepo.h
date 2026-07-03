#ifndef WEIGHTRECORDREPO_H
#define WEIGHTRECORDREPO_H

#include <QObject>
#include <QList>
#include <QDate>
#include <QSqlQuery>
#include "data/models/WeightRecord.h"

// 前向声明
class DatabaseManager;

class WeightRecordRepo : public QObject
{
    Q_OBJECT

public:
    explicit WeightRecordRepo(DatabaseManager &dbMgr, QObject *parent = nullptr);

    // === CRUD ===
    int insert(const WeightRecord &record);   // 返回新插入的 id, 失败返回 -1
    bool update(const WeightRecord &record);
    bool remove(int id);
    bool softDelete(int id);                  // 软删除（撤回），设置 deleted=1

    // === 查询 ===
    WeightRecord findById(int id);
    QList<WeightRecord> queryAll();                                    // 全部记录 (按时间倒序)
    QList<WeightRecord> queryByDateRange(const QDate &from, const QDate &to); // 日期范围查询
    QList<WeightRecord> queryByCategory(const QString &categoryName);  // 按类别查询
    QList<WeightRecord> queryUnsynced();                               // 未同步的记录

    // === 统计 ===
    QVariantMap queryStatsForDate(const QDate &date);   // { count, totalWeight }
    int totalCount();
    double totalWeight();

private:
    WeightRecord fromQuery(QSqlQuery &query);
    DatabaseManager &m_db;
};

#endif // WEIGHTRECORDREPO_H
