import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0

Rectangle {
    id: root
    height: 70
    color: "transparent"

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 44
        anchors.rightMargin: 44
        spacing: 20

        // ===== 左侧：设备型号信息 =====
        Text {
            text: "小管事AI视觉智能网络秤（型号:WLC200A-13C）"
            font.pixelSize: 24
            font.family: "PingFang SC"
            color: "#FFFFFF"
            Layout.alignment: Qt.AlignVCenter
            font.bold: true
        }
        // 弹性占位：把右侧推到最右
        Item { Layout.fillWidth: true }

        // ===== 中间：版本号 =====
        Text {
            id: versionText
            text: "版本号:" + (SystemInfo.appVersion || "2.13.2")
            font.pixelSize: 24
          
            font.bold: true
            color: "#FFFFFF"
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 40
        }

        // ===== 右侧：版权 + Logo =====
        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            // 公司 Logo 圆形图标
            Rectangle {
                width: 22; height: 22; radius: 11
                color: "#FFFFFF"

                Text {
                    anchors.centerIn: parent
                    text: "小"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#3B82F6"
                }
            }

            // 版权文字
            Text {
                text: "Copyright © 2026 上海小管事机器人有限公司"
                font.pixelSize: 24
                font.family: "PingFang SC"
                font.bold: true
                color: "#FFFFFF"
            }
        }
    }
}
