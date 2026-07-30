import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

/**
 * OtaDownloadConfirmDialog — OTA 下载更新确认弹窗
 *
 * 触发条件：点击设置页“立即下载”按钮后弹出
 * 展示待更新的新版本号，由用户确认是否立即下载
 * 风格参照 SaveConfirmDialog.qml
 */
Dialog {
    id: root

    // ===== 对外属性 =====
    property string versionText: ""   // 待更新版本文本，如 “发现新版本 v2.13.3”

    // ===== 信号 =====
    signal downloadConfirmed()        // 用户点击“立即下载”
    signal cancelled()                // 用户点击“取消”

    // ===== 接口 =====
    function openDialog(verText: string) {
        root.versionText = verText
        root.open()
    }

    onOpened: {
        // 把焦点移走，避免任何意外聚焦（本弹窗无输入框）
        Qt.callLater(function() { cancelMA.forceActiveFocus() })
    }

    // Dialog 基础配置（非模态 + 外部遮罩，避让虚拟键盘，风格同 SaveConfirmDialog）
    modal: false
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2  // 居中（键盘悬浮覆盖，不做避让）
    width: 600
    height: 420
    padding: 0
    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E5E7EB"
        border.width: 1

        // 阴影效果
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.15
            shadowBlur: 0.6
            shadowHorizontalOffset: 0
            shadowVerticalOffset: 4
        }
    }

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘，避让虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: root.visible
        MouseArea {
            anchors.fill: parent
            onClicked: { root.cancelled(); root.close() }  // 点击外部关闭
        }
    }

    enter: Transition {
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 200 }
    }
    exit: Transition {
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 150; easing.type: Easing.InCubic }
        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 150 }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ========== 头部：返回按钮 + 居中标题 ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 76

            // 返回按钮 — back2.png + “返回”（圆角胶囊 + 浅底边框），风格同 SettingsDialog
            Rectangle {
                anchors.left: parent.left
                anchors.leftMargin: 24
                anchors.verticalCenter: parent.verticalCenter
                width: 116; height: 44; radius: 22

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
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { root.cancelled(); root.close() }
                }
            }

            // 标题绝对居中（不受左侧返回按钮宽度影响）
            Text {
                anchors.centerIn: parent
                text: "下载更新"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
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

        // ========== 内容区 ==========
        // Item {
        //     Layout.fillWidth: true
        //     Layout.fillHeight: true
        //     Layout.margins: 32
        //     Layout.topMargin: 28
        //     Layout.bottomMargin: 20

        //     ColumnLayout {
        //         anchors.fill: parent
        //         spacing: 16
        //     }
        // }

        // ========== 提示信息（居中、显眼黑色） ==========
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32

            Text {
                anchors.centerIn: parent
                text: "是否立即下载最新版本进行更新？"
                font.pixelSize: 34
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#4649E5"
                width: 500
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
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

        // ========== 按钮区 ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 96

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 取消按钮
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15
                    color: cancelMA.containsMouse ? "#FFFFFF" : "#ECF1FE"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#4649E5"
                    }

                    MouseArea {
                        id: cancelMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.cancelled()
                            root.close()
                        }
                    }
                }

                // 立即下载按钮
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15

                    color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"

                    Text {
                        anchors.centerIn: parent
                        text: "立即下载"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        id: confirmMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.downloadConfirmed()
                            root.close()
                        }
                    }
                }
            } // RowLayout
        } // 按钮区 Item
    } // ColumnLayout
}
