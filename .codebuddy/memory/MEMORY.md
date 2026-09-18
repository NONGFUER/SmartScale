# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档。条目按主题合并，避免重复。

## 一、编译与资源
- 禁止 AI 自行执行 `make`/`cmake --build`；用户自跑 `make -j1`，AI 改完用 `read_lints` 验证。
- 资源：`qt_add_big_resources(RCC_SOURCES app.qrc)` → `target_sources`；新增图片必须编辑 `app.qrc`；改资源后清 build 重新 `cmake ..`+`make -j1`。
- 版本号：CMakeLists.txt `project(SmartScale VERSION x.y.z)`，构建号 `cmake -DBUILD_NUMBER=N`（默认9），`version.h.in` → `configure_file` → `SystemInfoService.appVersion / buildNumber`；`StatusBar.qml` 绑 `SystemInfo.appVersion`。
- QML 单例：纯 QML 用 `pragma Singleton` + CMake `set_source_files_properties(... QT_QML_SINGLETON_TYPE TRUE)`（如 `src/ui/Theme.qml`、`src/ui/WeightUnit.qml`）；C++ 用 `qmlRegisterSingletonInstance`（见下）。
- **QML 隐式导入只在「文件所在目录」内生效（重要，2026-09-18 踩坑）**：Qt6 隐式导入仅由**同目录**下的 QML 文件名构成，**不会覆盖整个模块**（官方结论见 Qt 博客 *Implicit Imports vs. QML Modules in Qt 6*）。因此 `src/ui/` 下的模块级单例（`Theme`、`WeightUnit`）在 **`pages/` 与 `components/` 子目录的文件里必须显式写 `import SmartScale`**，否则绑定时报 `xxx is not defined`、且**失败是静默的**：
  - 用在 `text:` 里 → 该文字直接空白（当时 WorkstationPage 的历史重量/称重数字/单价标签全部消失）；
  - 用在 `font.family`/`color` 里 → 悄悄回退默认值，肉眼看不出（导致 `DuplicateWeightDialog`、`NumberPadPopup`、`SaveSuccessDialog`、`SaveLoadingOverlay`、`AiResultSelectDialog`、`OtaDownloadConfirmDialog`、`pages/CategoryCorrectionDialog` 长期缺导入未被发现）。
  - 排查口诀：**页面/组件里出现「文字空白但其他都正常」先查 `import SmartScale` 是否漏了。** `SettingsDialog.qml`/`WeightRecordTableDialog.qml`/`WeightRecordSearchDialog.qml` 是正确示范。

## 二、C++ 单例注册（main.cpp ~443行）
- `App.Backend`：WeightManager(WeightSensor)、CameraController、BackendAuth、VisionAI、WeightHistoryService、CategoryService、UserIngredientService、VoiceSpeaker、SystemInfo、AppSettings、NetworkManager、MqttClient、CellularModem、UpdateService、OtaService。
- `SmartScale.Tools`：Translator(FoodTranslator)、PState；`SmartScale.Hwr`：Ppocr。

## 三、运行环境与交互规范
- 无鼠标光标：main.cpp 创建 QGuiApplication 后 `setOverrideCursor(Qt::BlankCursor)`；QML MouseArea 禁止 `cursorShape`。
- 弹窗输入框禁止自动聚焦（LoginDialog/WifiPasswordDialog 例外）：TextField `focus:false`，`onOpened` 末尾 `Qt.callLater` 移焦点到关闭/返回按钮。
- Toast/通知：Popup/Dialog 根 + `modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 background。
- 弹窗遮罩：`modal:true`+显式 `Overlay.modal: Rectangle{color:"#80000000"}`（LoginDialog / CategoryCorrectionDialog / SaveConfirmDialog 例外：modal:false + 外部遮罩 reparent 到 `window.contentItem`，`anchors.fill`+`z:40`，避让 InputPanel z:99999，不可改 modal:true 否则遮键盘）。
- 返回按钮标准：back2.png+"返回" 胶囊 116×44 radius:22，图标 22×22，文字 24px bold `#4649E5`；标题 `anchors.centerIn`。
- 主题常量集中 `src/ui/Theme.qml`；全局字体 PingFang SC（仅 Regular，main.cpp 内嵌注册）。
- 图片圆角用 `MultiEffect` `maskEnabled+maskSource`（Qt6 clip 不随 radius）。
- MultiEffect 阴影标准：`shadowColor "#002A75"`，`shadowOpacity 0.1`，`shadowBlur 1.0`（**不是50**），offset 0。
- 错误提示脱敏：`window.alert()` 脱敏 URL/技术错误；C++ emit 错误禁含技术细节。

## 四、认证与密码存储
- 云端（AuthService）：记住登录 `~/.config/SmartScale/last_login.conf`，历史 `~/.cache/smartscale/login_history.json`，password 仅 base64（=明文，有泄露风险）。token/refreshToken/userId/devId 仅内存，重启靠 last_login.conf 自动重登；用户信息经 USER_BY_ID 拉取缓存 `~/.cache/smartscale/product.json`。
- 本地离线账号：SQLite `data/smartscale.db` `users` 表 SHA256，`UserRepo::verifyPassword`。
- Token 刷新：`AuthService` 全局锁 `m_isRefreshing`+`tokenRefreshCompleted(bool,QString)`；失败>2次建议重登。已接入 WeightHistory/UserIngredient/Category/CameraController。

## 五、网络
- API 域：`API_BASE_URL=https://api.shxgs.cn:5196`，`USER_BASE_URL=https://user.shxgs.cn:5196`；`NetworkUtils::createApiRequest/createUserApiRequest/createMultipartApiRequest` 统一 json+Bearer+SSL VerifyNone+HTTP/1.1+**`setTransferTimeout(15000)`**。新增网络调用若不走 NetworkUtils 需自加超时。
- **SSL 关键**：VerifyNone 仅跳过证书验证，自签名/私有 CA 仍会触发 `sslErrors`；所有调用点必须 connect `reply->sslErrors` 并 `ignoreSslErrors()`，否则握手静默中止表现为"请求无回应"。Qt6 网络错误信号是 `errorOccurred`（非 Qt5 `error`）。
- `NetworkManagerService`（QML `App.Backend::NetworkManager`，2026-07-28 原生重构）：
  - 检测层零外部进程：WiFi/4G 判定走 `QNetworkInterface`（IsUp+全局 IPv4），WiFi 信号读 `/proc/net/wireless`，3s 轮询；SSID 仅 Connected 且缓存空时 nmcli 反查一次。
  - 4G 信号源 AT+CSQ：`CellularModemService::State::PollingCsq` 串口常驻 5s 轮询（rssi 0-31→×100/31，99 保持上次）；错误/3 次无响应→归零+重试，与联网判定解耦。main.cpp 接线 `signalStrengthChanged→setCellularSignal`、`operatorNameChanged→setCellularOperator`。
  - 控制层：nmcli + sudo ip link set；4G 开关用 `m_cellularEnablePending` 挂起窗口（30s 超时转 Error），命令后 500/1500/3000ms 单发刷新。
  - networkMode 双写者：`setNetworkMode()`（用户）+ `deriveNetworkModeFromState()`（落定态派生）；SettingsDialog `netMode` 只读，`setNetMode` 只调 `setNetworkMode()`。
  - 状态语义：`cellularUiActive` 已删，UI 以真实 `cellularStatus` 为唯一数据源。
- 网络模式四枚举 `WifiOnly/CellularOnly/AllWifiPriority/AllCellularPriority`，默认 AllCellularPriority，持久化 `AppSettings.networkMode`（-1=未设置），开机 5s 后恢复。route-metric 方案已撤回（`connection modify` 不推内核，重做需 `device reapply`）。设备 4G=eth1 "有线连接 1"，WiFi=wlan0。
- SettingsDialog 四个网络 ToggleSwitch 互斥单选，`syncSwitches()` 同步 `checked`；开关用 `onClicked`（禁 `onToggled` 防循环回弹）。
- 信号显示：WiFi 用 `StatusBar`/`WifiListDialog` 同源（`availableNetworks` 中 `ssid===wifiSsid` 项 `signal`，回退 `wifiSignal`）；WiFi/4G 共用 `signalLevel()` 4 格均分（0-25%=1格…），`Signal0`/`Wifi0` 仅未连接时用，有网最低 1 格；QML 比较 C++ 枚举必须用数值（`s===4`）。
- **`m_cellularSignal` 单一写者**：只能由 `setCellularSignal()`（AT+CSQ）修改，原生刷新绝不可归零。

## 六、数据与接口
- 雪花 ID（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 qint64/QString，**禁止 `toInt()`**。
- 重量：内部/DB/接口/语音/水印统一 **kg**；`WeightSensor` `displayWeight` 按 50g 分度（`DISPLAY_STEP_KG=0.05`）+ 迟滞（`HYSTERESIS_THRESHOLD=0.030`）输出，QML 显示/计算/保存统一用它。
- 价格单位 **元/kg**（后端 `price` 字段口径已确认）：`amount = unitPrice × netWeight(kg)`，`WeightHistoryService::addRecord` 内 `qRound(price*100)/100`；`UserIngredientService` 返回的 `price` 即元/kg，原样保留。
- 上传 `buildUploadJson`：`val`=重量(kg,2位小数)、`price`=元/kg、`amount`=元；paged 接口返回同为 kg/元。
- **按斤显示（2026-09-18）**：`AppSettings.weightUnit`（int，0=kg 默认/1=斤）+ QML 单例 **`src/ui/WeightUnit.qml`** 是唯一换算入口。**存储/接口/计算/水印一律 kg、元/kg，只换算显示与输入**：斤=kg×2、元/斤=(元/kg)÷2、金额为不变量。展示用 `WeightUnit.text/disp/unit/priceUnit`，单价输入用 `WeightUnit.price(打开键盘)` → `WeightUnit.priceToKg(确认回写)`。**新增重量/单价展示必须走该单例，禁止硬编码 "kg"/"元/kg"**。注意：QML 里比较 `AppSettings.weightUnit` 用数值 `=== 1`（C++ enum 不匹配）。`SaveConfirmDialog.qml` 为死代码（硬编码 元/斤），勿参考。
- 保存流程：`addRecord` DB 写入即上传并立即 `cloudSyncSuccess(newId)`；失败 toast"记录已保存，云端同步失败将自动重试"。`createUserWeightRecord`（val 传克）为遗留路径。
- **AI 识别反查基于 ingrCd（emsCd 已废弃，2026-07-30）**：`UserIngredientService::findByIngrCd` 按 `item["en"]`（ingrCd）匹配，`m_emsMap` 已删，`FoodTranslator` 仅 ingrCd→ingrNm。
- `SystemInfoService` 读 `/proc/meminfo` 暴露 `memTotal`（<3GB 显示 "2GB"，否则 "4GB"）。

## 七、虚拟键盘
- Qt6 `QtQuick.VirtualKeyboard`，`locale="zh_CN"`；`QT_IM_MODULE=qtvirtualkeyboard`；键盘悬浮覆盖：主布局与弹窗 `y:(parent.height-height)/2` 居中不避让；`keyboardContainer.parent: Overlay.overlay`+`z:99999`。
- **样式部署/加载（2026-09-18 修正，重要）**：Qt `stylePath()` 对每个导入路径拼 `<path>/QtQuick/VirtualKeyboard/Styles/<样式名>/style.qml` 并**倒序**匹配，系统目录下同名副本会抢先命中。因此：①`QT_VIRTUALKEYBOARD_STYLE` 用唯一名 `smartscale`（**禁用 "light"**）；②CMake 把 `style.qml` 拷到 `<build>/keyboard_styles/QtQuick/VirtualKeyboard/Styles/smartscale/style.qml`；③main.cpp `engine.addImportPath(applicationDirPath()+"/keyboard_styles")`。源码 `src/ui/vkbdstyle/light/style.qml`（入口名必须 style.qml，`keyboardDesignWidth/Height` 显式 2560×800）。`Main.qml InputPanel.scale=0.62`，背景 `#E9EEF4`。
- **样式硬约束**：`KeyboardStyle.traceInputKeyPanelDelegate`/`traceCanvasDelegate`/`handwritingKeyPanel` 基类默认 null；不定义 `traceCanvasDelegate` 则 `TraceInputArea.onPressed` 直接 return，手写区采不到笔迹。
- **手写输入法（PP-OCRv5，2026-09-17）**：`src/ai/PpocrRecognizer`（`AI/rec.onnx` 输入 [1,3,48,W]/输出 [1,T,18385] 已含 softmax；字典 18383 行 + 空格类 + blank） + `src/ai/HandwritingInputMethod`（`QVirtualKeyboardAbstractInputMethod` 子类，只用公开头文件，抬笔 380ms 去抖，QtConcurrent 识别）。注入：`src/ui/components/HandwritingBridge.qml` 调 `keyboard.setHandwritingMode(true)` 并覆盖 `InputContext.inputEngine.inputMethod`。入口 Main.qml 键盘左上角"手写"按钮，测试入口 SystemInfoDialog→HwrTestDialog。
- 系统自带 Example HWR 插件识别为随机字母占位；Debian 未打包 Cerence/MyScript（`scripts/setup_handwriting.sh` 走不通）。

## 八、语音
- `VoiceSpeaker`（src/hardware/）：sherpa-onnx C API + Matcha 中文模型，进程内合成 + QThread 后台线程 + aplay 播放；对外接口（speak/stop/warmup/isReady/isSpeaking/信号）不变；`dlopen(RTLD_LOCAL)` 隔离 onnxruntime 符号冲突。
- 播报入口：`CameraController::speakPredictedLabel` 设 `speakText` 为 `！！！<中文名>！！！`（FoodTranslator 译后）；QML 仅 WorkstationPage `onCloudSyncSuccess` speak("已保存") + Main.qml warmup。
- 语速：`genCfg.speed>0` 时按 `length_scale=1/speed` 覆盖模型配置（speed==0 才用模型值），当前 `0.898f`。sherpa 采样步数未暴露（库内写死）。

## 九、OTA 远程升级
- `OtaService`（QML `App.Backend::OtaService`）：状态机 Idle/Checking/HasUpdate/Downloading/Verifying/ReadyToInstall/Installing/Success/Failed/RolledBack；组合复用 `UpdateService`（纯查询，接口勿动）。Q_INVOKABLE：checkUpdate/startDownload/cancelDownload/install/resetState；信号：checkFinished(success,hasUpdate,version)、upgradeResult(success,version,rolledBack)。
- **版本比较用 QVersionNumber（远端 version 去 V 前缀 vs APP_VERSION_FULL），禁止 verCode vs BUILD_NUMBER 直接比**。
- 下载：QNAM 流式写 `data/ota/update.part`+增量 SHA256 对照 `UpdateService.hash`，进度 500ms 节流，Failed 可重试。**取消下载回 HasUpdate（非 Idle）**（startDownload 守卫仅放行 HasUpdate/Failed）。
- 刷写：`scripts/apply_update.sh`（app.qrc 注册，install() 导出 data/ota/ 执行，QProcess::startDetached）。流程：sudo -n 预检→解压→manifest 校验→探测 systemd service→停应用（**须轮询等进程真退出，最多15s再 SIGKILL**，否则旧进程持 `/dev/ttyAMA0` flock，新进程报 locking 失败）→备份 `.bak.<ts>`（留2份）→**AI 模型同步（包内含 `AI/` 则 `cp -a` 到 APP_DIR/AI，失败在替换二进制前中止）**→替换→拉起→60s 等进程+30s 观察→result.success/回滚。退出码 0/1/2解压校验或AI同步/3权限/4拉起/5存活。
- 打包：`scripts/make_update_package.sh <版本> [build目录]`；build/AI 存在时整目录进包并写 manifest files[]（逐文件 sha256）。OTA 包同时分发 `keyboard_styles` 与 `AI`。
- 首启自检：构造时读 `data/ota/result.*|pending.json`，延迟 3s emit upgradeResult → Main.qml alert 后 resetState()。UI：SettingsDialog 版本更新行 + `OtaUpdateDialog.qml`（NoAutoClose，进度条/取消/立即重启安装/重新下载）。

## 十、AppSettings（QSettings INI）
- 路径 `~/.config/SmartScale/AppSettings.conf`（UserScope, "SmartScale"/"AppSettings"）；QML 名 `AppSettings`。
- 现有项：`priceInputEnabled`(false)、`cellularEnabled`(true)、`wifiEnabled`(true)、`networkAutoSwitch`(true)、`networkMode`(-1)、`weightUnit`(0=kg/1=斤)。新增开关照此模式：Q_PROPERTY + 成员 + setter（写回 QSettings + emit changed）。
- **Qt 坑**：带 `Q_ENUM` 的枚举必须声明在 **public 区**，否则 moc 生成代码报 `... is private within this context`（class 默认 private，写在 `public:` 之前就会踩）。

## 十一、Plymouth 主题（/usr/share/plymouth/themes/pix）
- PNG 加载正常；**让图片消失的真凶**是把 sprite `z` 从 -100 改成 0（该构建 z=0 会被背景盖住），保持负值。
- 黑边=contain 适配；铺满用 cover（缩放条件对调，裁溢出）或 stretch（变形）。运行时直接读目录脚本/PNG，改完下次开机生效无需重建 initramfs；文件属 root 需 sudo。
