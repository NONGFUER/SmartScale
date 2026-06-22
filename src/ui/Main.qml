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

    Component.onCompleted: {
        VirtualKeyboard.locale = "zh_CN"
        VirtualKeyboard.availableLocales = ["zh_CN", "en_GB"]
        VirtualKeyboard.inputMethodHints = Qt.ImhNoAutoUppercase
        // 启动时自动弹出登录弹窗
        loginDialog.open()
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

    // 连接 StatusBar 调试信号 -> 弹窗打开
    Connections {
        target: statusBar
        function onDebugRequested() {
            console.log("[Main] 收到调试请求，打开系统信息弹窗")
            systemInfoDialog.open()
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
}