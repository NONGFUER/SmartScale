import QtQuick
import QtQuick.Controls
import QtQuick.Effects

/**
 * SaveSuccessDialog — 保存成功全屏遮罩弹窗
 *
 * 触发时机：本地保存完成后（onCloudSyncSuccess，即 addRecord DB 写入后立即 emit 的乐观完成信号）
 * 行为：modal 全屏遮罩 + 绿色勾选图标 + "已保存，将上传至服务器" + 语音播报"已保存"
 * 关闭方式：3 秒倒计时自动关闭（按钮显示剩余秒数），或手动点击"确认"按钮立即关闭
 * 用法：saveSuccessDialog.openDialog()
 */
Dialog {
    id: root

    modal: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 460
    height: 380
    anchors.centerIn: parent

    Overlay.modal: Rectangle {
        color: "#80000000"
    }

    background: Rectangle {
        radius: 24
        color: "#FFFFFF"

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
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
        NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        NumberAnimation { property: "scale"; from: 1.0; to: 0.9; duration: 150; easing.type: Easing.InCubic }
    }

    // 3 秒倒计时自动关闭（每秒递减，按钮显示剩余秒数）
    property int countdown: 3
    Timer {
        id: autoCloseTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown <= 0) {
                if (root.opened) root.close()
            }
        }
    }

    onOpened: {
        root.countdown = 3
        autoCloseTimer.start()
        Qt.callLater(function() { confirmMA.forceActiveFocus() })
    }

    onClosed: {
        autoCloseTimer.stop()
    }

    function openDialog() {
        root.open()
    }

    Column {
        anchors.centerIn: parent
        spacing: 32

        // 绿色勾选图标
        Rectangle {
            width: 96
            height: 96
            radius: 48
            color: "#22C55E"
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                anchors.fill: parent
                anchors.margins: 28
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#FFFFFF"
                    ctx.lineWidth = 5
                    ctx.lineCap = "round"
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(2, height * 0.55)
                    ctx.lineTo(width * 0.38, height - 2)
                    ctx.lineTo(width - 2, 2)
                    ctx.stroke()
                }
            }

            // 入场弹性缩放
            scale: 0
            NumberAnimation on scale {
                from: 0; to: 1.0; duration: 400
                easing.type: Easing.OutBack
                running: root.visible
            }
        }

        // 成功提示文案
        Text {
            text: "已保存，将上传至服务器"
            font.pixelSize: 28
            font.bold: true
            font.family: Theme.fontFamilyUi
            color: "#1E293B"
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
        }

        // 确认按钮（显示 3 秒倒计时，可手动点击立即关闭）
        Rectangle {
            width: 200
            height: 60
            radius: 15
            color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"
            anchors.horizontalCenter: parent.horizontalCenter

            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "确认 (" + root.countdown + "s)"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#FFFFFF"
            }

            MouseArea {
                id: confirmMA
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.close()
            }
        }
    }
}
