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

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 0

        // ===== 左侧：软件版本号 =====
        RowLayout {
            spacing: 20
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height
            Text {
                text: "软件版本: " + SystemInfo.appVersion
                font.pixelSize: 24
                font.bold: true
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item { Layout.fillWidth: true }

        // ===== 中间：大标题 =====
        Item {
            Layout.preferredHeight: root.height
            Layout.alignment: Qt.AlignVCenter
            // 外边距
            Layout.topMargin: 20
            Layout.leftMargin: 40
            Layout.rightMargin: 40

            Text {
                anchors.centerIn: parent   // 相当于 padding: 均匀分布
                text: "AI 视 觉 识 别 智 能 网 络 称"
                font.family: "AlibabaPuHuiTi"
                font.pixelSize: 36
                font.bold: true
                color: "#FFFFFF"
            }
        }

        Item { Layout.fillWidth: true }

        // ===== 右侧：日期时间 + 状态图标行 =====
        RowLayout {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height
            // 日期时间显示
            ColumnLayout {
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: dateText
                        text: ""
                        font.pixelSize: 18
                        color: "#E8F0FE"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        id: timeText
                        text: "00:00:00"
                        font.pixelSize: 24
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
                        width: 18; height: 18
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 1.6
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var cx = width / 2, cy = height / 2
                            // 终端窗口外形
                            ctx.strokeRect(cx - 7, cy - 5, 14, 10)
                            // 提示符 "_"
                            ctx.beginPath()
                            ctx.moveTo(cx - 4, cy + 2)
                            ctx.lineTo(cx, cy + 2)
                            ctx.moveTo(cx + 3, cy)
                            ctx.lineTo(cx + 3, cy + 4)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }

                    MouseArea {
                        id: debugMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
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
                        width: 20; height: 20
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 1.8
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var cx = width / 2, cy = height / 2
                            ctx.beginPath()
                            var r = 7, teeth = 8
                            for (var i = 0; i < teeth; i++) {
                                var a1 = (i / teeth) * 2 * Math.PI - Math.PI / 2
                                var a2 = ((i + 0.35) / teeth) * 2 * Math.PI - Math.PI / 2
                                var a3 = ((i + 0.65) / teeth) * 2 * Math.PI - Math.PI / 2
                                var a4 = ((i + 1) / teeth) * 2 * Math.PI - Math.PI / 2
                                var px1 = cx + r * Math.cos(a1), py1 = cy + r * Math.sin(a1)
                                var px2 = cx + (r + 2.5) * Math.cos(a2), py2 = cy + (r + 2.5) * Math.sin(a2)
                                var px3 = cx + (r + 2.5) * Math.cos(a3), py3 = cy + (r + 2.5) * Math.sin(a3)
                                var px4 = cx + r * Math.cos(a4), py4 = cy + r * Math.sin(a4)
                                if (i === 0) ctx.moveTo(px1, py1)
                                else ctx.lineTo(px1, py1)
                                ctx.lineTo(px2, py2); ctx.lineTo(px3, py3); ctx.lineTo(px4, py4)
                            }
                            ctx.closePath(); ctx.stroke()
                            ctx.beginPath()
                            ctx.arc(cx, cy, 3, 0, 2 * Math.PI)
                            ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }

                    // 点击区域放在最后，确保在最上层接收事件
                    MouseArea {
                        id: setGearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            console.log("[StatusBar] 设置图标被点击")
                            root.settingsRequested()
                        }
                    }
                }
            }
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
