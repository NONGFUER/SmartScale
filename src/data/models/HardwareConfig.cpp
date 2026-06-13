#include "HardwareConfig.h"

QVariantMap HardwareConfig::toMap() const
{
    QVariantMap map;
    map["id"] = id;
    map["key"] = key;
    map["value"] = value;
    map["updatedAt"] = updatedAt.toString(Qt::ISODate);
    return map;
}

HardwareConfig HardwareConfig::fromMap(const QVariantMap &map)
{
    HardwareConfig config;
    config.id = map.value("id", -1).toInt();
    config.key = map.value("key").toString();
    config.value = map.value("value").toString();
    config.updatedAt = QDateTime::fromString(map.value("updatedAt").toString(), Qt::ISODate);
    return config;
}

int HardwareConfig::valueInt(int defaultValue) const
{
    bool ok = false;
    int result = value.toInt(&ok);
    return ok ? result : defaultValue;
}

double HardwareConfig::valueDouble(double defaultValue) const
{
    bool ok = false;
    double result = value.toDouble(&ok);
    return ok ? result : defaultValue;
}

bool HardwareConfig::valueBool(bool defaultValue) const
{
    QString lower = value.toLower().trimmed();
    if (lower == "true" || lower == "1" || lower == "yes")
        return true;
    if (lower == "false" || lower == "0" || lower == "no")
        return false;
    return defaultValue;
}

HardwareConfig::HardwareConfig(const QString &key, const QString &value)
    : key(key)
    , value(value)
{
    updatedAt = QDateTime::currentDateTime();
}
