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
    height: Math.min(parent.height * 0.85, 640)
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

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 32
        spacing: 0

        // ====== 标题栏：返回箭头（圆形背景）+ 设置（居中）======
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 0

            // 返回按钮 — 使用 back.png（图标自含蓝色，故去掉浅蓝圆底，改透明 + 浅灰悬浮）
            Rectangle {
                width: 40; height: 40; radius: 20
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    height: parent.height * 0.6
                    fillMode: Image.PreserveAspectFit
                    source: "qrc:/resources/img/back.png"
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
                font.pixelSize: 28
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
        SettingRow { label: "秤自重:"; value: "20kg"; isLast: false }
        SettingRow { label: "SIM卡号(ICCID):"; value: (CellularModem.ccid !== undefined && CellularModem.ccid.length > 0) ? CellularModem.ccid : "—"; isLast: false }
        SettingRow { label: "IMSI:"; value: (CellularModem.imsi !== undefined && CellularModem.imsi.length > 0) ? CellularModem.imsi : "—"; isLast: true }

        // 分隔间距
        Item { Layout.preferredHeight: 20 }

        // ========================================
        // 软件版本 — 独立圆角背景卡片
        // ========================================

        Rectangle {
            Layout.fillWidth: true
            height: 56
            radius: 12
            color: "#F5F7FA"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 0

                Text {
                    text: "软件版本:"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 20
                    color: Theme.colorTextSecondary
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: SystemInfo.appVersion
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 20
                    color: Theme.colorTextPrimary
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        Item { Layout.preferredHeight: 12 }

        // ========================================
        // 功能设置 — 价格输入开关
        // ========================================
        Rectangle {
            Layout.fillWidth: true
            height: 56
            radius: 12
            color: "#F5F7FA"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 0

                Text {
                    text: "价格输入"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 20
                    color: Theme.colorTextSecondary
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                Switch {
                    checked: AppSettings.priceInputEnabled
                    onCheckedChanged: AppSettings.priceInputEnabled = checked
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }

        Item { Layout.preferredHeight: 28 }

        // ====== 底部关闭按钮 ======
        Button {
            id: closeBtn
            Layout.alignment: Qt.AlignHCenter
            text: "关闭"
            implicitWidth: 140
            implicitHeight: 46

            background: Rectangle {
                radius: 8
                color: closeBtn.hovered ? "#2563EB" : "#3B82F6"
            }

            contentItem: Text {
                text: closeBtn.text
                font.pixelSize: 17
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
                font.pixelSize: 20
                color: "#5A6577"
                Layout.alignment: Qt.AlignVCenter
            }

            Item { Layout.fillWidth: true }

            Text {
                text: value
                font.family: Theme.fontFamilyUi
                font.pixelSize: 20
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
}
