#include "AppPaths.h"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDateTime>
#include <QDebug>
#include <QStringList>

#include <cerrno>
#include <pwd.h>
#include <unistd.h>

namespace {

const char *kEnvHomeOverride = "SMARTSCALE_HOME";

/**
 * 解析家目录。结果只在首次调用时计算一次（进程内不会变化）。
 */
const QString &resolvedHome()
{
    static const QString cached = []() -> QString {
        // 1) 显式覆盖（部署/调试用，例如 SMARTSCALE_HOME=/home/sjwu）
        const QByteArray env = qgetenv(kEnvHomeOverride);
        if (!env.isEmpty()) {
            const QString path = QString::fromLocal8Bit(env);
            qInfo() << "[AppPaths] 使用 SMARTSCALE_HOME 覆盖:" << path;
            return path;
        }

        const QString processHome = QDir::homePath();

        // 2) 正常情况：进程用户就是设备使用用户，保持与历史行为完全一致
        if (::geteuid() != 0)
            return processHome;

        // 3) root（OTA 脚本兜底拉起）：纠正到第一个普通用户的家目录，
        //    否则会读写 /root 下另一套账号与设置
        QString userHome;
        ::setpwent();
        for (struct passwd *pw = ::getpwent(); pw != nullptr; pw = ::getpwent()) {
            if (pw->pw_uid >= 1000 && pw->pw_uid < 65534 && pw->pw_dir && *pw->pw_dir) {
                userHome = QString::fromLocal8Bit(pw->pw_dir);
                break;
            }
        }
        ::endpwent();

        if (!userHome.isEmpty() && QFileInfo(userHome).isWritable()) {
            qInfo() << "[AppPaths] 检测到以 root 启动，HOME 纠正:"
                    << processHome << "->" << userHome;
            return userHome;
        }

        qWarning() << "[AppPaths] 未能确定普通用户家目录，回退" << processHome;
        return processHome;
    }();
    return cached;
}

/**
 * 家目录属主（uid/gid）。仅在"以 root 启动且家目录已纠正到普通用户"时有效，
 * 其余情况 invalid=true 表示不需要/不能纠正属主。
 */
struct HomeOwner
{
    uid_t uid = 0;
    gid_t gid = 0;
    bool  valid = false;
};

const HomeOwner &homeOwner()
{
    static const HomeOwner cached = []() -> HomeOwner {
        HomeOwner owner;

        if (::geteuid() != 0)
            return owner;   // 非 root：无权限，也无必要

        const QString h = resolvedHome();
        if (h.startsWith(QStringLiteral("/root")))
            return owner;   // 家目录未纠正成功 → 不动属主（避免把 /root 的东西改了）

        const QFileInfo info(h);
        if (!info.exists())
            return owner;

        owner.uid = info.ownerId();
        owner.gid = info.groupId();
        owner.valid = (owner.uid != 0);   // 家目录本身属 root 时不纠正
        return owner;
    }();
    return cached;
}

/** 递归把 path 的属主改为 uid:gid，返回实际纠正的条目数 */
int chownTree(const QString &path, uid_t uid, gid_t gid)
{
    const QFileInfo info(path);
    if (!info.exists())
        return 0;

    int fixed = 0;
    if (info.ownerId() != uid || info.groupId() != gid) {
        const QByteArray native = QFile::encodeName(path);
        if (::lchown(native.constData(), uid, gid) == 0)
            ++fixed;
        else
            qWarning() << "[AppPaths] 修正属主失败:" << path << "errno=" << errno;
    }

    if (info.isDir() && !info.isSymLink()) {
        const QFileInfoList entries =
            QDir(path).entryInfoList(QDir::NoDotAndDotDot | QDir::AllEntries | QDir::System | QDir::Hidden);
        for (const QFileInfo &entry : entries)
            fixed += chownTree(entry.absoluteFilePath(), uid, gid);
    }

    return fixed;
}

} // namespace

namespace AppPaths {

QString home()
{
    return resolvedHome();
}

QString configDir()
{
    return home() + QStringLiteral("/.config/SmartScale");
}

QString cacheDir()
{
    return home() + QStringLiteral("/.cache/smartscale");
}

void ensureDir(const QString &dir)
{
    if (!dir.isEmpty())
        QDir().mkpath(dir);
}

void adoptOwnership(const QString &path)
{
    const HomeOwner &owner = homeOwner();
    if (!owner.valid || path.isEmpty())
        return;

    const int fixed = chownTree(path, owner.uid, owner.gid);
    if (fixed > 0)
        qInfo() << "[AppPaths] 已把" << fixed << "项属主纠正为 uid" << owner.uid << ":" << path;
}

void adoptAppDataOwnership()
{
    const HomeOwner &owner = homeOwner();
    if (!owner.valid)
        return;

    int fixed = 0;
    for (const QString &dir : { configDir(), cacheDir() })
        fixed += chownTree(dir, owner.uid, owner.gid);

    if (fixed > 0)
        qInfo() << "[AppPaths] 以 root 启动，已修正" << fixed
                << "项 root 遗留属主（普通用户实例否则无法写入→设置改动后重启失效）";
}

void retireStaleRootData()
{
    if (::geteuid() != 0)
        return;   // 只有 root 实例有权限、也才有必要

    // 家目录未纠正成功（仍指向 /root）时不动它，避免"作废了又被重新创建"
    if (home().startsWith(QStringLiteral("/root")))
        return;

    const QString stamp = QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss"));
    const QStringList staleDirs = {
        QStringLiteral("/root/.config/SmartScale"),
        QStringLiteral("/root/.cache/smartscale"),
    };

    for (const QString &dir : staleDirs) {
        if (!QFileInfo::exists(dir))
            continue;   // 已作废过或本来就没有 → 幂等
        const QString target = dir + QStringLiteral(".stale-") + stamp;
        if (QDir().rename(dir, target))
            qInfo() << "[AppPaths] 已作废 root 遗留数据:" << dir << "->" << target;
        else
            qWarning() << "[AppPaths] 作废 root 遗留数据失败:" << dir;
    }
}

} // namespace AppPaths
