import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0

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
    dim: false                          // 遮罩由 Main.qml 的独立 Rectangle 控制
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 0

    width: 480
    height: contentColumn.implicitHeight + topBar.height + 32

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
        id: background
        anchors.fill: parent
        radius: 12
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1

        // 左侧彩色竖条装饰（与其他弹窗保持一致）
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

        // ------ 顶部渐变栏 ------
        Rectangle {
            id: topBar
            Layout.fillWidth: true
            height: 52
            radius: 12
            color: "#1A5CB5"

            // 顶部两个圆角遮罩：底部两角不需要圆角
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

            Text {
                anchors.centerIn: parent
                text: "\U0001F4CA 系统调试信息"
                font.pixelSize: 18
                font.bold: true
                color: "#FFFFFF"
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
                    Layout.preferredWidth: 110
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

            InfoRow { label: "重启次数："; value: String(SystemInfo.restartCount) + " 次" }
            InfoRow { label: "上次开机："; value: formatTime(SystemInfo.lastBootTime) }
            InfoRow { label: "上次关机："; value: formatTime(SystemInfo.lastShutdownTime) }
            InfoRow { label: "本次开机："; value: formatTime(SystemInfo.currentBootTime) }

            // 分隔线
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: "#E2E8F0"
            }
        }

        // ------ 底部按钮栏 ------
        Rectangle {
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
