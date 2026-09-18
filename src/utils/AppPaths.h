#ifndef APPPATHS_H
#define APPPATHS_H

#include <QString>

/**
 * @brief 应用配置 / 缓存根目录的统一解析
 *
 * 背景（为什么需要它）：
 *   本应用会以两种身份被拉起 —— 桌面用户（正常开机、手动运行）与 root
 *   （OTA 刷写脚本 apply_update.sh 探测不到 systemd 服务时的 nohup 兜底）。
 *   而 Qt 的 QDir::homePath() / QSettings::UserScope 都以**进程的 HOME** 为准，
 *   于是同一台设备上出现两套互不相干的账号、设置与缓存：
 *     - 桌面用户启动 → /home/<user>/.config/SmartScale/last_login.conf
 *     - OTA 启动      → /root/.config/SmartScale/last_login.conf
 *   表现为"OTA 之后自动登录了另一个账号、设置也变了"。
 *
 * 解决方式：
 *   所有需要"家目录"的地方一律改用本模块，不再直接用 QDir::homePath()。
 *   非 root 时结果与 QDir::homePath() 完全相同（行为零变化），
 *   只在以 root 启动时才纠正到真实普通用户的家目录。
 *
 * 取值优先级：
 *   1) 环境变量 SMARTSCALE_HOME（部署/调试可覆盖）
 *   2) 非 root                     → QDir::homePath()
 *   3) root                        → /etc/passwd 中第一个 uid∈[1000,65534) 用户的家目录
 *                                     （取不到或不可写则回退 QDir::homePath()）
 */
namespace AppPaths {

/** 家目录（取代全部 QDir::homePath() 调用点） */
QString home();

/** 配置根：<home>/.config/SmartScale（账号、设置、wifi 密码） */
QString configDir();

/** 缓存根：<home>/.cache/smartscale（食材列表/图片、登录历史、productId） */
QString cacheDir();

/** 确保目录存在（mkpath） */
void ensureDir(const QString &dir);

/**
 * @brief 以 root 身份启动时，把 /root 下的旧配置与缓存改名作废
 *
 * 为什么需要：作废前，root 实例读的是 /root 下那份凭据（历史遗留的另一个账号）。
 * 虽然改用 AppPaths 后已不会再读它，但把它改名可以彻底消除误解与"万一规则失效"
 * 的兜底。非 root 启动时不做任何事；重复启动时源目录已不存在，天然幂等。
 *
 * 注意：若家目录未能纠正（仍解析到 /root，例如系统里没有 uid>=1000 的用户），
 *       则直接返回，避免出现"作废了又被重新创建"的来回折腾。
 */
void retireStaleRootData();

} // namespace AppPaths

#endif // APPPATHS_H
