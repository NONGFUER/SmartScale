import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings
import SmartScale.Hwr 1.0

/**
 * @brief 手写输入法桥接（PP-OCRv5）—— 把自研手写输入法注入 Qt 虚拟键盘
 *
 * 使用方式（Main.qml）：
 *   HandwritingBridge { id: hwrBridge; inputPanel: inputPanel }
 *   hwrBridge.toggle()      // 手写 <-> 键盘 切换
 *
 * 原理：
 *   1. keyboard.setHandwritingMode(true) 让 Qt 加载 handwriting 键盘布局
 *      （大号书写区 TraceInputKey + 退格/回车/标点/切回键盘键）；
 *   2. 本组件的 HandwritingInputMethod 实例被赋给 InputContext.inputEngine.inputMethod，
 *      笔迹事件因此进入 PP-OCRv5 识别链路；
 *   3. 识别结果通过 setPreeditText + 候选栏呈现，点选/下一笔自动落字到当前焦点输入框
 *      —— 因此业务弹窗完全无需改动。
 *
 * 说明：Qt 手写布局自身会通过 createInputMethod() 创建输入法实例，
 *      这里统一覆盖为 PP-OCRv5 版本（无论布局解析到哪个实现都生效）。
 */
Item {
    id: bridge

    /// 由 Main.qml 注入的键盘面板
    property var inputPanel: null

    readonly property var keyboard: inputPanel ? inputPanel.keyboard : null
    /// 是否处于手写模式
    readonly property bool handwritingActive: keyboard ? keyboard.handwritingMode : false
    /// 系统是否支持手写（Qt 编译特性 + 手写布局存在）
    readonly property bool available: keyboard ? keyboard.isHandwritingAvailable() : false

    /// 全屏手写请求（书写区 = 整个屏幕，由 Main.qml 的 HandwritingInputPanel 消费）
    property bool fullScreen: false

    // 输入法实例：跟随 QML 引擎生命周期，避免每次进出手写模式重建（重建会重复加载模型）
    // objectName 用于日志定位（避免只打印 [object Object]）
    HandwritingInputMethod {
        id: handwritingInputMethod
        objectName: "PpocrHandwritingInputMethod"
    }

    Component.onCompleted: {
        // 手写模式开关可能被历史设置持久化为禁用，这里强制打开
        VirtualKeyboardSettings.handwritingModeDisabled = false
        // 诊断：样式来源必须是随程序部署/系统目录里的**含手写样式项**的那份
        console.log("[HWR] 键盘样式:" + VirtualKeyboardSettings.style)
        logEngineState("启动")
    }

    /// 打印引擎状态（诊断"手写区采不到点"这类问题）
    function logEngineState(tag) {
        var engine = InputContext.inputEngine
        var im = engine ? engine.inputMethod : null
        console.log("[HWR][" + tag + "] 手写可用=" + bridge.available
                    + " 手写模式=" + bridge.handwritingActive
                    + " 当前输入法=" + (im ? (im.objectName || String(im)) : "无")
                    + " patternRecognitionModes=" + (engine ? engine.patternRecognitionModes : "n/a"))
    }

    /// 手写 <-> 键盘 切换
    function toggle() {
        if (!keyboard)
            return
        if (keyboard.handwritingMode) {
            keyboard.setHandwritingMode(false)
            console.log("[HWR] 切换回键盘")
        } else {
            keyboard.setHandwritingMode(true)
            console.log("[HWR] 进入手写模式")
            Qt.callLater(ensureInputMethod)
        }
    }

    /// 进入全屏手写（书写区放大到整屏）
    function enterFullScreen() {
        if (!available)
            return
        fullScreen = true
        console.log("[HWR] 进入全屏手写")
        Qt.callLater(ensureInputMethod)
    }

    /// 收起全屏手写：提交未确认的字，回到普通键盘
    function leaveFullScreen() {
        handwritingInputMethod.finishInput()     // 先落字，避免丢掉最后一个未确认的字
        fullScreen = false
        if (keyboard)
            keyboard.setHandwritingMode(false)
        console.log("[HWR] 退出全屏手写")
    }

    /// 确保引擎使用 PP-OCRv5 手写输入法
    function ensureInputMethod() {
        if (!handwritingActive)
            return
        var engine = InputContext.inputEngine
        if (!engine)
            return
        if (engine.inputMethod !== handwritingInputMethod) {
            engine.inputMethod = handwritingInputMethod
            logEngineState("注入输入法")
            if (engine.patternRecognitionModes.indexOf(InputEngine.PatternRecognitionMode.Handwriting) === -1) {
                console.warn("[HWR] 当前输入法不支持 Handwriting -> 手写区将采集不到笔迹")
            }
        }
    }

    Connections {
        target: bridge.keyboard
        function onHandwritingModeChanged() {
            if (bridge.handwritingActive) {
                Qt.callLater(bridge.ensureInputMethod)
            } else {
                // 退出（含手写布局里的"键盘"键、切语言等）：引擎切走输入法时不会通知旧输入法，
                // 这里主动提交未确认的预编辑文本，避免丢掉最后写的一个字
                handwritingInputMethod.finishInput()
                bridge.fullScreen = false
            }
        }
    }

    Connections {
        target: InputContext.inputEngine
        function onInputMethodChanged() {
            if (bridge.handwritingActive)
                Qt.callLater(bridge.ensureInputMethod)
        }
        function onPatternRecognitionModesChanged() {
            if (bridge.handwritingActive)
                Qt.callLater(bridge.ensureInputMethod)
        }
    }
}
