#include "WeightRecordRepo.h"
#include "data/DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>

WeightRecordRepo::WeightRecordRepo(DatabaseManager &dbMgr, QObject *parent)
    : QObject(parent)
    , m_db(dbMgr)
{
}

int WeightRecordRepo::insert(const WeightRecord &record)
{
    QSqlQuery q(m_db.database());
    q.prepare(R"(
        INSERT INTO weight_records (
            weight, category_name, ingr_id, ai_detected, record_time, operator_name,
            has_main_image, main_image_path,
            has_sub_image, sub_image_path,
            synced, cloud_id
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    )");
    q.addBindValue(record.weight);
    q.addBindValue(record.categoryName);
    q.addBindValue(record.ingrId);
    q.addBindValue(record.aiDetected ? 1 : 0);
    q.addBindValue(record.recordTime);
    q.addBindValue(record.operatorName);
    q.addBindValue(record.hasMainImage ? 1 : 0);
    q.addBindValue(record.mainImagePath);
    q.addBindValue(record.hasSubImage ? 1 : 0);
    q.addBindValue(record.subImagePath);
    q.addBindValue(record.synced ? 1 : 0);
    q.addBindValue(record.cloudId);

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] 插入失败:" << q.lastError().text();
        return -1;
    }

    int lastId = q.lastInsertId().toInt();
    qDebug() << "[WeightRecordRepo] 插入成功, id =" << lastId;
    return lastId;
}

bool WeightRecordRepo::update(const WeightRecord &record)
{
    if (record.id <= 0) {
        qWarning() << "[WeightRecordRepo] 更新失败: 无效 id";
        return false;
    }

    QSqlQuery q(m_db.database());
    q.prepare(R"(
        UPDATE weight_records SET
            weight = ?,
            category_name = ?,
            ingr_id = ?,
            ai_detected = ?,
            record_time = ?,
            operator_name = ?,
            has_main_image = ?,
            main_image_path = ?,
            has_sub_image = ?,
            sub_image_path = ?,
            synced = ?,
            cloud_id = ?,
            updated_at = datetime('now','localtime')
        WHERE id = ?
    )");
    q.addBindValue(record.weight);
    q.addBindValue(record.categoryName);
    q.addBindValue(record.ingrId);
    q.addBindValue(record.aiDetected ? 1 : 0);
    q.addBindValue(record.recordTime);
    q.addBindValue(record.operatorName);
    q.addBindValue(record.hasMainImage ? 1 : 0);
    q.addBindValue(record.mainImagePath);
    q.addBindValue(record.hasSubImage ? 1 : 0);
    q.addBindValue(record.subImagePath);
    q.addBindValue(record.synced ? 1 : 0);
    q.addBindValue(record.cloudId);
    q.addBindValue(record.id);

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] 更新失败:" << q.lastError().text();
        return false;
    }

    qDebug() << "[WeightRecordRepo] 更新成功, id =" << record.id;
    return true;
}

bool WeightRecordRepo::remove(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("DELETE FROM weight_records WHERE id = ?");
    q.addBindValue(id);

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] 删除失败:" << q.lastError().text();
        return false;
    }

    qDebug() << "[WeightRecordRepo] 删除成功, id =" << id;
    return true;
}

WeightRecord WeightRecordRepo::findById(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("SELECT * FROM weight_records WHERE id = ?");
    q.addBindValue(id);

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] findById 查询失败:" << q.lastError().text()
                    << "id=" << id;
        return WeightRecord();
    }

    if (q.next()) {
        return fromQuery(q);
    }
    return WeightRecord();
}

QList<WeightRecord> WeightRecordRepo::queryAll()
{
    QList<WeightRecord> list;
    QSqlQuery q(m_db.database());
    q.exec("SELECT * FROM weight_records ORDER BY record_time DESC");

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

QList<WeightRecord> WeightRecordRepo::queryByDateRange(const QDate &from, const QDate &to)
{
    QList<WeightRecord> list;
    QSqlQuery q(m_db.database());
    q.prepare(R"(
        SELECT * FROM weight_records
        WHERE DATE(record_time) BETWEEN ? AND ?
        ORDER BY record_time DESC
    )");
    q.addBindValue(from.toString("yyyy-MM-dd"));
    q.addBindValue(to.toString("yyyy-MM-dd"));

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] queryByDateRange 查询失败:" << q.lastError().text()
                    << "from=" << from << "to=" << to;
        return list;
    }

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

QList<WeightRecord> WeightRecordRepo::queryByCategory(const QString &categoryName)
{
    QList<WeightRecord> list;
    QSqlQuery q(m_db.database());
    q.prepare("SELECT * FROM weight_records WHERE category_name = ? ORDER BY record_time DESC");
    q.addBindValue(categoryName);

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] queryByCategory 查询失败:" << q.lastError().text()
                    << "category=" << categoryName;
        return list;
    }

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

QList<WeightRecord> WeightRecordRepo::queryUnsynced()
{
    QList<WeightRecord> list;
    QSqlQuery q(m_db.database());
    q.exec("SELECT * FROM weight_records WHERE synced = 0 ORDER BY created_at ASC");

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

QVariantMap WeightRecordRepo::queryStatsForDate(const QDate &date)
{
    QSqlQuery q(m_db.database());
    q.prepare(R"(
        SELECT COUNT(*) as cnt, COALESCE(SUM(weight), 0) as total
        FROM weight_records
        WHERE DATE(record_time) = ?
    )");
    q.addBindValue(date.toString("yyyy-MM-dd"));

    QVariantMap stats;
    stats["count"] = 0;
    stats["totalWeight"] = 0.0;

    if (!q.exec()) {
        qCritical() << "[WeightRecordRepo] queryStatsForDate 查询失败:" << q.lastError().text()
                    << "date=" << date;
        return stats;
    }

    if (q.next()) {
        stats["count"] = q.value("cnt").toInt();
        stats["totalWeight"] = q.value("total").toDouble();
    }
    return stats;
}

int WeightRecordRepo::totalCount()
{
    QSqlQuery q(m_db.database());
    q.exec("SELECT COUNT(*) FROM weight_records");
    return q.next() ? q.value(0).toInt() : 0;
}

double WeightRecordRepo::totalWeight()
{
    QSqlQuery q(m_db.database());
    q.exec("SELECT COALESCE(SUM(weight), 0) FROM weight_records");
    return q.next() ? q.value(0).toDouble() : 0.0;
}

WeightRecord WeightRecordRepo::fromQuery(QSqlQuery &q)
{
    WeightRecord r;
    r.id           = q.value("id").toInt();
    r.weight       = q.value("weight").toDouble();
    r.categoryName = q.value("category_name").toString();
    r.ingrId       = q.value("ingr_id").toString();
    r.aiDetected   = q.value("ai_detected").toInt() != 0;
    r.recordTime   = q.value("record_time").toString();
    r.operatorName = q.value("operator_name").toString();
    r.hasMainImage = q.value("has_main_image").toInt() != 0;
    r.mainImagePath= q.value("main_image_path").toString();
    r.hasSubImage  = q.value("has_sub_image").toInt() != 0;
    r.subImagePath = q.value("sub_image_path").toString();
    r.synced       = q.value("synced").toInt() != 0;
    r.cloudId      = q.value("cloud_id").toString();
    r.createdAt    = QDateTime::fromString(q.value("created_at").toString(), Qt::ISODate);
    r.updatedAt    = QDateTime::fromString(q.value("updated_at").toString(), Qt::ISODate);
    return r;
}
