# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档，不另起条目。

## 触摸屏环境（强制）

**目标设备是触摸屏，没有鼠标光标。**

1. **全局隐藏系统光标**：`main.cpp` 中 `QGuiApplication` 创建后立即调用 `QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor))`（需 `#include <QCursor>`）
2. **QML 层禁止设置 cursorShape**：所有 `MouseArea` 不要写 `cursorShape` 这一行（包括 `Qt.PointingHandCursor`、`Qt.ArrowCursor`、`Qt.BlankCursor` 等）。已有代码中所有 `cursorShape` 已批量清理

## QML 浮层提示规则（强制）

**全局 Toast / 通知 / 临时提示组件的根节点必须用 Qt Quick Controls 的 `Popup`（或 `Dialog`），禁止用裸 `Item` + `anchors` + `z:9999`。**

- **理由**：`Item` + `z` 在 `ApplicationWindow.contentItem` 上会被同层级的 `StackView` / `SwipeView` 等内容覆盖或裁剪，即使设 `z:9999`、`opacity=1`、`y=0` 也视觉不可见。`Popup` 是原生浮层，渲染在窗口 Overlay 顶层，不受 z-order 影响。
- **写法要点**：
  - `modal: false` + `closePolicy: Popup.NoAutoClose` + `padding: 0` + 透明 `background: Item {}`
  - 用 `root.open()` / `root.close()` 控制显隐，配 `enter/exit: Transition` 做动画
  - 队列逻辑（show/_next/_dismiss/timer）独立于类型，可以照搬
- **诊断套路**：若提示没弹出，先加日志串起 `C++ emit → QML Connections 收到 → window.toast() 调用 → _present() 执行` 四段链路，确认是渲染问题还是链路断点。链路全通但不可见，必是浮层类型问题。

## 版本号系统

- 主版本号在 `CMakeLists.txt` 的 `project(SmartScale VERSION x.y.z)` 中定义
- 构建号通过 `cmake -DBUILD_NUMBER=N` 手动指定（默认 9）
- 编译日期自动取当天
- 版本号经 `src/version.h.in` 模板由 `configure_file` 生成到 `build/generated/version.h`
- `SystemInfoService` 读取后暴露为 `Q_PROPERTY appVersion` 给 QML，`StatusBar.qml` 通过 `SystemInfo.appVersion` 动态显示

## 雪花 ID 类型安全

- 遇到雪花 ID 字段（ingrId/emsId/cateId/recoId/userId/productId）一律 `qint64`/`QString`，禁止 `toInt()`
- 详见 `.codebuddy/skills/id-type-safety/SKILL.md`

## QML 文件注册

- SmartScale 项目 `CMakeLists.txt` 用 `qt_add_qml_module` **显式列出** `QML_FILES`（非自动扫描）
- 新建 QML 文件后**必须**手动追加到 `QML_FILES` 列表，否则运行时报 "xxx is not a type" 导致 Main.qml 白屏

## QML Singleton 创建方式

- **纯 QML singleton**（如 Theme.qml）需要**三步**（缺一不可，Qt 6.8 实测）：
  1. QML 文件顶部 `pragma Singleton`
  2. CMake 中 `set_source_files_properties(xxx.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)`，**必须在 `qt_add_qml_module` 之前**
  3. 加入 `qt_add_qml_module` 的 `QML_FILES` 列表
- **诊断 singleton 是否真生效**：检查 `build/<URI>/qmldir`，singleton 行必须以 `singleton` 关键字开头（如 `singleton Theme 254.0 src/ui/Theme.qml`）。若缺 `singleton` 关键字，运行时 Theme 被当普通类型，`Theme.xxx` 引用全部静默失效但无报错
- **C++ singleton**（如 SystemInfo、WeightManager）：main.cpp 中 `qmlRegisterSingletonInstance("App.Backend", 1, 0, "XXX", ptr)` 注册。访问：`import App.Backend 1.0`
- 项目中两套模块并存：UI 主题常量用 `SmartScale`，业务服务用 `App.Backend`

## 全局主题常量（Theme.qml）

- 文件位置：`src/ui/Theme.qml`，singleton
- 集中管理字体族（`fontFamilyUi`/`fontFamilyTitle`/`fontFamilyMono`）、字号（按用途语义命名：`fontSizeTitleLg`=24、`fontSizeBody`=16 等）、颜色（`colorTextPrimary` 等）
- **新增 QML 字体/颜色一律走 Theme 引用，禁止硬编码**。已有文件按需逐步迁移
