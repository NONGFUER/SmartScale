import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale

/**
 * @brief Wi-Fi 密码输入弹窗 — 选中加密网络后弹出
 *
 * 使用方式：
 *   WifiPasswordDialog {
 *       id: pwdDialog
 *       onConnectRequested: function(ssid, password) {
 *           NetworkManager.connectWifi(ssid, password)
 *           pwdDialog.close()
 *       }
 *   }
 *   pwdDialog.openFor("MyWiFi")
 */
Popup {
    id: root

    // ---- 对外接口 ----
    /** 用户点击「连接」后触发，携带 SSID 和密码 */
    signal connectRequested(string ssid, string password)

    /** 目标网络 SSID（外部设置） */
    property string targetSsid: ""

    /** 设置目标并打开弹窗 */
    function openFor(ssid) {
        targetSsid = ssid
        passwordField.text = ""
        showError = false
        errorMsg = ""
        root.open()
    }

    /** 内部错误显示控制 */
    property bool showError: false
    property string errorMsg: ""

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape
    padding: 0

    width: 440
    height: 300

    // 进入/退出动画
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 120; easing.type: Easing.InCubic }
    }

    // ========================================================================
    // 主体背景
    // ========================================================================
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        Rectangle {
            width: 6
            height: parent.height
            radius: 12
            color: "#F59E0B"  // 橙色边条表示需要认证
            anchors.left: parent.left
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
            id: topBar
            Layout.fillWidth: true
            height: 54
            radius: 12
            color: "#1A5CB5"

            layer.enabled: true
            layer.effect: Item {
                Rectangle {
                    anchors.fill: parent
                    color: "#1A5CB5"
                    radius: 12
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.radius
                        color: parent.color
                    }
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 8

                // 锁图标
                Text {
                    text: "\uD83D\uDD11"
                    font.pixelSize: 22
                }

                Text {
                    text: "Wi-Fi 网络要求认证"
                    font.pixelSize: 17
                    font.bold: true
                    color: "#FFFFFF"
                }
            }
        }

        // ------ 表单区域 ------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.topMargin: 24
            Layout.bottomMargin: 16
            spacing: 16

            // 描述文字
            Text {
                Layout.fillWidth: true
                text: "访问 Wi-Fi 网络 \"" + root.targetSsid + "\" 需要密码或加密密钥。"
                font.pixelSize: Theme.fontSizeBodySm
                color: Theme.colorTextSecondary
                wrapMode: Text.Wrap
            }

            // 密码输入框
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "密码(P)"
                    font.pixelSize: Theme.fontSizeCaption
                    color: Theme.colorTextSecondary
                }

                    TextField {
                        id: passwordField
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        echoMode: showPasswordToggle.checked ? TextInput.Normal : TextInput.Password
                        font.pixelSize: Theme.fontSizeBodySm
                        font.family: Theme.fontFamilyMono
                        leftPadding: 12
                        rightPadding: 36
                        verticalAlignment: TextInput.AlignVCenter

                        background: Rectangle {
                            radius: 6
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
                            width: 28; height: 28; radius: 14
                            color: showPasswordToggle.checked ? "#E0E7FF" : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: showPasswordToggle.checked ? "\U0001F441" : "\U0001F576\uFE0F"
                                font.pixelSize: 15
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: showPasswordToggle.toggle()
                            }
                        }

                        Keys.onReturnPressed: handleConnect()
                    }
            }

            // 显示密码复选框（独立一行）
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                CheckBox {
                    id: showPasswordToggle
                    text: ""
                    implicitWidth: 22
                    implicitHeight: 22

                    indicator: Rectangle {
                        implicitWidth: 18
                        implicitHeight: 18
                        x: showPasswordToggle.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 3
                        color: showPasswordToggle.checked ? "#E0E7FF" : "#FFFFFF"
                        border.color: showPasswordToggle.checked ? "#6366F1" : "#D1D5DB"
                        border.width: 1.5

                        Text {
                            visible: showPasswordToggle.checked
                            anchors.centerIn: parent
                            text: "\u2713"
                            font.pixelSize: 12
                            font.bold: true
                            color: "#6366F1"
                        }
                    }

                    contentItem: null
                }

                Text {
                    text: "显示密码(W)"
                    font.pixelSize: Theme.fontSizeCaption
                    color: Theme.colorTextSecondary

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
                font.pixelSize: Theme.fontSizeCaption
                color: "#EF4444"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }

        // ------ 底部按钮栏 ------
        Rectangle {
            Layout.fillWidth: true
            height: 60
            color: "#F8FAFC"

            RowLayout {
                anchors.centerIn: parent
                spacing: 16

                // 取消按钮
                Rectangle {
                    width: 100; height: 36; radius: 8
                    color: cancelMouse.containsMouse ? "#F1F5F9" : "#FFFFFF"
                    border.color: "#D1D5DB"
                    border.width: 1

                    Text { anchors.centerIn: parent; text: "取消(C)"; font.pixelSize: 14; color: "#64748B" }

                    MouseArea {
                        id: cancelMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.close()
                    }
                }

                // 连接按钮
                Rectangle {
                    width: 120; height: 36; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: connectMouse.pressed ? "#2563EB" : (connectMouse.containsMouse ? "#4C72F9" : "#3B82F6") }
                        GradientStop { position: 1.0; color: connectMouse.pressed ? "#1D4ED8" : (connectMouse.containsMouse ? "#4BC8F6" : "#2563EB") }
                    }
                    opacity: canConnect ? 1.0 : 0.55

                    Behavior on scale { NumberAnimation { duration: 120 } }
                    scale: connectMouse.containsMouse && canConnect ? 1.02 : 1.0

                    Row {
                        anchors.centerIn: parent
                        spacing: 6

                        BusyIndicator {
                            running: NetworkManager.wifiStatus === NetworkManager.Connecting
                            width: 16; height: 16
                            visible: running
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NetworkManager.wifiStatus === NetworkManager.Connecting ? "连接中..." : "连接(O)"
                            font.pixelSize: 14
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }

                    MouseArea {
                        id: connectMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: canConnect &&
                                 NetworkManager.wifiStatus !== NetworkManager.Connecting
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
