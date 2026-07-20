import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

// ============================================================
// SettingsDialog — 设置信息弹窗（设备信息 + 软件版本）
//
// 用法：
//   SettingsDialog { id: settingsDialog }
//   settingsDialog.open()
//
// 样式规范（参照设计稿）：
//   - 返回按钮：浅蓝圆形背景 + ‹ 箭头
//   - 标题："设置" 居中，加粗大字
//   - 列表项：每项之间有分隔线，label左对齐、value右对齐
//   - 软件版本：独立浅灰圆角背景卡片
//   - 无区段标题（设备信息/系统信息文字去掉）
// ============================================================
Dialog {
    id: root

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width * 0.85, 680)
    height: Math.min(parent.height * 0.92, 1000)
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    title: ""

    background: Rectangle {
        radius: 24
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 20
            shadowOpacity: 0.15
            shadowVerticalOffset: 6
        }
    }

    Flickable {
        anchors.fill: parent
        anchors.margins: 32
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0

        // ====== 标题栏：返回箭头（圆形背景）+ 设置（居中）======
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 0

            // 返回按钮 — 使用 back2.png + "返回"文字（圆角胶囊 + 浅底边框）
            Rectangle {
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
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.close()
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "设备信息"
                font.family: Theme.fontFamilyUi
                font.pixelSize: 24
                font.bold: true
                color: Theme.colorTextPrimary
            }

            Item { Layout.fillWidth: true }
            // 右侧占位，保持标题居中
            Item { width: 40 }
        }

        // 标题下分隔线
        Rectangle {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            height: 1
            color: "#E8ECF0"
        }

        // ========================================
        // 设备信息列表（每项带底部分隔线）
        // ========================================

        SettingRow { label: "秤型号:"; value: "WLC200A-13C"; isLast: false }
        SettingRow { label: "序列号:"; value: WeightManager.sn.length > 0 ? WeightManager.sn : "----"; isLast: false }
        SettingRow { label: "量程范围及精度:"; value: "200kg / \u00B13‰"; isLast: false }
        //SettingRow { label: "秤自重:"; value: "20kg"; isLast: false }
        SettingRow { label: "SIM卡号(ICCID):"; value: (CellularModem.ccid !== undefined && CellularModem.ccid.length > 0) ? CellularModem.ccid : "—"; isLast: false }
       // SettingRow { label: "IMSI:"; value: (CellularModem.imsi !== undefined && CellularModem.imsi.length > 0) ? CellularModem.imsi : "—"; isLast: true }

        // 分隔间距
        Item { Layout.preferredHeight: 20 }

        // ========================================
        // 功能设置 — 统一灰色圆角卡片（价格输入 + 网络开关）
        // ========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: swCardCol.implicitHeight + 40
            radius: 12
            color: "#F5F7FA"

            ColumnLayout {
                id: swCardCol
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16

                // ----- 价格输入（最上面）-----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "价格输入"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch { id: swPrice; checked: AppSettings.priceInputEnabled; onToggled: AppSettings.priceInputEnabled = checked }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // ----- 启用4G网络 -----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "启用4G网络"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: sw4g; checked: AppSettings.cellularEnabled
                        onToggled: {
                            AppSettings.cellularEnabled = checked
                            if (checked) NetworkManager.enableCellular()
                            else NetworkManager.disableCellular()
                        }
                    }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // ----- 启用WiFi -----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "启用WiFi"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: swWifi; checked: AppSettings.wifiEnabled
                        onToggled: { AppSettings.wifiEnabled = checked; NetworkManager.setWifiEnabled(checked) }
                    }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // ----- 网络自动切换 -----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "网络自动切换"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch { id: swAuto; checked: AppSettings.networkAutoSwitch; onToggled: AppSettings.networkAutoSwitch = checked }
                }
            }
        }

        Item { Layout.preferredHeight: 24 }

        // ========================================
        // 公司信息
        // ========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            radius: 12
            color: "#F5F7FA"

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 8

                Text {
                    text: "上海小管事机器人有限公司"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.colorTextPrimary
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "© 2026 版权所有"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 24
                    color: Theme.colorTextSecondary
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        Item { Layout.preferredHeight: 28 }

        // ====== 底部关闭按钮 ======
        Button {
            id: closeBtn
            Layout.alignment: Qt.AlignHCenter
            text: "退出"
            implicitWidth: 140
            implicitHeight: 46

            background: Rectangle {
                radius: 8
                color: closeBtn.hovered ? "#4361EE" : "#3B82F6"
            }

            contentItem: Text {
                text: closeBtn.text
                font.pixelSize: 24
                font.bold: true
                color: "#FFFFFF"
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }

            onClicked: root.close()
        }

        Item { Layout.preferredHeight: 8 }
        Item { Layout.fillHeight: true }
        }  // end ColumnLayout
    }  // end Flickable

    // ==========================================
    // 内联组件定义
    // ==========================================

    component SettingRow: ColumnLayout {
        property string label
        property string value
        property bool isLast: false

        Layout.fillWidth: true
        spacing: 0

        // 内容行
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            Layout.topMargin: 4
            Layout.bottomMargin: 4

            Text {
                text: label
                font.family: Theme.fontFamilyUi
                font.pixelSize: 24
                color: "#5A6577"
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Text {
                text: value
                font.family: Theme.fontFamilyUi
                font.pixelSize: 24
                color: "#1A1A2E"
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // 底部分隔线（最后一项不显示）
        Rectangle {
            Layout.fillWidth: true
            height: 1
            visible: !isLast
            color: "#EEF0F4"
        }
    }

    // 开关控件（无背景，仅 iOS 风格 toggle）
    // 直接复用 Switch 自带的 toggled(bool) 信号（仅用户点击触发，程序赋值不触发）
    component ToggleSwitch: Switch {
        id: sw

        indicator: Rectangle {
            implicitWidth: 56
            implicitHeight: 32
            x: sw.leftPadding
            y: parent.height / 2 - height / 2
            radius: 16
            color: sw.checked ? "#4361EE" : "#CBD5E1"
            border.color: sw.checked ? "#4361EE" : "#CBD5E1"
            border.width: 1

            Behavior on color { ColorAnimation { duration: 150 } }

            Rectangle {
                x: sw.checked ? parent.width - width - 4 : 4
                y: 4
                width: parent.height - 8
                height: parent.height - 8
                radius: width / 2
                color: "#FFFFFF"

                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.InOutQuad } }
            }
        }
    }
}
