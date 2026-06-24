#include "WeightRecord.h"

QVariantMap WeightRecord::toMap() const
{
    QVariantMap map;
    map["id"] = id;
    map["weight"] = weight;
    map["categoryName"] = categoryName;
    map["ingrId"] = ingrId;
    map["aiDetected"] = aiDetected;
    map["recordTime"] = recordTime;
    map["operatorName"] = operatorName;
    map["hasMainImage"] = hasMainImage;
    map["mainImagePath"] = mainImagePath;
    map["hasSubImage"] = hasSubImage;
    map["subImagePath"] = subImagePath;
    map["synced"] = synced;
    map["cloudId"] = cloudId;
    map["createdAt"] = createdAt.toString(Qt::ISODate);
    map["updatedAt"] = updatedAt.toString(Qt::ISODate);
    return map;
}

WeightRecord WeightRecord::fromMap(const QVariantMap &map)
{
    WeightRecord record;
    record.id = map.value("id", -1).toInt();
    record.weight = map.value("weight", 0.0).toDouble();
    record.categoryName = map.value("categoryName").toString();
    record.ingrId = map.value("ingrId").toString();
    record.aiDetected = map.value("aiDetected", false).toBool();
    record.recordTime = map.value("recordTime").toString();
    record.operatorName = map.value("operatorName").toString();
    record.hasMainImage = map.value("hasMainImage", false).toBool();
    record.mainImagePath = map.value("mainImagePath").toString();
    record.hasSubImage = map.value("hasSubImage", false).toBool();
    record.subImagePath = map.value("subImagePath").toString();
    record.synced = map.value("synced", false).toBool();
    record.cloudId = map.value("cloudId").toString();
    record.createdAt = QDateTime::fromString(map.value("createdAt").toString(), Qt::ISODate);
    record.updatedAt = QDateTime::fromString(map.value("updatedAt").toString(), Qt::ISODate);
    return record;
}

QDate WeightRecord::date() const
{
    if (recordTime.isEmpty())
        return QDate();
    // 支持 "2026-04-26 14:30" 或 "2026-04-26T14:30:00" 格式
    QString dateStr = recordTime.left(10);
    return QDate::fromString(dateStr, "yyyy-MM-dd");
}

WeightRecord::WeightRecord(double weight,
                           const QString &categoryName,
                           const QString &operatorName,
                           const QString &recordTime,
                           const QString &mainImagePath,
                           const QString &subImagePath)
    : weight(weight)
    , categoryName(categoryName)
    , operatorName(operatorName)
    , synced(false)
{
    if (recordTime.isEmpty()) {
        this->recordTime = QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss");
    } else {
        this->recordTime = recordTime;
    }

    hasMainImage = !mainImagePath.isEmpty();
    this->mainImagePath = mainImagePath;

    hasSubImage = !subImagePath.isEmpty();
    this->subImagePath = subImagePath;

    createdAt = QDateTime::currentDateTime();
    updatedAt = createdAt;
}
