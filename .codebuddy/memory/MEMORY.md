# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档。

## 编译与资源
- 禁止 AI 自行执行 `make`/`cmake --build`；用户自跑 `make -j1`，AI 改完用 `read_lints` 验证语法。
- 资源：`qt_add_big_resources(RCC_SOURCES app.qrc)` → `target_sources`；新增图片必须编辑 `app.qrc`；改资源后清 build 重新 `cmake ..`+`make -j1`。
- 版本号：CMakeLists.txt `project(SmartScale VERSION x.y.z)`，构建号 `cmake -DBUILD_NUMBER=N`（默认9），`version.h.in` → `configure_file` → SystemInfoService.appVersion / buildNumber。

## 运行环境
- 无鼠标光标：main.cpp 创建 QGuiApplication 后 `setOverrideCursor(Qt::BlankCursor)`；QML MouseArea 禁止 `cursorShape`。
- 弹窗输入框禁止自动聚焦（LoginDialog/WifiPasswordDialog 例外）：TextField `focus:false`，`onOpened` 末尾 `Qt.callLater` 移焦点到关闭/返回按钮。

## 认证与密码存储
- 云端账号（AuthService）：记住登录存 `~/.config/SmartScale/last_login.conf`，历史存 `~/.cache/smartscale/login_history.json`，password 仅 base64（=明文，有泄露风险，建议改不持久化或 AES）。token/refreshToken/userId/devId 仅存内存，重启靠 last_login.conf 自动重登；用户信息经 USER_BY_ID 拉取缓存 `~/.cache/smartscale/product.json`。
- 本地离线账号：SQLite `data/smartscale.db` `users` 表，SHA256 哈希，`UserRepo::verifyPassword` 校验。

## 弹窗与浮层
- Toast/通知：Popup/Dialog 根 + `modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 background。
- 弹窗遮罩：`modal:true`+显式 `Overlay.modal: Rectangle{color:"#80000000"}`（LoginDialog 例外 modal:false+外部遮罩）。
- CategoryCorrectionDialog 外部遮罩 reparent 到 `window.contentItem`（anchors.fill+z:40），不可改 modal:true（会遮 InputPanel）。
- 返回按钮标准：back2.png+"返回" 胶囊 116×44 radius:22，图标 22×22，文字 24px bold `#4649E5`；标题 `anchors.centerIn` 居中。

## 数据与类型
- 雪花 ID（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 qint64/QString，禁止 `toInt()`。
- 价格单位元/kg：`amount = unitPrice × netWeight(kg)`，`addRecord` 内 `qRound(price*100)/100`。

## 网络
- API 域：`API_BASE_URL=https://api.shxgs.cn:5196`，`USER_BASE_URL=https://user.shxgs.cn:5196`；`NetworkUtils::createApiRequest/createUserApiRequest` 统一 json+Bearer+SSL VerifyNone+HTTP/1.1。**注意：VerifyNone 仅跳过证书验证，自签名/私有CA仍会触发 `sslErrors`；所有调用点必须 connect `reply->sslErrors` 并 `ignoreSslErrors()`，否则握手静默中止表现为"请求无回应"。UpdateService/OtaService 已接。** 另外 Qt6 网络错误信号是 `errorOccurred`（非 Qt5 的 `error`），诊断可连它早报。
- **请求传输超时（2026-08-22 修复登录转圈）**：`NetworkUtils::createApiRequest`/`createMultipartApiRequest` 已统一 `request.setTransferTimeout(15000)`（15s）。修复登录/刷新等请求在网络不可达（DNS 卡住/TCP 黑洞/握手无响应）时永久挂起、UI 一直转圈的问题。超时后 reply 触发 finished+TimeoutError，AuthService::onNetworkReply 走网络错误分支 emit loginFailed，LoginDialog 脱敏为"网络连接失败，请稍后重试"并关闭遮罩。新增网络调用若不走 NetworkUtils，需自行加超时。
- `NetworkManagerService`（QML `App.Backend::NetworkManager`）2026-07-28 原生重构：
  - 检测层零外部进程：WiFi/4G 判定走 `QNetworkInterface`（IsUp+全局 IPv4），WiFi 信号读 `/proc/net/wireless`，3s 轮询；SSID 仅 Connected 且缓存空时 nmcli 反查一次。mmcli/ip a 快速路径/去抖/防回退已全删。
  - 状态语义统一真实状态：`cellularUiActive` 已删，UI 全部以真实 `cellularStatus` 为唯一数据源。
  - 4G 信号源 AT+CSQ：`CellularModemService::State::PollingCsq` 串口常驻 5s 轮询（rssi 0-31→×100/31，99 保持上次）；错误/3 次无响应→信号归零+重试，与联网判定解耦。main.cpp 接线 signalStrengthChanged→`setCellularSignal`、operatorNameChanged→`setCellularOperator`。
  - 控制层：nmcli + sudo ip link set；4G 开关用 `m_cellularEnablePending` 挂起窗口（30s 超时转 Error），命令后 500/1500/3000ms 单发刷新。
  - networkMode 双写者：`setNetworkMode()`（用户）+ `deriveNetworkModeFromState()`（落定态派生，过渡态跳过）。SettingsDialog `netMode` 只读绑定，`setNetMode` 只调 `setNetworkMode()`。
- 网络模式四枚举 `WifiOnly/CellularOnly/AllWifiPriority/AllCellularPriority`，默认 AllCellularPriority，持久化 `AppSettings.networkMode`，开机 5s 后恢复；全开模式 route-metric（优先=10/非优先=300）。
- route-metric 修复已撤回（2026-07-24）：`connection modify` 只改持久化配置不推送内核，重做时需紧跟 `device reapply <iface>`（NM 1.20+）或 down+up；`connection up` 在已 active 时是 no-op。设备 4G=eth1 "有线连接 1"，WiFi=wlan0。
- SettingsDialog 四个 ToggleSwitch 互斥单选，`syncSwitches()` 同步 `checked`；开关用 `onClicked`（禁 `onToggled` 防循环回弹）。
- WiFi 信号显示统一：`StatusBar` 与 `WifiListDialog` 同用 `availableNetworks` 中 `ssid===wifiSsid` 项的 `signal`（`currentWifiSignal()`，找不到回退 `wifiSignal`）。
- 信号格数映射（2026-07-29）：WiFi/4G 共用 `signalLevel()` 4 格均分（0-25%=1格…76-100%=4格），`Signal0`/`Wifi0` 仅未连接时用，有网最低 1 格。QML 中 C++ 枚举比较必须用数值（`s===4`），禁枚举名（int/enum 不匹配）。
- **m_cellularSignal 单一写者**：只能由 `setCellularSignal()`（AT+CSQ）修改，原生刷新绝不可归零，否则 3s 轮询覆盖真实值。

## 核心服务行为
- Token 刷新：`AuthService` 全局锁 `m_isRefreshing`+`tokenRefreshCompleted(bool,QString)`；失败>2次建议重登。已接入 WeightHistory/UserIngredient/Category/CameraController。
- 保存流程：`WeightHistoryService.addRecord` DB 写入即上传并立即 `cloudSyncSuccess(newId)`；失败 toast "记录已保存，云端同步失败将自动重试"。
- **AI 识别反查链路基于 ingrCd（emsCd 已废弃，2026-07-30）**：后端 `/api/user/UserIngr/paged` 已取消 emsCd 字段，AI 返回的 code 即 ingrCd。`UserIngredientService::findByIngrCd`（原 findByEmsCd）按 item["en"]（ingrCd）匹配；m_emsMap 已删除；FoodTranslator 字典仅 ingrCd→ingrNm；getIngrId 无 emsCd 兜底。改动文件：UserIngredientService.h/cpp、FoodTranslator.h/cpp、WorkstationPage.qml、CategoryCorrectionDialog.qml。
- `SystemInfoService` 读 `/proc/meminfo` 暴露 `memTotal`（<3GB 显示 "2GB"，否则 "4GB"）。

## QML 工程规范
- `pages/` 引 `components/` 用 `import "../components"`。
- Singleton：纯 QML `pragma Singleton`+CMake `QT_QML_SINGLETON_TYPE`；C++ `qmlRegisterSingletonInstance`。
- `AppSettings`：QSettings INI，`priceInputEnabled` 默认 false，`networkMode` 默认 -1。
- 主题常量集中 `src/ui/Theme.qml`，禁止硬编码；全局字体 PingFang SC（仅 Regular）main.cpp 内嵌注册。
- 图片圆角用 `MultiEffect` `maskEnabled+maskSource`（Qt6 clip 不随 radius）。
- MultiEffect 阴影标准：`shadowColor "#002A75"`，`shadowOpacity 0.1`，`shadowBlur 1.0`，offset 0。
- 错误提示脱敏：`window.alert()` 脱敏 URL/技术错误；C++ emit 错误禁含技术细节。

## 虚拟键盘
- Qt6 `QtQuick.VirtualKeyboard`，`locale="zh_CN"`；`QT_IM_MODULE=qtvirtualkeyboard`，`QT_VIRTUALKEYBOARD_STYLE=light`。
- 键盘悬浮覆盖：主布局与弹窗 `y:(parent.height-height)/2` 居中不避让；`keyboardContainer.parent: Overlay.overlay`+`z:99999`。
- 自定义 light 样式 `src/ui/vkbdstyle/light/style.qml`（入口文件名必须 style.qml，`keyboardDesignWidth/Height` 显式 2560×800），同时拷贝到系统 Qt 路径免重编译。
- `Main.qml InputPanel.scale=0.62`，背景 `#E9EEF4`。

## 语音
- `VoiceSpeaker`（src/hardware/）：sherpa-onnx C API + Matcha 中文模型，进程内合成 + QThread 后台线程 + aplay 播放；对外接口（speak/stop/warmup/isReady/isSpeaking/信号）不变。`dlopen(RTLD_LOCAL)` 隔离 onnxruntime 符号冲突。
- 食材播报：`CameraController::speakPredictedLabel` 设 `speakText` 为 `！！！<中文名>！！！`（FoodTranslator 翻译后 speak）。
- TTS 语速：`genCfg.speed>0` 时按 `length_scale=1/speed` 覆盖模型配置（speed==0 时模型 length_scale 才生效）。当前 `genCfg.speed=0.898f`，调语速改它即可。
- sherpa-onnx 采样步数：Python/C 绑定未暴露 num_steps（库内写死），要控步数须改 sherpa-onnx 源码或换官方 Matcha 推理。

## OTA 远程升级
- `OtaService`（QML `App.Backend::OtaService`）：状态机 Idle/Checking/HasUpdate/Downloading/Verifying/ReadyToInstall/Installing/Success/Failed/RolledBack；组合复用 `UpdateService`（纯查询，接口勿动）。Q_INVOKABLE：checkUpdate/startDownload/cancelDownload/install/resetState；信号：checkFinished(success,hasUpdate,version)、upgradeResult(success,version,rolledBack)。
- **版本比较用 QVersionNumber（远端 version 去 V 前缀 vs APP_VERSION_FULL），禁止 verCode vs BUILD_NUMBER 直接比**。
- 下载：QNAM 流式写 `data/ota/update.part`+增量 SHA256 对照 `UpdateService.hash`，进度 500ms 节流，Failed 态可重试。**取消下载回 HasUpdate（非 Idle）**——startDownload 守卫仅放行 HasUpdate/Failed，回 Idle 会导致再次下载被静默拒绝。
- 刷写：`scripts/apply_update.sh`（app.qrc 注册，install() 导出 data/ota/ 执行，QProcess::startDetached）。流程：sudo -n 预检→解压→manifest 校验→探测 systemd service（第3参数/env SMARTSCALE_SERVICE 覆盖）→停应用（**须轮询等待进程真正退出，最多15s再 SIGKILL，否则旧进程残留持有 /dev/ttyAMA0 的 flock 锁，新进程报 Permission error while locking the device**）→备份 .bak.<ts>（留2份）→替换→拉起→60s 等进程+30s 稳定观察→result.success / 失败回滚 result.rolledback。退出码 0/1参数包备份/2解压校验/3权限/4拉起失败/5存活失败。
- 首启自检：构造时读 `data/ota/result.*|pending.json`，延迟 3s emit upgradeResult → Main.qml alert 后 resetState()。
- UI：SettingsDialog 版本更新行 + `OtaUpdateDialog.qml`（NoAutoClose，进度条/取消/立即重启安装/重新下载）。
