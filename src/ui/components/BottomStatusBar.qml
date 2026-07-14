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
        anchors.leftMargin: 54
        anchors.rightMargin: 54
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

        // ===== 右侧：版权 + Logo =====
        RowLayout {
            spacing: 8
            Layout.alignment: Qt.AlignVCenter

            // 公司 Logo 图标
            Image {
                source: "qrc:/resources/img/logo.png"
                width: 22; height: 22
                fillMode: Image.PreserveAspectFit
                asynchronous: true
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

    // ===== 版本号：绝对水平居中于整个状态栏 =====
    Text {
        id: versionText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        text: "版本号: " + (SystemInfo.appVersion || "2.13.2")
        font.pixelSize: 24
        font.bold: true
        color: "#FFFFFF"
    }
}
