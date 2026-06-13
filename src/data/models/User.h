#ifndef USER_H
#define USER_H

#include <QString>
#include <QVariantMap>
#include <QDateTime>

class User
{
public:
    int id = -1;
    QString username;            // 登录用户名
    QString passwordHash;        // 密码哈希 (不存明文)
    QString displayName;         // 显示名称 (可选)
    bool isActive = true;        // 账户是否启用

    QDateTime createdAt;
    QDateTime updatedAt;

public:
    QVariantMap toMap() const;
    static User fromMap(const QVariantMap &map);

    User() = default;
    explicit User(const QString &username, const QString &passwordHash);
};

#endif // USER_H
