import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale

/**
 * @brief Wi-Fi 网络列表弹窗 — 点击状态栏 WiFi 图标弹出
 *
 * 使用方式：
 *   WifiListDialog {
 *       id: wifiListDialog
 *       onNetworkSelected: function(ssid, secured) { ... }
 *   }
 *   wifiListDialog.open()
 */
Popup {
    id: root

    // ---- 对外接口 ----
    /** 用户选中一个网络后触发（需密码的网络由调用方打开密码弹窗） */
    signal networkSelected(string ssid, bool secured)

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0

    width: 600
    height: Math.min(760, contentArea.implicitHeight + topBar.height + btnBar.height + 28)

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

        // 底部按钮区左侧装饰条（不延伸到按钮栏）
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

                Text {
                    text: "\u{1F4F6}"
                    font.pixelSize: 28
                }
                Text {
                    text: "选择 Wi-Fi 网络"
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
            }
        }

        // ------ 网络列表区域 ------
        ColumnLayout {
            id: contentArea
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.topMargin: 24
            Layout.bottomMargin: 20
            spacing: 16

            // 当前连接状态 + 扫描按钮行
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                // 状态指示
                RowLayout {
                    spacing: 8
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: statusDot
                        width: 14; height: 14; radius: 7
                        color: {
                            switch (NetworkManager.wifiStatus) {
                            case NetworkManager.Connected:   return "#22C55E";
                            case NetworkManager.Connecting: return "#F59E0B";
                            case NetworkManager.Error:      return "#EF4444";
                            case NetworkManager.Disabled:   return "#9CA3AF";
                            default:                         return "#94A3B8";
                            }
                        }
                    }

                    Text {
                        id: statusText
                        font.pixelSize: 17
                        color: Theme.colorTextSecondary
                        text: {
                            var s = NetworkManager.wifiStatus
                            if (s === NetworkManager.Connected)
                                return "已连接: " + NetworkManager.wifiSsid
                            else if (s === NetworkManager.Connecting)
                                return "正在连接..."
                            else if (s === NetworkManager.Error)
                                return "连接失败"
                            else if (s === NetworkManager.Disabled)
                                return "Wi-Fi 已禁用"
                            else
                                return "未连接"
                        }
                    }
                }

                // 扫描按钮
                Rectangle {
                    id: scanBtn
                    width: 96; height: 42; radius: 8
                    color: scanBtnMouse.containsMouse ? "#EBF5FF" : "#F0F7FF"
                    border.color: "#3B82F6"
                    border.width: 1.5
                    opacity: NetworkManager.isScanning ? 0.6 : 1.0

                    visible: NetworkManager.wifiStatus !== NetworkManager.Connecting

                    Row {
                        anchors.centerIn: parent
                        spacing: 5

                        BusyIndicator {
                            running: NetworkManager.isScanning
                            width: 18; height: 18
                            visible: running
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NetworkManager.isScanning ? "扫描中..." : "扫描"
                            font.pixelSize: 15
                            font.bold: true
                            color: "#3B82F6"
                        }
                    }

                    MouseArea {
                        id: scanBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !NetworkManager.isScanning
                        onClicked: NetworkManager.scanWifiNetworks()
                    }
                }
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.colorDivider
            }

            // 网络列表（ListView）
            Rectangle {
                Layout.fillWidth: true
                Layout.minimumHeight: 360
                Layout.maximumHeight: 500
                radius: 10
                color: "#FAFBFC"
                border.color: Theme.colorDivider
                border.width: 1
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: 8
                    model: NetworkManager.availableNetworks
                    clip: true
                    spacing: 6

                    // 空状态提示
                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0 && !NetworkManager.isScanning
                        text: "暂无可用网络\n点击「扫描」搜索附近网络"
                        font.pixelSize: 17
                        color: Theme.colorTextTertiary
                        horizontalAlignment: Text.AlignHCenter
                        lineHeight: 1.4
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0 && NetworkManager.isScanning
                        text: "正在扫描..."
                        font.pixelSize: 17
                        color: Theme.colorTextTertiary
                    }

                    delegate: Rectangle {
                        id: netDelegate
                        width: listView.width - 16
                        height: 66
                        radius: 8

                        property bool isCurrentNetwork: NetworkManager.wifiStatus === NetworkManager.Connected &&
                                                        modelData.ssid === NetworkManager.wifiSsid

                        color: isCurrentNetwork ? "#ECFDF5" :
                               netMouse.containsMouse ? "#EEF4FF" : "transparent"

                        Behavior on color { ColorAnimation { duration: 120 } }

                        // 当前连接网络的左边框高亮
                        Rectangle {
                            visible: netDelegate.isCurrentNetwork
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 4
                            radius: 8
                            color: "#22C55E"
                            anchors.leftMargin: 0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            // 已连接 ✓ 标记
                            Text {
                                visible: netDelegate.isCurrentNetwork
                                text: "\u2713"
                                font.pixelSize: 22
                                font.bold: true
                                color: "#22C55E"
                            }

                            // SSID 名称
                            Text {
                                text: modelData.ssid || ""
                                font.pixelSize: 18
                                font.bold: netDelegate.isCurrentNetwork
                                color: netDelegate.isCurrentNetwork ? "#166534" : Theme.colorTextPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Layout.maximumWidth: 260
                            }

                            // 已连接标签
                            Text {
                                visible: netDelegate.isCurrentNetwork
                                text: "已连接"
                                font.pixelSize: 14
                                font.bold: true
                                color: "#FFFFFF"
                                Rectangle {
                                    z: -1
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    radius: 4
                                    color: "#22C55E"
                                }
                            }

                            // 频段标签（5G: 频率 > 4900 MHz）
                            Text {
                                visible: !netDelegate.isCurrentNetwork && (modelData.freq || 0) > 4900
                                text: "5G"
                                font.pixelSize: 14
                                font.bold: true
                                color: "#EF4444"
                            }

                            // 加密锁图标
                            Text {
                                visible: !netDelegate.isCurrentNetwork && modelData.secured
                                text: "\uD83D\uDD12"
                                font.pixelSize: 20
                            }

                            // 信号强度图标（WiFi 波形）
                            Item {
                                visible: !netDelegate.isCurrentNetwork
                                width: 28; height: 24
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        var sig = modelData.signal || 0
                                        ctx.strokeStyle = sig > 50 ? "#3B82F6" : (sig > 25 ? "#F59E0B" : "#9CA3AF")
                                        ctx.lineWidth = 2.2
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"
                                        var cx = 6, cy = 20
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, 4, Math.PI, 0)
                                        ctx.stroke()
                                        if (sig > 20) { ctx.beginPath(); ctx.arc(cx, cy, 8, Math.PI, 0); ctx.stroke() }
                                        if (sig > 45) { ctx.beginPath(); ctx.arc(cx, cy, 12, Math.PI, 0); ctx.stroke() }
                                        if (sig > 70) { ctx.beginPath(); ctx.arc(cx, cy, 16, Math.PI, 0); ctx.stroke() }
                                    }
                                    Component.onCompleted: requestPaint()
                                }
                            }

                            // 信号百分比
                            Text {
                                visible: !netDelegate.isCurrentNetwork
                                text: (modelData.signal || 0) + "%"
                                font.pixelSize: 15
                                color: Theme.colorTextTertiary
                                font.family: Theme.fontFamilyMono
                            }
                        }

                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !netDelegate.isCurrentNetwork
                            cursorShape: netDelegate.isCurrentNetwork ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                            onClicked: {
                                console.log("[WifiList] 选中网络:", modelData.ssid, "加密:", modelData.secured)
                                root.networkSelected(modelData.ssid, modelData.secured)
                            }
                        }
                    }
                }
            }

            // 提示文字
            Text {
                Layout.fillWidth: true
                text: "点击网络名称以连接"
                font.pixelSize: 15
                color: Theme.colorTextTertiary
                horizontalAlignment: Text.AlignHCenter
                visible: listView.count > 0
            }
        }

        // ------ 底部按钮栏 ------
        Rectangle {
            id: btnBar
            Layout.fillWidth: true
            height: 76
            color: "#F8FAFC"

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 断开连接按钮（仅 WiFi 已连接时可用）
                Button {
                    id: disconnectBtn
                    text: "断开连接"
                    implicitWidth: 130
                    implicitHeight: 46
                    // 始终占位，断开后置灰禁用而非隐藏，避免布局跳动
                    enabled: NetworkManager.wifiStatus === NetworkManager.Connected
                    opacity: enabled ? 1.0 : 0.4

                    background: Rectangle {
                        radius: 8
                        color: disconnectBtn.enabled ?
                               (disconnectBtn.hovered ? "#FEE2E2" : "#FEEAEA") :
                               "#F1F5F9"
                        border.color: disconnectBtn.enabled ? "#EF4444" : "#E2E8F0"
                        border.width: 1.2
                    }

                    contentItem: Text {
                        text: disconnectBtn.text
                        font.pixelSize: 16
                        font.bold: true
                        color: disconnectBtn.enabled ? "#EF4444" : "#94A3B8"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    hoverEnabled: true
                    onClicked: {
                        console.log("[WifiList] 断开当前 Wi-Fi 连接")
                        NetworkManager.disconnectWifi()
                    }
                }

                // 关闭按钮
                Button {
                    id: closeBtn
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
            }
        }
    }

    // ========================================================================
    // 打开时先刷新状态再扫描
    // ========================================================================
    onOpened: {
        console.log("[WifiList] 弹窗打开, 当前状态: wifiStatus="
                    + NetworkManager.wifiStatus
                    + ", wifiSsid='" + NetworkManager.wifiSsid + "'")
        NetworkManager.refreshWifiStatus()
        Qt.callLater(function() {
            console.log("[WifiList] refresh后状态: wifiStatus="
                        + NetworkManager.wifiStatus
                        + ", wifiSsid='" + NetworkManager.wifiSsid + "'")
            console.log("[WifiList] 开始扫描网络")
            NetworkManager.scanWifiNetworks()
        })
    }
}
