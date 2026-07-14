import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0

Rectangle {
    id: root
    height: 103
    color: "transparent"

    // 点击设置图标发出的信号
    signal settingsRequested()
    // 点击调试按钮发出的信号（测试阶段）
    signal debugRequested()
    // 点击网络图标发出的信号 — 根据状态打开 WiFi 或 4G 弹窗
    signal networkRequested()

    RowLayout {
        id: mainRow
        anchors.fill: parent
        anchors.leftMargin: 54
        anchors.rightMargin: 54
        spacing: 0
        height: parent.height                     // 显式约束不溢出
        Item {
            id: userArea
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height
            Layout.preferredWidth: userRow.implicitWidth
            visible: BackendAuth.avatarUrl || BackendAuth.currentUser

            RowLayout {
                id: userRow
                anchors.fill: parent
                spacing: 12
                Layout.alignment: Qt.AlignVCenter

                // 圆形头像（优先显示远程头像，回退到首字母）
                Rectangle {
                    width: 48; height: 48; radius: 24
                    color: "#FFFFFF"
                    clip: true

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        source: BackendAuth.avatarUrl || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                    }

                    Text {
                        anchors.centerIn: parent
                        text: BackendAuth.currentUser ? BackendAuth.currentUser.charAt(0).toUpperCase() : "?"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#3B82F6"
                        visible: avatarImage.status !== Image.Ready || !BackendAuth.avatarUrl
                    }
                }

                // 用户名
                Text {
                    text: BackendAuth.currentUser || "未登录"
                    font.pixelSize: 34
                    font.bold: true
                    color: "#FFFFFF"
                    elide: Text.ElideRight
                    Layout.maximumWidth: 200
                }
            }

            // 点击跳转登录/退出（覆盖整个用户区，父级是 Item 非 layout，anchors 合法）
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.settingsRequested()
                }
            }
        }

        // 弹性占位：把右侧推到最右
        Item { Layout.fillWidth: true }

        // ===== 右侧：日期时间 + 状态图标行 =====
        RowLayout {
            spacing: 16
            Layout.alignment: Qt.AlignVCenter
            Layout.preferredHeight: root.height       // 占满栏高，垂直方向有明确基准
            // 日期时间显示（上下两行）
            ColumnLayout {
                spacing: 2
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: dateText
                    text: ""
                    font.pixelSize: 24
                  
                    font.bold: true
                    color: "#FFFFFF"
                }

                RowLayout {
                    spacing: 8

                    Text {
                        id: weekText
                        text: ""
                        font.pixelSize: 24
                       
                        font.bold: true
                        color: "#FFFFFF"
                    }

                    Text {
                        id: timeText
                        text: "00:00:00"
                        font.pixelSize: 24
                        font.family: "Monospace"
                        font.bold: true
                        color: "#FFFFFF"
                    }
                }
            }

    // ===== 智能网络状态图标（根据当前连接状态自动切换） =====
    // 逻辑: 4G开→显示4G+信号 | WiFi开4G关→显示WiFi波形 | 都关→断网图标
    Item {
        id: networkIconArea
        width: 44; height: 44
        Layout.alignment: Qt.AlignVCenter

        // ---- 4G 图标 (cellularEnabled 时显示) ----
        Item {
            id: icon4g
            anchors.fill: parent
            visible: isCellularActive() && NetworkManager.wifiStatus !== NetworkManager.Connected

            Row {
                anchors.centerIn: parent
                spacing: 4

                

                Image {
                    source: "qrc:/resources/img/Signal" + signalLevel(NetworkManager.cellularSignal) + ".png"
                    width: 44; height: 44
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // ---- WiFi 图标 (WiFi已连接时显示) ----
        Item {
            id: iconWifi
            anchors.fill: parent
            visible: NetworkManager.wifiStatus === NetworkManager.Connected

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

            Image {
                anchors.centerIn: parent
                source: "qrc:/resources/img/Wifi" + signalLevel(NetworkManager.wifiSignal) + ".png"
                width: 44; height: 44
                fillMode: Image.PreserveAspectFit
            }
        }

        // ---- 断网图标 (都未连接时显示) ----
        Item {
            id: iconDisconnected
            anchors.fill: parent
            visible: !isCellularActive() && NetworkManager.wifiStatus !== NetworkManager.Connected

            Image {
                anchors.centerIn: parent
                source: "qrc:/resources/img/Wifi0.png"
                width: 40; height: 40
                fillMode: Image.PreserveAspectFit
            }
        }

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
            // Item {
            //     width: 46; height: 46
            //     Layout.alignment: Qt.AlignVCenter

            //         Rectangle {
            //             id: debugBg
            //             anchors.fill: parent
            //             radius: 6
            //             color: "transparent"

            //             states: State {
            //                 name: "hovered"; when: debugMouse.containsMouse
            //                 PropertyChanges { target: debugBg; color: "#25FFFFFF" }
            //             }
            //         }

            //         // 调试图标 (bug / 终端风格)
            //         Canvas {
            //             anchors.centerIn: parent
            //             width: 30; height: 30
            //             onPaint: {
            //                 var ctx = getContext("2d")
            //                 ctx.strokeStyle = "#FFFFFF"
            //                 ctx.lineWidth = 2.6
            //                 ctx.lineCap = "round"
            //                 ctx.lineJoin = "round"
            //                 var cx = width / 2, cy = height / 2
            //                 ctx.strokeRect(cx - 11, cy - 7.5, 22, 15)
            //                 ctx.beginPath()
            //                 ctx.moveTo(cx - 6, cy + 4)
            //                 ctx.lineTo(cx, cy + 4)
            //                 ctx.moveTo(cx + 5, cy)
            //                 ctx.lineTo(cx + 5, cy + 6)
            //                 ctx.stroke()
            //             }
            //             Component.onCompleted: requestPaint()
            //         }

            //         MouseArea {
            //             id: debugMouse
            //             anchors.fill: parent
            //             hoverEnabled: true
            //             onClicked: {
            //                 console.log("[StatusBar] 调试按钮被点击")
            //                 root.debugRequested()
            //             }
            //         }
            //     }

                // 设置齿轮图标
                Item {
                    width: 44; height: 44
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: gearBg
                        anchors.fill: parent
                        radius: 6
                        color: "transparent"

                        states: State {
                            name: "hovered"; when: setGearMouse.containsMouse
                            PropertyChanges { target: gearBg; color: "#25FFFFFF" }
                        }
                    }

                    Image {
                        anchors.centerIn: parent
                        source: "qrc:/resources/img/Setting.png"
                        width: 30; height: 30
                        fillMode: Image.PreserveAspectFit
                    }

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
        text: BackendAuth.custNm || ""
        
        font.pixelSize: 40
        font.bold: true
        font.family: "Alimama ShuHeiTi"
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
            var y = currentDate.getFullYear()
            var m = currentDate.getMonth() + 1
            var d = currentDate.getDate()
            var weekDays = ["日", "一", "二", "三", "四", "五", "六"]
            var w = weekDays[currentDate.getDay()]
            dateText.text = y + "年" + m + "月" + d + "日"
            weekText.text = "星期" + w
            timeText.text = currentDate.toLocaleTimeString(Qt.locale(), "hh:mm:ss")
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
     * @brief 将信号强度 (0~100) 映射为图标等级 (0~4)
     * @param sig - 信号强度百分比
     * @return 等级字符串 "0" ~ "4"
     */
    function signalLevel(sig) {
        var s = Math.max(0, Math.min(100, sig || 0))
        if (s <= 20) return "0"
        if (s <= 40) return "1"
        if (s <= 60) return "2"
        if (s <= 80) return "3"
        return "4"
    }
}
