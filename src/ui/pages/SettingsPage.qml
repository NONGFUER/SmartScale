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
                // 第二区：网络控制（核心新功能）
                // ========================================

                SectionHeader { text: "网络控制"; isNotFirst: true }

                // --- 2a. Wi-Fi 控制区块 ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: wifiContentCol.implicitHeight + 48
                    radius: 12
                    border.color: "#E8ECF1"
                    border.width: 1
                    color: "#FAFBFC"

                    ColumnLayout {
                        id: wifiContentCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 24
                        spacing: 16

                        // Wi-Fi 标题行：状态指示器 + 标题
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // 状态圆点 + 文字
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                color: wifiStatusColor()
                            }

                            Text {
                                text: "Wi-Fi"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                color: Theme.colorTextPrimary
                            }

                            Item { Layout.fillWidth: true }

                            // 当前状态文字
                            WifiStatusLabel {}

                            // 扫描按钮
                            Button {
                                visible: !NetworkManager.isScanning
                                text: "\uD83D\uDCE1 扫描"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeCaption
                                Layout.preferredWidth: 80
                                Layout.preferredHeight: 34
                                background: Rectangle {
                                    radius: 6
                                    color: scanWifiBtn.hovered ? "#E8EEFF" : "#EFF3FA"
                                    border.color: scanWifiBtn.hovered ? "#4C72F9" : "transparent"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: scanWifiBtn.text
                                    font: scanWifiBtn.font
                                    color: "#4C72F9"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                id: scanWifiBtn
                                hoverEnabled: true
                                onClicked: NetworkManager.scanWifiNetworks()
                            }

                            // 扫描中动画
                            BusyIndicator {
                                visible: NetworkManager.isScanning
                                running: NetworkManager.isScanning
                                implicitWidth: 28; implicitHeight: 28
                            }
                        }

                        // Wi-Fi 连接信息行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            visible: NetworkManager.wifiStatus === NetworkManager.Connected ||
                                     NetworkManager.wifiStatus === NetworkManager.Connecting

                            // SSID 显示
                            Text {
                                text: "网络:"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBodySm
                                color: Theme.colorTextSecondary
                            }

                            Text {
                                text: NetworkManager.wifiSsid || (NetworkManager.wifiStatus === NetworkManager.Connecting ? "连接中..." : "--")
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBodySm
                                color: Theme.colorTextPrimary
                                font.bold: true
                            }

                            Item { Layout.preferredWidth: 20 }

                            // 信号强度
                            Text {
                                text: "\uD83D\uDCF5"
                                font.pixelSize: 18
                            }
                            SignalBar {
                                signalStrength: NetworkManager.wifiSignal
                                barWidth: 60
                                barHeight: 6
                            }
                            Text {
                                text: NetworkManager.wifiSignal + "%"
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSizeCaptionSm
                                color: Theme.colorTextTertiary
                            }

                            Item { Layout.preferredWidth: 20 }

                            // IP 地址
                            Text {
                                text: "IP: " + (NetworkManager.wifiIpAddress || "--")
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSizeCaptionSm
                                color: Theme.colorTextTertiary
                            }

                            Item { Layout.fillWidth: true }

                            // 断开按钮
                            Button {
                                visible: NetworkManager.wifiStatus === NetworkManager.Connected
                                text: "断开"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeCaption
                                Layout.preferredWidth: 64
                                Layout.preferredHeight: 32
                                background: Rectangle {
                                    radius: 6
                                    color: disconnectWifiBtn.hovered ? "#FFF0F0" : "#FFF5F5"
                                    border.color: "#FF6B6B"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: disconnectWifiBtn.text
                                    font: disconnectWifiBtn.font
                                    color: "#E74C3C"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                                id: disconnectWifiBtn
                                hoverEnabled: true
                                onClicked: NetworkManager.disconnectWifi()
                            }
                        }

                        // Wi-Fi 连接操作行（未连接时显示）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            visible: NetworkManager.wifiStatus !== NetworkManager.Connected &&
                                     NetworkManager.wifiStatus !== NetworkManager.Connecting

                            // 网络选择（下拉框或文本框）
                            Text {
                                text: "SSID:"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBodySm
                                color: Theme.colorTextSecondary
                            }

                            ComboBox {
                                id: wifiSsidCombo
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                model: ListModel { id: comboModel }
                                editable: true
                                textRole: "displayText"
                                valueRole: "ssid"

                                Component.onCompleted: updateComboModel()

                                Connections {
                                    target: NetworkManager
                                    function onNetworksUpdated() { wifiSsidCombo.updateComboModel() }
                                }

                                function updateComboModel() {
                                    var networks = NetworkManager.availableNetworks;

                                    // 直接操作预定义的 comboModel，而非动态创建
                                    comboModel.clear();
                                    comboModel.append({ ssid: "", secured: false, signal: 0, displayText: "手动输入 SSID..." });

                                    for (var i = 0; i < networks.length; i++) {
                                        var net = networks[i];
                                        var display = net.ssid;
                                        if (net.secured) display += " \uD83D\uDD12";
                                        display += " (" + net.signal + "%)";
                                        comboModel.append({
                                            ssid: net.ssid,
                                            secured: net.secured,
                                            signal: net.signal,
                                            displayText: display
                                        });
                                    }
                                }

                                delegate: ItemDelegate {
                                    width: wifiSsidCombo.width - 8
                                    highlighted: wifiSsidCombo.highlightedIndex === index
                                    contentItem: Row {
                                        spacing: 8
                                        Text {
                                            text: modelData.displayText || modelData.ssid || ""
                                            font.pixelSize: Theme.fontSizeBodySm
                                            color: Theme.colorTextPrimary
                                        }
                                        Text {
                                            visible: modelData.secured
                                            text: "\uD83D\uDD12"
                                            font.pixelSize: 14
                                        }
                                    }
                                    background: Rectangle {
                                        color: parent.highlighted ? "#EBF0FF" : "transparent"
                                        radius: 4
                                    }
                                }
                            }

                            // 密码输入
                            TextField {
                                id: wifiPasswordInput
                                Layout.preferredWidth: 160
                                Layout.preferredHeight: 38
                                placeholderText: "密码"
                                echoMode: TextInput.Password
                                font.pixelSize: Theme.fontSizeBodySm
                                leftPadding: 12
                                verticalAlignment: TextInput.AlignVCenter
                                background: Rectangle {
                                    radius: 6
                                    border.color: wifiPasswordInput.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                                    color: Theme.colorInputBg
                                }
                            }

                            // 连接按钮
                            Button {
                                id: connectWifiBtn
                                text: "连接"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBodySm
                                font.bold: true
                                Layout.preferredWidth: 76
                                Layout.preferredHeight: 38
                                enabled: wifiSsidCombo.currentText.trim().length > 0 &&
                                         !NetworkManager.isScanning

                                background: Rectangle {
                                    radius: 19
                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: connectWifiBtn.enabled ? "#4C72F9" : "#B0B8CC" }
                                        GradientStop { position: 1.0; color: connectWifiBtn.enabled ? "#4BC8F6" : "#9098AA" }
                                    }
                                    Behavior on scale {
                                        NumberAnimation { duration: 200 }
                                    }
                                    scale: connectWifiBtn.hovered && connectWifiBtn.enabled ? 1.03 : 1.0
                                }
                                contentItem: Text {
                                    text: connectWifiBtn.text
                                    font: connectWifiBtn.font
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }

                                hoverEnabled: true
                                onClicked: {
                                    var ssid = wifiSsidCombo.currentText.trim();
                                    var pwd = wifiPasswordInput.text.trim();
                                    if (ssid.length > 0) {
                                        NetworkManager.connectWifi(ssid, pwd);
                                    }
                                }
                            }
                        }
                    }
                }

                // --- 2b. 4G 移动数据控制区块 ---
                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 16
                    Layout.preferredHeight: cellularContentCol.implicitHeight + 44
                    radius: 12
                    border.color: "#E8ECF1"
                    border.width: 1
                    color: "#FAFBFC"

                    ColumnLayout {
                        id: cellularContentCol
                        anchors.left: parent.left; anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.margins: 22
                        spacing: 14

                        // 4G 标题行
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // 状态圆点
                            Rectangle {
                                width: 12; height: 12; radius: 6
                                color: cellularStatusColor()
                            }

                            Text {
                                text: "4G 移动数据"
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBody
                                font.bold: true
                                color: Theme.colorTextPrimary
                            }

                            Item { Layout.fillWidth: true }

                            CellularStatusLabel {}

                            // 开关按钮
                            Switch {
                                id: cellularSwitch
                                checked: isCellularEnabled()

                                indicator: Rectangle {
                                    implicitWidth: 52; implicitHeight: 28
                                    x: cellularSwitch.leftPadding
                                    y: parent.height / 2 - height / 2
                                    radius: 14
                                    color: cellularSwitch.checked ? "#4CAF50" : "#D1D5DB"
                                    border.width: 0

                                    Rectangle {
                                        x: cellularSwitch.checked ? parent.width - width - 2 : 2
                                        width: 24; height: 24
                                        y: (parent.height - height) / 2
                                        radius: 12
                                        color: "white"
                                        border.color: "#999"
                                        Behavior on x { NumberAnimation { duration: 150 } }
                                    }
                                }

                                onToggled: {
                                    if (checked) {
                                        NetworkManager.enableCellular();
                                    } else {
                                        NetworkManager.disableCellular();
                                    }
                                }
                            }
                        }

                        // 4G 详细信息行（已连接/注册时显示）
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 20
                            visible: NetworkManager.cellularStatus === NetworkManager.CellRegistered ||
                                     NetworkManager.cellularStatus === NetworkManager.CellConnected ||
                                     NetworkManager.cellularStatus === NetworkManager.CellRoaming

                            // 运营商
                            Text {
                                text: "\uD83C\uDDE8\uD83C\uDDF3 " +
                                      (NetworkManager.cellularOperator || "未知运营商")
                                font.family: Theme.fontFamilyUi
                                font.pixelSize: Theme.fontSizeBodySm
                                color: Theme.colorTextPrimary
                            }

                            // 信号强度
                            Text { text: "\uD83D\uDCF5"; font.pixelSize: 18 }
                            SignalBar {
                                signalStrength: NetworkManager.cellularSignal
                                barWidth: 56; barHeight: 5
                                barColor: "#22C55E"
                            }
                            Text {
                                text: NetworkManager.cellularSignal + "%"
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSizeCaptionSm
                                color: Theme.colorTextTertiary
                            }

                            Item { Layout.preferredWidth: 16 }

                            // IP 地址
                            Text {
                                text: "IP: " + (NetworkManager.cellularIpAddr || "--")
                                font.family: Theme.fontFamilyMono
                                font.pixelSize: Theme.fontSizeCaptionSm
                                color: Theme.colorTextTertiary
                            }
                        }

                        // 错误提示
                        Text {
                            Layout.fillWidth: true
                            visible: NetworkManager.cellularStatus === NetworkManager.Error
                            text: "\u26A0 " + (NetworkManager.lastError() || "4G 操作失败")
                            font.pixelSize: Theme.fontSizeCaption
                            color: "#E74C3C"
                            wrapMode: Text.Wrap
                        }
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
    // 内联组件定义
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
        property bool editable: false

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

    // Wi-Fi 状态标签组件
    component WifiStatusLabel: Text {
        function statusText() {
            switch (NetworkManager.wifiStatus) {
                case NetworkManager.Unknown:     return "未知";
                case NetworkManager.Disabled:    return "已禁用";
                case NetworkManager.Disconnected:return "未连接";
                case NetworkManager.Connecting:  return "连接中...";
                case NetworkManager.Connected:   return "已连接 \u2705";
                case NetworkManager.Error:       return "错误";
                default: return "";
            }
        }
        text: statusText()
        font.pixelSize: Theme.fontSizeCaption
        font.bold: NetworkManager.wifiStatus === NetworkManager.Connected
        color: wifiStatusTextColor()
    }

    // 4G 状态标签组件
    component CellularStatusLabel: Text {
        function statusText() {
            switch (NetworkManager.cellularStatus) {
                case NetworkManager.CellUnknown:   return "未知";
                case NetworkManager.CellDisabled:  return "已关闭";
                case NetworkManager.CellSearching: return "搜索中...";
                case NetworkManager.CellRegistered: return "已注册";
                case NetworkManager.CellConnected:  return "已连接 \u2705";
                case NetworkManager.CellRoaming:    return "漫游中 \uD83C\uDF0D";
                case NetworkManager.CellError:      return "错误";
                default: return "";
            }
        }
        text: statusText()
        font.pixelSize: Theme.fontSizeCaption
        font.bold: NetworkManager.cellularStatus === NetworkManager.CellConnected
        color: cellularStatusTextColor()
    }

    // 信号强度条形图
    component SignalBar: Item {
        property int signalStrength: 0
        property int barWidth: 50
        property int barHeight: 6
        property color barColor: "#4CAF50"

        implicitWidth: barWidth
        implicitHeight: barHeight

        Rectangle {
            width: parent.barWidth
            height: parent.barHeight
            radius: 3
            color: "#E5E7EB"
        }

        Rectangle {
            width: Math.max(0, (parent.signalStrength / 100) * parent.barWidth)
            height: parent.barHeight
            radius: 3
            color: parent.barColor
            Behavior on width { NumberAnimation { duration: 300 } }
        }
    }

    // ==========================================
    // 辅助 JS 函数
    // ==========================================

    /** @brief 返回 Wi-Fi 状态对应的颜色 */
    function wifiStatusColor() {
        switch (NetworkManager.wifiStatus) {
            case NetworkManager.Connected:   return "#22C55E";
            case NetworkManager.Connecting:  return "#F59E0B";
            case NetworkManager.Error:       return "#EF4444";
            case NetworkManager.Disabled:
            case NetworkManager.Disconnected:return "#9CA3AF";
            default: return "#9CA3AF";
        }
    }

    /** @brief Wi-Fi 状态文字颜色 */
    function wifiStatusTextColor() {
        switch (NetworkManager.wifiStatus) {
            case NetworkManager.Connected:   return "#16A34A";
            case NetworkManager.Connecting:  return "#D97706";
            case NetworkManager.Error:       return "#DC2626";
            default: return Theme.colorTextTertiary;
        }
    }

    /** @brief 4G 状态对应的圆点颜色 */
    function cellularStatusColor() {
        switch (NetworkManager.cellularStatus) {
            case NetworkManager.CellConnected: return "#22C55E";
            case NetworkManager.CellRoaming:   return "#8B5CF6";
            case NetworkManager.CellSearching: return "#F59E0B";
            case NetworkManager.CellRegistered:return "#3B82F6";
            case NetworkManager.CellError:     return "#EF4444";
            case NetworkManager.CellDisabled:  return "#9CA3AF";
            default: return "#9CA3AF";
        }
    }

    /** @brief 4G 状态文字颜色 */
    function cellularStatusTextColor() {
        switch (NetworkManager.cellularStatus) {
            case NetworkManager.CellConnected: return "#16A34A";
            case NetworkManager.CellRoaming:   return "#7C3AED";
            case NetworkManager.CellSearching: return "#D97706";
            case NetworkManager.CellError:     return "#DC2626";
            default: return Theme.colorTextTertiary;
        }
    }

    /** @brief 判断 4G 是否处于启用状态 */
    function isCellularEnabled() {
        var s = NetworkManager.cellularStatus;
        return s >= NetworkManager.CellSearching && s <= NetworkManager.CellRoaming;
    }

}  // end root Item
