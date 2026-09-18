#include "EmbeddedAssets.h"
#include "AppPaths.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QDebug>

namespace {

/// 内嵌资源前缀（app.qrc 中的 alias 前缀）
const char *kEmbeddedPrefix = ":/embedded/";

/// 缓存目录下的兜底释放子目录（设备目录不可写时才用）
const char *kReleaseRoot = "/embedded";

struct AssetSet {
    QString    subDir;    // 相对路径，例如 "AI"
    QString    fsBaseDir; // 优先使用的设备目录，例如 <APP_DIR>/AI
    QStringList files;    // 需要齐备的文件名
};

/**
 * 返回可用的资源目录，优先级：
 *   ① 设备目录（`<APP_DIR>/<子目录>`）文件齐备且大小与内嵌副本一致 → 直接用（零拷贝）
 *   ② 把内嵌副本释放到设备目录（与"随包部署"后的布局一致，便于运维查看）——
 *      仅当该目录可写时可用
 *   ③ 释放到缓存目录（必然可写，兜住 <APP_DIR> 属 root/只读的情况）
 *   ④ 都不可用返回空（调用方回退并告警）
 */
QString resolveDir(const AssetSet &set)
{
    const QString embeddedBase = QString::fromLatin1(kEmbeddedPrefix) + set.subDir + QLatin1Char('/');

    // 内嵌副本是否齐全（若未内嵌则整体降级为"只认设备目录"）
    bool embeddedComplete = true;
    for (const QString &name : set.files) {
        if (!QFileInfo::exists(embeddedBase + name)) {
            embeddedComplete = false;
            break;
        }
    }

    // ① 设备目录：文件齐备、且大小与内嵌副本一致时直接使用（零拷贝、行为与历史一致）
    if (!set.fsBaseDir.isEmpty()) {
        bool same = true;
        for (const QString &name : set.files) {
            const QFileInfo fsInfo(set.fsBaseDir + QLatin1Char('/') + name);
            if (!fsInfo.exists()) {
                same = false;
                break;
            }
            if (embeddedComplete
                && fsInfo.size() != QFileInfo(embeddedBase + name).size()) {
                same = false;   // 尺寸不同 ⇒ 视为过期，改用内嵌副本
                break;
            }
        }
        if (same)
            return set.fsBaseDir;
    }

    if (!embeddedComplete)
        return QString();

    // ② / ③ 释放位置候选：设备目录优先（与随包部署一致），其次缓存目录
    QStringList candidates;
    if (!set.fsBaseDir.isEmpty())
        candidates << set.fsBaseDir;
    candidates << AppPaths::cacheDir() + QString::fromLatin1(kReleaseRoot)
                  + QLatin1Char('/') + set.subDir;

    for (const QString &releaseDir : candidates) {
        if (!QDir().mkpath(releaseDir))
            continue;
        // mkpath 成功不代表可写（目录可能属其它用户且无写权限）
        if (!QFileInfo(releaseDir).isWritable()) {
            qWarning() << "[EmbeddedAssets] 释放目录不可写，尝试下一个:" << releaseDir;
            continue;
        }

        bool ok = true;
        for (const QString &name : set.files) {
            const QString src  = embeddedBase + name;
            const QString dest = releaseDir + QLatin1Char('/') + name;
            const QFileInfo destInfo(dest);
            if (destInfo.exists() && destInfo.size() == QFileInfo(src).size())
                continue;   // 已释放且版本一致
            QFile::remove(dest);
            if (!QFile::copy(src, dest)) {
                qWarning() << "[EmbeddedAssets] 释放失败:" << src << "->" << dest;
                ok = false;
                break;
            }
            qInfo() << "[EmbeddedAssets] 已释放内嵌资源:" << dest;
        }
        if (ok)
            return releaseDir;
    }

    qWarning() << "[EmbeddedAssets] 无可用释放目录:" << set.subDir;
    return QString();
}

} // namespace

namespace EmbeddedAssets {

QString aiDir()
{
    // 本地 mobilenetv3 已在 CameraController 中停用（识别走在线接口），
    // 因此这里只需要手写识别用到的两个文件。
    static const AssetSet set = {
        QStringLiteral("AI"),
        QCoreApplication::applicationDirPath() + QStringLiteral("/AI"),
        { QStringLiteral("rec.onnx"), QStringLiteral("ppocrv5_dict.txt") },
    };
    return resolveDir(set);
}

QString keyboardStyleRoot()
{
    static const AssetSet set = {
        QStringLiteral("keyboard_styles"),
        QCoreApplication::applicationDirPath() + QStringLiteral("/keyboard_styles"),
        { QStringLiteral("QtQuick/VirtualKeyboard/Styles/smartscale/style.qml") },
    };
    return resolveDir(set);
}

} // namespace EmbeddedAssets
