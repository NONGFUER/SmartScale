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

    // 当前选中的网络模式（与 NetworkManager.networkMode 同步，用于高亮按钮；默认全开优先4G）
    property int netMode: NetworkManager.AllCellularPriority

    // 应用某个网络模式：更新高亮、持久化记忆、下发设备、同步四个开关
    function setNetMode(m: int) {
        netMode = m
        AppSettings.networkMode = m
        NetworkManager.setNetworkMode(m)
        syncSwitches()
    }

    // 根据 netMode 强制同步四个开关的 checked（用 onClicked 替代 onToggled 后无需防重入标志，
    // 因为 clicked 仅在用户点击时触发，程序赋值 checked 不会触发）
    function syncSwitches() {
        swWifiOnly.checked = (netMode === NetworkManager.WifiOnly)
        swCellOnly.checked = (netMode === NetworkManager.CellularOnly)
        swAllWifi.checked  = (netMode === NetworkManager.AllWifiPriority)
        swAllCell.checked  = (netMode === NetworkManager.AllCellularPriority)
    }

    // 打开时推导应高亮的模式（四个中必须选一个，默认全开优先4G）
    // 优先级：NetworkManager.networkMode（设备已应用）> AppSettings.networkMode（持久化记忆）> 实时状态推导
    function refreshNetMode() {
        if (NetworkManager.networkMode >= 0) {
            netMode = NetworkManager.networkMode
            return
        }
        if (AppSettings.networkMode >= 0) {
            netMode = AppSettings.networkMode
            return
        }
        var wifiOn = (NetworkManager.wifiStatus === NetworkManager.WifiConnected
                      || NetworkManager.wifiStatus === NetworkManager.WifiConnecting)
        var cellOn = (NetworkManager.cellularStatus === NetworkManager.CellConnected
                      || NetworkManager.cellularStatus === NetworkManager.CellRegistered
                      || NetworkManager.cellularStatus === NetworkManager.CellRoaming)
        if (wifiOn && !cellOn) netMode = NetworkManager.WifiOnly
        else if (!wifiOn && cellOn) netMode = NetworkManager.CellularOnly
        else netMode = NetworkManager.AllCellularPriority   // 默认：全开优先4G（两者都开或都关时）
    }

    onOpened: {
        refreshNetMode()
        syncSwitches()
        // 首次打开（用户尚未选择过任何模式）：直接把设备设为默认 全开优先4G 并记忆
        if (AppSettings.networkMode < 0) {
            setNetMode(NetworkManager.AllCellularPriority)
        }
        NetworkManager.refreshWifiStatus()
        NetworkManager.refreshCellularStatus()
    }

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

    // ====== 固定头部：标题栏 + 分隔线（不随内容滚动）======
    RowLayout {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 32
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
        Item { width: 40 }
    }

    // 标题下分隔线
    Rectangle {
        id: headerDivider
        anchors.top: headerBar.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        anchors.topMargin: 24
        height: 1
        color: "#E8ECF0"
    }

    // ====== 可滚动内容区（设备信息 + 功能设置）======
    Flickable {
        id: contentFlickable
        anchors.top: headerDivider.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: footerBar.top
        anchors.topMargin: 8
        anchors.leftMargin: 32
        anchors.rightMargin: 32
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: parent.width
            spacing: 0

        // ========================================
        // 设备信息列表（每项带底部分隔线）
        // ========================================

        SettingRow { label: "秤型号:"; value: "WLC200A-13C"; isLast: false }
        SettingRow { label: "序列号:"; value: WeightManager.sn.length > 0 ? WeightManager.sn : "----"; isLast: false }
        SettingRow { label: "量程范围及精度:"; value: "200kg / \u00B13‰"; isLast: false }
        //SettingRow { label: "秤自重:"; value: "20kg"; isLast: false }
        SettingRow { label: "SIM卡号(ICCID):"; value: (CellularModem.ccid !== undefined && CellularModem.ccid.length > 0) ? CellularModem.ccid : "—"; isLast: false }
       // SettingRow { label: "IMSI:"; value: (CellularModem.imsi !== undefined && CellularModem.imsi.length > 0) ? CellularModem.imsi : "—"; isLast: true }
        SettingRow { label: "内存容量:"; value: SystemInfo.memTotal; isLast: false }

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

                // ----- 网络模式（四选一）-----
                // Text {
                //     text: "网络模式"
                //     font.family: Theme.fontFamilyUi
                //     font.pixelSize: 24
                //     color: Theme.colorTextSecondary
                //     Layout.alignment: Qt.AlignVCenter
                // }

                // // 当前网络状态
                // RowLayout {
                //     Layout.fillWidth: true
                //     spacing: 24
                //     Text {
                //         text: "WIFI：" + ((NetworkManager.wifiStatus === NetworkManager.WifiConnected
                //                            || NetworkManager.wifiStatus === NetworkManager.WifiConnecting)
                //                           ? "已开启" : "已关闭")
                //         font.family: Theme.fontFamilyUi
                //         font.pixelSize: 22
                //         color: "#475569"
                //     }
                //     Text {
                //         text: "4G：" + ((NetworkManager.cellularStatus === NetworkManager.CellConnected
                //                          || NetworkManager.cellularStatus === NetworkManager.CellRegistered
                //                          || NetworkManager.cellularStatus === NetworkManager.CellRoaming)
                //                         ? "已开启" : "已关闭")
                //         font.family: Theme.fontFamilyUi
                //         font.pixelSize: 22
                //         color: "#475569"
                //     }
                // }

                // 仅开启WIFI
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "仅开启WIFI"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: swWifiOnly
                        onClicked: {
                            if (!checked) { checked = true; return }  // 不允许关闭当前模式（单选）
                            setNetMode(NetworkManager.WifiOnly)
                        }
                    }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // 仅开启4G
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "仅开启4G"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: swCellOnly
                        onClicked: {
                            if (!checked) { checked = true; return }
                            setNetMode(NetworkManager.CellularOnly)
                        }
                    }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // 全开优先WIFI
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "全开优先WIFI"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: swAllWifi
                        onClicked: {
                            if (!checked) { checked = true; return }
                            setNetMode(NetworkManager.AllWifiPriority)
                        }
                    }
                }

                // 分隔线
                Rectangle { Layout.fillWidth: true; height: 1; color: "#E2E8F0" }

                // 全开优先4G
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "全开优先4G"
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: Theme.colorTextSecondary
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Item { Layout.fillWidth: true }
                    ToggleSwitch {
                        id: swAllCell
                        onClicked: {
                            if (!checked) { checked = true; return }
                            setNetMode(NetworkManager.AllCellularPriority)
                        }
                    }
                }
            }
        }

        }  // end ColumnLayout
    }  // end Flickable

    // ====== 固定底部：公司信息 + 退出按钮（不随内容滚动）======
    Rectangle {
        id: footerBar
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: footerCol.implicitHeight + 64
        color: "transparent"

        ColumnLayout {
            id: footerCol
            anchors.fill: parent
            anchors.margins: 32
            spacing: 24

            // 公司信息
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

            // 退出按钮
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
        }
    }

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
