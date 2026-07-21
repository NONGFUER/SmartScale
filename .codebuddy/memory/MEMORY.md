# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档，不另起条目。

## 编译约束（强制）
- **禁止 AI 自行执行 `make`/`cmake --build`**（目标板资源有限，并行编译会宕机）。用户自跑 `make -j1`；AI 改完用 `read_lints` 验证语法即可。

## 触摸屏环境（强制）
- 无鼠标光标：`main.cpp` 创建 QGuiApplication 后立即 `setOverrideCursor(Qt::BlankCursor)`；QML 所有 MouseArea 禁止 `cursorShape`。
- **弹窗输入框禁止自动聚焦**：Dialog/Popup 内 TextField/TextInput 必须 `focus:false`，`onOpened` 末尾 `Qt.callLater(function(){ closeBtnMouseArea.forceActiveFocus() })` 把焦点移到关闭/返回按钮 MouseArea。LoginDialog/WifiPasswordDialog 例外（打开即为输入）。

## QML 浮层与弹窗规则（强制）
- Toast/通知根节点必须用 Popup/Dialog（禁裸 Item+z:9999）：`modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 background，open()/close() 控制，配 enter/exit Transition。
- 弹窗遮罩：`modal:true`+显式 `Overlay.modal: Rectangle{color:"#80000000"}`，删 `dim:false`。LoginDialog 例外（保留 modal:false+外部遮罩）。
- CategoryCorrectionDialog 外部遮罩必须 reparent 到 `window.contentItem`（anchors.fill+z:40），否则盖不住 StatusBar；该弹窗不可改 modal:true（modal 层 z 高于 InputPanel(99) 会遮键盘）。

## 弹窗返回按钮标准样式
- back2.png + "返回"文字圆角胶囊：116×44, radius:22，图标 22×22，文字 24px bold `#4649E5`，hover `#F1F5F9`。标题用 `anchors.centerIn` 绝对居中，避免被返回按钮挤压。参考 WifiPasswordDialog/AlertDialog/SettingsDialog/CategoryCorrectionDialog。

## 雪花 ID 类型安全
- ingrId/emsId/cateId/recoId/userId/productId/custId/devId 一律 qint64/QString，禁止 toInt()。详见 `.codebuddy/skills/id-type-safety/SKILL.md`。

## 版本号系统
- 主版本号：CMakeLists.txt `project(SmartScale VERSION x.y.z)`；构建号 `cmake -DBUILD_NUMBER=N`（默认9）；version.h.in → configure_file → SystemInfoService 暴露 appVersion。

## Token 无感刷新协调器
- AuthService 全局锁 m_isRefreshing+信号 tokenRefreshCompleted(bool,QString)；接口 requestTokenRefresh()/isRefreshingToken()/isUnauthorizedError()（401/403）。每 Service m_refreshing+全局双层锁；失败>2次建议重登。已接入 WeightHistory/UserIngredient/Category/CameraController。

## 网络请求（NetworkUtils，src/core/）
- API_BASE_URL=https://api.shxgs.cn:5196（ems 域），USER_BASE_URL=https://user.shxgs.cn:5196（user 域）。createApiRequest/createUserApiRequest(apiPath,token)：json+Bearer+SSL VerifyNone+HTTP/1.1。缓存 ~/.cache/smartscale/。

## NetworkManagerService
- src/services/，QML 名 App.Backend::NetworkManager。nmcli(Wi-Fi)+mmcli(4G)，10秒轮询。nmcli 坑：device show 只认 GENERAL.*；GENERAL.CONNECTION 是 profile 名需 connection show 反查 ssid；-t 输出取首冒号后首行；两步连接 connection add→up；扫描需 polkit 放行。**四模式网络控制**：新增 NetworkMode 枚举(WifiOnly/CellularOnly/AllWifiPriority/AllCellularPriority) + Q_INVOKABLE setNetworkMode(mode) + networkMode 属性(int,-1未知)。**SettingsDialog.qml（标题「设备信息」的弹窗）** 的「功能设置」卡片内新增「网络模式」区：WIFI/4G 状态显示 + 四个 ToggleSwitch 开关行（与「价格输入」同款样式，互斥单选：仅开启WIFI/仅开启4G/全开优先WIFI/全开优先4G），**必选其一+默认+持久化**：四个开关用 JS 显式 `syncSwitches()` 同步 `checked`（用户点击会打断 QML 绑定，故不能绑 checked，否则会出现全不选/多选）；`setNetMode` 写 `AppSettings.networkMode` 持久化并调 `NetworkManager.setNetworkMode`。`netMode` 初值与 `refreshNetMode` 兜底均为 **AllCellularPriority（用户指定默认）**；`refreshNetMode` 优先级 NetworkManager.networkMode > AppSettings.networkMode > 实时状态推导。`onOpened` 时若 `AppSettings.networkMode<0`（首次）直接 `setNetMode(AllCellularPriority)` 把设备设为默认并记忆。**重启记忆**：`AppSettings` 新增 `networkMode` 属性（QSettings INI，默认-1）；`main.cpp` 开机延迟5s 调 `networkManagerService->setNetworkMode(savedMode)` 恢复（旧 cellularEnabled 记忆仅在 networkMode<0 时生效，避免冲突）。**注意：之前误改到 SystemInfoDialog（「系统调试信息」弹窗），已撤销。** 全开模式用路由 metric 实现优先级（findActiveWifiConnection/findCellularConnection 取连接名→setConnectionRouteMetric 设 ipv4/ipv6.route-metric：优先=10/非优先=300→reactivateConnection 重新激活优先连接使低 metric 默认路由生效），延迟 8s 应用等两接口起来；metric 配置持久化。

## QML 工程规范
- 跨目录：pages/ 引 components/ 必须 `import "../components"`。
- Singleton：纯 QML 用 `pragma Singleton`+CMake `QT_QML_SINGLETON_TYPE`（qt_add_qml_module 前）；C++ 用 qmlRegisterSingletonInstance。
- AppSettingsService（QML 名 AppSettings）：priceInputEnabled（默认 false）等，QSettings INI 持久化。项目启用 QT_NO_KEYWORDS（用 Q_SIGNALS/Q_EMIT）。
- **价格单位统一元/kg**：amount = unitPrice × netWeight(kg)，不做元/斤换算；addRecord 内部 qRound(price*100)/100。
- 两套模块：UI 主题 SmartScale，业务服务 App.Backend。主题常量集中 src/ui/Theme.qml，禁硬编码。
- 图片圆角（Qt6 坑）：clip 不随 radius，用 MultiEffect mask（maskEnabled+maskSource，需 import QtQuick.Effects）。
- MultiEffect 阴影标准：shadowColor "#002A75"/shadowOpacity 0.1/shadowBlur 1.0/offset 0。
- **错误提示脱敏（强制）**：window.alert() 内置智能脱敏（URL→`<接口地址>`，技术错误特征自动移入 detail 收起）。C++ emit 错误禁含技术细节（走 qWarning）。LoginDialog/LoginPage 有 sanitizeLoginError QML 兜底。
- 全局字体 PingFang SC（仅 Regular 字重，粗体靠 Qt 合成）：main.cpp addApplicationFontFromData 注册内嵌 ttf + setFont 兜底。授权受限，分发可改 Noto Sans CJK SC。

## 保存流程（addRecord 乐观完成）
- WeightHistoryService.addRecord：DB 写入即 uploadSingleRecord(model,true) 异步上传，**立即 emit cloudSyncSuccess(newId)** 关 overlay。onCloudReply fromAddRecord 不重复 emit。
- QML onCloudSyncSuccess：关 overlay+VoiceSpeaker.speak("已保存")+SaveSuccessDialog.openDialog()（460×380 绿勾白卡，"确认 (Ns)" 3秒倒计时自动关）。onCloudSyncFailed：toast warning "记录已保存，云端同步失败将自动重试"。

## 关键文件索引
- 登录：AuthService.h/.cpp + LoginPage.qml + LoginDialog.qml + LogoutConfirmDialog.qml。快捷登录历史 ~/.cache/smartscale/login_history.json（userCode/userNm/custNm **+ 记住的密码 base64**）随登录成功写入。**快捷登录流程**：onOpened 时默认选中最近登录账号（historyCombo.currentIndex=0，免手动点击）；下拉与弹窗项显示**完整账号名，不脱敏**；输入密码登录成功后在 onLoginSuccess 调 rememberHistoryPassword 记住密码 → 之后打开弹窗若默认选中的最近账号 hasRememberedPassword 为真则直接 loginByHistory 自动登录。hasRememberedPassword/loginByHistory/rememberHistoryPassword 为在用方法；firstRememberedHistoryIndex 已不再被 QML 调用（保留为通用辅助）。"记住登录"复选框（单账号 last_login.conf）仍独立保留（账号登录页半自动：预填账号，按登录即 autoLogin）。
- Modbus 串口：src/hardware/WeightSensorWorker.h/.cpp（QMutexLocker RAII+连续5次错误重启）。
- 语音：src/hardware/VoiceSpeaker（piper TTS，QML 名 VoiceSpeaker），Main.qml 开机 warmup()。
- ONNX Runtime：3rdparty/onnxruntime-linux-aarch64-1.24.4/lib/。

## 虚拟键盘（VirtualKeyboard）
- Qt6 官方 QtQuick.VirtualKeyboard：Main.qml locale="zh_CN"+InputPanel。中英切换用键盘自带 ChangeLanguageKey（light 样式按 InputContext.locale 动态显示"中文"/"英文"）；右上角浮动切换按钮已删。
- 环境变量（main.cpp）：QT_IM_MODULE=qtvirtualkeyboard+QT_VIRTUALKEYBOARD_STYLE=light（自定义白底黑字）。勿设 QT_VIRTUALKEYBOARD_LAYOUTS/LANGUAGE_FILTER。keyboardContainer 背景与键盘一致 **#E9EEF4**（2026-07-19 由纯白改浅灰蓝，衬托白色键帽）。
- **键盘视觉标准（2026-07-20 字号加大）**：键帽白底 + 边框 #CBD5E1（激活态 #60A5FA）宽 `Math.max(2, Math.round(3.5*scaleHint))`；键帽字号统一 `80*scaleHint`（≈视觉37px，字符预览 100、长按备选 68）；回车键 #2563EB（按下 #1D4ED8）。边框/底色全局统一勿单独改。
- **两侧空白折叠（2026-07-19）**：keyboardContainer 不再全宽，`anchors.horizontalCenter` 居中 + `width: inputPanel.width*inputPanel.scale`（1920×0.62=1190）；InputPanel 改 `width: window.width` + `x:(parent.width-width)/2` 居中，保持全宽布局仅靠 scale 缩放，视觉区恰好填满收窄容器。
- 自定义 light 样式：源 src/ui/vkbdstyle/light/style.qml，经 app.qrc alias 嵌入，并拷贝到系统 /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Styles/light/style.qml（系统路径免重编译即生效）。
- **Qt6.8 样式查找（关键）**：搜索 Styles/<风格名>/**style.qml**（入口文件名必须 style.qml，找不到警告 fallback default 暗黑）；样式目录不放 qmldir；**样式编译失败→keyboard.style=null 键盘整体消失**（不是回退！改完必须看日志确认）。
- **KeyboardStyle 约束（QtObject）**：keyboardDesignWidth/Height 默认 0 必须显式设（2560×800，否则 scaleHint=NaN 全毁）；selectionListHeight/alternateKeysListItemWidth/Height 也要设；SelectionListItem 是裸 Item（Text 直接放，display 上下文属性，高亮用 ListView.isCurrentItem State）。参考 github qtvirtualkeyboard v6.8.2 default/style.qml。
- **KeyPanel control 属性**：key/text/displayText/smallText/smallTextVisible/alternativeKeys/enabled/pressed/uppercased/highlighted/functionKey。无 control.mode；Shift 激活态用 control.uppercased；Shift/语言键 displayText 为空，须 Canvas 画图标。
- 键盘大小：Main.qml InputPanel.scale（现 0.62）。
- **键盘悬浮覆盖模式（2026-07-20，替代旧避让方案）**：键盘像手机一样直接浮在最上层，主布局与所有弹窗一律 `y:(parent.height-height)/2` 纯居中、**不做任何键盘避让**；mainLayout `anchors.bottom: parent.bottom` 固定。已统一：Main.qml（mainLayout/Login/SystemInfo/WifiList/WifiPassword/Cellular）+ SaveConfirm/AddIngredient/WeightRecordSearch/CategoryCorrection 四弹窗。旧的 `inputPanel.active?...` 避让公式已全部删除，勿再加回。
- **键盘必须在 Overlay 层（2026-07-20 关键修复）**：Qt 的 Dialog/Popup 渲染在窗口 Overlay 层，普通 item 设多大 z 都压不过（z:99 无效，弹窗会盖住键盘）。keyboardContainer 必须 `parent: Overlay.overlay` + `z: 99999` 才能浮在所有弹窗之上。
- Pinyin 插件：Debian 13 自编译 v6.8.2 部署到系统 QtQuick/VirtualKeyboard/Plugins/Pinyin/。

## 资源编译（rcc OOM 防护）
- CMakeLists.txt 用 qt_add_big_resources（**旧式 API**：首参是输出变量，不支持 PREFIX/FILES）：手写 app.qrc → `qt_add_big_resources(RCC_SOURCES app.qrc)` → `target_sources(appSmartScale PRIVATE ${RCC_SOURCES})`。
- 新增图片必须编辑 app.qrc 加 `<file>` 行；无 qrc:/ 引用的文件（lock.png/shuiyin.png/history*.png/camera.png/opr.png）不要加。改资源后清 build 重新 `cmake ..`+`make -j1`。大图(>100K)尽量压缩。
