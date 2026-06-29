import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale

/**
 * @brief 4G 移动数据控制弹窗 — 管理蜂窝网络开关和状态查看
 *
 * 使用方式：
 *   CellularDialog {
 *       id: cellularDialog
 *   }
 *   cellularDialog.open()
 */
Popup {
    id: root

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0

    width: 520
    height: Math.min(540, contentArea.implicitHeight + topBar.height + btnBar.height + 28)

    // 进入/退出动画
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 150; easing.type: Easing.InCubic }
    }

    // ========================================================================
    // 主体背景
    // ========================================================================
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        Rectangle {
            width: 6
            height: parent.height - btnBar.height
            radius: 16
            color: "transparent"
            anchors.left: parent.left
            anchors.top: parent.top
        }

        Rectangle {
            width: 6
            height: btnBar.height
            radius: 16
            color: "transparent"
            anchors.left: parent.left
            anchors.bottom: parent.bottom
        }
    }

    // ========================================================================
    // 内容区
    // ========================================================================
    ColumnLayout {
        id: mainContainer
        anchors.fill: parent
        spacing: 0

        // ------ 顶部标题栏 ------
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            height: 72
            radius: 16
            color: "#FFFFFF"

            layer.enabled: false

            RowLayout {
                anchors.centerIn: parent
                spacing: 12
                // 顶层标题栏 Rectangle 不受 ColumnLayout 管理位置，anchors.centerIn 安全

                Text {
                    text: "\u{1F4F1}"
                    font.pixelSize: 28
                }
                Text {
                    text: "4G 移动数据"
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
            }
        }

        // ------ 内容区域 ------
        ColumnLayout {
            id: contentArea
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.topMargin: 24
            Layout.bottomMargin: 20
            spacing: 18

            // ===== 当前状态行 =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // 状态圆点
                Rectangle {
                    width: 14; height: 14; radius: 7
                    color: statusDotColor()
                }

                // 状态文字
                Text {
                    font.pixelSize: 17
                    font.bold: NetworkManager.cellularStatus === NetworkManager.CellConnected ||
                              NetworkManager.cellularStatus === NetworkManager.CellRoaming
                    color: statusTextColor()
                    text: statusText()
                }

                Item { Layout.fillWidth: true }

                // 操作中加载指示器
                BusyIndicator {
                    visible: isOperating()
                    running: isOperating()
                    implicitWidth: 22; implicitHeight: 22
                }
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.colorDivider
            }

            // ===== 详情信息区（已连接/注册时显示） =====
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 14
                visible: showDetails()

                // 运营商信息卡片
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: operatorRow.implicitHeight + 30
                    radius: 10
                    color: "#F0FDF4"
                    border.color: "#BBF7D0"
                    border.width: 1

                    RowLayout {
                        id: operatorRow
                        // 父 Rectangle 不是 Layout，用 anchors.centerIn 安全
                        anchors.centerIn: parent
                        spacing: 12

                        Text { text: "\uD83C\uDFE5"; font.pixelSize: 20 }

                        Text {
                            text: "运营商: " + (NetworkManager.cellularOperator || "未知")
                            font.pixelSize: 16
                            font.bold: true
                            color: "#166534"
                        }

                        // 漫游标签
                        Text {
                            visible: NetworkManager.cellularStatus === NetworkManager.CellRoaming
                            text: "\uD83C\uDF0D 漫游"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#FFFFFF"
                            Rectangle {
                                z: -1
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 4
                                color: "#8B5CF6"
                            }
                        }
                    }
                }

                // 信号强度行
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Text {
                        text: "\uD83D\uDCF5 信号:"
                        font.pixelSize: 15
                        color: Theme.colorTextSecondary
                    }

                    // 信号条
                    Item {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 8

                        Rectangle {
                            anchors.fill: parent
                            radius: 4
                            color: "#E5E7EB"
                        }

                        Rectangle {
                            width: Math.max(0, (NetworkManager.cellularSignal / 100) * parent.width)
                            height: parent.height
                            radius: 4
                            color: NetworkManager.cellularSignal > 60 ? "#22C55E" :
                                   NetworkManager.cellularSignal > 30 ? "#F59E0B" : "#EF4444"
                            Behavior on width { NumberAnimation { duration: 300 } }
                        }
                    }

                    Text {
                        text: (NetworkManager.cellularSignal || 0) + "%"
                        font.family: "Monospace"
                        font.pixelSize: 15
                        font.bold: true
                        color: Theme.colorTextPrimary
                    }
                }

                // IP 地址行（已连接且有 IP 时显示）
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    visible: NetworkManager.cellularIpAddr && NetworkManager.cellularIpAddr.length > 3

                    Text {
                        text: "\uD83D\uDCC1 IP:"
                        font.pixelSize: 15
                        color: Theme.colorTextSecondary
                    }

                    Text {
                        text: NetworkManager.cellularIpAddr || "--"
                        font.family: "Monospace"
                        font.pixelSize: 15
                        color: Theme.colorTextPrimary
                    }
                }
            }

            // ===== 无硬件警告区（仅无4G模块时显示） =====
            Rectangle {
                Layout.fillWidth: true
                visible: !hasModem()
                Layout.preferredHeight: noModemContent.implicitHeight + 24
                radius: 10
                color: "#FEF3C7"
                border.color: "#FCD34D"
                border.width: 1

                ColumnLayout {
                    id: noModemContent
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: "\u26A0 未检测到 4G 模块"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#92400E"
                        Layout.alignment: Qt.AlignHCenter
                    }
                    Text {
                        text: NetworkManager.lastError() || "请检查硬件连接或 ModemManager 是否运行"
                        font.pixelSize: 14
                        color: "#B45309"
                        Layout.alignment: Qt.AlignHCenter
                    }
                }
            }

            // ===== 开关控制区 =====
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: switchRow.implicitHeight + 36
                radius: 10
                border.color: "#E8ECF1"
                border.width: 1
                color: "#FAFBFC"

                RowLayout {
                    id: switchRow
                    anchors.centerIn: parent
                    spacing: 16

                    Text {
                        text: "移动数据开关"
                        font.pixelSize: 16
                        font.bold: true
                        color: Theme.colorTextPrimary
                    }

                    Item { Layout.fillWidth: true }

                    // 自定义 Switch
                    Item {
                        width: 54; height: 30
                        enabled: !isOperating() && hasModem()

                        Rectangle {
                            id: switchTrack
                            anchors.fill: parent
                            radius: 15
                            color: switchMouse.checked ? "#22C55E" : "#D1D5DB"

                            Behavior on color { ColorAnimation { duration: 150 } }

                            Rectangle {
                                x: switchMouse.checked ? parent.width - width - 2 : 2
                                y: (parent.height - height) / 2
                                width: 26; height: 26
                                radius: 13
                                color: "white"
                                border.color: "#999"
                                border.width: 1

                                Behavior on x { NumberAnimation { duration: 150 } }
                            }
                        }

                        // 无硬件时覆盖层（半透明 + 禁用图标）
                        Rectangle {
                            anchors.fill: parent
                            visible: !hasModem()
                            radius: 15
                            color: "#00000044"

                            Text {
                                anchors.centerIn: parent
                                text: "\u2717"
                                font.pixelSize: 16
                                color: "#FFFFFFAA"
                            }
                        }

                        MouseArea {
                            id: switchMouse
                            anchors.fill: parent
                            // 直接绑定 Q_PROPERTY，确保 cellularStatus 变化时自动更新
                            property bool checked: NetworkManager.cellularStatus >= NetworkManager.CellSearching &&
                                                   NetworkManager.cellularStatus <= NetworkManager.CellRoaming
                            enabled: parent.enabled

                            onClicked: {
                                console.log("[CellularDialog] 切换 4G 开关, 当前:", checked ? "ON" : "OFF")
                                if (!checked) {
                                    // 当前是 OFF → 要开启
                                    root.showToast("正在开启 4G...", 0)
                                    NetworkManager.enableCellular()
                                } else {
                                    // 当前是 ON → 要关闭
                                    root.showToast("正在关闭 4G...", 0)
                                    NetworkManager.disableCellular()
                                }
                            }
                        }
                    }
                }
            }

            // ===== 错误提示区 =====
            Text {
                Layout.fillWidth: true
                visible: NetworkManager.cellularStatus === NetworkManager.CellError
                text: "\u26A0 " + (NetworkManager.lastError() || "4G 操作失败")
                font.pixelSize: 15
                color: "#EF4444"
                wrapMode: Text.Wrap
            }

            // ===== 提示文字 =====
            Text {
                Layout.fillWidth: true
                text: hintMessage()
                font.pixelSize: 14
                color: Theme.colorTextTertiary
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }
        }

        // ------ 底部按钮栏 ------
        Rectangle {
            id: btnBar
            Layout.fillWidth: true
            height: 76
            color: "#F8FAFC"

            Button {
                id: closeBtn
                text: "关闭"
                anchors.centerIn: parent
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

                hoverEnabled: true
                onClicked: root.close()
            }
        }
    }

    // ========================================================================
    // Toast 反馈（作为 Popup 直接子项，避免 Layout anchors 冲突）
    // ========================================================================
    property string toastMsg: ""
    property int toastType: 0       // 0=hidden, 1=success, 2=error, 3=info
    property bool toastVis: false

    function showToast(msg, type) {
        toastMsg = msg
        toastType = type
        toastVis = true
        toastHideTimer.restart()
    }

    Timer {
        id: toastHideTimer
        interval: 2500
        onTriggered: root.toastVis = false
    }

    // Toast 绝对定位在 Popup 内，不参与 ColumnLayout 排版
    Rectangle {
        id: toastRect
        x: (root.width - width) / 2
        y: root.height - btnBar.height - 52
        z: 10
        width: toastContent.implicitWidth + 36
        height: 40
        radius: 8
        visible: toastVis || toastAnim.running

        color: root.toastType === 1 ? "#22C55E" :
               root.toastType === 2 ? "#EF4444" : "#3B82F6"

        Behavior on opacity { NumberAnimation { duration: 200 } }
        PropertyAnimation {
            id: toastAnim
            target: toastRect; property: "opacity"
            from: 1; to: 0; duration: 200
            running: !root.toastVis && !toastHideTimer.running
        }

        RowLayout {
            id: toastContent
            anchors.centerIn: parent
            spacing: 6

            Text {
                text: root.toastType === 1 ? "\u2705" :
                      root.toastType === 2 ? "\u26A0" : "\u2139\uFE0F"
                font.pixelSize: 14; color: "white"
            }
            Text {
                text: root.toastMsg
                font.pixelSize: 14; font.bold: true; color: "white"
            }
        }
    }

    // ========================================================================
    // 结果监听
    // ========================================================================
    Connections {
        target: NetworkManager

        function onCellularEnabled() {
            root.showToast("4G 已开启", 1)
        }
        function onCellularDisabled() {
            root.showToast("4G 已关闭", 1)
        }
        function onCellularOperationFailed(errorMsg) {
            root.showToast(errorMsg || "操作失败", 2)
        }
    }

    // ========================================================================
    // 打开时刷新状态
    // ========================================================================
    onOpened: {
        console.log("[CellularDialog] 弹窗打开, 当前 4G 状态:", NetworkManager.cellularStatus)
        NetworkManager.refreshCellularStatus()
    }

    // ========================================================================
    // 辅助函数
    // ========================================================================

    function statusDotColor() {
        var s = NetworkManager.cellularStatus
        if (s === NetworkManager.CellConnected) return "#22C55E"
        if (s === NetworkManager.CellRoaming) return "#8B5CF6"
        if (s === NetworkManager.CellSearching) return "#F59E0B"
        if (s === NetworkManager.CellRegistered) return "#3B82F6"
        if (s === NetworkManager.CellError) return "#EF4444"
        if (s === NetworkManager.CellDisabled) return "#9CA3AF"
        return "#94A3B8"
    }

    function statusTextColor() {
        var s = NetworkManager.cellularStatus
        if (s === NetworkManager.CellConnected) return "#16A34A"
        if (s === NetworkManager.CellRoaming) return "#7C3AED"
        if (s === NetworkManager.CellSearching) return "#D97706"
        if (s === NetworkManager.CellError) return "#DC2626"
        return Theme.colorTextSecondary
    }

    function statusText() {
        var s = NetworkManager.cellularStatus
        switch (s) {
            case NetworkManager.CellUnknown:   return "未知状态"
            case NetworkManager.CellDisabled:  return "已关闭"
            case NetworkManager.CellSearching: return "搜索网络中..."
            case NetworkManager.CellRegistered: return "已注册（等待连接）"
            case NetworkManager.CellConnected:  return "已连接 \u2705"
            case NetworkManager.CellRoaming:    return "漫游中 \uD83C\uDF0D"
            case NetworkManager.CellError:      return "错误"
            default: return ""
        }
    }

    /** @brief 是否显示详细信息区（已注册及以上） */
    function showDetails() {
        var s = NetworkManager.cellularStatus
        return s >= NetworkManager.CellRegistered && s <= NetworkManager.CellRoaming
    }

    /** @brief 判断是否正在执行操作（防止重复点击） */
    function isOperating() {
        return NetworkManager.cellularStatus === NetworkManager.CellSearching
    }

    /** @brief 判断是否有4G硬件（支持 ModemManager modem 和网络接口两种模式） */
    function hasModem() {
        return NetworkManager.hasCellularHardware
    }

    /** @brief 判断开关当前是否处于"开"的状态 */
    function isSwitchChecked() {
        var s = NetworkManager.cellularStatus
        return s >= NetworkManager.CellSearching && s <= NetworkManager.CellRoaming
    }

    function hintMessage() {
        var s = NetworkManager.cellularStatus
        // 无硬件时优先显示
        if (!hasModem()) {
            return "\u26A0 未检测到 4G 模块（请检查硬件连接或 ModemManager 服务）"
        }
        if (s === NetworkManager.CellDisabled || s === NetworkManager.CellUnknown) {
            return "点击上方开关启用 4G 移动数据"
        } else if (s >= NetworkManager.CellSearching && s <= NetworkManager.CellRoaming) {
            return "4G 已启用，关闭将断开移动数据连接"
        } else if (s === NetworkManager.CellError) {
            return "请检查 SIM 卡或 4G 模块状态"
        }
        return ""
    }
}
