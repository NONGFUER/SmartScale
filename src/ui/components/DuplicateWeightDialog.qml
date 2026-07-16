import QtQuick
import QtQuick.Controls
import QtQuick.Effects

/**
 * DuplicateWeightDialog — 重复称重提醒弹窗
 *
 * 触发时机：保存时检测到重复称重（checkDuplicate 返回 duplicate=true）
 * 风格：套用 SaveSuccessDialog（大圆圈图标 + 大字体 + 弹性入场）
 * 行为：取消=拦截保存，确认=继续执行保存
 * 用法：duplicateWeightDialog.openDialog(dupInfo)
 */
Dialog {
    id: root

    // ===== 对外属性 =====
    property string categoryName: ""
    property real dupWeight: 0
    property string recordTime: ""

    // ===== 信号 =====
    signal confirmed()
    signal cancelled()

    modal: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 480
    height: 420
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

    onOpened: {
        Qt.callLater(function() { cancelMA.forceActiveFocus() })
    }

    function openDialog(dupInfo) {
        if (dupInfo) {
            root.categoryName = dupInfo["categoryName"] || ""
            root.dupWeight = Number(dupInfo["weight"]) || 0
            root.recordTime = dupInfo["recordTime"] || ""
        }
        root.open()
    }

    Column {
        anchors.centerIn: parent
        spacing: 28

        // 蓝色圆圈 + Canvas 白色感叹号
        Rectangle {
            width: 96
            height: 96
            radius: 48
            color: "#4649E5"
            anchors.horizontalCenter: parent.horizontalCenter

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.fillStyle = "#FFFFFF"
                    // 感叹号竖线（圆角矩形）
                    var bx = width * 0.44, by = height * 0.22
                    var bw = width * 0.12, bh = height * 0.42, br = 4
                    ctx.beginPath()
                    ctx.moveTo(bx + br, by)
                    ctx.arcTo(bx + bw, by, bx + bw, by + bh, br)
                    ctx.arcTo(bx + bw, by + bh, bx, by + bh, br)
                    ctx.arcTo(bx, by + bh, bx, by, br)
                    ctx.arcTo(bx, by, bx + bw, by, br)
                    ctx.closePath()
                    ctx.fill()
                    // 感叹号底部圆点
                    ctx.beginPath()
                    ctx.arc(width * 0.5, height * 0.74, width * 0.06, 0, Math.PI * 2)
                    ctx.fill()
                }
            }

            // 弹性入场动画
            scale: 0
            NumberAnimation on scale {
                from: 0; to: 1.0; duration: 400
                easing.type: Easing.OutBack
                running: root.visible
            }
        }

        // 标题
        Text {
            text: "是否重复称重？"
            font.pixelSize: 28
            font.bold: true
            font.family: Theme.fontFamilyUi
            color: "#1E293B"
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // 重复记录详情
        Text {
            text: "刚刚已称过：" + root.categoryName + "  " + root.dupWeight.toFixed(2) + " kg" +
                  (root.recordTime ? "  (" + root.recordTime.substring(5, 16) + ")" : "")
            width: 400
            wrapMode: Text.WordWrap
            font.pixelSize: 24
            font.family: Theme.fontFamilyUi
            color: "#4649E5"
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
        }

        // 按钮区
        Row {
            spacing: 20
            anchors.horizontalCenter: parent.horizontalCenter

            // 取消按钮
            Rectangle {
                width: 160
                height: 60
                radius: 15
                color: cancelMA.containsMouse ? "#FFFFFF" : "#ECF1FE"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "取消"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
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

            // 确认保存按钮
            Rectangle {
                width: 160
                height: 60
                radius: 15
                color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "继续保存"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#FFFFFF"
                }

                MouseArea {
                    id: confirmMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.confirmed()
                        root.close()
                    }
                }
            }
        }
    }
}
