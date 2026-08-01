import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

/**
 * OtaDownloadConfirmDialog — OTA 下载更新确认弹窗（需输入密码）
 *
 * 触发条件：点击设置页“立即下载”按钮后弹出
 * 必须输入固定下载密码并校验通过，才能触发下载
 * 样式参考 WifiPasswordDialog.qml（密码输入框 + 显示密码开关）
 */
Dialog {
    id: root

    // ===== 常量 =====
    readonly property string fixedPassword: "20210903"  // 固定下载密码（8 位）

    // ===== 对外属性 =====
    property string versionText: ""   // 待更新版本文本，如 “发现新版本 v2.13.3”

    // ===== 信号 =====
    signal downloadConfirmed()        // 用户点击“立即下载”且密码正确
    signal cancelled()                // 用户点击“取消”

    // ===== 接口 =====
    function openDialog(verText: string) {
        root.versionText = verText
        passwordField.text = ""
        showPwdToggle.checked = true   // 默认显示密码（按需求“显示密码”）
        showError = false
        errorMsg = ""
        root.open()
    }

    // 密码错误提示
    property bool showError: false
    property string errorMsg: ""

    onOpened: {
        // 把焦点移到密码框，方便直接输入（无自动聚焦禁用场景，本弹窗允许输入）
        Qt.callLater(function() { passwordField.forceActiveFocus() })
    }

    // Dialog 基础配置（非模态 + 外部遮罩，避让虚拟键盘，风格同 SaveConfirmDialog）
    modal: false
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2 - 40 // 居中（键盘悬浮覆盖，不做避让）
    width: 600
    height: 420
    padding: 0
    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E5E7EB"
        border.width: 1

        // 阴影效果
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.15
            shadowBlur: 0.6
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
        }
    }

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘，避让虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: root.visible
        MouseArea {
            anchors.fill: parent
            onClicked: { root.cancelled(); root.close() }  // 点击外部关闭
        }
    }

    enter: Transition {
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
    }
    exit: Transition {
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150 }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ========== 头部：返回按钮 + 居中标题 ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 76

            // 返回按钮 — back2.png + “返回”（圆角胶囊 + 浅底边框），风格同 SettingsDialog
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: 116; height: 44; radius: 22

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/resources/img/back2.png"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "返回"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#4649E5"
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { root.cancelled(); root.close() }
                }
            }

            // 标题绝对居中（不受左侧返回按钮宽度影响）
            Text {
                anchors.centerIn: parent
                text: "下载更新"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
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

        // ========== 内容区 ==========
        // Item {
        //     Layout.fillWidth: true
        //     Layout.fillHeight: true
        //     Layout.margins: 32
        //     Layout.topMargin: 28
        //     Layout.bottomMargin: 20

        //     ColumnLayout {
        //         anchors.fill: parent
        //         spacing: 16
        //     }
        // }

        // ========== 提示信息（居中、显眼） ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            Layout.topMargin: 12

            Text {
                anchors.centerIn: parent
                text: "是否立即下载最新版本进行更新？"
                font.pixelSize: 26
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
                width: 500
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
        }

        // ========== 密码输入框（样式参考 WifiPasswordDialog） ==========
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 48
            Layout.rightMargin: 48
            Layout.bottomMargin: 8
            spacing: 10

            Text {
                text: "下载密码(P)"
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: "#64748B"
            }

            TextField {
                id: passwordField
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase | Qt.ImhNoPredictiveText
                echoMode: showPwdToggle.checked ? TextInput.Normal : TextInput.Password
                font.pixelSize: 24
                font.family: Theme.fontFamilyMono
                leftPadding: 16
                rightPadding: 48
                verticalAlignment: TextInput.AlignVCenter
                placeholderText: "请输入下载密码"
                maximumLength: 16

                background: Rectangle {
                    radius: 8
                    color: passwordField.activeFocus ? "#FFFFFF" : "#F8FAFC"
                    border.color: passwordField.activeFocus ? "#4361EE"
                                                     : (root.showError ? "#EF4444" : "#E2E8F0")
                    border.width: passwordField.activeFocus ? 2 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                // 眼睛图标（切换显示/隐藏密码）
                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 8
                    width: 36; height: 36; radius: 18
                    color: showPwdToggle.checked ? "#E0E7FF" : "transparent"

                    Image {
                        anchors.centerIn: parent
                        source: showPwdToggle.checked ? "qrc:/resources/icon/eye-fill.png" : "qrc:/resources/icon/eye-close-fill.png"
                        sourceSize: Qt.size(22, 22)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: showPwdToggle.toggle()
                    }
                }

                Keys.onReturnPressed: handleConfirm()
            }

            // 显示密码复选框（28框/18勾/蓝实底白勾，与 WifiPasswordDialog 一致）
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CheckBox {
                    id: showPwdToggle
                    text: ""
                    implicitWidth: 28
                    implicitHeight: 28
                    checked: true

                    indicator: Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        x: showPwdToggle.leftPadding
                        y: parent.height / 2 - height / 2
                        radius: 4
                        color: showPwdToggle.checked ? "#4361EE" : "#FFFFFF"
                        border.color: showPwdToggle.checked ? "#4361EE" : "#CBD5E1"
                        border.width: 1.5

                        Text {
                            visible: showPwdToggle.checked
                            anchors.centerIn: parent
                            text: "✓"
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
                    color: "#64748B"
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: showPwdToggle.toggle()
                    }
                }
            }

            // 错误提示
            Text {
                visible: root.showError
                text: root.errorMsg
                font.pixelSize: 22
                font.family: Theme.fontFamilyUi
                color: "#EF4444"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
            }
        }

        // 占位撑开
        Item { Layout.fillHeight: true }

        // 分隔线
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            height: 1
            color: "#E2E8F0"
        }

        // ========== 按钮区 ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 96

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 取消按钮
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15
                    color: cancelMA.containsMouse ? "#FFFFFF" : "#ECF1FE"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#4649E5"
                    }

                    MouseArea {
                        id: cancelMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.cancelled()
                            root.close()
                        }
                    }
                }

                // 立即下载按钮
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15

                    color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"

                    Text {
                        anchors.centerIn: parent
                        text: "立即下载"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        id: confirmMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: handleConfirm()
                    }
                }
            } // RowLayout
        } // 按钮区 Item
    } // ColumnLayout

    // ===== 内部逻辑 =====
    function handleConfirm() {
        var input = passwordField.text.trim()
        if (input.length === 0) {
            root.showError = true
            root.errorMsg = "请输入下载密码"
            return
        }
        if (input !== root.fixedPassword) {
            root.showError = true
            root.errorMsg = "下载密码错误，请重新输入"
            passwordField.text = ""
            Qt.callLater(function() { passwordField.forceActiveFocus() })
            return
        }
        root.showError = false
        root.downloadConfirmed()
        root.close()
    }
}
