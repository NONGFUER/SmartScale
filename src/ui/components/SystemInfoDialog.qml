import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale

/**
 * @brief 系统调试信息弹窗 — 独立组件，展示重启次数与开/关机时间
 *
 * 使用方式：
 *   SystemInfoDialog { id: infoDialog }
 *   infoDialog.open()
 */
Popup {
    id: root

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }   // 显式遮罩，强制 Qt 用此 Rectangle 替换默认 dimmer
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0

    width: 480
    height: contentColumn.implicitHeight + topBar.height + btnBar.height + 32

    // 进入/退出动画
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150; easing.type: Easing.InCubic }
    }

    // ========================================================================
    // 主体背景（与 WifiListDialog 风格一致）
    // ========================================================================
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        // 左侧透明竖条装饰（与 WifiListDialog 一致，无彩色）
        Rectangle {
            width: 6
            height: parent.height - btnBar.height
            radius: 16
            color: "transparent"
            anchors.left: parent.left
            anchors.top: parent.top
        }

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

        // ------ 顶部标题栏（与 WifiListDialog 风格一致：白色无渐变）------
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            height: 72
            radius: 16
            color: "#FFFFFF"

            RowLayout {
                anchors.centerIn: parent
                spacing: 12

                Text {
                    text: "\u{1F4CA}"
                    font.pixelSize: 28
                }
                Text {
                    text: "系统调试信息"
                    font.pixelSize: 24
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
            }
        }

        // ------ 信息列表 ------
        ColumnLayout {
            id: contentColumn
            Layout.fillWidth: true
            Layout.leftMargin: 28
            Layout.rightMargin: 28
            Layout.topMargin: 24
            Layout.bottomMargin: 20
            spacing: 16

            // 信息行组件定义（复用）
            component InfoRow: RowLayout {
                id: infoRow
                property string label: ""
                property string value: ""

                spacing: 12
                Layout.fillWidth: true

                Text {
                    text: infoRow.label
                    font.pixelSize: 16
                    font.bold: true
                    color: "#334155"
                    Layout.preferredWidth: 130
                }

                Text {
                    text: infoRow.value
                    font.pixelSize: 16
                    color: "#475569"
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
            }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#E2E8F0"
            }

            InfoRow { label: "关机次数："; value: String(SystemInfo.bootCount) + " 次" }
            //InfoRow { label: "关机次数："; value: String(SystemInfo.shutdownCount) + " 次" }
            //InfoRow { label: "上次开机："; value: formatTime(SystemInfo.lastBootTime) }
           // InfoRow { label: "上次关机："; value: formatTime(SystemInfo.lastShutdownTime) }
            InfoRow { label: "上次关机："; value: formatTime(SystemInfo.currentBootTime) }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#E2E8F0"
            }

            // ---- 蜂窝模组 SIM 卡信息（AT 指令读取，未取到显示 —）----
            InfoRow { label: "SIM卡号(ICCID)："; value: (CellularModem.ccid !== undefined && CellularModem.ccid.length > 0) ? CellularModem.ccid : "—" }
            InfoRow { label: "IMSI：";          value: (CellularModem.imsi !== undefined && CellularModem.imsi.length > 0) ? CellularModem.imsi : "—" }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#E2E8F0"
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

                implicitWidth: 120
                implicitHeight: 36

                background: Rectangle {
                    radius: 6
                    color: closeBtn.hovered ? "#2563EB" : "#3B82F6"
                }

                contentItem: Text {
                    text: closeBtn.text
                    font.pixelSize: 15
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
    // 工具函数
    // ========================================================================

    /**
     * 将 ISO 8601 格式时间字符串转为可读格式，空值显示"—"
     */
    function formatTime(isoStr: string): string {
        if (!isoStr || isoStr.length === 0) return "\u2014"
        var d = new Date(isoStr)
        if (isNaN(d.getTime())) return isoStr  // 解析失败则原样返回
        return d.toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm:ss")
    }
}
