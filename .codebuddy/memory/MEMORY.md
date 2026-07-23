# SmartScale 长期记忆

> 跨会话稳定约定与硬性规则。冲突时直接更新本文档。

## 编译约束
- 禁止 AI 自行执行 `make`/`cmake --build`；用户自跑 `make -j1`，AI 改完用 `read_lints` 验证语法。

## 运行环境
- 无鼠标光标：`main.cpp` 创建 QGuiApplication 后立即 `QGuiApplication::setOverrideCursor(Qt::BlankCursor)`；QML MouseArea 禁止 `cursorShape`。
- 弹窗输入框禁止自动聚焦（LoginDialog/WifiPasswordDialog 例外打开即输入）：Dialog/Popup 内 TextField `focus:false`，`onOpened` 末尾 `Qt.callLater` 把焦点移到关闭/返回按钮 MouseArea。

## 弹窗与浮层
- Toast/通知根节点用 Popup/Dialog：`modal:false`+`closePolicy:Popup.NoAutoClose`+`padding:0`+透明 background+open/close+转场。
- 弹窗遮罩：`modal:true`+显式 `Overlay.modal: Rectangle{color:"#80000000"}`（LoginDialog 例外保留 modal:false+外部遮罩）。
- CategoryCorrectionDialog 外部遮罩必须 reparent 到 `window.contentItem`（anchors.fill+z:40），不可改 `modal:true`（会遮 InputPanel）。
- 返回按钮标准：back2.png+"返回" 胶囊 116×44 radius:22，图标 22×22，文字 24px bold `#4649E5`；标题 `anchors.centerIn` 绝对居中。

## 数据与类型
- 雪花 ID（ingrId/emsId/cateId/recoId/userId/productId/custId/devId）一律 qint64/QString，禁止 `toInt()`。
- 价格单位统一元/kg：`amount = unitPrice × netWeight(kg)`，`addRecord` 内 `qRound(price*100)/100`。
- 版本号：CMakeLists.txt `project(SmartScale VERSION x.y.z)`，构建号 `cmake -DBUILD_NUMBER=N`（默认9），`version.h.in` → `configure_file` → SystemInfoService.appVersion。

## 网络
- API 域：`API_BASE_URL=https://api.shxgs.cn:5196`，`USER_BASE_URL=https://user.shxgs.cn:5196`；`NetworkUtils::createApiRequest/createUserApiRequest` 统一 json+Bearer+SSL VerifyNone+HTTP/1.1。
- `NetworkManagerService`（QML `App.Backend::NetworkManager`）：nmcli+mmcli，3s 轮询；4G 状态新增 `ip a` 快速路径（`refreshCellularStatusFast`），命令发出后 300/800/1500/2500/4000/6000ms 快速轮询，以「接口有 IPv4 inet 地址 且 管理态 state UP」判定数据激活（避免 LOWER_UP 误匹配），配 `m_fastExpectEnable` 方向标志（开启中无IP保持Searching、关闭中无IP立即Disabled），`onCellularOpFinished` 命令返回即先调快速刷新，解决开关状态刷新慢问题。
- 网络模式：四模式枚举 `WifiOnly/CellularOnly/AllWifiPriority/AllCellularPriority`，默认 `AllCellularPriority`，持久化到 `AppSettings.networkMode`，开机 5s 后恢复。全开模式用 route-metric（优先=10/非优先=300）实现优先级。
- SettingsDialog（设备信息弹窗）功能设置卡片用四个 ToggleSwitch 互斥单选，`syncSwitches()` 显式同步 `checked`；开关用 `onClicked`（不能用 `onToggled`，否则程序赋值会循环回弹）。

## 核心服务行为
- Token 刷新：`AuthService` 全局锁 `m_isRefreshing`+`tokenRefreshCompleted(bool,QString)`；失败>2次建议重登。已接入 WeightHistory/UserIngredient/Category/CameraController。
- 保存流程：`WeightHistoryService.addRecord` DB 写入即上传并立即 `cloudSyncSuccess(newId)` 关 overlay；失败 toast "记录已保存，云端同步失败将自动重试"。
- 系统信息：`SystemInfoService` 读取 `/proc/meminfo` 暴露 `memTotal`（<3GB 显示 "2GB"，否则 "4GB"）。

## QML 工程规范
- 跨目录引用：`pages/` 引 `components/` 用 `import "../components"`。
- Singleton：纯 QML `pragma Singleton`+CMake `QT_QML_SINGLETON_TYPE`；C++ 用 `qmlRegisterSingletonInstance`。
- `AppSettings`（QML 名）：QSettings INI 持久化，`priceInputEnabled` 默认 false，`networkMode` 默认 -1。
- 主题常量集中在 `src/ui/Theme.qml`，禁止硬编码。
- 图片圆角：Qt6 `clip` 不随 radius，用 `MultiEffect` `maskEnabled+maskSource`。
- MultiEffect 阴影标准：`shadowColor "#002A75"`，`shadowOpacity 0.1`，`shadowBlur 1.0`，offset 0。
- 错误提示脱敏：`window.alert()` 智能脱敏 URL 和技术错误；C++ emit 错误禁含技术细节。
- 全局字体 PingFang SC（仅 Regular），main.cpp 内嵌注册。

## 虚拟键盘
- Qt6 官方 `QtQuick.VirtualKeyboard`，`Main.qml` `locale="zh_CN"`；中英切换用键盘自带 ChangeLanguageKey。
- 环境变量：`QT_IM_MODULE=qtvirtualkeyboard`，`QT_VIRTUALKEYBOARD_STYLE=light`。
- 键盘悬浮覆盖：主布局与弹窗一律 `y:(parent.height-height)/2` 居中，不做避让；`mainLayout.anchors.bottom: parent.bottom`。
- 键盘必须在 Overlay 层：`keyboardContainer.parent: Overlay.overlay` + `z: 99999`。
- 自定义 light 样式源文件 `src/ui/vkbdstyle/light/style.qml`，同时拷贝到系统 Qt 路径免重编译生效。
- 样式入口文件名必须 `style.qml`；`keyboardDesignWidth/Height` 必须显式设（2560×800）。
- 键盘大小：`Main.qml InputPanel.scale = 0.62`；背景色 `#E9EEF4`。

## 语音
- `src/hardware/VoiceSpeaker`（QML 名 `VoiceSpeaker`）：已迁移到 sherpa-onnx C API + Matcha 中文模型，进程内合成，QThread 后台合成线程，aplay 播放；对外接口（speak/stop/warmup/isReady/isSpeaking/信号）不变。用 `dlopen(RTLD_LOCAL)` 隔离 onnxruntime 符号冲突。
- 食材语音播报格式：`CameraController::speakPredictedLabel` 把 `speakText` 设为 `！！！<食材中文名>！！！`（前后各 3 个全角感叹号，经 `FoodTranslator` 翻译后由 `m_voiceSpeaker->speak` 播报）。
- TTS 语速：sherpa-onnx 中生成时若 `genCfg.speed > 0`，按 `length_scale = 1/speed` **覆盖**模型配置 `config.model.matcha.length_scale`（后者仅当 speed==0 生效）。当前 `synthesize()` 内 `genCfg.speed = 0.7347f`（在 0.8163 基础上再慢 10%，相对最初 1.0204 累计慢约 28%，对应 length_scale≈1.361），模型 `length_scale` 配置实际被忽略。语速调参改 `genCfg.speed` 即可，`TtsSynthWorker::synthesize` 经 `requestSynthesize` 信号由 `VoiceSpeaker::speak` 触发，未被废弃。
- sherpa-onnx 采样步数：VITS 模型本无 steps 概念（流生成）；Matcha 虽是 Flow 模型有步数，但 sherpa-onnx 的 Python/C 绑定未暴露 `num_steps/steps` 字段（Matcha 配置仅 acoustic_model/vocoder/lexicon/tokens/data_dir/dict_dir/noise_scale/length_scale，VITS 仅 model/lexicon/tokens/data_dir/dict_dir/noise_scale/noise_scale_w/length_scale），步数在库内固定写死，外部无法设为 10/20。要控步数须改 sherpa-onnx C++ 源码或换官方 Matcha 推理。

## 资源编译
- `qt_add_big_resources(RCC_SOURCES app.qrc)` → `target_sources(appSmartScale PRIVATE ${RCC_SOURCES})`。
- 新增图片必须编辑 `app.qrc`；改资源后清 build 重新 `cmake ..`+`make -j1`。
