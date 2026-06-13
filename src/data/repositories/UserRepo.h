#ifndef USERREPO_H
#define USERREPO_H

#include <QObject>
#include <QList>
#include <QSqlQuery>
#include "data/models/User.h"

class DatabaseManager;

class UserRepo : public QObject
{
    Q_OBJECT

public:
    explicit UserRepo(DatabaseManager &dbMgr, QObject *parent = nullptr);

    // === CRUD ===
    int insert(const User &user);
    bool update(const User &user);
    bool remove(int id);

    // === 查询 ===
    User findById(int id);
    User findByUsername(const QString &username);
    QList<User> queryAll();

    // === 认证相关 ===
    bool verifyPassword(const QString &username, const QString &plainPassword);
    bool usernameExists(const QString &username);

private:
    User fromQuery(QSqlQuery &q);
    DatabaseManager &m_db;
};

#endif // USERREPO_H
