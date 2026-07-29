import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale

// ============================================================
// OtaUpdateDialog — OTA 升级进度弹窗
//
// 用法：
//   OtaUpdateDialog { id: otaDialog }
//   otaDialog.open()   // 状态全部由 OtaService.state 驱动
//
// 状态展示（OtaService.State）：
//   Downloading    进度条 + 百分比 + 速度 + 已下载大小，按钮[取消下载]
//   Verifying      "正在校验安装包..."（瞬间态）
//   ReadyToInstall "下载完成"，按钮[立即重启安装]（提示应用将重启）
//   Installing     "正在安装，请勿断电"（应用即将被脚本停止，无按钮）
//   Failed         errorString + 按钮[重新下载]
// ============================================================
Dialog {
    id: root

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: 560
    height: 420
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.NoAutoClose   // 下载/安装中不允许点遮罩误关
    title: ""

    // 状态文案（单一数据源：OtaService.state）
    readonly property int otaState: OtaService.state

    function formatMB(bytes) {
        return (bytes / 1024.0 / 1024.0).toFixed(1)
    }
    function formatSpeed(kbs) {
        return kbs >= 1024 ? (kbs / 1024.0).toFixed(1) + " MB/s"
                           : Math.round(kbs) + " KB/s"
    }

    background: Rectangle {
        radius: 24
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
    }

    // ===== 头部：返回按钮 + 居中标题 =====
    RowLayout {
        id: headerBar
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 28
        spacing: 0

        Rectangle {
            width: 116; height: 44; radius: 22
            visible: root.otaState !== OtaService.Installing   // 安装中禁止离开（应用即将停止）

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
                    font.family: Theme.fontFamilyUi
                    color: "#4649E5"
                }
            }

            MouseArea {
                id: backMouse
                anchors.fill: parent
                onClicked: root.close()
            }
        }

        Item { Layout.fillWidth: true }

        Text {
            text: "系统更新"
            font.family: Theme.fontFamilyUi
            font.pixelSize: 24
            font.bold: true
            color: Theme.colorTextPrimary
        }

        Item { Layout.fillWidth: true }
        Item { width: 116 }
    }

    // ===== 内容区 =====
    ColumnLayout {
        anchors.top: headerBar.bottom
        anchors.topMargin: 20
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 40
        anchors.rightMargin: 40
        spacing: 14

        // 版本信息
        Text {
            Layout.fillWidth: true
            text: "新版本：" + OtaService.latestVersion
            font.family: Theme.fontFamilyUi
            font.pixelSize: 24
            color: Theme.colorTextPrimary
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: "当前版本：" + SystemInfo.appVersion
            font.family: Theme.fontFamilyUi
            font.pixelSize: 18
            color: Theme.colorTextSecondary
            horizontalAlignment: Text.AlignHCenter
        }

        // 进度条（track + fill，百分比驱动）
        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 6
            height: 14
            radius: 7
            color: "#E2E8F0"

            Rectangle {
                width: parent.width * Math.max(0, Math.min(100, OtaService.percent)) / 100
                height: parent.height
                radius: parent.radius
                color: Theme.colorAccent
                Behavior on width { NumberAnimation { duration: 200 } }
            }
        }

        // 状态行：百分比/速度/大小 或 状态描述
        Text {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.family: Theme.fontFamilyUi
            font.pixelSize: 22
            color: root.otaState === OtaService.Failed ? "#EF4444" : Theme.colorTextSecondary
            text: {
                switch (root.otaState) {
                case OtaService.Downloading:
                    return OtaService.percent + "%  ·  " + root.formatSpeed(OtaService.speedKBs)
                           + "  ·  " + root.formatMB(OtaService.bytesReceived) + "/"
                           + root.formatMB(OtaService.bytesTotal) + " MB"
                case OtaService.Verifying:
                    return "正在校验安装包..."
                case OtaService.ReadyToInstall:
                    return "下载完成，可以安装"
                case OtaService.Installing:
                    return "正在安装，应用将自动重启，请勿断电"
                case OtaService.Failed:
                    return OtaService.errorString.length > 0 ? OtaService.errorString : "升级失败"
                default:
                    return ""
                }
            }
        }

        // 按钮区
        Item { Layout.preferredHeight: 4 }

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // 取消下载（仅 Downloading）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: root.otaState === OtaService.Downloading
                radius: 8
                color: "#FFFFFF"
                border.color: "#D1D5DB"
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "取消下载"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#475569"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        OtaService.cancelDownload()
                        root.close()
                    }
                }
            }

            // 立即重启安装（仅 ReadyToInstall）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: root.otaState === OtaService.ReadyToInstall
                radius: 8
                color: Theme.colorAccent

                Text {
                    anchors.centerIn: parent
                    text: "立即重启安装"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#FFFFFF"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: OtaService.install()
                }
            }

            // 重新下载（仅 Failed，OtaService 允许 Failed 态重试）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: root.otaState === OtaService.Failed
                radius: 8
                color: Theme.colorAccent

                Text {
                    anchors.centerIn: parent
                    text: "重新下载"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#FFFFFF"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: OtaService.startDownload()
                }
            }
        }
    }

    // 弹窗无输入框，焦点给返回按钮（项目焦点规范）
    onOpened: Qt.callLater(function() { backMouse.forceActiveFocus() })
}
