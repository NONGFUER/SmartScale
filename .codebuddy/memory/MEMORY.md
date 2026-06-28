# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档，不另起条目。

## 编译约束（强制 — 违反会导致主板宕机）

- **禁止 AI 自行执行 `make` / `cmake --build` 等编译命令**。目标主板资源有限，并行编译（如 `make -j4`）会导致主板宕机。
- 用户平时用 `make -j1` 手动编译。AI 改完代码后只需用 `read_lints` 验证语法，**不要触发构建**。
- 若需验证编译，明确告知用户自行执行 `make -j1`，不要代劳。

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

## 弹窗遮罩修复范式（Popup/Dialog）

**症状**：弹窗打开后无黑色遮罩，背景透出，弹窗与下层页面粘连无层次。

**通用修复（照搬即可）**：Popup/Dialog 设 `modal: true` + 显式 `Overlay.modal: Rectangle { color: "#80000000" }`，**删除 `dim: false`**。显式 Overlay.modal 强制 Qt 用此 Rectangle 替换默认（可能异常透明）的 dimmer。

**根因模式（反复出现）**：`modal: true` + `dim: false` + 注释"遮罩由外部 Rectangle 控制" → 外部其实没画遮罩。这是从 LoginDialog 照搬的"外部遮罩"策略，但 LoginDialog 的遮罩是 Main.qml 手动画的 `loginOverlay` Rectangle（z:40），**不是** Qt 内置 dimmer；LoginDialog 用外部遮罩是为"避免 Qt 内部 modal 层遮挡虚拟键盘"。其他弹窗无此约束，不要照搬。

**已修复**：CategoryCorrectionDialog（Dialog）、SystemInfoDialog（Popup）。
**LoginDialog 例外**：保留 modal:false + 外部遮罩（虚拟键盘冲突），勿动。

## 版本号系统

- 主版本号在 `CMakeLists.txt` 的 `project(SmartScale VERSION x.y.z)` 中定义
- 构建号通过 `cmake -DBUILD_NUMBER=N` 手动指定（默认 9）
- 编译日期自动取当天
- 版本号经 `src/version.h.in` 模板由 `configure_file` 生成到 `build/generated/version.h`
- `SystemInfoService` 读取后暴露为 `Q_PROPERTY appVersion` 给 QML，`StatusBar.qml` 通过 `SystemInfo.appVersion` 动态显示

## 雪花 ID 类型安全

- 遇到雪花 ID 字段（ingrId/emsId/cateId/recoId/userId/productId）一律 `qint64`/`QString`，禁止 `toInt()`
- 详见 `.codebuddy/skills/id-type-safety/SKILL.md`

## 网络管理服务（NetworkManagerService）

- 位置：`src/services/NetworkManagerService.h|.cpp`，QML 绑定名 `App.Backend::NetworkManager`
- 统一管理 Wi-Fi 和 4G 网络，通过 nmcli (NetworkManager CLI) 和 mmcli (ModemManager CLI) 控制
- **Wi-Fi 功能**：扫描、连接/断开、状态查询、信号强度、IP 地址
- **4G 功能**：启用/禁用移动数据、运营商信息、信号强度、漫游检测
- 权限检查：`checkPermissions()` 验证 nmcli 可执行性和用户权限
- 状态轮询：每 10 秒自动刷新网络状态，通过 Q_PROPERTY + NOTIFY 实时同步到 UI
- 入口位置：`SettingsPage.qml` 的「网络控制」区段 + 状态栏 WiFi 图标弹窗模式

### nmcli 关键技术要点（踩坑记录）

**合法字段（nmcli device show）**：GENERAL.*、CAPABILITIES、INTERFACE-FLAGS、WIFI-PROPERTIES、AP、WIRED-PROPERTIES 等。**不含 WIFI.SIGNAL / CONNECTIONS.WIFI-SSID**，使用会导致 exitCode=2 整个命令失败。
- 查连接状态用：`GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS`
- **GENERAL.CONNECTION ≠ 真实 SSID**：返回的是连接 profile 名（可能被 sanitize 截断中文/特殊字符），需额外用 `nmcli -t -f 802-11-wireless.ssid connection show <connName>` 反查真实 SSID
- **nmcli -t 输出格式统一为 `field.name:value`**，必须取第一个冒号后的部分；且可能返回多行重复值，只取第一行即可
- **WiFi 设备名不一定是 wlan0**：必须先通过 `nmcli -t -f DEVICE,TYPE device` 动态发现 type=wifi 的设备名
- **两步连接法**：`connection add` (带 wifi-sec.key-mgmt wpa-psk) → `connection up <name>`，比一步 `device wifi connect` 更可靠避免 key-mgmt 缺失错误
- **Qt 资源路径**：CMake `qt_add_resources PREFIX "/" FILES resources/icon/x.png` 实际映射为 `qrc:/resources/icon/x.png`（保留完整子目录路径，不是 `qrc:/x.png`）
- **扫描权限**：需要 polkit 放行 `org.freedesktop.NetworkManager.wifi.scan`，否则报 "not authorized"

## QML 文件注册

## QML 跨目录类型引用（WorkstationPage 白屏根因）

- `WorkstationPage.qml` 在 `src/ui/pages/`，通过 `StackView.initialItem: "pages/WorkstationPage.qml"` **文件路径加载**，脱离 SmartScale 模块上下文
- 它能用同目录的 `CategoryCorrectionDialog` 是因为**同目录本地文件可见性**，不是因为模块注册
- 引用 `src/ui/components/` 下的 QML 组件（如 `ActionButton`、`FoodItemCard`）**必须**在文件顶部加 `import "../components"`，否则类型解析失败 → WorkstationPage 加载失败 → 白屏（仅剩背景图）
- `Main.qml` 在 `src/ui/` 下用 `import "components"`；`pages/` 下的文件用 `import "../components"`
- **诊断**：QML_FILES 已注册 + qrc 已含文件 + 构建成功，但页面白屏 → 检查引用方是否缺相对路径 import

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

## 虚拟键盘（VirtualKeyboard）

- 项目使用 Qt6 官方 `QtQuick.VirtualKeyboard` 模块。
- **Debian 13 (trixie) 的 Qt6 VirtualKeyboard 默认不打包 Pinyin 插件**（`Plugins/` 目录原本只有 Hangul/Hunspell/Thai）。已于 2026-06-25 自编译 v6.8.2 Pinyin 插件并部署到 `/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Pinyin/`（`libqtvkbpinyinplugin.so` + qmldir + plugins.qmltypes），父级 Plugins/qmldir 已追加 `import ...Pinyin auto`。词典 `dict_pinyin.dat` 已作 rcc 内嵌进 .so，无需独立数据文件。
- **自编译方法（如需重做）**：`git clone --depth 1 --branch v6.8.2 https://code.qt.io/qt/qtvirtualkeyboard.git`（GitHub 直连失败用 code.qt.io）→ 装 `qt6-base-private-dev` → `/usr/lib/qt6/bin/qt-cmake <src> -G Ninja -DCMAKE_BUILD_TYPE=Release`（必须用 qt-cmake 提供 BuildInternals 宏）→ `ninja -j1 qtvkbpinyinplugin`（主板 2GB 内存用 -j1）→ 拷贝 3 产物到 Plugins/Pinyin/ + 父级 qmldir 加 Pinyin import。
- 核心代码在 `src/ui/Main.qml`：导入(:5-6)、`Component.onCompleted` 设 `locale="zh_CN"`、`InputPanel` 实例、右上角"中/EN"切换按钮调用 `toggleInputMode()`。
- `InputPanel.active` 驱动主布局底部避让（`Main.qml:52`），各 Dialog 用 `inputPanel.active ? inputPanel.height + 20 : 0` 做 y 避让。
- **API 速查**（Qt 6.8.2 实测）：
  - `VirtualKeyboardSettings.locale`(rw) — 切换键盘布局/输入法
  - `VirtualKeyboardSettings.activeLocales`(rw) — 限制语言选择器列表；**没拼音引擎时设了反而让列表为空**，装了拼音插件后可设 `["zh_CN","en_GB"]`
  - `VirtualKeyboardSettings.availableLocales`(只读)
  - `VirtualKeyboardSettings.visibleFunctionKeys`(rw) — 控制地球/隐藏按钮可见性，枚举 `KeyboardFunctionKeys.None=0/Hide=1/Language=2/All=3`
  - **不存在** `languageFilterFunc`（曾编造过，已删除）
- **环境变量**（main.cpp）：只需 `QT_IM_MODULE=qtvirtualkeyboard` + `QT_VIRTUALKEYBOARD_STYLE=default`。`QT_VIRTUALKEYBOARD_LAYOUTS` 值是布局名（chinese/english）不是 locale（zh_CN）；`QT_VIRTUALKEYBOARD_LANGUAGE_FILTER` 不是 Qt 标准变量——这两个不要设。
- **验证拼音引擎是否真加载**：用 `nm -D libqtvkbpinyinplugin.so | grep -i pinyin` 看符号（不要用 strings，strings 里的 "Pinyin" 只是枚举常量名不可靠）。
