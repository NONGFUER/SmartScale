import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    height: 60
    color: "transparent"

    // 点击设置图标发出的信号
    signal settingsRequested()
    // 点击调试按钮发出的信号（测试阶段）
    signal debugRequested()
    // 点击 WiFi 图标发出的信号 — 打开网络选择弹窗
    signal wifiRequested()

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

            // 信号强度图标（4格柱状）
            Item {
                width: 20; height: 16
                Layout.alignment: Qt.AlignVCenter

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.strokeStyle = "#FFFFFF"
                        ctx.lineWidth = 1.5
                        ctx.lineCap = "round"
                        var barW = 3, gap = 2, baseY = height - 1
                        for (var i = 0; i < 4; i++) {
                            var h = [5, 8, 11, 15][i]
                            var x = i * (barW + gap) + 1
                            ctx.beginPath()
                            ctx.moveTo(x, baseY)
                            ctx.lineTo(x, baseY - h)
                            ctx.stroke()
                        }
                    }
                    Component.onCompleted: requestPaint()
                }
            }

            // Wi-Fi 图标（点击弹出网络选择弹窗）
            Item {
                width: 36; height: 28
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    id: wifiBg
                    anchors.fill: parent
                    radius: 4
                    color: "transparent"

                    states: State {
                        name: "hovered"; when: wifiMouse.containsMouse
                        PropertyChanges { target: wifiBg; color: "#25FFFFFF" }
                    }
                }

                // WiFi 波形图标
                Canvas {
                    anchors.centerIn: parent
                    width: 22; height: 18
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.strokeStyle = "#FFFFFF"
                        ctx.lineWidth = 2.0
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        var cx = width / 2, cy = height - 2
                        // 从外到内画三道弧 + 底部圆点
                        if (true) { ctx.beginPath(); ctx.arc(cx, cy - 1, 9, Math.PI * 1.15, Math.PI * 1.85); ctx.stroke() }
                        if (true) { ctx.beginPath(); ctx.arc(cx, cy - 1, 6, Math.PI * 1.2, Math.PI * 1.8); ctx.stroke() }
                        if (true) { ctx.beginPath(); ctx.arc(cx, cy - 1, 3, Math.PI * 1.25, Math.PI * 1.75); ctx.stroke() }
                        ctx.beginPath()
                        ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
                        ctx.fillStyle = "#FFFFFF"
                        ctx.fill()
                    }
                    Component.onCompleted: requestPaint()
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        console.log("[StatusBar] WiFi 图标被点击")
                        root.wifiRequested()
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
}
