import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

/**
 * NumberPadPopup — 底部弹出的 9 宫格数字键盘
 *
 * 用途：单价输入等纯数字场景，点击输入区时从底部上滑出现。
 * 设计要点：
 *   - 纯 Text + MouseArea 按键，无 TextInput，从根本上规避触摸屏虚拟键盘自动弹出问题
 *   - 标准布局 1-9 + 0 + 小数点 + 退格，底部"确定"键确认并收起
 *   - 校验：最多 2 位小数、禁止多个小数点、空串视为 0、禁止前导零
 *
 * 用法：
 *   NumberPadPopup {
 *       onConfirmed: function(v) { myPrice = v }
 *   }
 *   numberPad.openPad(myPrice)   // 传入当前值作为初始显示
 */
Popup {
    id: root

    // ===== 对外 =====
    property string displayText: "0"     // 当前输入缓冲（字符串）

    signal confirmed(real value)         // 用户点击"确定"，返回最终数值
    signal cancelled()                   // 用户点击遮罩/取消

    // ===== 接口 =====
    function openPad(initial: real) {
        // 格式化初始值：去除无意义尾零，0 显示为 "0"
        var s = Number(initial.toFixed(2)).toString()
        root.displayText = (s === "" || s === "NaN") ? "0" : s
        root.open()
    }

    // ===== Popup 基础配置 =====
    parent: Overlay.overlay
    modal: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    padding: 0
    width: parent ? parent.width * 0.35 : 0   // 覆盖 40% 屏宽
    height: parent ? parent.height * 0.58 : 0 // 60% 屏高，露顶部 40% 给食材卡片
    x: parent ? parent.width - width-35 : 0     // 贴右（Popup 无 anchors，用坐标）
    y: parent ? parent.height - height-40 : 0   // 贴底，顶部留出食材卡片可见区

    Overlay.modal: Rectangle { color: "#00000000" }

    background: Rectangle {
        radius: 24
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

    enter: Transition {
        NumberAnimation { property: "x"; from: root.parent ? root.parent.width : 0; to: root.parent ? root.parent.width - root.width - 45 : 0; duration: 220; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
    }
    exit: Transition {
        NumberAnimation { property: "x"; from: root.parent ? root.parent.width - root.width - 45 : 0; to: root.parent ? root.parent.width : 0; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 160 }
    }

    onClosed: {
        root.displayText = "0"   // 关闭后复位缓冲，避免下次打开残留
    }

    // ===== 主体 =====
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // ---------- 显示栏：当前输入值 + 单位 + 清空 ----------
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 72

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "单价"
                font.pixelSize: 22
                font.family: Theme.fontFamilyUi
                color: "#64748B"
            }

            Text {
                anchors.centerIn: parent
                text: root.displayText
                font.pixelSize: 40
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    text: "元/kg"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: "#94A3B8"
                    anchors.verticalCenter: parent.verticalCenter
                }

                // 清空按钮：一键复位为 "0"
                Rectangle {
                    width: 88; height: 44; radius: 22
                    color: clearMA.containsMouse ? "#FEF2F2" : "#F1F5F9"
                    border.color: clearMA.containsMouse ? "#EF4444" : "#E2E8F0"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: "清空"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: clearMA.containsMouse ? "#EF4444" : "#64748B"
                    }

                    MouseArea {
                        id: clearMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.displayText = "0"
                    }
                }
            }
        }

        // ---------- 9 宫格按键区（3 列 × 4 行，自适应占满中部）----------
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            rowSpacing: 12
            columnSpacing: 12

            // 1-9
            Repeater {
                model: 9
                Rectangle {
                    required property int index
                    readonly property int digit: index + 1

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: kMA.containsMouse ? "#E0E7FF" : "#F8FAFC"
                    border.color: kMA.containsMouse ? "#4361EE" : "#E2E8F0"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 100 } }

                    Text {
                        anchors.centerIn: parent
                        text: String(parent.digit)
                        font.pixelSize: 32
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#1E293B"
                    }

                    MouseArea {
                        id: kMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root._appendDigit(parent.digit)
                    }
                }
            }

            // 小数点
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: dotMA.containsMouse ? "#E0E7FF" : "#F8FAFC"
                border.color: dotMA.containsMouse ? "#4361EE" : "#E2E8F0"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "."
                    font.pixelSize: 36
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#1E293B"
                }

                MouseArea {
                    id: dotMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root._appendDot()
                }
            }

            // 0
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: zeroMA.containsMouse ? "#E0E7FF" : "#F8FAFC"
                border.color: zeroMA.containsMouse ? "#4361EE" : "#E2E8F0"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "0"
                    font.pixelSize: 36
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#1E293B"
                }

                MouseArea {
                    id: zeroMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root._appendDigit(0)
                }
            }

            // 退格
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 14
                color: bsMA.containsMouse ? "#FEF2F2" : "#F8FAFC"
                border.color: bsMA.containsMouse ? "#EF4444" : "#E2E8F0"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 100 } }

                Text {
                    anchors.centerIn: parent
                    text: "\u232B"      // ⌫
                    font.pixelSize: 36
                    font.family: Theme.fontFamilyUi
                    color: "#EF4444"
                }

                MouseArea {
                    id: bsMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root._backspace()
                }
            }
        }

        // ---------- 确定 + 关闭 并排 ----------
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // 关闭按钮（左侧）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 16
                color: closeMA.containsMouse ? "#E0E7FF" : "transparent"
                border.color: closeMA.containsMouse ? "#4361EE" : "#4361EE"
                border.width: 2

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "退出"
                    font.pixelSize: 30
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#4361EE"
                }

                MouseArea {
                    id: closeMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.close()
                }
            }

            // 确定按钮（右侧）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                radius: 16
                color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "确定"
                    font.pixelSize: 30
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#FFFFFF"
                }

                MouseArea {
                    id: confirmMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var v = parseFloat(root.displayText)
                        if (isNaN(v)) v = 0
                        v = Math.round(v * 100) / 100   // 最多 2 位小数
                        root.confirmed(v)
                        root.close()
                    }
                }
            }
        }
    }

    // ===== 输入处理函数 =====
    function _appendDigit(d) {
        var s = root.displayText
        var dotIdx = s.indexOf(".")
        if (dotIdx >= 0 && s.length - dotIdx - 1 >= 2)
            return                          // 小数部分已满 2 位
        if (s === "0") {
            root.displayText = String(d)    // 去前导零
            return
        }
        root.displayText = s + d
    }

    function _appendDot() {
        var s = root.displayText
        if (s.indexOf(".") >= 0)
            return                          // 已有小数点
        root.displayText = (s.length === 0 ? "0" : s) + "."
    }

    function _backspace() {
        var s = root.displayText
        if (s.length <= 1) {
            root.displayText = "0"
            return
        }
        root.displayText = s.substring(0, s.length - 1)
        if (root.displayText === "")
            root.displayText = "0"
    }
}
