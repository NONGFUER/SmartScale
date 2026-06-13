#include "User.h"

QVariantMap User::toMap() const
{
    QVariantMap map;
    map["id"] = id;
    map["username"] = username;
    map["passwordHash"] = passwordHash;   // 注意: 敏感字段, 仅内部使用, 不应直接暴露给 QML
    map["displayName"] = displayName;
    map["isActive"] = isActive;
    map["createdAt"] = createdAt.toString(Qt::ISODate);
    map["updatedAt"] = updatedAt.toString(Qt::ISODate);
    return map;
}

User User::fromMap(const QVariantMap &map)
{
    User user;
    user.id = map.value("id", -1).toInt();
    user.username = map.value("username").toString();
    user.passwordHash = map.value("passwordHash").toString();
    user.displayName = map.value("displayName").toString();
    user.isActive = map.value("isActive", true).toBool();
    user.createdAt = QDateTime::fromString(map.value("createdAt").toString(), Qt::ISODate);
    user.updatedAt = QDateTime::fromString(map.value("updatedAt").toString(), Qt::ISODate);
    return user;
}

User::User(const QString &username, const QString &passwordHash)
    : username(username)
    , passwordHash(passwordHash)
    , isActive(true)
{
    createdAt = QDateTime::currentDateTime();
    updatedAt = createdAt;
}
