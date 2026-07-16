import QtQuick
import QtQuick.Controls
import QtQuick.Effects

/**
 * SaveLoadingOverlay — 保存中全屏遮罩 Loading
 *
 * 触发时机：用户点击"确认保存"后，拍照 + 上传云端期间显示
 * 行为：modal 阻断所有交互，居中卡片显示旋转动画 + "保存中..." 文案
 * 用法：saveLoadingOverlay.open() / saveLoadingOverlay.close()
 */
Popup {
    id: root

    modal: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    anchors.centerIn: parent
    width: 300
    height: 300

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
    }

    Column {
        anchors.centerIn: parent
        spacing: 30

        // 旋转动画
        Item {
            width: 80
            height: 80
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                id: spinnerCanvas
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#4361EE"
                    ctx.lineWidth = 5
                    ctx.lineCap = "round"
                    ctx.beginPath()
                    ctx.arc(width / 2, height / 2, width / 2 - 4, 0, Math.PI * 1.4)
                    ctx.stroke()
                }
                NumberAnimation on rotation {
                    from: 0; to: 360; duration: 800
                    loops: Animation.Infinite
                    running: root.visible
                }
            }
        }

        Text {
            text: "保存中..."
            font.pixelSize: 28
            font.bold: true
            font.family: Theme.fontFamilyUi
            color: "#1E293B"
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
