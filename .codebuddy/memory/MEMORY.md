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
- 云端（AuthService）：记住登录 `~/.config/SmartScale/last_login.conf`，历史 `~/.cache/smartscale/login_history.json`，password 仅 base64（=明文，有泄露风险；实测 `last_login.conf` 权限 644 本机任意用户可读）。
  - **看文件时别被格式误导**：`last_login.conf` 里键名是 **`password`**（不是 `pass`），值是 `@ByteArray(MTIzNDU2Nzg=)` —— 因为 `m_pendingPassword.toUtf8().toBase64()` 返回的是 **QByteArray**，QSettings 按 ByteArray 变体序列化；要解码的是括号里的 base64 串（实测 = `12345678`）。读回时 `.toString()` 会自动转换，功能正常。
  - **密码来源优先级**：启动路径 `autoLogin()` **只读 `last_login.conf`，完全不看 `login_history.json`**；弹窗快捷登录 `loginByHistory()` / `hasRememberedPassword()` 才是「history 条目的 password 优先，为空再回退 `last_login.conf`（要求 userCode 相同）」。token/refreshToken/userId/devId 仅内存，重启靠 last_login.conf 自动重登；用户信息经 USER_BY_ID 拉取缓存 `~/.cache/smartscale/product.json`。
- **自动登录实现（2026-09-18 梳理）**：判据唯一 = `hasSavedLogin()`（`rememberLogin && userCode非空 && password非空`）。触发点在 `Main.qml Component.onCompleted` → `tryAutoLogin()`，且**必须先等 `deviceSn` 非空**（登录体 `Sn` 由串口异步读回，空 SN 会被服务端拒），未就绪则挂 `_pendingAutoLogin` + 3s 超时兜底转手动登录。执行体 `autoLogin()` = base64 解码后调 `login()`——**与手动登录同一条链路，不是新协议**，因此继承 admin 走离线 / 非 admin 走 `tryOnlineLogin` 等行为。
- 凭据写入只有两条路径：①「记住登录」勾选 + 首次登录成功 → `saveLastLogin()` 写 `last_login.conf`（`remember=true / userCode / password=base64`，有 `if(!m_rememberLogin) return` 守卫，写的是 `m_pendingUserCode/m_pendingPassword`）；②「快捷登录」成功后 `rememberHistoryPassword()` 把密码写进 `login_history.json` 对应条目（`addLoginHistory()` 本身**刻意不写密码**）。第二触发点：`LoginDialog.onOpened` 时若下拉默认选中的历史账号 `hasRememberedPassword()` 为真 → 直接 `loginByHistory()`。登出 `clearSavedLoginData()` 会 `QFile::remove(last_login.conf)`。
- **坑（详见 OTA 章节）**：以上路径全部以 `QDir::homePath()` 为根 → 凭据与设置随「谁启动进程」而分裂（root 拉起读 `/root/...`）。
- **配置/缓存根目录统一走 `src/utils/AppPaths`（2026-09-18 落地，硬规则）**：`AppPaths::home()/configDir()/cacheDir()` 已取代全部 12 处 `QDir::homePath()`，`AppSettingsService` 也从 `QSettings::UserScope` 改为显式路径。**新增代码禁止再直接使用 `QDir::homePath()` / `QSettings::UserScope`**。取值优先级：环境变量 `SMARTSCALE_HOME` → 非 root 时 = `QDir::homePath()`（行为与历史完全一致）→ root 时 = `/etc/passwd` 里首个 `uid∈[1000,65534)` 且可写的家目录（本机/设备都是 `/home/sjwu`），解析结果进程内缓存一次并打日志。
- 配套：`main.cpp` 在日志初始化后、**任何配置读取之前**调 `AppPaths::retireStaleRootData()` —— 以 root 启动时把 `/root/.config/SmartScale` 与 `/root/.cache/smartscale` 改名 `.stale-<时间戳>`（幂等；若家目录未纠正仍指向 /root 则跳过，避免"作废了又被重建"）。涉及文件：AuthService、AppSettingsService、UserIngredientService、CategoryService、FoodTranslator、NetworkManagerService、CameraController、main.cpp（`app/main.cpp` + `src/utils/AppPaths.*`，CMake 已加 SOURCES）。
- 注意：`last_login.conf` 路径已从文件级 `static const` 改为函数 `lastLoginPath()` —— 常量会在 main() 之前求值，拿不到运行期才确定的 AppPaths 解析结果。
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
- **食材图片缓存（2026-09-18 修复"后台换图、设备仍显示旧图"）**：`~/.cache/smartscale/ingr_images/`，文件名 = `MD5(去掉 query 的 URL) + 扩展名`（S3 预签名 URL 每次签名不同，**必须去 query** 才能复用）；索引 `ingredients.json` 每项的 `imgLocal` 指向它。**不变式：`imgLocal` 必须等于 `localImagePathFor(当前 img URL)`** —— `fetchIngredients` 的复用判断（约 310 行）与 `downloadIngredientImages` 的跳过判断（约 500 行）都必须做这个比对；只按「ingrId + 文件存在」复用会让新图永不下载（实测农夫山泉）。后端图片对象名是 **UUID**（`/ingr/cust<N>/<ingrId>/<uuid>.<ext>`，少数旧数据 `/ingr/<ingrId>/<uuid>.<ext>`），换图 = 换路径；响应里有 `updAt`（有图条目全都有），已纳入持久化（`item["updAt"]`，随 ingredients.json 落盘）并参与复用判断：同 URL 但 `updAt` 变 → 视为后端覆盖了同一 key → 重下。**`updAt` 绝不可并入文件名哈希**（那会让升级后 642 张图全部重下≈490MB）；且旧 JSON 无 `updAt` 时按"版本未知"宽松处理（仅比 URL），否则升级后首次 fetch 会整批重下。
- 孤儿清理：`cleanupOrphanImages()` 仅在 `fetchIngredients` 拿到完整快照后调用（`pageSize=10000` 一次拿全，白名单 = 索引 `imgLocal` + 在途下载目标），并**保留 7 天内**的孤儿（防切换账号后整批重下）。实测可回收 385MB（3146 文件 → 保留 643）。图片请求认证：预签名 URL（含 `X-Amz-Signature`）**绝不加 Bearer 头**（S3 见 Authorization 头会改用 SigV4 校验 → 403）。
- **按斤显示（2026-09-18）**：`AppSettings.weightUnit`（int，0=kg 默认/1=斤）+ QML 单例 **`src/ui/WeightUnit.qml`** 是唯一换算入口。**存储/接口/计算/水印一律 kg、元/kg，只换算显示与输入**：斤=kg×2、元/斤=(元/kg)÷2、金额为不变量。展示用 `WeightUnit.text/disp/unit/priceUnit`，单价输入用 `WeightUnit.price(打开键盘)` → `WeightUnit.priceToKg(确认回写)`。**新增重量/单价展示必须走该单例，禁止硬编码 "kg"/"元/kg"**。注意：QML 里比较 `AppSettings.weightUnit` 用数值 `=== 1`（C++ enum 不匹配）。`SaveConfirmDialog.qml` 为死代码（硬编码 元/斤），勿参考。
- 保存流程：`addRecord` DB 写入即上传并立即 `cloudSyncSuccess(newId)`；失败 toast"记录已保存，云端同步失败将自动重试"。`createUserWeightRecord`（val 传克）为遗留路径。
- **AI 识别反查基于 ingrCd（emsCd 已废弃，2026-07-30）**：`UserIngredientService::findByIngrCd` 按 `item["en"]`（ingrCd）匹配，`m_emsMap` 已删，`FoodTranslator` 仅 ingrCd→ingrNm。
- **AI 候选名称一律以「库名」为准（2026-09-18 统一）**：AI 返回的 `{code=ingrCd, name=AI中文名}` 中 `name` **只作兜底**；所有对外显示/播报的食材名必须走反查（`Translator.translate(code)` 或 `UserIngredientService.findByIngrCd(code)` 的 `cn`），反查不到（未登录/不在库中）才回退 `name`。已统一位置：识别结果选择弹窗 `AiResultSelectDialog.displayName()`、纠错弹窗 `CategoryCorrectionDialog.getDisplayItems()`、工作台卡片 `ingredientNameText`、toast、语音 `CameraController::speakPredictedLabel`（C++ 侧同样先 translate 再兜底 `name`）。**新增任何展示 AI 食材名的地方都要遵守，否则会出现"弹窗写豆角、选完变四季豆"类不一致**。
- `SystemInfoService` 读 `/proc/meminfo` 暴露 `memTotal`（<3GB 显示 "2GB"，否则 "4GB"）。

## 七、虚拟键盘
- Qt6 `QtQuick.VirtualKeyboard`，`locale="zh_CN"`；`QT_IM_MODULE=qtvirtualkeyboard`；键盘悬浮覆盖：主布局与弹窗 `y:(parent.height-height)/2` 居中不避让；`keyboardContainer.parent: Overlay.overlay`+`z:99999`。
- **样式部署/加载（2026-09-18 修正，重要）**：Qt `stylePath()` 对每个导入路径拼 `<path>/QtQuick/VirtualKeyboard/Styles/<样式名>/style.qml` 并**倒序**匹配，系统目录下同名副本会抢先命中。因此：①`QT_VIRTUALKEYBOARD_STYLE` 用唯一名 `smartscale`（**禁用 "light"**）；②CMake 把 `style.qml` 拷到 `<build>/keyboard_styles/QtQuick/VirtualKeyboard/Styles/smartscale/style.qml`；③main.cpp `engine.addImportPath(applicationDirPath()+"/keyboard_styles")`。源码 `src/ui/vkbdstyle/light/style.qml`（入口名必须 style.qml，`keyboardDesignWidth/Height` 显式 2560×800）。`Main.qml InputPanel.scale=0.62`，背景 `#E9EEF4`。
- **样式硬约束**：`KeyboardStyle.traceInputKeyPanelDelegate`/`traceCanvasDelegate`/`handwritingKeyPanel` 基类默认 null；不定义 `traceCanvasDelegate` 则 `TraceInputArea.onPressed` 直接 return，手写区采不到笔迹。
- **手写区"一个笔画都采不到"的已知机制（2026-09-18，已实证）**：`main.cpp` 找不到键盘样式 → 回退系统 `light` → 系统那份是 Debian 原版、不含 `traceCanvasDelegate` → `TraceInputArea.onPressed` 直接 return。`.34/.35/.36` 的 OTA 包**从不带 `keyboard_styles`**，所以设备上极易触发。**实证日志（另一台机器 2026-09-18 21:31/21:39）**：`WARN: [Main] 未找到部署样式: "/home/sjwu/SmartScale/build/keyboard_styles/.../smartscale/style.qml" => 回退系统 light 样式` 紧跟 `[HWR] 键盘样式:file:///usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Styles/light/style.qml` —— 即该机器上 `keyboard_styles` 目录不存在，实际用了系统 light。
- **资源自愈模块 `src/utils/EmbeddedAssets`（2026-09-19 落地，替代早期内联实现）**：`aiDir()` / `keyboardStyleRoot()` 统一按 ①设备目录（`<APP_DIR>/AI`、`<APP_DIR>/keyboard_styles`，要求文件齐备且**尺寸与内嵌副本一致**）→ ②释放内嵌副本到**设备目录**（首选，与"随包部署"布局一致、运维查看直观；目录不可写则跳过）→ ③退回 `<AppPaths::cacheDir()>/embedded/<子目录>/`（必然可写，兜住 APP_DIR 属 root/只读）→ ④都没有返回空（调用方回退告警）。释放仅在缺失或尺寸不同时重写。内嵌来源：`app.qrc` 的 `alias="embedded/AI/rec.onnx"`、`alias="embedded/AI/ppocrv5_dict.txt"`、`alias="embedded/keyboard_styles/QtQuick/VirtualKeyboard/Styles/smartscale/style.qml"`。使用点：`main.cpp`（键盘样式根目录 + `QT_VIRTUALKEYBOARD_STYLE`，日志 `[Main] 键盘样式根目录:`）、`PpocrRecognizer::loadModel()`（模型目录，日志 `[EmbeddedAssets] 已释放内嵌资源:`）。**为什么必须内嵌**：OTA 刷写脚本由设备上运行的旧版本导出、且只 `cp appSmartScale`，包内其它目录到不了设备（实证见 OTA 章节），客户只做一次 OTA 就必须把资源送到 ⇒ 资源必须随二进制走。尺寸比较而非哈希：避免每次启动读 16MB 模型。
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
- **刷写脚本改动的生效时序（2026-09-18 结论，重要）**：`OtaService::install()` 是把**当前运行版本**内嵌的 `:/scripts/apply_update.sh` 导出到 `<APP_DIR>/data/ota/` 再执行 ⇒ **现场老设备第一次 OTA 跑的是旧脚本**，对 `apply_update.sh` 的新增逻辑要等**第二次** OTA 才生效。因此"要在存量设备上做一次性修复"必须由**新版二进制自身的启动逻辑**完成（随第一次 OTA 立即生效），不能依赖改脚本。
- **为什么"别的机器 OTA 后 `<APP_DIR>/` 下没有 AI 与 keyboard_styles"（2026-09-18 实证）**：`apply_update.sh` 的"7.5 资源目录同步"（`for asset_dir in AI keyboard_styles` → `mkdir -p` + `cp -a`）是 commit **`f4974a3`（2026-09-18 16:11，feat(hwr) 接入 PP-OCRv5）** 才加入的。跑着该提交**之前**版本的机器，第一次 OTA 用的是**它自己内嵌的旧脚本**（流程只有 备份→新版就位，`asset_dir`/`AI` 命中数为 0）⇒ 包里的 `AI/`、`keyboard_styles/` 被**静默忽略**，只换了二进制；**第二次** OTA（此时机器上已是新版、内嵌新脚本）才会真正落地资源目录。⇒ 存量机器要么补第二次 OTA，要么手工拷 `<APP_DIR>/AI/` + `<APP_DIR>/keyboard_styles/`。
- 依赖 `AI/` 的两个功能（缺文件时都会打 qCritical，可远程判定）：手写识别需 `AI/rec.onnx` + `AI/ppocrv5_dict.txt`（`[PPOCR] 模型或字典缺失`）；食材识别需 `AI/mobilenetv3_food.onnx` + `AI/labels.txt`（+`.data`）（`[Vision AI 致命错误] 找不到模型或标签文件！`）。
- 刷写：`scripts/apply_update.sh`（app.qrc 注册，install() 导出 data/ota/ 执行，QProcess::startDetached）。流程：sudo -n 预检→解压→manifest 校验→探测 systemd service→停应用（**须轮询等进程真退出，最多15s再 SIGKILL**，否则旧进程持 `/dev/ttyAMA0` flock，新进程报 locking 失败）→备份 `.bak.<ts>`（留2份）→**AI 模型同步（包内含 `AI/` 则 `cp -a` 到 APP_DIR/AI，失败在替换二进制前中止）**→替换→拉起→60s 等进程+30s 观察→result.success/回滚。退出码 0/1/2解压校验或AI同步/3权限/4拉起/5存活。
- 打包：`scripts/make_update_package.sh <版本> [build目录]`（在 `scripts/` 下执行，包落在当前目录）；`build/AI`、`build/keyboard_styles` 存在时整目录进包并写 manifest files[]（逐文件 sha256）。**打包后务必 `tar -tzf` 确认这两个目录真的进包了**。
- **AI 与样式的分发方式（2026-09-19 定稿，取代 09-18 的"随包分发"约定）**：`AI/rec.onnx` + `AI/ppocrv5_dict.txt` + 键盘样式**一律内嵌进二进制**（`app.qrc` → `EmbeddedAssets` 自愈释放），**不再随包分发**；`make_update_package.sh` 的 `ASSET_DIRS=()` 默认空（需要临时用包分发某目录时再加）。这样包体积回到 ~25MB（二进制涨到 ~41MB），且**任何存量机器一次 OTA 即恢复手写**（不依赖脚本、不依赖第二次 OTA）。`labels.txt`/`mobilenetv3_food.*` 连内嵌都不需要 —— 本地模型已停用（见"核心服务"里的说明）。
- **本地视觉模型已停用（重要）**：`CameraController` 里 `//m_aiService = new VisionAIService(this);`（注释"暂不启用本地AI模型"），`aiService()` 恒为 `nullptr`（qmlRegisterSingletonInstance 注册的 `VisionAI` 也是空单例，`CategoryCorrectionDialog.qml` 里 `VisionAI.submitCorrection(...)` 是无效路径）。**食材识别走在线接口**（日志前缀 `[在线AI]`）⇒ `AI/mobilenetv3_food.onnx`、`.data`、`labels.txt` 不需要部署/打包/内嵌。
- 版本号命名：OTA 包名**不带日期后缀**，用纯 `2.13.3.37`（`2.13.3.37_20260918` 这类写法会把日期变成 QVersionNumber 的 suffix，数字段相同 → 已在该版本上的设备判不出更新）。
- **打包前必须确认 `build/AI`、`build/keyboard_styles` 存在（2026-09-18 实测踩坑，重要）**：这两个目录由 CMake **配置期** `file(COPY ...)` 生成，**只跑 `make` 不重跑 `cmake` 就不会出现**。实测 `.34/.35/.36` 三个包内**只有 `appSmartScale`+`manifest.json`** ⇒ **过去几版 OTA 从未分发过键盘样式与 AI 模型**（设备缺 `keyboard_styles` 时 main.cpp 会回退系统 light 样式）。`2.13.3.37` 是第一个真正带上 `keyboard_styles` 的包；代价是包体从 ~11MB 涨到 40MB（AI 占 33MB：`mobilenetv3_food.onnx.data` 16MB + `rec.onnx` 16MB）。只想发增量时可在打包前临时移开 `build/AI`（打完再放回），此时 manifest 只剩 appSmartScale + 键盘样式。
- 首启自检：构造时读 `data/ota/result.*|pending.json`，延迟 3s emit upgradeResult → Main.qml alert 后 resetState()。UI：SettingsDialog 版本更新行 + `OtaUpdateDialog.qml`（NoAutoClose，进度条/取消/立即重启安装/重新下载）。

## 十、AppSettings（QSettings INI）
- 路径 `~/.config/SmartScale/AppSettings.conf`（UserScope, "SmartScale"/"AppSettings"）；QML 名 `AppSettings`。
- 现有项：`priceInputEnabled`(false)、`cellularEnabled`(true)、`wifiEnabled`(true)、`networkAutoSwitch`(true)、`networkMode`(-1)、`weightUnit`(0=kg/1=斤)。新增开关照此模式：Q_PROPERTY + 成员 + setter（写回 QSettings + emit changed）。
- **Qt 坑**：带 `Q_ENUM` 的枚举必须声明在 **public 区**，否则 moc 生成代码报 `... is private within this context`（class 默认 private，写在 `public:` 之前就会踩）。

## 十一、Plymouth 主题（/usr/share/plymouth/themes/pix）
- PNG 加载正常；**让图片消失的真凶**是把 sprite `z` 从 -100 改成 0（该构建 z=0 会被背景盖住），保持负值。
- 黑边=contain 适配；铺满用 cover（缩放条件对调，裁溢出）或 stretch（变形）。运行时直接读目录脚本/PNG，改完下次开机生效无需重建 initramfs；文件属 root 需 sudo。
