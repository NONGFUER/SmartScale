// pragma Singleton 必须在文件第一行（注释除外）
pragma Singleton
import QtQuick

// ============================================================================
// 全局主题常量（字体族、字号、颜色等）
// ============================================================================
//
// 使用方式：
//   1. 在 QML 文件顶部加：import SmartScale
//   2. 引用：font.family: Theme.fontFamilyUi
//           font.pixelSize: Theme.fontSizeBody
//
// 注册方式：
//   - 顶部 `pragma Singleton` + 加入 CMakeLists.txt 的 QML_FILES
//   - qt_add_qml_module 会自动注册为 SmartScale 模块的 singleton
//
// 命名规范：
//   - font 族：fontFamilyXxx
//   - 字号：fontSizeXxx（按用途语义命名，不按数字大小）
//   - 颜色：colorXxx
// ============================================================================

QtObject {
    // ============================================================
    // 字体族
    // ============================================================
    readonly property string fontFamilyUi:    "Microsoft YaHei"  // 主 UI 字体
    readonly property string fontFamilyTitle: "AlibabaPuHuiTi"   // 大标题字体
    readonly property string fontFamilyMono:  "Monospace"        // 等宽字体（时间/数字）

    // ============================================================
    // 字号（按用途语义命名，便于全局调整）
    // ============================================================

    // --- 标题系列 ---
    readonly property int fontSizeTitleXl: 36   // 状态栏主标题（如"AI视觉识别智能网络称"）
    readonly property int fontSizeTitleLg: 36   // 页面标题（如"设置"）
    readonly property int fontSizeTitleMd: 18   // 区段标题/卡片标题

    // --- 正文系列 ---
    readonly property int fontSizeBody:    30   // 设置项标签/值等常规文本
    readonly property int fontSizeBodySm:  15   // 输入框、按钮内文字
    readonly property int fontSizeCaption: 13   // 小标签、辅助说明
    readonly property int fontSizeCaptionSm: 12 // 极小标签（如状态徽章）

    // --- 大数字显示系列（重量、计数等） ---
    readonly property int fontSizeDigitMd: 28   // 中等数字
    readonly property int fontSizeDigitLg: 48   // 大数字
    readonly property int fontSizeDigitXl: 88   // 重量主显示
    readonly property int fontSizeDigitXxl: 148 // 超大数字

    // --- 返回/导航按钮图标 ---
    readonly property int fontSizeIconBack: 28

    // ============================================================
    // 颜色（按需扩展，目前只列 SettingsPage 用到的）
    // ============================================================
    readonly property color colorTextPrimary:   "#1B263B"  // 主要文字
    readonly property color colorTextSecondary: "#666666"  // 标签文字
    readonly property color colorTextTertiary:  "#94A3B8"  // 辅助箭头等
    readonly property color colorDivider:       "#E5E7EB"  // 分隔线
    readonly property color colorInputBg:       "#FAFAFA"  // 输入框背景
    readonly property color colorInputBorder:   "#D1D5DB"  // 输入框边框
    readonly property color colorAccent:        "#4361EE"  // 主色调（聚焦边框等）
}
