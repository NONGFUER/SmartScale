#include "AppPaths.h"

#include <QDir>
#include <QFileInfo>
#include <QDateTime>
#include <QDebug>
#include <QStringList>

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
