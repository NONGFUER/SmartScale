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

    width: 420
    height: Math.min(580, contentArea.implicitHeight + topBar.height + btnBar.height + 16)

    // 进入/退出动画
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
    }

    // ========================================================================
    // 主体背景
    // ========================================================================
    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        Rectangle {
            width: 6
            height: parent.height
            radius: 12
            color: "#3B82F6"
            anchors.left: parent.left
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
            height: 52
            radius: 12
            color: "#FFFFFF"

            layer.enabled: true
            layer.effect: Item {
                Rectangle {
                    anchors.fill: parent
                    color: "#1A5CB5"
                    radius: 12
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.radius
                        color: parent.color
                    }
                }
            }

            RowLayout {
                anchors.centerIn: parent
                spacing: 10

                Text {
                    text: "\U0001F4F6"
                    font.pixelSize: 20
                }
                Text {
                    text: "选择 Wi-Fi 网络"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#FFFFFF"
                }
            }
        }

        // ------ 网络列表区域 ------
        ColumnLayout {
            id: contentArea
            Layout.fillWidth: true
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            Layout.topMargin: 16
            Layout.bottomMargin: 12
            spacing: 10

            // 当前连接状态 + 扫描按钮行
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // 状态指示
                Row {
                    spacing: 6
                    Layout.fillWidth: true

                    Rectangle {
                        id: statusDot
                        width: 10; height: 10; radius: 5
                        y: (parent.height - height) / 2
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
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: Theme.fontSizeCaption
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
                    width: 72; height: 30; radius: 6
                    color: scanBtnMouse.containsMouse ? "#EBF5FF" : "#F0F7FF"
                    border.color: "#3B82F6"
                    border.width: 1
                    opacity: NetworkManager.isScanning ? 0.6 : 1.0

                    visible: NetworkManager.wifiStatus !== NetworkManager.Connecting

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        BusyIndicator {
                            running: NetworkManager.isScanning
                            width: 14; height: 14
                            visible: running
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: NetworkManager.isScanning ? "扫描中..." : "扫描"
                            font.pixelSize: Theme.fontSizeCaptionSm
                            font.bold: true
                            color: "#3B82F6"
                            visible: !NetworkManager.isScanning || !NetworkManager.isScanning  // always show text
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
                Layout.minimumHeight: 280
                Layout.maximumHeight: 400
                radius: 8
                color: "#FAFBFC"
                border.color: Theme.colorDivider
                border.width: 1
                clip: true

                ListView {
                    id: listView
                    anchors.fill: parent
                    anchors.margins: 4
                    model: NetworkManager.availableNetworks
                    clip: true
                    spacing: 2

                    // 空状态提示
                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0 && !NetworkManager.isScanning
                        text: "暂无可用网络\n点击「扫描」搜索附近网络"
                        font.pixelSize: Theme.fontSizeBodySm
                        color: Theme.colorTextTertiary
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: listView.count === 0 && NetworkManager.isScanning
                        text: "正在扫描..."
                        font.pixelSize: Theme.fontSizeBodySm
                        color: Theme.colorTextTertiary
                    }

                    delegate: Rectangle {
                        id: netDelegate
                        width: listView.width - 8
                        height: 48
                        radius: 6

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
                            width: 3
                            radius: 6
                            color: "#22C55E"
                            anchors.leftMargin: 0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 12
                            spacing: 10

                            // 已连接 ✓ 标记
                            Text {
                                visible: netDelegate.isCurrentNetwork
                                text: "\u2713"
                                font.pixelSize: 16
                                font.bold: true
                                color: "#22C55E"
                            }

                            // SSID 名称
                            Text {
                                text: modelData.ssid || ""
                                font.pixelSize: Theme.fontSizeBodySm
                                font.bold: netDelegate.isCurrentNetwork
                                color: netDelegate.isCurrentNetwork ? "#166534" : Theme.colorTextPrimary
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                                Layout.maximumWidth: 180
                            }

                            // 已连接标签
                            Text {
                                visible: netDelegate.isCurrentNetwork
                                text: "已连接"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#FFFFFF"
                                Rectangle {
                                            z: -1
                                            anchors.fill: parent
                                            anchors.margins: -3
                                            radius: 3
                                            color: "#22C55E"
                                        }
                            }

                            // 额外信息（5G / 频段标签）
                            Text {
                                visible: !netDelegate.isCurrentNetwork && modelData.signal >= 70
                                text: "5G"
                                font.pixelSize: 11
                                font.bold: true
                                color: "#EF4444"
                            }

                            // 加密锁图标
                            Text {
                                visible: !netDelegate.isCurrentNetwork && modelData.secured
                                text: "\uD83D\uDD12"
                                font.pixelSize: 15
                            }

                            // 信号强度图标（WiFi 波形）
                            Item {
                                visible: !netDelegate.isCurrentNetwork
                                width: 20; height: 16
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        var sig = modelData.signal || 0
                                        ctx.strokeStyle = sig > 50 ? "#3B82F6" : (sig > 25 ? "#F59E0B" : "#9CA3AF")
                                        ctx.lineWidth = 1.8
                                        ctx.lineCap = "round"
                                        ctx.lineJoin = "round"
                                        var cx = 4, cy = 14
                                        ctx.beginPath()
                                        ctx.arc(cx, cy, 3, Math.PI, 0)
                                        ctx.stroke()
                                        if (sig > 20) { ctx.beginPath(); ctx.arc(cx, cy, 6, Math.PI, 0); ctx.stroke() }
                                        if (sig > 45) { ctx.beginPath(); ctx.arc(cx, cy, 9, Math.PI, 0); ctx.stroke() }
                                        if (sig > 70) { ctx.beginPath(); ctx.arc(cx, cy, 12, Math.PI, 0); ctx.stroke() }
                                    }
                                    Component.onCompleted: requestPaint()
                                }
                            }

                            // 信号百分比
                            Text {
                                visible: !netDelegate.isCurrentNetwork
                                text: (modelData.signal || 0) + "%"
                                font.pixelSize: Theme.fontSizeCaptionSm
                                color: Theme.colorTextTertiary
                                font.family: Theme.fontFamilyMono
                            }
                        }

                        MouseArea {
                            id: netMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: !netDelegate.isCurrentNetwork  // 已连接的网络不可重复点击
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
                font.pixelSize: Theme.fontSizeCaptionSm
                color: Theme.colorTextTertiary
                horizontalAlignment: Text.AlignHCenter
                visible: listView.count > 0
            }
        }

        // ------ 底部按钮栏 ------
        Rectangle {
            id: btnBar
            Layout.fillWidth: true
            height: 56
            color: "#F8FAFC"

            Button {
                id: closeBtn
                text: "关闭"
                anchors.centerIn: parent
                implicitWidth: 100
                implicitHeight: 34

                background: Rectangle {
                    radius: 6
                    color: closeBtn.hovered ? "#2563EB" : "#3B82F6"
                }

                contentItem: Text {
                    text: closeBtn.text
                    font.pixelSize: 14
                    font.bold: true
                    color: "#FFFFFF"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: root.close()
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
        // 延迟一点扫描，确保 refreshWifiStatus 已完成
        Qt.callLater(function() {
            console.log("[WifiList] refresh后状态: wifiStatus="
                        + NetworkManager.wifiStatus
                        + ", wifiSsid='" + NetworkManager.wifiSsid + "'")
            console.log("[WifiList] 开始扫描网络")
            NetworkManager.scanWifiNetworks()
        })
    }
}
