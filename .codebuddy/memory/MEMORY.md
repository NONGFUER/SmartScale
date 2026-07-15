# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档，不另起条目。

## 编译约束（强制）
- **禁止 AI 自行执行 `make` / `cmake --build`**。目标主板资源有限，并行编译会宕机。
- 用户用 `make -j1` 手动编译。AI 改完用 `read_lints` 验证语法即可，不要触发构建；需验证时告知用户自跑 `make -j1`。

## 触摸屏环境（强制）
- 目标设备无鼠标光标。
- `main.cpp` 中 `QGuiApplication` 创建后立即 `setOverrideCursor(QCursor(Qt::BlankCursor))`（需 `#include <QCursor>`）。
- QML 所有 `MouseArea` 禁止写 `cursorShape` 行（PointingHand/Arrow/Blank 等均不要）。清理进行中：CategoryCorrectionDialog 已清；WorkstationPage/AddIngredientDialog/AlertDialog/SettingsDialog/WeightRecordSearchDialog/WifiListDialog/SettingsPage 仍有残留，待后续遇到相关改动时顺手清理。

## QML 浮层与弹窗规则（强制）
- **Toast/通知根节点必须用 `Popup`/`Dialog`**，禁止裸 `Item`+`anchors`+`z:9999`（会被 StackView 覆盖，即使 z:9999 也不可见）。
  - 写法：`modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 `background:Item{}`，用 `open()/close()` 控制，配 `enter/exit:Transition`。
  - 诊断：串起 `C++ emit → QML Connections 收到 → toast() 调用 → _present() 执行` 四段链路；全通但不可见必是浮层类型问题。
- **弹窗遮罩**：`modal:true` + 显式 `Overlay.modal: Rectangle { color:"#80000000" }`，**删除 `dim:false`**。
  - 根因：从 LoginDialog 照搬"外部遮罩"策略，但 LoginDialog 用 Main.qml 手绘 `loginOverlay` 且为避让虚拟键盘才 `modal:false`，其他弹窗无此约束，勿照搬。
  - LoginDialog 例外：保留 `modal:false`+外部遮罩，勿动。已修复：CategoryCorrectionDialog、SystemInfoDialog。

## 雪花 ID 类型安全
- 字段（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 `qint64`/`QString`，禁止 `toInt()`。
- `AuthService` 的 custId/devId 已改 `qint64`（2026-07-05）。详见 `.codebuddy/skills/id-type-safety/SKILL.md`。

## 版本号系统
- 主版本号：`CMakeLists.txt` 的 `project(SmartScale VERSION x.y.z)`。
- 构建号：`cmake -DBUILD_NUMBER=N`（默认 9）；编译日期自动取当天。
- 经 `src/version.h.in` 由 `configure_file` 生成 `build/generated/version.h`；`SystemInfoService` 暴露 `appVersion` 给 QML，`StatusBar.qml` 动态显示。

## Token 无感刷新协调器
- `AuthService` 内置全局锁 `m_isRefreshing` + 信号 `tokenRefreshCompleted(bool,QString)`，所有 Service 经此重发排队请求。
- 关键接口：`requestTokenRefresh()`、`isRefreshingToken()`、静态 `isUnauthorizedError(QNetworkReply*)`（检测 401/403）。
- 已接入：WeightHistoryService、UserIngredientService、CategoryService、CameraController（预检+401拦截+排队重发）。
- 防竞态：每 Service `m_refreshing` + 全局 `m_isRefreshing` 双层锁；`m_refreshFailCount` 超 2 次建议重登。

## 网络请求约定（NetworkUtils）
- 位置 `src/core/NetworkUtils.h|.cpp`。域名：`API_BASE_URL="https://api.shxgs.cn:5196"`（ems 域）、`USER_BASE_URL="https://user.shxgs.cn:5196"`（user 域）。
- EMS 域 `createApiRequest(apiPath,token)`；USER 域 `createUserApiRequest(apiPath,token)`；自定义 query 用 `createApiRequest(baseUrl,apiPath,token)`。
- 统一：`Content-Type:application/json` + `Bearer` token + SSL VerifyNone + 强制 HTTP/1.1。
- 本地缓存目录统一 `~/.cache/smartscale/`（如 `ingredients.json`、`ingr_categories.json`）。

## 网络管理服务（NetworkManagerService）
- 位置 `src/services/NetworkManagerService.h|.cpp`，QML 名 `App.Backend::NetworkManager`。统一管理 Wi-Fi/4G（nmcli + mmcli）。
- Wi-Fi：扫描/连接断开/状态/信号/IP；4G：开关移动数据/运营商/信号/漫游。
- `checkPermissions()` 校验 nmcli 权限；每 10 秒轮询状态经 Q_PROPERTY 同步。入口：SettingsPage「网络控制」+ 状态栏 WiFi 弹窗。
- **nmcli 踩坑**：
  - `nmcli device show` 合法字段 GENERAL.* 等，**不含** WIFI.SIGNAL/CONNECTIONS.WIFI-SSID（会导致 exitCode=2）。查状态用 `GENERAL.STATE,GENERAL.CONNECTION,IP4.ADDRESS`。
  - `GENERAL.CONNECTION` 是 profile 名（可能截断中文），用 `nmcli -t -f 802-11-wireless.ssid connection show <conn>` 反查真实 SSID。
  - `-t` 输出 `field.name:value`，取首冒号后、只取首行。
  - WiFi 设备名先 `nmcli -t -f DEVICE,TYPE device` 动态发现（不一定是 wlan0）。
  - 两步连接：`connection add`(wifi-sec.key-mgmt wpa-psk) → `connection up <name>`。
  - 扫描需 polkit 放行 `org.freedesktop.NetworkManager.wifi.scan`。
  - Qt 资源：`qt_add_resources PREFIX "/" FILES resources/icon/x.png` → `qrc:/resources/icon/x.png`。

## QML 工程规范
- **跨目录引用**：pages/ 下文件引用 components/ 组件必须 `import "../components"`（Main.qml 用 `import "components"`），否则类型解析失败白屏。WorkstationPage 因文件路径加载脱离模块上下文，靠同目录可见性才可用同级 Dialog。
- **Singleton**：
  - 纯 QML（如 Theme.qml）：`pragma Singleton` + CMake `set_source_files_properties(... QT_QML_SINGLETON_TYPE TRUE)`（须在 `qt_add_qml_module` 前）+ 加入 QML_FILES。验证看 `build/<URI>/qmldir` 是否以 `singleton` 开头。
  - C++（SystemInfo/WeightManager）：`qmlRegisterSingletonInstance("App.Backend",1,0,"XXX",ptr)`。
  - 两套模块并存：UI 主题用 `SmartScale`，业务服务用 `App.Backend`。
- **主题常量**：`src/ui/Theme.qml` 集中字体/字号/颜色，新增一律走 Theme 引用，禁止硬编码。
- **图片圆角（Qt6 关键坑）**：`Rectangle.clip:true` 只裁矩形包围盒，**不跟随 `radius`**，所以 `Rectangle{radius;clip:true;Image{anchors.fill:parent}}` 的图片四角仍是直角。正确做法用 `MultiEffect` mask：源 `Image{visible:false}` + 遮罩 `Rectangle{id:mask;radius;color:"#FFFFFF";visible:false;layer.enabled:true}` + 显示项 `MultiEffect{source:img;maskEnabled:true;maskSource:mask;anchors.fill:img}`（需 `import QtQuick.Effects`）。mask 用 alpha 通道，须 `layer.enabled:true` 才渲染成纹理。若配合 hover 缩放，把 `scale` 放外层容器（整瓦缩放），勿放被 clip 的 Image 上（会切出直角）。
- **MultiEffect 阴影标准参数**：`shadowColor:"#002A75"`, `shadowOpacity:0.1`, `shadowBlur:1.0`, `shadowHorizontalOffset:0`, `shadowVerticalOffset:0`。
- **全局字体（方案一已实施）**：主字体族统一为 `PingFang SC`。`main.cpp` 经 `QFontDatabase::addApplicationFontFromData` 注册内嵌 `resources/fonts/PingFangSC-Regular.ttf`（打包进 Qt 资源 `:/resources/fonts/...`），并 `app.setFont(QFont("PingFang SC"))` 兜底全局未显式设 family 的 QML 文本；`Theme.qml` 的 `fontFamilyUi`/`fontFamilyTitle` 已改为 `PingFang SC`。
  - 边界：`setFont` 只覆盖未写 `font.family` 的 QML 文本；已硬编码 `font.family`（如 `Monospace`、旧 `Microsoft YaHei`）需方案二/三清理才生效。
  - 仅用 Regular 一个字重；若需 Light/Medium/Semibold 做层级，往 `resources/fonts/` 加对应文件 + CMake `FILES` + `main.cpp` 多读几个文件即可，零成本。
  - 授权提醒：PingFang SC 为 Apple 专有字体，Linux 不可合法分发；若分发受限改用思源黑体/Noto Sans CJK SC（代码不变，只换文件名）。

## 项目关键文件索引
- 登录：`src/services/AuthService.h/.cpp` + `src/ui/pages/LoginPage.qml` + `src/ui/components/LoginDialog.qml`，退出确认 `LogoutConfirmDialog.qml`。
- Modbus 串口：`src/hardware/WeightSensorWorker.h/.cpp`（poll/doTare/doCalibrate/doReadSN），QMutexLocker RAII + 连续 5 次错误自动重启。
- ONNX Runtime：`3rdparty/onnxruntime-linux-aarch64-1.24.4/lib/`（libonnxruntime.so 等 3 文件）。

## 虚拟键盘（VirtualKeyboard）
- Qt6 官方 `QtQuick.VirtualKeyboard`。
- Debian 13 默认无 Pinyin 插件，已自编译 v6.8.2 部署到 `/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Pinyin/`（libqtvkbpinyinplugin.so+qmldir+plugins.qmltypes），父级 Plugins/qmldir 已加 Pinyin import，dict 已 rcc 内嵌。
- 自编译：`git clone --depth 1 --branch v6.8.2 https://code.qt.io/qt/qtvirtualkeyboard.git` → 装 `qt6-base-private-dev` → `/usr/lib/qt6/bin/qt-cmake <src> -G Ninja -DCMAKE_BUILD_TYPE=Release` → `ninja -j1 qtvkbpinyinplugin`（主板 2GB 用 -j1）→ 拷贝 3 产物 + 父级 qmldir 加 import。
- 核心在 `src/ui/Main.qml`：导入、`Component.onCompleted` 设 `locale="zh_CN"`、`InputPanel` 实例、右上角"中/EN"按钮 `toggleInputMode()`。`InputPanel.active` 驱动底部避让（各 Dialog 用 `inputPanel.active ? inputPanel.height+20 : 0`）。
- **API 速查（Qt 6.8.2）**：`VirtualKeyboardSettings.locale`(rw)、`activeLocales`(rw，没拼音引擎时设了列表为空)、`availableLocales`(只读)、`visibleFunctionKeys`(rw，枚举 None=0/Hide=1/Language=2/All=3)。**不存在** `languageFilterFunc`。
- **环境变量**（main.cpp）：只需 `QT_IM_MODULE=qtvirtualkeyboard` + `QT_VIRTUALKEYBOARD_STYLE=default`。勿设 `QT_VIRTUALKEYBOARD_LAYOUTS`(值是布局名非 locale)、`QT_VIRTUALKEYBOARD_LANGUAGE_FILTER`(非标准)。
- 验证拼音引擎：`nm -D libqtvkbpinyinplugin.so | grep -i pinyin`（勿用 strings）。
