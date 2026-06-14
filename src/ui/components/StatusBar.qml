import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0

Rectangle {
    id: root
    height: 70

    // 点击设置图标发出的信号
    signal settingsRequested()

    // 蓝色渐变背景（左深右浅）
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#1A5CB5" }
        GradientStop { position: 1.0; color: "#4A90D9" }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 0

        // ===== 左侧：公司 logo + 名称 =====
        RowLayout {
            spacing: 10
            Layout.alignment: Qt.AlignVCenter

            // Logo 圆形图标
            Rectangle {
                width: 36
                height: 36
                radius: 18
                color: "#FFFFFF"
                opacity: 0.95
                Layout.alignment: Qt.AlignVCenter

                Text {
                    anchors.centerIn: parent
                    text: "A"
                    font.pixelSize: 22
                    font.bold: true
                    color: "#1A5CB5"
                }
            }

            Text {
                text: "小管事机器人集团公司"
                font.pixelSize: 18
                font.bold: true
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
            }
        }

        Item { Layout.fillWidth: true }

        // ===== 中间：大标题 =====
        Text {
            text: "AI称重系统"
            font.pixelSize: 28
            font.bold: true
            color: "#FFFFFF"
            Layout.alignment: Qt.AlignVCenter
        }

        Item { Layout.fillWidth: true }

        // ===== 右侧：日期时间 + 状态图标行 =====
        RowLayout {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter

            // 日期时间显示
            ColumnLayout {
                    spacing: 2
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: dateText
                        text: ""
                        font.pixelSize: 13
                        color: "#E8F0FE"
                        Layout.alignment: Qt.AlignHCenter
                    }

                    Text {
                        id: timeText
                        text: "00:00:00"
                        font.pixelSize: 18
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

                // WiFi 图标
                Item {
                    width: 18; height: 16
                    Layout.alignment: Qt.AlignVCenter

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.strokeStyle = "#FFFFFF"
                            ctx.lineWidth = 1.5
                            ctx.lineCap = "round"
                            ctx.lineJoin = "round"
                            var cx = width / 2, by = height - 1.5

                            // 三层弧线 + 底部圆点
                            ctx.beginPath(); ctx.arc(cx, by - 2, 2, Math.PI, 0); ctx.stroke()
                            ctx.beginPath(); ctx.arc(cx, by - 6, 5, 7 * Math.PI / 6, 11 * Math.PI / 6); ctx.stroke()
                            ctx.beginPath(); ctx.arc(cx, by - 9, 8, 13 * Math.PI / 12, 23 * Math.PI / 12); ctx.stroke()
                        }
                        Component.onCompleted: requestPaint()
                    }
                }

                // 设置齿轮图标
                Item {
                    width: 30; height: 30
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
