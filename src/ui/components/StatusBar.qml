import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0

Rectangle {
    id: root
    height: 60
    color: "transparent"

    // 点击设置图标发出的信号
    signal settingsRequested()
    // 点击调试按钮发出的信号（测试阶段）
    signal debugRequested()
    // 点击网络图标发出的信号 — 根据状态打开 WiFi 或 4G 弹窗
    signal networkRequested()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 0
        RowLayout {
            spacing: 20
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height
            Text {
                text: "© 2026 小管事机器人集团公司 Inc."
                font.pixelSize: 24
                font.bold: true
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
                Layout.maximumWidth: 500              // 限制最大宽度，防止吃掉中间空间
                elide: Text.ElideRight                // 超出省略号
            }
        }

        // 弹性占位：把右侧推到最右
        Item { Layout.fillWidth: true }

        // ===== 右侧：日期时间 + 状态图标行 =====
        RowLayout {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height       // 占满栏高，垂直方向有明确基准
            // 日期时间显示
            ColumnLayout {
                spacing: 0
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: dateText
                    text: ""
                    font.pixelSize: 14
                    color: "#E8F0FE"
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    id: timeText
                    text: "00:00:00"
                    font.pixelSize: 22
                    font.family: "Monospace"
                    font.bold: true
                    color: "#FFFFFF"
                    Layout.alignment: Qt.AlignHCenter
                }
            }

    // ===== 智能网络状态图标（根据当前连接状态自动切换） =====
    // 逻辑: 4G开→显示4G+信号 | WiFi开4G关→显示WiFi波形 | 都关→断网图标
    Item {
        id: networkIconArea
        width: 44; height: 32
        Layout.alignment: Qt.AlignVCenter

        // ---- 4G 图标 (cellularEnabled 时显示) ----
        // Item {
        //     id: icon4g
        //     anchors.fill: parent
        //     visible: isCellularActive()

        //     // "4G" 文字标签
        //     Text {
        //         anchors.left: parent.left
        //         anchors.verticalCenter: parent.verticalCenter
        //         text: isCellularRoaming() ? "R" : "4G"
        //         font.pixelSize: isCellularRoaming() ? 11 : 13
        //         font.bold: true
        //         color: "#FFFFFF"
        //     }

        //     // 4G 信号强度柱（紧跟文字右侧）
        //     Item {
        //         anchors.right: parent.right
        //         anchors.verticalCenter: parent.verticalCenter
        //         width: 18; height: 14

        //         Canvas {
        //             id: canvas4g
        //             anchors.fill: parent
        //             onPaint: {
        //                 var ctx = getContext("2d")
        //                 ctx.fillStyle = "#FFFFFF"
        //                 var sig = NetworkManager.cellularSignal || 0
        //                 var barW = 3, gap = 1.5, baseY = height - 1
        //                 var levels = [3, 6, 9, 12]
        //                 for (var i = 0; i < 4; i++) {
        //                     var x = i * (barW + gap)
        //                     var h = (sig > (i * 25 + 10)) ? levels[i] : 0
        //                     if (h > 0) {
        //                         // QML Canvas 不支持 roundRect，用圆角矩形辅助函数绘制
        //                         drawRoundedRect(ctx, x, baseY - h, barW, h, 1)
        //                     }
        //                 }
        //             }
        //             Component.onCompleted: requestPaint()
        //             // 4G 状态变化时重绘（用 id 引用，避免 parent 动态解析错误）
        //             Connections {
        //                 target: NetworkManager
        //                 function onCellularStatusChanged() { canvas4g.requestPaint() }
        //             }
        //         }
        //     }
        // }

        // ---- WiFi 图标 (WiFi已连接时显示) ----
        Item {
            id: iconWifi
            anchors.fill: parent
            visible: NetworkManager.wifiStatus === NetworkManager.Connected

            // 断网调试：追踪状态变化
            Connections {
                target: NetworkManager
                function onWifiStatusChanged() {
                    console.log("[StatusBar-DBG] onWifiStatusChanged:",
                                "status=", NetworkManager.wifiStatus,
                                "ssid='", NetworkManager.wifiSsid, "'",
                                "signal=", NetworkManager.wifiSignal,
                                "ip=", NetworkManager.wifiIpAddress,
                                "iconWifi.visible=", iconWifi.visible)
                }
            }

            Canvas {
                anchors.centerIn: parent
                width: 24; height: 20
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.strokeStyle = "#FFFFFF"
                    ctx.lineWidth = 2.2
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    var cx = width / 2, cy = height - 2
                    ctx.beginPath(); ctx.arc(cx, cy - 1, 9, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy - 1, 6, Math.PI * 1.2, Math.PI * 1.8); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy - 1, 3, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
                    ctx.fillStyle = "#FFFFFF"; ctx.fill()
                }
                Component.onCompleted: requestPaint()
            }

            // WiFi 信号强度小点（右下角）
            Rectangle {
                anchors.right: parent.right; anchors.bottom: parent.bottom
                width: 7; height: 7; radius: 3.5
                color: NetworkManager.wifiSignal > 60 ? "#4ADE80" :
                       NetworkManager.wifiSignal > 30 ? "#FACC15" : "#F87171"

                // WiFi 状态变化时更新颜色
                Connections {
                    target: NetworkManager
                    function onWifiStatusChanged() { parent.visible = (NetworkManager.wifiStatus === NetworkManager.Connected) }
                }
            }
        }

        // ---- 断网图标 (都未连接时显示) ----
        // Item {
        //     id: iconDisconnected
        //     anchors.fill: parent
        //     visible: !isCellularActive() && NetworkManager.wifiStatus !== NetworkManager.Connected

        //     // 斜杠划掉的信号波形
        //     Canvas {
        //         anchors.centerIn: parent
        //         width: 24; height: 20
        //         onPaint: {
        //             var ctx = getContext("2d")
        //             ctx.strokeStyle = "#8899AA"
        //             ctx.lineWidth = 2.0
        //             ctx.lineCap = "round"
        //             ctx.lineJoin = "round"
        //             var cx = width / 2, cy = height - 2
        //             // 淡色波形
        //             ctx.globalAlpha = 0.45
        //             ctx.beginPath(); ctx.arc(cx, cy - 1, 9, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke()
        //             ctx.beginPath(); ctx.arc(cx, cy - 1, 6, Math.PI * 1.2, Math.PI * 1.8); ctx.stroke()
        //             ctx.beginPath(); ctx.arc(cx, cy - 1, 3, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke()
        //             ctx.beginPath(); ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
        //             ctx.fillStyle = "#8899AA"; ctx.fill()
        //             ctx.globalAlpha = 1.0
        //             // 斜杠
        //             ctx.strokeStyle = "#EF4444"
        //             ctx.lineWidth = 2.5
        //             ctx.beginPath()
        //             ctx.moveTo(2, 2)
        //             ctx.lineTo(width - 2, height - 2)
        //             ctx.stroke()
        //         }
        //         Component.onCompleted: requestPaint()
        //     }
        // }

        // 点击区域 — 统一打开网络弹窗
        MouseArea {
            id: networkMouse
            anchors.fill: parent
            hoverEnabled: true

            property bool hovered: containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: networkMouse.hovered ? "#25FFFFFF" : "transparent"
                visible: networkMouse.hovered
            }

            onClicked: {
                console.log("[StatusBar] 网络图标被点击, 当前状态:"
                            , "wifi=" + NetworkManager.wifiStatus
                            , "4g=" + NetworkManager.cellularStatus)
                root.networkRequested()
            }
        }
    }

            // 调试按钮（测试阶段，放在设置齿轮左侧）
            Item {
                width: 40; height: 40
                Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: debugBg
                        anchors.fill: parent
                        radius: 4
                        color: "transparent"

                        states: State {
                            name: "hovered"; when: debugMouse.containsMouse
                            PropertyChanges { target: debugBg; color: "#25FFFFFF" }
                        }
                    }

                    // 调试图标 (bug / 终端风格)
                    Canvas {
                        anchors.centerIn: parent
                        width: 24; height: 24
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 2.2
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var cx = width / 2, cy = height / 2
                            // 终端窗口外形
                            ctx.strokeRect(cx - 9, cy - 6, 18, 12)
                            // 提示符 "_"
                            ctx.beginPath()
                            ctx.moveTo(cx - 5, cy + 3)
                            ctx.lineTo(cx, cy + 3)
                            ctx.moveTo(cx + 4, cy)
                            ctx.lineTo(cx + 4, cy + 5)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }

                    MouseArea {
                        id: debugMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("[StatusBar] 调试按钮被点击")
                            root.debugRequested()
                        }
                    }
                }

                // 设置齿轮图标
                Item {
                    width: 40; height: 40
                    Layout.alignment: Qt.AlignVCenter

                    // 悬停背景
                    Rectangle {
                        id: gearBg
                        anchors.fill: parent
                        radius: 4
                        color: "transparent"

                        states: State {
                            name: "hovered"; when: setGearMouse.containsMouse
                            PropertyChanges { target: gearBg; color: "#25FFFFFF" }
                        }
                    }

                    // 齿轮图形
                    Canvas {
                        id: gearIcon
                        anchors.centerIn: parent
                        width: 26; height: 26
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 2.4
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var cx = width / 2, cy = height / 2
                            ctx.beginPath()
                            var r = 9, teeth = 8
                            for (var i = 0; i < teeth; i++) {
                                var a1 = (i / teeth) * 2 * Math.PI - Math.PI / 2
                                var a2 = ((i + 0.35) / teeth) * 2 * Math.PI - Math.PI / 2
                                var a3 = ((i + 0.65) / teeth) * 2 * Math.PI - Math.PI / 2
                                var a4 = ((i + 1) / teeth) * 2 * Math.PI - Math.PI / 2
                                var px1 = cx + r * Math.cos(a1), py1 = cy + r * Math.sin(a1)
                                var px2 = cx + (r + 3) * Math.cos(a2), py2 = cy + (r + 3) * Math.sin(a2)
                                var px3 = cx + (r + 3) * Math.cos(a3), py3 = cy + (r + 3) * Math.sin(a3)
                                var px4 = cx + r * Math.cos(a4), py4 = cy + r * Math.sin(a4)
                                if (i === 0) ctx.moveTo(px1, py1)
                                else ctx.lineTo(px1, py1)
                                ctx.lineTo(px2, py2); ctx.lineTo(px3, py3); ctx.lineTo(px4, py4)
                            }
                            ctx.closePath(); ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(cx, cy, 4, 0, 2 * Math.PI)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // 点击区域放在最后，确保在最上层接收事件
                    MouseArea {
                        id: setGearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("[StatusBar] 设置图标被点击")
                            root.settingsRequested()
                        }
                    }
                }
            }
    }

    // ===== 中间：大标题（独立锚定到 root 中心，不参与 RowLayout） =====
    Text {
        anchors.centerIn: parent
        height: 60                              // 框铺满状态栏高度
        text: "AI 视 觉 识 别 智 能 网 络 秤"
        font.family: "AlibabaPuHuiTi"
        font.pixelSize: 36
        font.bold: true
        color: "#FFFFFF"
        elide: Text.ElideRight
        width: Math.min(implicitWidth, parent.width - 600)   // 极端情况也不溢出
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter                // 文字在框内垂直居中
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            var currentDate = new Date()
            timeText.text = currentDate.toLocaleTimeString(Qt.locale(), "hh:mm:ss")
            dateText.text = currentDate.toLocaleDateString(Qt.locale(), "yyyy-MM-dd")
        }
    }

    // ===== 网络状态判断辅助函数 =====

    /** @brief 判断 4G 是否处于激活状态（有数据连接：已连接/漫游） */
    function isCellularActive() {
        var s = NetworkManager.cellularStatus
        return s === NetworkManager.CellConnected || s === NetworkManager.CellRoaming
    }

    /** @brief 判断 4G 是否处于漫游状态 */
    function isCellularRoaming() {
        return NetworkManager.cellularStatus === NetworkManager.CellRoaming
    }

    /**
     * @brief 在 Canvas 上下文中绘制圆角矩形（QML Canvas 不支持 roundRect）
     * @param ctx   - Canvas 2D context
     * @param x, y  - 左上角坐标
     * @param w, h  - 宽高
     * @param r     - 圆角半径
     */
    function drawRoundedRect(ctx, x, y, w, h, r) {
        if (r <= 0) {
            ctx.fillRect(x, y, w, h)
            return
        }
        // 限制半径不超过半边长
        r = Math.min(r, Math.min(w / 2, h / 2))
        ctx.beginPath()
        ctx.moveTo(x + r, y)
        ctx.lineTo(x + w - r, y)
        ctx.arcTo(x + w, y, x + w, y + r, r)
        ctx.lineTo(x + w, y + h - r)
        ctx.arcTo(x + w, y + h, x + w - r, y + h, r)
        ctx.lineTo(x + r, y + h)
        ctx.arcTo(x, y + h, x, y + h - r, r)
        ctx.lineTo(x, y + r)
        ctx.arcTo(x, y, x + r, y, r)
        ctx.closePath()
        ctx.fill()
    }
}
