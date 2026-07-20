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
    // 点击用户头像/名字区域发出的信号 — 已登录时弹出退出登录确认
    signal userAreaClicked()
    // 点击用户头像/名字区域发出的信号 — 未登录时打开登录弹窗
    signal loginRequested()

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
            visible: true  // 始终显示：未登录时作为登录入口

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
                    text: BackendAuth.currentUser || "点击登录"
                    font.pixelSize: 34
                    font.bold: true
                    color: "#FFFFFF"
                    elide: Text.ElideRight
                    Layout.maximumWidth: 200
                }
            }

            // 点击用户区域：已登录 → 退出登录确认；未登录 → 打开登录弹窗
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    if (BackendAuth.currentUser) {
                        root.userAreaClicked()
                    } else {
                        root.loginRequested()
                    }
                }
            }
        }

        // 弹性占位：把右侧图标组推到最右
        Item { Layout.fillWidth: true }

        // ===== 右侧：状态图标行 =====
        RowLayout {
            spacing: 12
            Layout.alignment: Qt.AlignVCenter

            // ---- 4G 信号图标 ----
            Item {
                width: 44; height: 44
                visible: isCellularActive()

                Rectangle {
                    id: cellBg
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"

                    states: State {
                        name: "hovered"; when: cellMouse.containsMouse
                        PropertyChanges { target: cellBg; color: "#25FFFFFF" }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/resources/img/Signal" + signalLevel(NetworkManager.cellularSignal) + ".png"
                    width: 44; height: 44
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.networkRequested()
                }
            }

            // ---- WiFi 图标 ----
            Item {
                width: 44; height: 44
                visible: NetworkManager.wifiStatus === NetworkManager.Connected

                Connections {
                    target: NetworkManager
                    function onWifiStatusChanged() {
                        console.log("[StatusBar-DBG] onWifiStatusChanged:",
                                    "status=", NetworkManager.wifiStatus,
                                    "ssid='", NetworkManager.wifiSsid, "'",
                                    "signal=", NetworkManager.wifiSignal)
                    }
                }

                Rectangle {
                    id: wifiBg
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"

                    states: State {
                        name: "hovered"; when: wifiMouse.containsMouse
                        PropertyChanges { target: wifiBg; color: "#25FFFFFF" }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/resources/img/Wifi" + signalLevel(NetworkManager.wifiSignal) + ".png"
                    width: 44; height: 44
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: wifiMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.networkRequested()
                }
            }

            // ---- 断网占位（都未连接时显示，避免布局塌缩） ----
            Item {
                width: 44; height: 44
                visible: !isCellularActive() && NetworkManager.wifiStatus !== NetworkManager.Connected

                Rectangle {
                    id: discBg
                    anchors.fill: parent
                    radius: 6
                    color: "transparent"

                    states: State {
                        name: "hovered"; when: discMouse.containsMouse
                        PropertyChanges { target: discBg; color: "#25FFFFFF" }
                    }
                }

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/resources/img/Wifi0.png"
                    width: 44; height: 44
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: discMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.networkRequested()
                }
            }

            // ---- 设置齿轮图标 ----
            Item {
                width: 44; height: 44

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
                    width: 40; height: 40
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: setGearMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.settingsRequested()
                }
            }
        }
    }

    // ===== 中间：大标题（独立锚定到 root 中心，不参与 RowLayout） =====
    Text {
        id: titleText
        anchors.centerIn: parent
        height: 60                              // 框铺满状态栏高度
        text: BackendAuth.custNm || ""
        
        font.pixelSize: 40
        font.bold: true
        font.family: "Alimama ShuHeiTi"
        color: "#FFFFFF"
        elide: Text.ElideRight
        width: 900                              // 固定占位宽度，避免字数变化影响布局
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter                // 文字在框内垂直居中
    }

    // ===== 日期时间显示（上下两行）— 锚定到大标题右侧 =====
    // 布局：ColumnLayout 宽度自动跟随 Row（"星期五 18:10:20"）的宽度，
    //       dateText 居中于 ColumnLayout = 居中于时间行的整体中心。
    ColumnLayout {
        id: dateTimeCol
        anchors.left: titleText.right
        anchors.leftMargin: 30
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
            id: dateText
            text: ""
            font.pixelSize: 24
            font.bold: true
            color: "#FFFFFF"
            Layout.alignment: Qt.AlignHCenter  // 年月日居中于（星期+时分秒）的总宽度
        }

        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignHCenter

            Text {
                id: weekText
                text: ""
                font.pixelSize: 24
                font.bold: true
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
                // 显式设 height + verticalAlignment 让中文字符框与数字字符框行内垂直居中
                height: 32
                verticalAlignment: Text.AlignVCenter
            }

            Text {
                id: timeText
                text: "00:00:00"
                font.pixelSize: 24
               
                font.bold: true
                color: "#FFFFFF"
                Layout.alignment: Qt.AlignVCenter
                height: 32
                verticalAlignment: Text.AlignVCenter
            }
        }
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
