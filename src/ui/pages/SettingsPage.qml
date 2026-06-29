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
        width: Math.min(parent.width * 0.85, 960)
        height: Math.min(parent.height * 0.88, 860)
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

        // ===== 可滚动内容区 =====
        Flickable {
            id: flickable
            anchors.fill: parent
            anchors.margins: 40
            contentHeight: contentColumn.implicitHeight + 40
            clip: true

            ColumnLayout {
                id: contentColumn
                width: parent.width
                spacing: 0

                // ===== 标题栏 =====
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 30
                    spacing: 0

                    Rectangle {
                        width: 72; height: 72; radius: 8
                        color: backMouse.containsMouse ? "#F0F4F8" : "transparent"

                        Text {
                            anchors.centerIn: parent
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
                    Item { width: 36 }
                }

                // 分隔线
                Rectangle {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 28
                    height: 1
                    color: Theme.colorDivider
                }

                // ========================================
                // 第一区：设备信息（只读）
                // ========================================

                // 区段标题
                SectionHeader { text: "设备信息" }

                SettingItem { label: "秤型号:"; value: "WLC200A-13C" }
                SettingItem {
                    label: "序列号:"
                    value: WeightManager.sn.length > 0 ? WeightManager.sn : "----"
                }
                SettingItem { label: "量程范围及精度:"; value: "200kg / ±50g" }
                SettingItem { label: "秤自重:"; value: "20kg" }

                // 分隔间距
                Item { Layout.topMargin: 32 }

                // ========================================
                // 第二区：网络控制（入口按钮）
                // ========================================

                SectionHeader { text: "网络控制"; isNotFirst: true }

                // --- Wi-Fi 入口 ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: wifiEntryRow.implicitHeight + 32
                    radius: 12
                    border.color: wifiEntryMouse.containsMouse ? "#3B82F6" : "#E8ECF1"
                    border.width: 1.5
                    color: wifiEntryMouse.containsMouse ? "#F0F7FF" : "#FAFBFC"

                    RowLayout {
                        id: wifiEntryRow
                        anchors.centerIn: parent
                        spacing: 14

                        // 状态圆点
                        Rectangle { width: 12; height: 12; radius: 6; color: wifiStatusDotColor() }

                        Text { text: "Wi-Fi"; font.pixelSize: Theme.fontSizeBody; font.bold: true; color: Theme.colorTextPrimary }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: wifiStatusText()
                            font.pixelSize: Theme.fontSizeCaption
                            color: wifiStatusTextColor()
                        }

                        // 箭头
                        Text { text: "\u203A"; font.pixelSize: 22; font.bold: true; color: Theme.colorTextTertiary }
                    }

                    MouseArea {
                        id: wifiEntryMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ApplicationWindow.window.openWifiDialog()
                    }
                }

                // --- 4G 移动数据入口 ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    Layout.preferredHeight: cellularEntryRow.implicitHeight + 32
                    radius: 12
                    border.color: cellularEntryMouse.containsHover ? "#22C55E" : "#E8ECF1"
                    border.width: 1.5
                    color: cellularEntryMouse.containsHover ? "#F0FDF4" : "#FAFBFC"

                    RowLayout {
                        id: cellularEntryRow
                        anchors.centerIn: parent
                        spacing: 14

                        Rectangle { width: 12; height: 12; radius: 6; color: cellularStatusDotColor() }

                        Text { text: "4G 移动数据"; font.pixelSize: Theme.fontSizeBody; font.bold: true; color: Theme.colorTextPrimary }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: cellularStatusText()
                            font.pixelSize: Theme.fontSizeCaption
                            color: cellularStatusTextColor()
                        }

                        Text { text: "\u203A"; font.pixelSize: 22; font.bold: true; color: Theme.colorTextTertiary }
                    }

                    MouseArea {
                        id: cellularEntryMouse
                        property bool containsHover: containsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ApplicationWindow.window.openCellularDialog()
                    }
                }

                // 第三区：软件版本
                Item { Layout.topMargin: 32 }

                SectionHeader { text: "系统信息"; isNotFirst: true }

                SettingItem {
                    label: "软件版本:"
                    value: SystemInfo.appVersion
                }
            }  // end ColumnLayout

            // 滚动条（必须在 Flickable 内部）
            ScrollBar.vertical: ScrollBar {
                policy: flickable.contentHeight > flickable.height ?
                             ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                width: 6
                background: Rectangle { color: "transparent" }
                contentItem: Rectangle {
                    radius: 3
                    color: parent.pressed ? "#94A3B8" : "#CBD5E1"
                }
            }
        }  // end Flickable
    }  // end card

    // ==========================================
    // 内联组件定义（精简版）
    // ==========================================

    // 区段标题
    component SectionHeader: Text {
        property string text: ""
        property bool isNotFirst: false
        Layout.fillWidth: true
        Layout.topMargin: isNotFirst ? 24 : 16
        Layout.bottomMargin: 8
        font.family: Theme.fontFamilyTitle
        font.pixelSize: Theme.fontSizeTitleMd
        font.bold: true
        color: Theme.colorTextPrimary
    }

    // 只读设置项
    component SettingItem: RowLayout {
        property string label
        property string value

        Layout.fillWidth: true
        Layout.topMargin: index > 0 && label !== "秤型号:" ? 14 : 0

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

    // ==========================================
    // 入口按钮状态文字/颜色辅助函数
    // ==========================================

    function wifiStatusDotColor() {
        switch (NetworkManager.wifiStatus) {
            case NetworkManager.Connected:   return "#22C55E";
            case NetworkManager.Connecting:  return "#F59E0B";
            case NetworkManager.Error:       return "#EF4444";
            default: return "#9CA3AF";
        }
    }

    function wifiStatusText() {
        switch (NetworkManager.wifiStatus) {
            case NetworkManager.Connected:   return NetworkManager.wifiSsid + " \u2705";
            case NetworkManager.Connecting:  return "连接中...";
            case NetworkManager.Error:       return "错误";
            default: return "未连接";
        }
    }

    function wifiStatusTextColor() {
        switch (NetworkManager.wifiStatus) {
            case NetworkManager.Connected:   return "#16A34A";
            case NetworkManager.Connecting:  return "#D97706";
            case NetworkManager.Error:       return "#DC2626";
            default: return Theme.colorTextTertiary;
        }
    }

    function cellularStatusDotColor() {
        var s = NetworkManager.cellularStatus;
        if (s === NetworkManager.CellConnected) return "#22C55E";
        if (s === NetworkManager.CellRoaming)   return "#8B5CF6";
        if (s === NetworkManager.CellSearching) return "#F59E0B";
        if (s === NetworkManager.CellError)     return "#EF4444";
        return "#9CA3AF";
    }

    function cellularStatusText() {
        var s = NetworkManager.cellularStatus;
        switch (s) {
            case NetworkManager.CellConnected:  return "已连接 \u2705";
            case NetworkManager.CellRoaming:    return "漫游中";
            case NetworkManager.CellSearching:  return "搜索中...";
            case NetworkManager.CellRegistered: return "已注册";
            case NetworkManager.CellDisabled:   return "已关闭";
            case NetworkManager.CellError:      return "错误";
            default: return "未知";
        }
    }

    function cellularStatusTextColor() {
        var s = NetworkManager.cellularStatus;
        if (s === NetworkManager.CellConnected) return "#16A34A";
        if (s === NetworkManager.CellRoaming)   return "#7C3AED";
        if (s === NetworkManager.CellSearching) return "#D97706";
        if (s === NetworkManager.CellError)     return "#DC2626";
        return Theme.colorTextTertiary;
    }

}  // end root Item
