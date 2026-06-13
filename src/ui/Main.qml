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

    Component.onCompleted: {
        VirtualKeyboard.locale = "zh_CN"
        VirtualKeyboard.availableLocales = ["zh_CN", "en_GB"]
        VirtualKeyboard.inputMethodHints = Qt.ImhNoAutoUppercase
        // 启动时自动弹出登录弹窗
        loginDialog.open()
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
}