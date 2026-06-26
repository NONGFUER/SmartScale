import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

Item {
    id: root
    anchors.fill: parent

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
                    width: 72; height: 72; radius: 8
                    color: backMouse.containsMouse ? "#F0F4F8" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        width: 72
                         height: 72
                        text: "\u2039"
                        font.pixelSize: Theme.fontSizeIconBack
                        font.bold: true
                        color: Theme.colorTextPrimary
                    }

                    MouseArea {
                        id: backMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: stackView.pop()
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "设置"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: Theme.fontSizeTitleLg
                    font.bold: true
                    color: Theme.colorTextPrimary
                }

                Item { Layout.fillWidth: true }
                Item { width: 36 } // 占位，与返回按钮对称
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 28
                height: 1
                color: Theme.colorDivider
            }

            // ===== 设置项列表 =====
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // --- 秤型号 ---
                SettingItem {
                    label: "秤型号:"
                    value: "WLC200A-13C"
                    editable: false
                }

                // --- 序列号 ---
                SettingItem {
                    label: "序列号:"
                    value: WeightManager.sn.length > 0 ? WeightManager.sn : "----"
                    editable: false
                }

                // --- 量程范围及精度 ---
                SettingItem {
                    label: "量程范围及精度:"
                    value: "200kg"
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
                    value: "  * "
                    editable: false
                }

                // --- WiFi名称（带连接按钮）---
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    spacing: 20

                    Text {
                        text: "WiFi名称:"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeBody
                        color: Theme.colorTextSecondary
                        Layout.preferredWidth: 140
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: wifiNameInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 44
                        leftPadding: 16
                        text: "CMCC-*****-5G"
                        font.pixelSize: Theme.fontSizeBodySm
                        color: Theme.colorTextPrimary
                        verticalAlignment: TextInput.AlignVCenter
                        background: Rectangle {
                            radius: 8
                            border.color: wifiNameInput.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                            color: Theme.colorInputBg
                        }
                    }

                    Button {
                        id: wifiConnectBtn
                        text: "连接"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: Theme.fontSizeBodySm
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


                // --- 软件版本（只读，从 SystemInfo 读取）---
                SettingItem {
                    label: "软件版本:"
                    value: SystemInfo.appVersion
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
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeBody
            color: Theme.colorTextSecondary
            Layout.preferredWidth: 160
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: value
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeBody
            color: Theme.colorTextPrimary
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
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeBody
            color: Theme.colorTextSecondary
            Layout.preferredWidth: 160
            Layout.alignment: Qt.AlignVCenter
        }

        TextField {
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            leftPadding: 16
            text: parent.inputText
            font.pixelSize: Theme.fontSizeBodySm
            color: Theme.colorTextPrimary
            echoMode: parent.isPassword ? TextInput.Password : TextInput.Normal
            verticalAlignment: TextInput.AlignVCenter
            background: Rectangle {
                radius: 8
                border.color: activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                color: Theme.colorInputBg
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
            font.family: Theme.fontFamilyUi
            font.pixelSize: Theme.fontSizeBody
            color: Theme.colorTextPrimary
            Layout.preferredWidth: 200
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "\u203A"
            font.pixelSize: 20
            color: Theme.colorTextTertiary
            Layout.alignment: Qt.AlignVCenter
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: parent.clicked()
        }
    }
}
