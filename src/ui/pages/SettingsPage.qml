import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root
    anchors.fill: parent

    // 蓝色渐变背景（与整体风格一致）
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1A5CB5" }
            GradientStop { position: 1.0; color: "#4A90D9" }
        }
    }

    // 主内容卡片（白色圆角）
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.85, 900)
        height: Math.min(parent.height * 0.88, 780)
        radius: 24
        color: "#FFFFFF"

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 20
            shadowOpacity: 0.15
            shadowVerticalOffset: 6
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 40
            spacing: 0

            // ===== 标题栏：返回 + 设置标题 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 30
                spacing: 0

                // 返回按钮
                Rectangle {
                    width: 36; height: 36; radius: 8
                    color: backMouse.containsMouse ? "#F0F4F8" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2039"
                        font.pixelSize: 28
                        font.bold: true
                        color: "#333333"
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: stackView.pop()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "设置"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#1B263B"
                }

                Item { Layout.fillWidth: true }
                Item { width: 36 } // 占位，与返回按钮对称
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 28
                height: 1
                color: "#E5E7EB"
            }

            // ===== 设置项列表 =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // --- 秤型号 ---
                SettingItem {
                    label: "秤型号:"
                    value: "V-XXXXXX"
                    editable: false
                }

                // --- 序列号 ---
                SettingItem {
                    label: "序列号:"
                    value: "V-XXXXXX"
                    editable: false
                }

                // --- 量程范围及精度 ---
                SettingItem {
                    label: "量程范围及精度:"
                    value: "150kg"
                    editable: false
                }

                // --- 秤自重 ---
                SettingItem {
                    label: "秤自重:"
                    value: "20kg"
                    editable: false
                }

                // --- 秤尺寸 ---
                SettingItem {
                    label: "秤尺寸:"
                    value: "100*20"
                    editable: false
                }

                // --- WiFi名称（带连接按钮）---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 20

                    Text {
                        text: "WiFi名称:"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 16
                        color: "#666666"
                        Layout.preferredWidth: 140
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: wifiNameInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        leftPadding: 16
                        text: "CMCC-*****-5G"
                        font.pixelSize: 15
                        color: "#1B263B"
                        verticalAlignment: TextInput.AlignVCenter
                        background: Rectangle {
                            radius: 8
                            border.color: wifiNameInput.activeFocus ? "#4361EE" : "#D1D5DB"
                            color: "#FAFAFA"
                        }
                    }

                    Button {
                        id: wifiConnectBtn
                        text: "连接"
                        font.family: "Microsoft YaHei"
                        font.pixelSize: 15
                        font.bold: true
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 44

                        background: Rectangle {
                            radius: 22
                            gradient: Gradient {
                                GradientStop { position: 0.0; color: "#4C72F9" }
                                GradientStop { position: 1.0; color: "#4BC8F6" }
                            }
                            states: State {
                                name: "hovered"
                                when: wifiConnectBtn.hovered
                                PropertyChanges {
                                    target: wifiConnectBtn.background
                                    scale: 1.03
                                }
                            }
                            transitions: Transition {
                                NumberAnimation { properties: "scale"; duration: 200 }
                            }
                        }

                        contentItem: Text {
                            text: wifiConnectBtn.text
                            font: wifiConnectBtn.font
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: console.log("[Settings] WiFi 连接请求")
                    }
                }

                // --- WiFi密码 ---
                SettingRow {
                    label: "WiFi密码:"
                    inputText: "**************"
                    isPassword: true
                }

                // --- 管理员管理（可点击行）===
                ClickableSettingItem {
                    label: "管理员管理"
                    onClicked: console.log("[Settings] 打开管理员管理")
                }

                // --- 电池电量（预留接口）---
                SettingItem {
                    label: "电池电量(预留接口):"
                    value: "--"
                    editable: false
                }
            }

            Item { Layout.fillHeight: true }
        }
    }

    // ==========================================
    // 可复用组件定义
    // ==========================================

    // 只读设置项（标签 + 值显示）
    component SettingItem: RowLayout {
        property string label
        property string value
        property bool editable

        Layout.fillWidth: true
        Layout.topMargin: index > 0 && !isFirst ? 16 : 16
        property bool isFirst: label === "秤型号:"

        Text {
            text: label
            font.family: "Microsoft YaHei"
            font.pixelSize: 16
            color: "#666666"
            Layout.preferredWidth: 160
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: value
            font.family: "Microsoft YaHei"
            font.pixelSize: 16
            color: "#1B263B"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            horizontalAlignment: Text.AlignRight
        }
    }

    // 输入框设置行
    component SettingRow: RowLayout {
        property string label
        property string inputText
        property bool isPassword: false

        Layout.fillWidth: true
        Layout.topMargin: 16

        Text {
            text: label
            font.family: "Microsoft YaHei"
            font.pixelSize: 16
            color: "#666666"
            Layout.preferredWidth: 160
            Layout.alignment: Qt.AlignVCenter
        }

        TextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            leftPadding: 16
            text: parent.inputText
            font.pixelSize: 15
            color: "#1B263B"
            echoMode: parent.isPassword ? TextInput.Password : TextInput.Normal
            verticalAlignment: TextInput.AlignVCenter
            background: Rectangle {
                radius: 8
                border.color: activeFocus ? "#4361EE" : "#D1D5DB"
                color: "#FAFAFA"
            }
        }
    }

    // 可点击的设置项（如管理员管理）
    component ClickableSettingItem: RowLayout {
        property string label
        signal clicked()

        Layout.fillWidth: true
        Layout.topMargin: 16

        Text {
            text: parent.label
            font.family: "Microsoft YaHei"
            font.pixelSize: 16
            color: "#333333"
            Layout.preferredWidth: 200
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "\u203A"
            font.pixelSize: 20
            color: "#94A3B8"
            Layout.alignment: Qt.AlignVCenter
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: parent.clicked()
        }
    }
}
