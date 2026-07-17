import QtQuick
import QtQuick.Controls
import App.Backend 1.0
import "components"
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Settings
import QtQuick.Layouts
ApplicationWindow {

    id: window
    width: 1920
    height: 1080
    visible: true
    title: "AI秤"
    visibility: Window.FullScreen

    // 安全退出登录：重新弹出登录弹窗
    function appLogout() {
        BackendAuth.logout()
        loginDialog.open()
    }

    // 打开登录弹窗（供子页面调用）
    function showLogin() {
        loginDialog.open()
    }

    property bool chineseInputMode: false  // true=拼音中文, false=纯英文（默认英文）
    property var _origConsoleError: null  // 保存原始 console.error（全局错误拦截用）
    property bool _pendingAutoLogin: false  // 等待 SN 就绪后再自动登录的标志

    // 自动登录协调：SN 由串口异步读回，必须等其就绪再登录，
    // 否则带空 SN 的请求会被服务端拒绝（"登录的设备sn非法"）
    function tryAutoLogin() {
        if (!BackendAuth.hasSavedLogin) {
            loginDialog.open()
            return
        }
        if (BackendAuth.deviceSn !== "") {
            console.log("[Main] SN 已就绪，自动登录...")
            BackendAuth.autoLogin()
        } else {
            console.log("[Main] 等待设备 SN 读回后再自动登录...")
            _pendingAutoLogin = true
            autoLoginSnTimer.start()
        }
    }

    Component.onCompleted: {
        // 已自编译部署 Qt VirtualKeyboard Pinyin 插件到系统 Plugins/Pinyin/
        // 延迟到事件循环空闲再设置，避开 InputPanel 初始化竞态（直接设会被覆盖）
        Qt.callLater(function() {
            VirtualKeyboardSettings.activeLocales = ["zh_CN", "en_GB"]  // 地球图标只显示中英
            VirtualKeyboardSettings.locale = "en_GB"  // 默认英文
            VirtualKeyboardSettings.inputMethod = ""  // 确保默认拼音输入法（清手写残留，避免候选词失效）
        })
        // 预热语音合成：后台加载 piper 模型到 OS page cache，避免首次语音播报延迟
        VoiceSpeaker.warmup()
        // 启动时检查是否有记住的登录信息
        // 注意：SN 由串口异步读回，自动登录必须等 SN 就绪，
        // 否则带空 SN 的请求会被服务端拒绝（"登录的设备sn非法"）
        if (BackendAuth.hasSavedLogin) {
            window.tryAutoLogin()
        } else {
            // 无保存信息，弹出登录弹窗
            loginDialog.open()
        }

        // 监听自动登录失败事件，回退到手动登录弹窗
        __autoLoginFailedConnection.target = BackendAuth

        // ===== 全局 QML JS 错误拦截 =====
        _origConsoleError = console.error
        console.error = function() {
            _origConsoleError.apply(console, arguments)
            var msg = ""
            for (var i = 0; i < arguments.length; i++) {
                if (i > 0) msg += " "
                msg += String(arguments[i])
            }
            if (msg.indexOf("Error:") >= 0 ||
                msg.indexOf("error") >= 0 ||
                msg.indexOf("TypeError") >= 0 ||
                msg.indexOf("ReferenceError") >= 0 ||
                msg.indexOf("Warning:") >= 0) {
                Qt.callLater(function() {
                    if (typeof globalToast !== 'undefined') {
                        globalToast.show("[QML Error] " + msg.substring(0, 200), "error", 10000)
                    }
                })
            }
        }
        console.log("[Main] ✅ 全局 QML 错误拦截已安装 — 任何 QML/JS 错误都会显示为 Toast")
    }

    // ===== 全局 QML 错误捕获 =====
    // 捕获所有 QML JavaScript 运行时错误，输出完整堆栈到控制台 + 全局 Toast
    // 用于定位"断网后页面崩溃"等难以复现的 QML 引擎异常
    Component.onDestruction: {
        if (qmlGlobalErrorHandler) qmlGlobalErrorHandler.disconnect()
    }
    Connections {
        id: qmlGlobalErrorHandler
        target: window  // ApplicationWindow 自身

        // 捕获所有未处理的 QML JS 异常
        function onWidthChanged() {}  // dummy，确保 Connections 活跃

        // 注意：Qt6 没有 ApplicationWindow 级别的统一 error 信号，
        // 改用 Qt.objectCreated + Console.category 机制
    }

    // 方案：监控 mainLayout 可见性 + 拦截 console.error 并弹 Toast
    Timer {
        id: errorMonitorTimer
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            // 监控 mainLayout 是否意外消失（用于诊断+自动恢复"断网后白屏"）
            if (mainLayout && !mainLayout.visible) {
                console.warn("[QML-DEBUG] ⚠️ mainLayout.visible=false! 强制恢复可见")
                mainLayout.visible = true
                if (typeof globalToast !== 'undefined')
                    globalToast.show("已恢复布局可见性 (wifi=" + NetworkManager.wifiStatus + ")", "warning", 3000)
            }
        }
    }

    // 中英输入切换（供键盘右上角按钮调用）
    function toggleInputMode() {
        window.chineseInputMode = !window.chineseInputMode
        VirtualKeyboardSettings.locale = window.chineseInputMode ? "zh_CN" : "en_GB"
        console.log("[Main] 输入法切换:", window.chineseInputMode ? "中文拼音" : "英文")
    }


    // ===== 全屏背景图 =====
    Image {
        id: globalBg
        anchors.fill: parent
        source: "qrc:/resources/img/workstation_bg.png"
        fillMode: Image.PreserveAspectCrop
        z: -1
        onStatusChanged: console.log("[Main] bgImage status:", status, "source:", source)
    }

    // 页面栈路由器
    ColumnLayout {
        id:mainLayout
        visible: true  // ★ 防御性绑定：WiFi 断开时 QML 引擎会异常将此设为 false
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputPanel.active ? keyboardContainer.top : parent.bottom
        spacing: 0

        onVisibleChanged: {
            console.log("[QML-DEBUG] 📍 mainLayout.visible 变化:", visible,
                        "调用堆栈:", new Error().stack)
            if (!visible) {
                console.warn("[QML-DEBUG] ⚠️ 检测到 mainLayout 被设为不可见！强制恢复...")
                visible = true
            }
        }

        StatusBar{
            id: statusBar
            Layout.fillWidth: true
        }

        Connections {
            target: statusBar
            function onSettingsRequested() {
                console.log("[Main] 收到设置请求，打开设置弹窗")
                settingsDialog.open()
            }
            function onUserAreaClicked() {
                console.log("[Main] 用户区域点击，弹出退出登录确认")
                logoutConfirmDialog.open()
            }
            function onLoginRequested() {
                console.log("[Main] 用户区域点击（未登录），打开登录弹窗")
                loginDialog.open()
            }
        }

        StackView {
            id: stackView
            Layout.fillHeight: true;
            Layout.fillWidth: true;
            initialItem: "pages/WorkstationPage.qml"
        }

        BottomStatusBar {
            id: bottomStatusBar
            Layout.fillWidth: true
        }
    }

    // 在 StackView 下方添加键盘面板（包裹容器：裁剪缩放后多余区域）
    Rectangle {
        id: keyboardContainer
        z: 99
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: inputPanel.active ? inputPanel.height * inputPanel.scale : 0
        clip: true   // 裁剪掉缩小后顶部空白
        color: "#1E1E2E"  // 与键盘深色背景一致，遮住露出的蓝色

        InputPanel {
            id: inputPanel
            y: 0
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            scale: 0.82
            transformOrigin: Item.Bottom

            // 中英切换按钮（盖在键盘右上角，避免误触内置语言选择器）
            Rectangle {
                id: langToggle
                width: 100
                height: 60
                radius: 12
                color: window.chineseInputMode ? "#4361EE" : "#E2E8F0"
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.top: parent.top
                anchors.topMargin: 4
                z: 100  // 高于键盘内部
                visible: inputPanel.active
                border.color: window.chineseInputMode ? "#4361EE" : "#9CA3AF"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: window.chineseInputMode ? "中" : "EN"
                    font.pixelSize: 32
                    font.bold: true
                    color: window.chineseInputMode ? "white" : "#1B263B"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: window.toggleInputMode()
                }
            }
            
            states: State {
                name: "visible"
                when: inputPanel.active
                PropertyChanges {
                    target: inputPanel
                    y: parent.height - inputPanel.height // 弹出（相对于容器）
                }
            }
            transitions: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: 250
                    easing.type: Easing.InOutQuad
                }
            }
        }
    }
    //Shortcut
    Shortcut{
        sequence: "Escape"
        enabled: true
        context: Qt.ApplicationShortcut
        onActivated: Qt.quit()
    }

    // 登录弹窗遮罩层（放在弹窗外、键盘下，避免遮挡输入）
    Rectangle {
        id: loginOverlay
        anchors.fill: parent
        color: "#0D1B2A"
        opacity: loginDialog.visible ? 0.5 : 0
        visible: opacity > 0
        z: 40  // 低于 loginDialog(z:50)，远低于键盘(z:99)

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: loginDialog.onOverlayClicked()
        }
    }

    // 登录弹窗（启动自动弹出，退出登录时重新弹出）
    LoginDialog {
        id: loginDialog
        // Popup 不支持 anchors，用 x/y 手动居中 + 键盘避让
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))

        // 自动登录失败时打开登录弹窗让用户手动输入
        Connections {
            id: __autoLoginFailedConnection
            target: null  // 启用时由 Component.onCompleted 设置 target

            function onLoginFailed(errorMsg) {
                // 仅在自动登录场景下触发（此时弹窗未打开）
                if (!loginDialog.visible && BackendAuth.hasSavedLogin) {
                    console.log("[Main] 自动登录失败，打开登录弹窗:", errorMsg)
                    Qt.callLater(function() { loginDialog.open() })
                }
            }
        }

        // SN 异步读回后，若正处于等待状态则立即补发自动登录
        Connections {
            target: BackendAuth
            function onDeviceSnChanged() {
                if (window._pendingAutoLogin && BackendAuth.deviceSn !== "") {
                    window._pendingAutoLogin = false
                    autoLoginSnTimer.stop()
                    console.log("[Main] SN 就绪，补发自动登录...")
                    BackendAuth.autoLogin()
                }
            }
        }
    }

    // SN 等待超时兜底：串口读不回 SN 时转手动登录，避免一直卡在等待
    Timer {
        id: autoLoginSnTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (window._pendingAutoLogin) {
                window._pendingAutoLogin = false
                console.log("[Main] 等待 SN 超时（3s），转手动登录")
                loginDialog.open()
            }
        }
    }

    // 系统调试信息弹窗（独立组件，与工作台解耦）
    SystemInfoDialog {
        id: systemInfoDialog
        // 居中显示，考虑键盘避让
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    }

    // 退出登录确认弹窗
    LogoutConfirmDialog {
        id: logoutConfirmDialog
        onLogoutConfirmed: window.appLogout()
    }

    // Wi-Fi 网络列表弹窗
    WifiListDialog {
        id: wifiListDialog
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))

        onNetworkSelected: function(ssid, secured) {
            console.log("[Main] 选中网络:", ssid, "加密:", secured)
            if (secured) {
            // 加密网络 → 关闭列表，打开密码输入弹窗
            wifiListDialog.close()
            wifiPasswordDialog.openFor(ssid)
            } else {
                // 开放网络 → 直接连接
                NetworkManager.connectWifi(ssid, "")
            }
        }
    }

    // Wi-Fi 密码输入弹窗
    WifiPasswordDialog {
        id: wifiPasswordDialog
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))

        onConnectRequested: function(ssid, password) {
            NetworkManager.connectWifi(ssid, password)
        }
    }

    // 4G 移动数据控制弹窗
    CellularDialog {
        id: cellularDialog
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    }

    // 连接 StatusBar 调试信号 -> 弹窗打开
    Connections {
        target: statusBar
        function onDebugRequested() {
            console.log("[Main] 收到调试请求，打开系统信息弹窗")
            systemInfoDialog.open()
        }
    }

    // 连接 StatusBar 网络图标信号 -> 打开网络列表弹窗（统一入口）
    Connections {
        target: statusBar
        function onNetworkRequested() {
            console.log("[Main] 收到网络请求，打开 Wi-Fi 列表弹窗")
            wifiListDialog.open()
        }
    }

    // Wi-Fi 连接结果处理（全局：关闭弹窗 + Toast 提示）
    Connections {
        target: NetworkManager

        function onWifiConnectionSuccess(ssid) {
            console.log("[Main] Wi-Fi 连接成功:", ssid)

            // 关闭所有 WiFi 相关弹窗
            wifiPasswordDialog.close()
            wifiListDialog.close()

            // 显示成功提示
            window.toast("已成功连接到 " + ssid, "success")
        }

        function onWifiConnectionFailed(errorMsg) {
            console.log("[Main] Wi-Fi 连接失败:", errorMsg)

            // 如果密码弹窗已经关闭了，用全局 Toast 报错
            // （密码弹窗内部也会显示错误信息）
            if (!wifiPasswordDialog.visible) {
                window.toast("连接失败: " + errorMsg, "error", 4000)
            }
        }
    }

    // 全局 Toast 提示组件（成功/失败/警告/信息），所有页面共享
    // 调用方式：mainWindow.toast.show("保存成功") / .show("保存失败", "error")
    Toast {
        id: globalToast
        z: 9999
    }

    // 全局 Alert 弹窗（重要错误/确认，需用户手动关闭）
    // 调用方式：window.alert("网络连接失败", "error", "错误标题", "详细错误信息")
    //          window.confirm("确定删除？", function() { /* 确认回调 */ }, "确认")
    AlertDialog {
        id: globalAlert
        z: 9998  // 低于 Toast(9999)
    }

    // 设置弹窗（设备信息 + 软件版本）
    SettingsDialog {
        id: settingsDialog
    }

    // 暴露给子页面调用
    function toast(message, type, duration) {
        globalToast.show(message, type, duration)
    }

    /**
     * 全局 Alert 弹窗 — 用于重要错误/信息提示（需用户手动关闭）
     * @param message  正文消息
     * @param type     "error"|"warning"|"success"|"info"（默认 "info"）
     * @param title    标题（可选）
     * @param detail   详细信息（可选，支持展开/收起）
     *
     * 智能脱敏：若 message 含底层技术错误特征（reply->errorString / HTTP / SSL 等）
     * 且调用方未单独传 detail，则自动将原始信息移入 detail（默认收起），
     * message 改用基于 title 的友好提示；业务友好提示（如"未登录"、"名称已存在"）原样保留。
     */
    function alert(message, type, title, detail) {
        // 脱敏：隐藏网络错误中的接口地址（避免暴露域名/端口/路径给用户）
        var sanitized = message ? message.replace(/https?:\/\/[^\s]+/g, "<接口地址>") : ""
        if (detail) detail = detail.replace(/https?:\/\/[^\s]+/g, "<接口地址>")

        // 技术错误特征检测：命中则将原始信息移入 detail，message 改用友好提示
        var techPatterns = ["Error transferring", "server replied", "QNetworkReply",
                            "Host ", "Connection ", "timeout", "HTTP ", "SSL",
                            "网络请求失败", "JSON 解析失败", "数据解析失败"]
        if (!detail && sanitized) {
            for (var i = 0; i < techPatterns.length; i++) {
                if (sanitized.indexOf(techPatterns[i]) >= 0) {
                    detail = sanitized
                    sanitized = title ? title + "，请稍后重试" : "操作失败，请稍后重试"
                    break
                }
            }
        }

        globalAlert.show(sanitized, type, title, detail)
    }

    /**
     * 全局 Confirm 弹窗 — 双按钮确认对话框
     * @param message      正文消息
     * @param onConfirm    确认回调函数
     * @param title        标题（可选）
     * @param cancelText   取消按钮文字（可选，默认 "取消"）
     * @param actionText   确认按钮文字（可选，默认 "确定"）
     */
    function confirm(message, onConfirm, title, cancelText, actionText) {
        globalAlert.confirm(message, onConfirm, title, cancelText, actionText)
    }

    // 打开 Wi-Fi 列表弹窗（供 SettingsPage 等子页面调用）
    function openWifiDialog() {
        console.log("[Main] openWifiDialog()")
        wifiListDialog.open()
    }

    // 打开 4G 移动数据控制弹窗（供 SettingsPage 等子页面调用）
    function openCellularDialog() {
        console.log("[Main] openCellularDialog()")
        cellularDialog.open()
    }

    // ============================================================
    //  全局错误信号集中处理 — C++ 服务层 → window.alert()
    //  注意: LoginDialog/LoginPage 的 loginFailed 保持各自内联处理
    //        (表单上下文的内联错误提示比弹窗更直观)
    // ============================================================

    // --- AuthService: Token 刷新失败 ---
    Connections {
        target: BackendAuth
        function onTokenRefreshFailed(errorMsg) {
            console.warn("[GlobalAlert] Token 刷新失败:", errorMsg)
            window.alert(errorMsg, "error", "认证失败", errorMsg)
        }
    }

    // --- UserIngredientService: 创建/获取食材失败 ---
    Connections {
        target: UserIngredientService
        function onCreateFailed(errorMsg) {
            console.warn("[GlobalAlert] 创建食材失败:", errorMsg)
            // AddIngredientDialog 也监听此信号做 UI 反馈，此处仅兜底弹窗
            if (!addIngredientDialog || !addIngredientDialog.visible) {
                window.alert(errorMsg, "error", "创建食材失败")
            }
        }
        function onFetchFailed(errorMsg) {
            console.warn("[GlobalAlert] 获取食材列表失败:", errorMsg)
            window.alert(errorMsg, "warning", "获取数据失败")
        }
    }

    // --- CategoryService: 获取分类失败 ---
    Connections {
        target: CategoryService
        function onFetchFailed(errorMsg) {
            console.warn("[GlobalAlert] 获取分类列表失败:", errorMsg)
            window.alert(errorMsg, "warning", "获取分类失败")
        }
    }
}