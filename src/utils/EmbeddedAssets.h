#ifndef EMBEDDEDASSETS_H
#define EMBEDDEDASSETS_H

#include <QString>

/**
 * @brief 二进制内嵌资源（键盘样式、手写识别模型）的可用性保障
 *
 * 背景（为什么需要它）：
 *   OTA 刷写脚本 `apply_update.sh` 是由**设备上正在运行的那个版本**导出的
 *   （`OtaService::install()` 从 `:/scripts/apply_update.sh` 导出）。2026-09-18 之前
 *   的版本里没有"同步 AI/ 与 keyboard_styles/ 目录"这一步，而且该步骤本身也只
 *   `cp` 一个文件 `appSmartScale`。于是存量机器第一次 OTA 后会出现
 *   "新二进制 + 缺样式 + 缺模型"：样式缺失会让手写区一个笔画都采不到
 *   （回退的系统 light 样式没有 traceCanvasDelegate），模型缺失则手写无法识别。
 *   客户只做一次 OTA，因此资源必须**随二进制一起送到**。
 *
 * 做法：
 *   样式与手写模型在 `app.qrc` 里各内嵌一份副本；本模块在启动/首次使用时按序：
 *   ①设备目录（`<APP_DIR>/<子目录>`）文件齐备且**尺寸与内嵌副本一致** → 直接用（零开销）；
 *   ②把内嵌副本释放到**设备目录**（与"随包部署"后的布局一致，运维查看直观）；
 *   ③设备目录不可写（例如属 root）→ 退回 `<AppPaths::cacheDir()>/embedded/<子目录>`；
 *   ④都不可用 → 返回空，调用方回退并告警。
 *
 * 注意：判断"一致"用的是文件大小（与内嵌副本比较），避免每次启动都哈希 16MB 模型。
 */
namespace EmbeddedAssets {

/**
 * AI 模型目录（`rec.onnx` + `ppocrv5_dict.txt` 均在）。
 * 优先 `<APP_DIR>/AI`（已有则直接用，缺失则释放到该目录）；不可写时退回缓存目录；
 * 都不可用返回空字符串。
 */
QString aiDir();

/**
 * 键盘样式根目录，其下为 `QtQuick/VirtualKeyboard/Styles/smartscale/style.qml`。
 * 优先 `<APP_DIR>/keyboard_styles`（已有则直接用，缺失则释放到该目录）；不可写时退回缓存目录；
 * 都不可用返回空字符串。
 */
QString keyboardStyleRoot();

} // namespace EmbeddedAssets

#endif // EMBEDDEDASSETS_H
