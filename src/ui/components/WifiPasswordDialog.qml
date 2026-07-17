import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

/**
 * @brief Wi-Fi 密码输入弹窗 — 选中加密网络后弹出
 *
 * 非模态 + 外部遮罩（避让虚拟键盘：modal 层 z 高于 InputPanel(99) 会盖住键盘使灰暗，
 * 改用 modal:false + reparent 到 window.contentItem 的外部遮罩 z:40 < 键盘 99）。
 * y 坐标键盘避让由 Main.qml 实例化处处理。
 */
Popup {
    id: root

    // ---- 对外接口 ----
    signal connectRequested(string ssid, string password)
    property string targetSsid: ""
    property bool showError: false
    property string errorMsg: ""

    function openFor(ssid) {
        targetSsid = ssid
        passwordField.text = ""
        showError = false
        errorMsg = ""
        root.open()
    }

    modal: false
    closePolicy: Popup.CloseOnEscape
    padding: 0
    z: 50

    width: 560
    height: 500

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘 z:99，不挡虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: root.visible

        Behavior on opacity { NumberAnimation { duration: 180 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 120; easing.type: Easing.InCubic }
    }

    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#002A75"
            shadowOpacity: 0.1
            shadowBlur: 1.0
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
    }

    // ========================================================================
    // 内容区
    // ========================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ------ 顶部标题栏 ------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            radius: 16
            color: "#FFFFFF"

            RowLayout {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "\uD83D\uDD11"
                    font.pixelSize: 28
                }

                Text {
                    text: "Wi-Fi 网络要求认证"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextPrimary
                }
            }
        }

        // 分隔线
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            height: 1
            color: "#E2E8F0"
        }

        // ------ 表单区域 ------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 36
            Layout.rightMargin: 36
            Layout.topMargin: 24
            Layout.bottomMargin: 20
            spacing: 18

            // 描述文字
            Text {
                Layout.fillWidth: true
                text: "访问 Wi-Fi 网络 \"" + root.targetSsid + "\" 需要密码或加密密钥。"
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextSecondary
                wrapMode: Text.Wrap
            }

            // 密码输入框
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                Text {
                    text: "密码(P)"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextSecondary
                }

                TextField {
                    id: passwordField
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                    echoMode: showPasswordToggle.checked ? TextInput.Normal : TextInput.Password
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyMono
                    leftPadding: 16
                    rightPadding: 48
                    verticalAlignment: TextInput.AlignVCenter

                    background: Rectangle {
                        radius: 8
                        color: passwordField.activeFocus ? "#FFFFFF" : Theme.colorInputBg
                        border.color: passwordField.activeFocus ? Theme.colorAccent :
                                       (root.showError ? "#EF4444" : Theme.colorInputBorder)
                        border.width: passwordField.activeFocus ? 2 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    // 密码可见性切换按钮（眼睛图标）
                    Rectangle {
                        id: eyeIconBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 8
                        width: 36; height: 36; radius: 18
                        color: showPasswordToggle.checked ? "#E0E7FF" : "transparent"

                        Image {
                            anchors.centerIn: parent
                            source: showPasswordToggle.checked ? "qrc:/resources/icon/eye-fill.png" : "qrc:/resources/icon/eye-close-fill.png"
                            sourceSize: Qt.size(22, 22)
                            cache: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: showPasswordToggle.toggle()
                        }
                    }

                    Keys.onReturnPressed: handleConnect()
                }
            }

            // 显示密码复选框（样式与 LoginDialog 一致：28框/18勾/蓝实底白勾）
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CheckBox {
                    id: showPasswordToggle
                    text: ""
                    implicitWidth: 28
                    implicitHeight: 28

                    indicator: Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        x: showPasswordToggle.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 4
                        color: showPasswordToggle.checked ? "#4361EE" : "#FFFFFF"
                        border.color: showPasswordToggle.checked ? "#4361EE" : "#CBD5E1"
                        border.width: 1.5

                        Text {
                            visible: showPasswordToggle.checked
                            anchors.centerIn: parent
                            text: "\u2713"
                            font.pixelSize: 18
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }

                    contentItem: null
                }

                Text {
                    text: "显示密码(W)"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextSecondary
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: showPasswordToggle.toggle()
                    }
                }
            }

            // 错误提示
            Text {
                visible: root.showError
                text: root.errorMsg
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: "#EF4444"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }

        // ------ 底部按钮栏（参照 SaveConfirmDialog 样式：180×60 r15）------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            Layout.bottomMargin: 24

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 取消按钮（浅蓝底）
                Rectangle {
                    width: 180; height: 60; radius: 15
                    color: cancelMouse.containsMouse ? "#FFFFFF" : "#ECF1FE"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#4649E5"
                    }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.close()
                    }
                }

                // 连接按钮（蓝实底）
                Rectangle {
                    width: 180; height: 60; radius: 15
                    color: connectMouse.containsMouse ? "#4649E5" : "#4361EE"
                    opacity: canConnect && NetworkManager.wifiStatus !== NetworkManager.Connecting ? 1.0 : 0.55
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 8

                        BusyIndicator {
                            running: NetworkManager.wifiStatus === NetworkManager.Connecting
                            width: 24; height: 24
                            visible: running
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NetworkManager.wifiStatus === NetworkManager.Connecting ? "连接中..." : "连接"
                            font.pixelSize: 24
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#FFFFFF"
                        }
                    }

                    MouseArea {
                        id: connectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: canConnect && NetworkManager.wifiStatus !== NetworkManager.Connecting
                        onClicked: handleConnect()
                    }
                }
            }
        }
    }

    // ========================================================================
    // 内部逻辑
    // ========================================================================

    property bool canConnect: passwordField.text.trim().length > 0

    function handleConnect() {
        if (!canConnect) return
        console.log("[WifiPassword] 发起连接:", root.targetSsid)
        root.connectRequested(root.targetSsid, passwordField.text.trim())
    }

    /** 外部调用：显示错误信息 */
    function showErrorMessage(msg) {
        showError = true
        errorMsg = msg
    }

    Connections {
        target: NetworkManager

        function onWifiConnectionFailed(errorMsg) {
            if (root.visible) {
                showErrorMessage(errorMsg)
            }
        }
    }
}
