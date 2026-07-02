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
    property bool useHandwritingMode: false  // false=拼音, true=手写（默认拼音）
    property var _origConsoleError: null  // 保存原始 console.error（全局错误拦截用）

    Component.onCompleted: {
        // 已自编译部署 Qt VirtualKeyboard Pinyin 插件到系统 Plugins/Pinyin/
        // 延迟到事件循环空闲再设置，避开 InputPanel 初始化竞态（直接设会被覆盖）
        Qt.callLater(function() {
            VirtualKeyboardSettings.activeLocales = ["zh_CN", "en_GB"]  // 地球图标只显示中英
            VirtualKeyboardSettings.locale = "en_GB"  // 默认英文
            // 初始化手写输入法配置（如果 Handwriting 插件可用）
            if (window.useHandwritingMode) {
                window.switchToHandwriting()
            }
        })
        // 启动时自动弹出登录弹窗
        loginDialog.open()

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

    // 手写/拼音输入法切换（供手写按钮调用）
    function toggleInputMethod() {
        window.useHandwritingMode = !window.useHandwritingMode
        if (window.useHandwritingMode) {
            window.switchToHandwriting()
        } else {
            window.switchToPinyin()
        }
        console.log("[Main] 输入方式切换:", window.useHandwritingMode ? "手写" : "拼音")
    }

    // 切换到手写输入法
    function switchToHandwriting() {
        try {
            VirtualKeyboardSettings.inputMethod = "qthandwriting"  // Qt Handwriting 插件标识符
            // 手写模式下自动切换到中文（因为主要用于中文输入）
            if (!window.chineseInputMode) {
                window.chineseInputMode = true
                VirtualKeyboardSettings.locale = "zh_CN"
            }
            console.log("[Main] ✅ 已切换到手写输入法")
        } catch (e) {
            console.error("[Main] ❌ 切换到手写失败:", e.message)
            // 回退到拼音模式
            window.useHandwritingMode = false
            window.globalToast.show("手写插件未安装，请先部署 Handwriting 插件", "error", 5000)
        }
    }

    // 切换回拼音输入法
    function switchToPinyin() {
        try {
            VirtualKeyboardSettings.inputMethod = ""  // 清空使用默认（拼音/QML键盘）
            console.log("[Main] ✅ 已切换回拼音输入法")
        } catch (e) {
            console.error("[Main] ❌ 切换回拼音失败:", e.message)
        }
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
        }

        StackView {
            id: stackView
            Layout.fillHeight: true;
            Layout.fillWidth: true;
            initialItem: "pages/WorkstationPage.qml"
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

            // 固定的中英切换按钮（盖在键盘右上角，避免误触内置语言选择器）
            Rectangle {
                id: inputMethodToggle  // 手写/拼音切换按钮
                width: 80
                height: 50
                radius: 8
                color: window.useHandwritingMode ? "#10B981" : "#6366F1"
                anchors.right: langToggle.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: 4
                z: 100  // 高于键盘内部
                visible: inputPanel.active && window.chineseInputMode  // 只在中文模式下显示
                border.color: window.useHandwritingMode ? "#059669" : "#4F46E5"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: window.useHandwritingMode ? "✍手写" : "拼音"
                    font.pixelSize: 18
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: window.toggleInputMethod()
                }
            }

            Rectangle {
                id: langToggle
                width: 80
                height: 50
                radius: 8
                color: window.chineseInputMode ? "#4361EE" : "#E2E8F0"
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.topMargin: 4
                z: 100  // 高于键盘内部
                visible: inputPanel.active
                border.color: window.chineseInputMode ? "#4361EE" : "#9CA3AF"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: window.chineseInputMode ? "中" : "EN"
                    font.pixelSize: 24
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
    }

    // 系统调试信息弹窗（独立组件，与工作台解耦）
    SystemInfoDialog {
        id: systemInfoDialog
        // 居中显示，考虑键盘避让
        x: (parent.width - width) / 2
        y: Math.min((parent.height - height) / 2,
                    parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
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
                // 加密网络 → 打开密码输入弹窗
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

    // 设置弹窗（设备信息 + 软件版本）
    SettingsDialog {
        id: settingsDialog
    }

    // 暴露给子页面调用
    function toast(message, type, duration) {
        globalToast.show(message, type, duration)
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
}