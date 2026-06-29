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

    property bool chineseInputMode: true  // true=拼音中文, false=纯英文

    Component.onCompleted: {
        // 已自编译部署 Qt VirtualKeyboard Pinyin 插件到系统 Plugins/Pinyin/
        // 延迟到事件循环空闲再设置，避开 InputPanel 初始化竞态（直接设会被覆盖）
        Qt.callLater(function() {
            VirtualKeyboardSettings.activeLocales = ["zh_CN", "en_GB"]  // 地球图标只显示中英
            VirtualKeyboardSettings.locale = "zh_CN"  // 默认中文拼音
        })
        // 启动时自动弹出登录弹窗
        loginDialog.open()
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
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: inputPanel.active ? inputPanel.top : parent.bottom
        spacing: 0

        StatusBar{
            id: statusBar
            Layout.fillWidth: true
        }

        Connections {
            target: statusBar
            function onSettingsRequested() {
                console.log("[Main] 收到设置请求，跳转设置页")
                stackView.push("pages/SettingsPage.qml")
            }
        }

        StackView {
            id: stackView
            Layout.fillHeight: true;
            Layout.fillWidth: true;
            initialItem: "pages/WorkstationPage.qml"
        }
    }

    // 在 StackView 下方添加键盘面板
    InputPanel {
        id: inputPanel
        z: 99
        y: parent.height
        anchors.left: parent.left
        anchors.right: parent.right

        // 固定的中英切换按钮（盖在键盘右上角，避免误触内置语言选择器）
        Rectangle {
            id: langToggle
            width: 60
            height: 36
            radius: 6
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
                font.pixelSize: 18
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
                y: parent.height - inputPanel.height // 弹出
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