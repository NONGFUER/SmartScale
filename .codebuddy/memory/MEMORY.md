# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档；按主题合并，避免重复。

## 一、编译与资源
- 禁止 AI 执行 `make`/`cmake --build`；用户自跑 `make -j1`，AI 改完用 `read_lints` 验证。
- 资源：`qt_add_big_resources(RCC_SOURCES app.qrc)`；新增图片必须编辑 `app.qrc`；改资源后清 build 重新 `cmake ..` + `make -j1`。
- 版本号：CMakeLists.txt `project(SmartScale VERSION x.y.z)`，构建号 `cmake -DBUILD_NUMBER=N`（默认9）；`version.h.in` → `configure_file` → `SystemInfoService.appVersion/buildNumber`，`StatusBar.qml` 绑定显示。
- QML 单例：纯 QML 用 `pragma Singleton` + CMake `set_source_files_properties(... QT_QML_SINGLETON_TYPE TRUE)`（`src/ui/Theme.qml`、`WeightUnit.qml`）；C++ 用 `qmlRegisterSingletonInstance`。
- **QML 隐式导入只在「文件所在目录」生效**：`src/ui/` 下的模块级单例（Theme/WeightUnit）在 `pages/`、`components/` 子目录**必须显式 `import SmartScale`**，否则绑定静默失败（`text:` 空白、`font.family`/`color` 悄悄回退默认值）。排查口诀：**页面里"文字空白但其他都正常"先查 import 是否漏了**。`SettingsDialog.qml` 是正确示范。

## 二、C++ 单例注册（main.cpp ~443 行）
- `App.Backend`：WeightManager(WeightSensor)、CameraController、BackendAuth、VisionAI、WeightHistoryService、CategoryService、UserIngredientService、VoiceSpeaker、SystemInfo、AppSettings、NetworkManager、MqttClient、CellularModem、UpdateService、OtaService。
- `SmartScale.Tools`：Translator(FoodTranslator)、PState；`SmartScale.Hwr`：Ppocr。

## 三、运行环境与交互规范
- 无鼠标光标：main.cpp `QGuiApplication::setOverrideCursor(Qt::BlankCursor)`；QML MouseArea 禁写 `cursorShape`。
- 弹窗输入框禁止自动聚焦（LoginDialog/WifiPasswordDialog 例外）：`focus:false` + `onOpened` 末尾 `Qt.callLater` 移焦点到关闭/返回按钮。
- Toast/通知：Popup/Dialog 根 + `modal:false` + `closePolicy:Popup.NoAutoClose` + `padding:0` + 透明 background。
- 弹窗遮罩：`modal:true` + 显式 `Overlay.modal: Rectangle{color:"#80000000"}`。LoginDialog/CategoryCorrectionDialog/SaveConfirmDialog 例外：`modal:false` + 外部遮罩 reparent 到 `window.contentItem`（`anchors.fill`+`z:40`，避让 InputPanel `z:99999`），**不可改成 modal:true，否则遮住键盘**。
- 返回按钮标准：back2.png + "返回" 胶囊 116×44 radius:22，图标 22×22，文字 24px bold `#4649E5`；标题 `anchors.centerIn`。
- 主题常量集中 `src/ui/Theme.qml`；全局字体 PingFang SC（仅 Regular，main.cpp 内嵌注册）。
- 图片圆角用 `MultiEffect` `maskEnabled+maskSource`（Qt6 clip 不随 radius）。
- MultiEffect 阴影标准：`shadowColor "#002A75"`、`shadowOpacity 0.1`、`shadowBlur 1.0`（**不是 50**）、offset 0。
- 错误提示脱敏：`window.alert()` 去掉 URL/技术错误；C++ emit 的错误不含技术细节。

## 四、路径 / 认证 / 密码存储
- **配置与缓存根统一走 `src/utils/AppPaths`（硬规则）**：`home()/configDir()/cacheDir()/ensureDir()`；**新增代码禁止直接 `QDir::homePath()` / `QSettings::UserScope`**。优先级：`SMARTSCALE_HOME` 环境变量 → 非 root = `QDir::homePath()` → root = `/etc/passwd` 首个 `uid∈[1000,65534)` 且可写的家目录（进程内缓存一次并打日志）。main.cpp 在日志初始化后、任何配置读取前调 `AppPaths::retireStaleRootData()`（root 时把 `/root/.config/SmartScale`、`/root/.cache/smartscale` 改名 `.stale-<ts>`，幂等；家目录仍是 /root 则跳过）。
- **属主硬规则（2026-09-30）**：root 实例（OTA 脚本兜底 `nohup` 拉起）会在**用户家目录**写出 `root:root` 文件，之后普通用户实例写不进去且 QSettings 静默失败 ⇒ 现象是"设置改了、重启后还是旧值"（实测 `/home/sjwu/.config/SmartScale/AppSettings.ini` 变成 root:root → `echo >>` 报权限不够）。已加 `AppPaths::adoptOwnership(path)` / `adoptAppDataOwnership()`（仅 `euid==0` 且家目录已纠正时生效，递归 chown 到家目录属主，幂等），main.cpp 启动即调用；`AppSettingsService::persist()` 每次落盘后再纠正一次（覆盖 root 实例运行期间新写的文件），构造时若文件不可写打 qWarning。`apply_update.sh` 兜底拉起改为 `runuser -u <APP_DIR 属主> -- env HOME=<owner home>`（**脚本改动第二次 OTA 才生效**，存量设备靠二进制自身启动逻辑）。同一类坑还会拖累 `last_login.conf`、`ingr_images/*`、`cache/embedded`。
- **`<APP_DIR>` 同样会被 root 写走（2026-09-30 补充）**：`AI/`、`keyboard_styles/`（目录本身）、`appSmartScale` 都可能变成 root:root —— 来源是 root 实例的 `EmbeddedAssets` 释放 + 脚本的 `cp`/`cp -a`。后果：普通用户实例判定"释放目录不可写"→ 退回 `cacheDir/embedded`（部署布局分裂），用户侧 `make`/打包/覆盖样式写不进去。修复：`EmbeddedAssets::resolveDir()` 的**每个返回分支**都走 `adoptAndReturn()`（释放后立即 chown）；`apply_update.sh` 的 `adopt_owner()` 在资源目录同步后与二进制替换 `chmod` 后各调一次（纠正为 APP_DIR 属主）。排查命令：`sudo find <APP_DIR> ~/.config/SmartScale ~/.cache/smartscale -user root`。
- 云端登录：`~/.config/SmartScale/last_login.conf`、历史 `~/.cache/smartscale/login_history.json`；password 仅 base64（等于明文）。`last_login.conf` 键名是 **`password`**，值是 `@ByteArray(base64)`（QByteArray 变体序列化，读回 `.toString()` 正常）。
- **密码来源优先级**：启动的 `autoLogin()` **只读 last_login.conf**；弹窗快捷登录 `loginByHistory()/hasRememberedPassword()` 是 history 条目 password 优先、为空再回退 `last_login.conf`（要求 userCode 相同）。写入只有两条：①记住登录勾选 + 首次登录成功 → `saveLastLogin()`；②快捷登录成功 → `rememberHistoryPassword()`（`addLoginHistory()` 刻意不写密码）。登出 `clearSavedLoginData()` 会删 last_login.conf。
- 自动登录：判据唯一 = `hasSavedLogin()`（rememberLogin && userCode && password 非空）；触发点 `Main.qml Component.onCompleted → tryAutoLogin()`，**必须先等 deviceSn 非空**（挂 `_pendingAutoLogin` + 3s 超时兜底转手动）；`autoLogin()` = base64 解码后 `login()`，与手动登录同链路。
- 本地离线账号：SQLite `data/smartscale.db` `users` 表 SHA256（`UserRepo::verifyPassword`）。
- Token 刷新：`AuthService` 全局锁 `m_isRefreshing` + `tokenRefreshCompleted(bool,QString)`；已接入 WeightHistory/UserIngredient/Category/CameraController。

## 五、网络
- API 域：`API_BASE_URL=https://api.shxgs.cn:5196`、`USER_BASE_URL=https://user.shxgs.cn:5196`；统一走 `NetworkUtils::createApiRequest/createUserApiRequest/createMultipartApiRequest`（json + Bearer + SSL VerifyNone + HTTP/1.1 + `setTransferTimeout(15000)`）。不走 NetworkUtils 的调用必须自加超时。
- **SSL**：VerifyNone 只跳过证书验证，自签名/私有 CA 仍触发 `sslErrors`，所有调用点必须 `connect(reply, &QNetworkReply::sslErrors, ...) → ignoreSslErrors()`，否则表现为"请求无回应"。Qt6 信号是 `errorOccurred`。
- `NetworkManagerService`（QML `App.Backend::NetworkManager`）：检测层零外部进程（`QNetworkInterface` + `/proc/net/wireless`，3s 轮询，SSID 仅 Connected 且缓存空时 nmcli 反查）；4G 信号源 `CellularModemService::State::PollingCsq` 串口常驻 5s 轮询（rssi 0-31→×100/31，99 保持上次，错误/3 次无响应归零重试），main.cpp 接线 `signalStrengthChanged→setCellularSignal`、`operatorNameChanged→setCellularOperator`；控制层 nmcli + `sudo ip link set`，4G 开关有 `m_cellularEnablePending` 挂起窗口（30s 超时转 Error），命令后 500/1500/3000ms 单发刷新。
- networkMode 双写者：`setNetworkMode()`（用户）+ `deriveNetworkModeFromState()`（落定态派生，Unknown/Connecting 跳过）；四枚举 `WifiOnly/CellularOnly/AllWifiPriority/AllCellularPriority`，默认 AllCellularPriority，持久化 `AppSettings.networkMode`（-1=未设置），开机 5s 后由 main.cpp 恢复（`networkMode<0` 且 `cellularEnabled==false` 时走 3s 恢复 4G 禁用）。route-metric 方案已撤回（`connection modify` 不推内核）。设备 4G=eth1 "有线连接 1"，WiFi=wlan0。
- `m_cellularSignal` **单一写者**：只能由 `setCellularSignal()`（AT+CSQ）修改，原生刷新绝不可归零。
- SettingsDialog 四个网络开关互斥单选，`syncSwitches()` 同步 `checked`，用 `onClicked`（禁 `onToggled` 防回弹）。
- 信号显示：WiFi 与 `WifiListDialog` 同源（`availableNetworks` 中 `ssid===wifiSsid` 的 `signal`，回退 `wifiSignal`）；WiFi/4G 共用 `signalLevel()` 4 格均分，`Signal0`/`Wifi0` 仅未连接时用；QML 比较 C++ 枚举必须用数值（`s===4`）。

## 六、数据与接口
- 雪花 ID（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 qint64/QString，**禁止 `toInt()`**。
- 重量：内部/DB/接口/语音/水印统一 **kg**；`WeightSensor::displayWeight` 按 50g 分度（`DISPLAY_STEP_KG=0.05`）+ 迟滞（`HYSTERESIS_THRESHOLD=0.030`），QML 显示/计算/保存统一用它。
- 价格单位 **元/kg**：`amount = unitPrice × netWeight(kg)`；`WeightHistoryService::addRecord` 内 `qRound(price*100)/100`；上传 `val`=kg(2位)、`price`=元/kg、`amount`=元。
- **按斤显示**：`AppSettings.weightUnit`（0=kg/1=斤）+ QML 单例 `src/ui/WeightUnit.qml` 是唯一换算入口（斤=kg×2、元/斤=(元/kg)÷2，金额不变量）；**存储/接口/计算/水印一律 kg、元/kg**。新增重量/单价展示必须走该单例，禁硬编码 "kg"/"元/kg"；QML 比较用数值 `=== 1`。`SaveConfirmDialog.qml` 是死代码，勿参考。
- **食材图片缓存**：`~/.cache/smartscale/ingr_images/`，文件名 = `MD5(去掉 query 的 URL)+扩展名`（预签名 URL 每次签名不同，**必须去 query**）。**不变式：`imgLocal` 必须等于 `localImagePathFor(当前 img URL)`**；`fetchIngredients` 复用判断与 `downloadIngredientImages` 跳过判断都要比对 URL（+ `updAt`）。**`updAt` 绝不可并入文件名哈希**（会让 642 张图全部重下 ≈490MB）；旧 JSON 无 `updAt` 按"版本未知"宽松处理。孤儿清理 `cleanupOrphanImages()` 仅在拿到完整快照（`pageSize=10000`）后调用，保留 7 天内孤儿。图片请求走预签名 URL，**绝不加 Bearer 头**（S3 会改 SigV4 → 403）。
- 保存流程：`addRecord` 写 DB 即上传并立即 `cloudSyncSuccess(newId)`；失败 toast"记录已保存，云端同步失败将自动重试"。`createUserWeightRecord`（val 传克）为遗留路径。
- **AI 识别反查基于 ingrCd**（`UserIngredientService::findByIngrCd` 匹配 `item["en"]`，emsCd 已废弃；`FoodTranslator` 仅 ingrCd→ingrNm）。
- **AI 候选名称一律以「库名」为准**：`{code=ingrCd, name=AI中文名}` 的 `name` 只作兜底，显示/播报必须走反查（`Translator.translate(code)` 或 `findByIngrCd(code)["cn"]`）。已统一位置：`AiResultSelectDialog.displayName()`、`CategoryCorrectionDialog.getDisplayItems()`、工作台卡片、toast、`CameraController::speakPredictedLabel`。
- `SystemInfoService` 读 `/proc/meminfo` 暴露 `memTotal`（<3GB 显示 "2GB"，否则 "4GB"）。

## 七、虚拟键盘与手写
- Qt6 `QtQuick.VirtualKeyboard`，`locale="zh_CN"`，`QT_IM_MODULE=qtvirtualkeyboard`；键盘悬浮覆盖：主布局与弹窗 `y:(parent.height-height)/2` 居中不避让；`keyboardContainer.parent: Overlay.overlay` + `z:99999`。
- **样式部署**：`QT_VIRTUALKEYBOARD_STYLE=smartscale`（**禁用 "light"**：Qt 对 `<path>/QtQuick/VirtualKeyboard/Styles/<名>/style.qml` 倒序匹配，系统同名副本会抢先）；CMake 拷到 `<build>/keyboard_styles/QtQuick/VirtualKeyboard/Styles/smartscale/style.qml`；main.cpp `engine.addImportPath(appDir+"/keyboard_styles")`。源码 `src/ui/vkbdstyle/light/style.qml`（入口必须叫 style.qml，`keyboardDesignWidth/Height` 显式 2560×800）。`Main.qml InputPanel.scale=0.62`，背景 `#E9EEF4`。
- **样式硬约束**：不定义 `traceCanvasDelegate` 则 `TraceInputArea.onPressed` 直接 return，手写区采不到笔迹（系统 `light` 就是这种情况，日志特征 `WARN: [Main] 未找到部署样式 ... => 回退系统 light 样式`）。
- **资源自愈 `src/utils/EmbeddedAssets`**：`aiDir()`/`keyboardStyleRoot()` 按 ①设备目录（`<APP_DIR>/AI`、`<APP_DIR>/keyboard_styles`，要求齐备且**尺寸与内嵌副本一致**）→ ②释放内嵌副本到设备目录（目录不可写则跳过）→ ③退回 `<cacheDir>/embedded/<子目录>` → ④返回空并告警。内嵌来源 `app.qrc` 的 `embedded/AI/rec.onnx`、`embedded/AI/ppocrv5_dict.txt`、`embedded/keyboard_styles/.../style.qml`。用尺寸比较而非哈希（避免每次启动读 16MB 模型）。
- **手写输入（PP-OCRv5）**：`src/ai/PpocrRecognizer`（`AI/rec.onnx` 输入 [1,3,48,W] 输出 [1,T,18385] 含 softmax；字典 18383 行 + 空格类 + blank）+ `src/ai/HandwritingInputMethod`（`QVirtualKeyboardAbstractInputMethod` 子类，仅用公开头文件，抬笔 380ms 去抖，QtConcurrent 识别）。注入：`HandwritingBridge.qml` 调 `keyboard.setHandwritingMode(true)` 并覆盖 `InputContext.inputEngine.inputMethod`；入口 Main.qml 键盘左上角"手写"，测试入口 SystemInfoDialog→HwrTestDialog。
- 系统自带 Example HWR 插件是随机字母占位；Debian 未打包 Cerence/MyScript（`scripts/setup_handwriting.sh` 走不通）。

## 八、语音
- `VoiceSpeaker`（src/hardware/）：sherpa-onnx C API + Matcha 中文模型（`matcha-icefall-zh-baker`，22050Hz），进程内合成 + 后台 QThread + `aplay` 播放；对外接口（speak/stop/warmup/isReady/isSpeaking/4 信号）不变；`dlopen(RTLD_LOCAL)` 隔离 onnxruntime 符号冲突。合成放独立线程（同线程串行省锁），播放/合成双取消 token 保证 `stop()` 即时。
- 播报入口：`CameraController::speakPredictedLabel` 设 `speakText` 为 `！！！<中文名>！！！`（译后）；QML 仅 WorkstationPage `onCloudSyncSuccess` speak("已保存") + Main.qml `warmup()`。
- 语速：`genCfg.speed>0` 时按 `length_scale=1/speed` 覆盖模型配置，当前 `0.898f`；采样步数库内写死未暴露。冒烟：板端 `python3 scripts/tts_worker.py`。

## 九、OTA 远程升级
- `OtaService`（`App.Backend::OtaService`）：状态机 Idle/Checking/HasUpdate/Downloading/Verifying/ReadyToInstall/Installing/Success/Failed/RolledBack；复用 `UpdateService`（纯查询，接口勿动）。Q_INVOKABLE checkUpdate/startDownload/cancelDownload/install/resetState；信号 checkFinished(success,hasUpdate,version)、upgradeResult(success,version,rolledBack)。
- **版本比较用 `QVersionNumber`**（远端去 V 前缀 vs `APP_VERSION_FULL`），禁止 verCode vs BUILD_NUMBER 直接比；包名用纯 `2.13.3.37`（带日期会成 QVersionNumber suffix → 判不出更新）。
- 下载：QNAM 流式写 `data/ota/update.part` + 增量 SHA256 对照 `UpdateService.hash`，进度 500ms 节流；**取消下载回 HasUpdate（非 Idle）**，`startDownload` 守卫仅放行 HasUpdate/Failed。
- **没有 systemd 服务可依赖（2026-09-30 确认）**：`/etc/systemd/system/smartscale.service`（4/18）的 `ExecStart=/home/sjwu/SmartScale/start_app.sh` 里的脚本已在 commit `c731a1b` 被删除（内容为 `cd build && ./appSmartScale`，带 `QT_QPA_PLATFORM=xcb`），unit 状态 `disabled`+`inactive` ⇒ **历史残留，别去修/别 enable**。真正的开机自启是 `~/.config/labwc/autostart`（内容仅一行 `<APP_DIR>/appSmartScale &`，labwc 以 sjwu 身份执行；本机 APP_DIR 顶层无二进制故无效，设备上有效）。**推论：`apply_update.sh` 的服务探测永远失败 ⇒ OTA 必定走 `nohup` 兜底（root 身份）** —— 所以 `launch_direct()`（runuser 到 APP_DIR 属主 + 正确 HOME）是这条路径的必需修复，不是可选加固。
- 首启自检：构造时读 `data/ota/result.*|pending.json`，延迟 3s emit upgradeResult → Main.qml alert 后 `resetState()`。UI：SettingsDialog 版本更新行 + `OtaUpdateDialog.qml`（NoAutoClose）。
- 刷写 `scripts/apply_update.sh`（app.qrc 注册，`install()` 导出到 `data/ota/` 执行，`QProcess::startDetached`）：sudo -n 预检→解压→manifest 校验→探测 systemd service→停应用（**必须轮询等进程真退出，最多 15s 再 SIGKILL**，否则旧进程持 `/dev/ttyAMA0` flock）→备份 `.bak.<ts>`（留 2 份）→资源目录同步→替换→拉起（**兜底拉起以 APP_DIR 属主身份 + 正确 HOME，避免 root 属主配置文件**）→60s 等进程 + 30s 观察。退出码 0/1/2/3权限/4拉起/5存活。
- **脚本改动的生效时序（重要）**：`install()` 是把**当前运行版本**内嵌的脚本导出后执行 ⇒ 现场老设备第一次 OTA 跑的是旧脚本，脚本新逻辑要**第二次** OTA 才生效。要在存量设备上做一次性修复，必须由**新版二进制自身的启动逻辑**完成。
- **资源分发方式（2026-09-19 定稿）**：`AI/rec.onnx` + `ppocrv5_dict.txt` + 键盘样式一律内嵌进二进制（`EmbeddedAssets` 自愈释放），**不再随包分发**；`make_update_package.sh` 的 `ASSET_DIRS=()` 默认为空。包体 ~25MB，二进制 ~41MB。
- **本地视觉模型已停用**：`CameraController` 里 `//m_aiService = new VisionAIService(this);`，`aiService()` 恒为 nullptr（`VisionAI` 是空单例，`CategoryCorrectionDialog` 里 `VisionAI.submitCorrection` 是无效路径）。**食材识别走在线接口**（日志前缀 `[在线AI]`）⇒ `AI/mobilenetv3_food.onnx/.data/labels.txt` 无需部署/打包/内嵌。
- 打包：`scripts/make_update_package.sh <版本> [build目录]`（在 `scripts/` 下执行）；`build/AI`、`build/keyboard_styles` 由 CMake **配置期** `file(COPY)` 生成（只跑 make 不重跑 cmake 就不会有）；打包后务必 `tar -tzf` 确认内容。

## 十、AppSettings（QSettings IniFormat）
- 路径 `<AppPaths::configDir()>/AppSettings.ini`（**显式路径 + IniFormat**，不是 UserScope、不是 `.conf`）；QML 名 `AppSettings`。
- 现有项：`priceInputEnabled`(false)、`cellularEnabled`(true)、`wifiEnabled`(true)、`networkAutoSwitch`(true)、`networkMode`(-1)、`weightUnit`(0=kg/1=斤)。
- 新增开关照此模式：Q_PROPERTY + 成员 + setter（改内存 → `setValue` → `persist()` → emit changed）。**Qt 坑**：带 `Q_ENUM` 的枚举必须声明在 **public 区**（class 默认 private，否则 moc 报 `... is private within this context`）。

## 十一、Plymouth 主题（/usr/share/plymouth/themes/pix）
- PNG 加载正常；**让图片消失的真凶**是把 sprite `z` 从 -100 改成 0（该构建 z=0 会被背景盖住），保持负值。
- 黑边 = contain 适配；铺满用 cover（缩放条件对调，裁溢出）或 stretch（变形）。运行时直接读目录脚本/PNG，改完下次开机生效、无需重建 initramfs；文件属 root 需 sudo。
