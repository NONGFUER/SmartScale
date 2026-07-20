import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

/**
 * @brief 4G 信息弹窗 — 显示当前运营商，提供"启用SIM卡"开关（重启记忆）
 *
 * 样式完全对齐 WifiPasswordDialog：
 *   - 非模态 + 外部遮罩（避让虚拟键盘）
 *   - 顶部：back2.png + "返回" 圆角胶囊；中间标题绝对居中
 *   - 底部按钮：180×60 r15 浅蓝底"关闭"
 *   - 全文字号统一 24px
 *
 * 数据源：
 *   - 运营商：NetworkManager.cellularOperator
 *   - 开关状态：NetworkManager.cellularStatus（实际硬件状态）
 *   - 开关持久化：AppSettings.cellularEnabled（重启后恢复上次状态）
 *
 * 控制命令：底层由 NetworkManagerService 走 sudo ip link set <dev> up/down，
 *          依赖 sudoers 免密配置（/etc/sudoers.d/smartscale-4g）。
 *
 * 使用方式：
 *   CellularDialog { id: cellularDialog }
 *   cellularDialog.open()
 */
Popup {
    id: root

    modal: false
    closePolicy: Popup.CloseOnEscape
    padding: 0
    z: 50

    width: 560
    height: 420

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘，不挡虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: root.visible

        Behavior on opacity { NumberAnimation { duration: 180 } }

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
        NumberAnimation { property: "scale"; from: 0.95; to: 1.0; duration: 180; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 120; easing.type: Easing.InCubic }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.95; duration: 120; easing.type: Easing.InCubic }
    }

    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#002A75"
            shadowOpacity: 0.1
            shadowBlur: 1.0
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 0
        }
    }

    // ========================================================================
    // 内容区
    // ========================================================================
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ------ 顶部标题栏 ------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 80
            radius: 16
            color: "#FFFFFF"

            // 左侧：返回按钮 — back2.png + "返回"（圆角胶囊）
            Rectangle {
                id: backBtn
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 116; height: 44; radius: 22
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/resources/img/back2.png"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "返回"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#4649E5"
                    }
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.close()
                }
            }

            // 中间：标题（绝对居中）
            Text {
                anchors.centerIn: parent
                text: "4G 移动数据"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextPrimary
            }
        }

        // 分隔线
        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            height: 1
            color: "#E2E8F0"
        }

        // ------ 信息区域 ------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 36
            Layout.rightMargin: 36
            Layout.topMargin: 32
            Layout.bottomMargin: 20
            spacing: 28

            // ===== 运营商行 =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "运营商"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextSecondary
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: operatorText()
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextPrimary
                }
            }

            // ===== 启用SIM卡开关行 =====
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                Text {
                    text: "启用SIM卡"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextSecondary
                }

                Item { Layout.fillWidth: true }

                // 自定义 Switch（54×30，开=绿/关=灰）
                Item {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 36
                    enabled: NetworkManager.hasCellularHardware && !isOperating()

                    Rectangle {
                        id: switchTrack
                        anchors.fill: parent
                        radius: 18
                        color: isSimOn() ? "#4361EE" : "#D1D5DB"

                        Behavior on color { ColorAnimation { duration: 150 } }

                        Rectangle {
                            x: isSimOn() ? parent.width - width - 3 : 3
                            y: (parent.height - height) / 2
                            width: 30; height: 30
                            radius: 15
                            color: "white"
                            border.color: "#999"
                            border.width: 1

                            Behavior on x { NumberAnimation { duration: 150 } }
                        }
                    }

                    // 无硬件时覆盖层（半透明 + 禁用图标）
                    Rectangle {
                        anchors.fill: parent
                        visible: !NetworkManager.hasCellularHardware
                        radius: 18
                        color: "#00000044"

                        Text {
                            anchors.centerIn: parent
                            text: "\u2717"
                            font.pixelSize: 18
                            color: "#FFFFFFAA"
                        }
                    }

                    MouseArea {
                        id: switchMouse
                        anchors.fill: parent
                        enabled: parent.enabled

                        onClicked: {
                            var turningOn = !isSimOn()
                            console.log("[CellularDialog] 切换 4G 开关 ->", turningOn ? "ON" : "OFF")

                            // 先写持久化记忆（无论操作成败都记住用户意图，重启后按此恢复）
                            AppSettings.cellularEnabled = turningOn

                            if (turningOn) {
                                NetworkManager.enableCellular()
                            } else {
                                NetworkManager.disableCellular()
                            }
                        }
                    }
                }
            }

            // 错误提示（操作失败时显示，仍用 24px 保持全文字号统一）
            Text {
                Layout.fillWidth: true
                visible: NetworkManager.cellularStatus === NetworkManager.CellError
                text: NetworkManager.lastError || "4G 操作失败"
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: "#EF4444"
                wrapMode: Text.Wrap
            }

            // 弹性占位：把下方按钮栏压到底部
            Item { Layout.fillHeight: true }
        }

        // ------ 底部按钮栏（180×60 r15，与 WifiPasswordDialog 一致）------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            Layout.bottomMargin: 24

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 关闭按钮（浅蓝底）
                Rectangle {
                    width: 180; height: 60; radius: 15
                    color: closeMouse.containsMouse ? "#FFFFFF" : "#ECF1FE"
                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "退出"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#4649E5"
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.close()
                    }
                }
            }
        }
    }

    // ========================================================================
    // 结果反馈：操作失败用全局 toast 提示（成功状态由轮询自动刷新到开关上）
    // ========================================================================
    Connections {
        target: NetworkManager

        function onCellularOperationFailed(errorMsg) {
            if (root.visible) {
                window.toast(errorMsg || "4G 操作失败", "error", 3000)
            }
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

    /**
     * @brief 运营商显示文本
     *
     * 数据源优先级：
     *   1. CellularModem.operatorName — AT+COPS? 串口直查的真实运营商名（如 "CHINA MOBILE"）
     *      不依赖网络连接状态，只要 SIM 已注册网络就有值
     *   2. NetworkManager.cellularOperator — nmcli 接口模式的连接名（仅已连接时有意义）
     *   3. 状态占位文案（未启用/搜索中/未检测到模块）
     */
    function operatorText() {
        // AT 直查到的运营商名最权威，有就直接用
        if (CellularModem.operatorName && CellularModem.operatorName.length > 0)
            return CellularModem.operatorName

        var s = NetworkManager.cellularStatus
        if (!NetworkManager.hasCellularHardware)
            return "未检测到模块"
        if (s === NetworkManager.CellConnected || s === NetworkManager.CellRoaming)
            return NetworkManager.cellularOperator || "未知"
        if (s === NetworkManager.CellSearching)
            return "搜索中..."
        return "未启用"
    }

    /** @brief SIM 卡开关是否处于"开"状态（已注册/已连接/漫游/搜索中都算开） */
    function isSimOn() {
        var s = NetworkManager.cellularStatus
        return s >= NetworkManager.CellSearching && s <= NetworkManager.CellRoaming
    }

    /** @brief 是否正在执行开关切换（防止重复点击） */
    function isOperating() {
        return NetworkManager.cellularStatus === NetworkManager.CellSearching
    }
}
