#include "UserRepo.h"
#include "data/DatabaseManager.h"

#include <QSqlQuery>
#include <QSqlError>
#include <QDebug>
#include <QCryptographicHash>

UserRepo::UserRepo(DatabaseManager &dbMgr, QObject *parent)
    : QObject(parent)
    , m_db(dbMgr)
{
}

int UserRepo::insert(const User &user)
{
    QSqlQuery q(m_db.database());
    q.prepare(R"(
        INSERT INTO users (username, password_hash, display_name, is_active)
        VALUES (?, ?, ?, ?)
    )");
    q.addBindValue(user.username);
    q.addBindValue(user.passwordHash);
    q.addBindValue(user.displayName);
    q.addBindValue(user.isActive ? 1 : 0);

    if (!q.exec()) {
        qCritical() << "[UserRepo] 插入失败:" << q.lastError().text();
        return -1;
    }

    int lastId = q.lastInsertId().toInt();
    qDebug() << "[UserRepo] 插入成功, id =" << lastId;
    return lastId;
}

bool UserRepo::update(const User &user)
{
    if (user.id <= 0) return false;

    QSqlQuery q(m_db.database());
    q.prepare(R"(
        UPDATE users SET
            username = ?,
            password_hash = ?,
            display_name = ?,
            is_active = ?,
            updated_at = datetime('now','localtime')
        WHERE id = ?
    )");
    q.addBindValue(user.username);
    q.addBindValue(user.passwordHash);
    q.addBindValue(user.displayName);
    q.addBindValue(user.isActive ? 1 : 0);
    q.addBindValue(user.id);

    if (!q.exec()) {
        qCritical() << "[UserRepo] 更新失败:" << q.lastError().text();
        return false;
    }
    return true;
}

bool UserRepo::remove(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("DELETE FROM users WHERE id = ?");
    q.addBindValue(id);
    return q.exec();
}

User UserRepo::findById(int id)
{
    QSqlQuery q(m_db.database());
    q.prepare("SELECT * FROM users WHERE id = ?");
    q.addBindValue(id);
    return q.next() ? fromQuery(q) : User();
}

User UserRepo::findByUsername(const QString &username)
{
    QSqlQuery q(m_db.database());
    qDebug() << "[UserRepo] findByUsername 数据库:" << m_db.database().databaseName()
             << "连接名:" << m_db.database().connectionName()
             << "打开:" << m_db.database().isOpen();
    q.prepare("SELECT * FROM users WHERE username = ?");
    q.addBindValue(username);
    if (!q.exec()) {
        qDebug() << "[UserRepo] 查询失败:" << q.lastError().text();
        return User();
    }
    bool hasData = q.next();
    qDebug() << "[UserRepo] 查询结果:" << (hasData ? "有数据" : "无数据");
    return hasData ? fromQuery(q) : User();
}

QList<User> UserRepo::queryAll()
{
    QList<User> list;
    QSqlQuery q(m_db.database());
    q.exec("SELECT * FROM users ORDER BY id");

    while (q.next()) {
        list.append(fromQuery(q));
    }
    return list;
}

bool UserRepo::verifyPassword(const QString &username, const QString &plainPassword)
{
    User user = findByUsername(username);
    if (user.id <= 0) {
        qDebug() << "[UserRepo] 用户不存在:" << username;
        return false;
    }

    // 对输入明文做 SHA256 哈希后比对
    QByteArray hash = QCryptographicHash::hash(
        plainPassword.toUtf8(), QCryptographicHash::Sha256).toHex();
    bool ok = (hash == user.passwordHash.toUtf8());

    if (!ok) {
        qDebug() << "[UserRepo] 密码错误:" << username;
    } else {
        qDebug() << "[UserRepo] 验证通过:" << username;
    }
    return ok;
}

bool UserRepo::usernameExists(const QString &username)
{
    QSqlQuery q(m_db.database());
    q.prepare("SELECT COUNT(*) FROM users WHERE username = ?");
    q.addBindValue(username);
    return (q.next() && q.value(0).toInt() > 0);
}

User UserRepo::fromQuery(QSqlQuery &q)
{
    User u;
    u.id          = q.value("id").toInt();
    u.username    = q.value("username").toString();
    u.passwordHash= q.value("password_hash").toString();
    u.displayName = q.value("display_name").toString();
    u.isActive    = q.value("is_active").toInt() != 0;

    // 数据库存储的是本地时间字符串，按 LocalTime 解析
    QString createdAtStr = q.value("created_at").toString();
    QString updatedAtStr = q.value("updated_at").toString();
    u.createdAt   = QDateTime::fromString(createdAtStr, Qt::ISODate);
    u.updatedAt   = QDateTime::fromString(updatedAtStr, Qt::ISODate);
    return u;
}
