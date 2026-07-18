# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档，不另起条目。

## 编译约束（强制）
- **禁止 AI 自行执行 `make` / `cmake --build`**。目标主板资源有限，并行编译会宕机。
- 用户用 `make -j1` 手动编译。AI 改完用 `read_lints` 验证语法即可，不要触发构建；需验证时告知用户自跑 `make -j1`。

## 触摸屏环境（强制）
- 目标设备无鼠标光标。`main.cpp` 中 `QGuiApplication` 创建后立即 `setOverrideCursor(Qt::BlankCursor)`。
- QML 所有 `MouseArea` 禁止写 `cursorShape`。清理进行中：CategoryCorrectionDialog 已清；WorkstationPage/AddIngredientDialog/AlertDialog/SettingsDialog/WeightRecordSearchDialog/WifiListDialog/SettingsPage 仍有残留，遇相关改动时顺手清理。
- **弹窗输入框禁止自动聚焦**（强制）：Dialog/Popup 内 `TextField`/`TextInput` 必须 `focus:false`，且 `onOpened` 末尾用 `Qt.callLater(function(){ someCloseBtnMouseArea.forceActiveFocus() })` 把焦点移到关闭/返回按钮 MouseArea，防虚拟键盘自动弹出。LoginDialog/WifiPasswordDialog 例外（打开即为输入）。

## QML 浮层与弹窗规则（强制）
- **Toast/通知根节点必须用 `Popup`/`Dialog`**，禁止裸 `Item`+`anchors`+`z:9999`（会被 StackView 覆盖）。写法：`modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 `background:Item{}`，用 `open()/close()` 控制，配 `enter/exit:Transition`。
- **弹窗遮罩**：`modal:true` + 显式 `Overlay.modal: Rectangle{color:"#80000000"}`，**删除 `dim:false`**。LoginDialog 例外保留 `modal:false`+外部遮罩勿动。
- **CategoryCorrectionDialog 外部遮罩必须 reparent 到 `window.contentItem`**（`anchors.fill:parent`+`z:40`），否则盖不到顶部 StatusBar/底部 BottomStatusBar。该弹窗不可改 `modal:true`（Qt modal 层 z 高于 InputPanel(99) 会遮键盘）。`window`（Main.qml ApplicationWindow id）跨文件可见。

## 雪花 ID 类型安全
- 字段（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 `qint64`/`QString`，禁止 `toInt()`。详见 `.codebuddy/skills/id-type-safety/SKILL.md`。

## 版本号系统
- 主版本号：`CMakeLists.txt` 的 `project(SmartScale VERSION x.y.z)`。构建号：`cmake -DBUILD_NUMBER=N`（默认9）。经 `src/version.h.in` → `configure_file` → `SystemInfoService` 暴露 `appVersion`。

## Token 无感刷新协调器
- `AuthService` 内置全局锁 `m_isRefreshing`+信号 `tokenRefreshCompleted(bool,QString)`。接口：`requestTokenRefresh()`、`isRefreshingToken()`、静态 `isUnauthorizedError(QNetworkReply*)`（检测 401/403）。防竞态：每 Service `m_refreshing`+全局 `m_isRefreshing` 双层锁；`m_refreshFailCount` 超 2 次建议重登。已接入 WeightHistoryService/UserIngredientService/CategoryService/CameraController。

## 网络请求约定（NetworkUtils）
- 位置 `src/core/NetworkUtils.h|.cpp`。域名：`API_BASE_URL="https://api.shxgs.cn:5196"`（ems 域）、`USER_BASE_URL="https://user.shxgs.cn:5196"`（user 域）。
- EMS 域 `createApiRequest(apiPath,token)`；USER 域 `createUserApiRequest(apiPath,token)`。统一 `Content-Type:application/json`+`Bearer` token+SSL VerifyNone+HTTP/1.1。本地缓存 `~/.cache/smartscale/`。

## 网络管理服务（NetworkManagerService）
- 位置 `src/services/NetworkManagerService.h|.cpp`，QML 名 `App.Backend::NetworkManager`。nmcli(Wi-Fi) + mmcli(4G)。每 10 秒轮询状态。入口：SettingsPage「网络控制」+状态栏 WiFi 弹窗。
- **nmcli 踩坑**：`device show` 只认 `GENERAL.*`（不含 WIFI.SIGNAL 等）；`GENERAL.CONNECTION` 是 profile 名需 `nmcli -t -f 802-11-wireless.ssid connection show <conn>` 反查；`-t` 输出取首冒号后首行；设备名动态发现；两步连接 `connection add`→`connection up`；扫描需 polkit 放行。Qt 资源 `qrc:/resources/icon/x.png`。

## QML 工程规范
- **跨目录引用**：pages/ 引用 components/ 必须 `import "../components"`。
- **Singleton**：纯 QML（Theme）`pragma Singleton`+CMake `set_source_files_properties(... QT_QML_SINGLETON_TYPE TRUE)`（`qt_add_qml_module` 前）；C++ 用 `qmlRegisterSingletonInstance("App.Backend",1,0,"XXX",ptr)`。
- **AppSettingsService**（`src/services/AppSettingsService.h/.cpp`）：C++ 单例 QML 名 `AppSettings`，`Q_PROPERTY bool priceInputEnabled`（默认 false）+QSettings INI 持久化。项目启用 `QT_NO_KEYWORDS`，信号 `Q_SIGNALS:`/发射 `Q_EMIT`。
- **价格输入单位（元/kg）**：链路统一元/kg——QML `currentUnitPrice`/`pendingUnitPrice`、DB `WeightRecord.unitPrice`、上传 json["price"]、表格。公式 `amount = unitPrice * netWeight(kg)`，**不要**做元/斤换算。`WeightHistoryService.addRecord(...,unitPrice)` 接收元/kg，内部 `qRound(price*100)/100` 存 DB+上传。
- **两套模块**：UI 主题 `SmartScale`，业务服务 `App.Backend`。
- **主题常量**：`src/ui/Theme.qml` 集中字体/字号/颜色，禁止硬编码。
- **图片圆角（Qt6 坑）**：`Rectangle.clip:true` 不跟随 radius，图片四角仍直角。用 `MultiEffect` mask：源 `Image{visible:false}`+遮罩 `Rectangle{id:mask;radius;color:"#FFFFFF";visible:false;layer.enabled:true}`+`MultiEffect{source:img;maskEnabled:true;maskSource:mask}`（需 `import QtQuick.Effects`）。hover 缩放放外层容器勿放被 clip 的 Image。
- **MultiEffect 阴影标准参数**：`shadowColor:"#002A75"`, `shadowOpacity:0.1`, `shadowBlur:1.0`, offset:0。
- **错误提示脱敏（强制）**：`window.alert()`（Main.qml）内置智能脱敏——URL 替换为 `<接口地址>`；含技术错误特征（`Error transferring`/`server replied`/`HTTP `/`SSL`/`网络请求失败`/`JSON 解析失败` 等）且未传 detail，自动移入 detail（默认收起），message 改 `title+"，请稍后重试"`。业务友好提示原样保留。C++ 层 emit 错误消息禁止含技术细节（走 `qWarning` 日志）。LoginDialog/LoginPage 有 `sanitizeLoginError(msg)` QML 兜底。
- **全局字体**：主字体族 `PingFang SC`。`main.cpp` 经 `addApplicationFontFromData` 注册内嵌 `resources/fonts/PingFangSC-Regular.ttf`，`app.setFont(QFont("PingFang SC"))` 兜底；`Theme.qml` fontFamilyUi/Title 已改 PingFang SC。`setFont` 只覆盖未写 `font.family` 的文本。仅 Regular 一个字重。授权：Apple 专有字体，分发受限改思源黑体/Noto Sans CJK SC。

## 保存流程（addRecord 乐观完成）
- `WeightHistoryService.addRecord`：DB 写入后立即 `uploadSingleRecord(model,true)` 异步上传，**立即 `Q_EMIT cloudSyncSuccess(newId)`**（关 overlay，用户感知完成），不等网络。`onCloudReply` 成功：fromAddRecord 不重复 emit（只静默更新 DB synced）。
- QML `onCloudSyncSuccess`（本地保存完成点）：关 overlay + `VoiceSpeaker.speak("已保存")` + `saveSuccessDialog.openDialog()`（"已保存，将上传至服务器"，3秒倒计时自动消失）。`onCloudSyncFailed`：`window.toast("记录已保存，云端同步失败将自动重试","warning",3000)`。
- **SaveSuccessDialog.qml**（`src/ui/components/`）：modal Dialog 460×380 居中白卡+绿勾 OutBack 入场+文案+"确认 (Ns)"按钮（N 从3递减，3秒后自动关，可手动立即关）。

## 项目关键文件索引
- 登录：`src/services/AuthService.h/.cpp`+`src/ui/pages/LoginPage.qml`+`src/ui/components/LoginDialog.qml`，退出 `LogoutConfirmDialog.qml`。
- Modbus 串口：`src/hardware/WeightSensorWorker.h/.cpp`（QMutexLocker RAII+连续5次错误重启）。
- 语音：`src/hardware/VoiceSpeaker.h/.cpp`（piper TTS，QML 名 `VoiceSpeaker`），`warmup()` 在 `Main.qml` 开机预加载模型。
- ONNX Runtime：`3rdparty/onnxruntime-linux-aarch64-1.24.4/lib/`。

## 虚拟键盘（VirtualKeyboard）
- Qt6 官方 `QtQuick.VirtualKeyboard`。核心在 `src/ui/Main.qml`：`locale="zh_CN"`+`InputPanel`+右上"中/EN"按钮。
- Debian 13 自编译 v6.8.2 Pinyin 插件部署到 `/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Pinyin/`。
- 环境变量（main.cpp）：`QT_IM_MODULE=qtvirtualkeyboard`+`QT_VIRTUALKEYBOARD_STYLE=retro`（**retro=浅色明亮风格**，default=深色暗黑）。`Main.qml` 的 `keyboardContainer` 背景须与键盘一致：retro 用 `#E8E8E8`。勿设 `QT_VIRTUALKEYBOARD_LAYOUTS`/`QT_VIRTUALKEYBOARD_LANGUAGE_FILTER`（非标准）。
- 样式可选值（Qt6 内置仅2个）：`default`（深灰硬编码背景）、`retro`（浅色金黄装饰复古风）。如需纯白现代风须自定义 `KeyboardStyle.qml`（60+ 属性，放 qrc `/qt-project.org/imports/QtQuick/VirtualKeyboard/Styles/<name>/`，集成风险高）。
- API（Qt 6.8.2）：`locale`(rw)/`activeLocales`(rw)/`availableLocales`(ro)/`visibleFunctionKeys`(rw，None=0/Hide=1/Language=2/All=3)。**不存在** `languageFilterFunc`。验证引擎 `nm -D libqtvkbpinyinplugin.so | grep -i pinyin`。
