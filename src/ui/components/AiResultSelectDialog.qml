import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

/**
 * AiResultSelectDialog — AI 识别多结果选择弹窗
 *
 * 触发时机：识别完成且返回多个候选（>1）时弹出
 * 行为：展示最多 5 个识别结果供用户选择；弹出后开始 5 秒倒计时，
 *       倒计时结束未手动选择则自动选中第一个结果并关闭。
 * 关闭方式：点击某个结果（选中）、左上角返回/右上角关闭/底部取消（放弃选择）、倒计时自动选中第 1 个。
 * 用法：aiResultSelectDialog.openDialog(candidates)
 *       candidates: [{code, name}, ...]
 * 信号：resultSelected(code, name)  用户/自动选中某结果
 *       cancelled()                 用户主动放弃选择
 */
Dialog {
    id: root

    // ===== 对外属性 =====
    property var candidates: []        // 候选列表 [{code, name}, ...]，最多取前 5 个
    property int countdown: 5          // 倒计时秒数

    // ===== 信号 =====
    signal resultSelected(string code, string name)
    signal cancelled()

    // ===== 接口 =====
    function openDialog(cands) {
        // 最多保留 5 个候选
        var list = (cands || []).slice(0, 5)
        root.candidates = list
        if (list.length === 0) return
        root.open()
    }

    modal: true
    closePolicy: Popup.NoAutoClose
    padding: 0
    width: 560
    // 高度随候选数量自适应：标题栏 + 副标题 + 列表 + 底部操作行 + 边距/间距
    height: 262 + listView.contentHeight
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

    // 5 秒倒计时：结束未选择则自动选中第一个
    Timer {
        id: autoSelectTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1
            if (root.countdown <= 0) {
                autoSelectTimer.stop()
                if (root.opened && root.candidates.length > 0) {
                    var code = root.candidates[0]["code"] || ""
                    var name = root.candidates[0]["name"] || ""
                    root.close()
                    root.resultSelected(code, name)
                }
            }
        }
    }

    onOpened: {
        root.countdown = 5
        autoSelectTimer.start()
    }

    onClosed: {
        autoSelectTimer.stop()
    }

    // 主动放弃选择（返回/关闭/取消共用）
    function dismiss() {
        autoSelectTimer.stop()
        root.close()
        root.cancelled()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 20

        // ===== 标题栏：左返回 / 中标题 / 右关闭 =====
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 58

            // 左上角返回（项目标准胶囊样式）
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 116
                height: 44
                radius: 22
                color: backMA.containsMouse ? "#EEF2FF" : "#F1F5F9"

                Behavior on color { ColorAnimation { duration: 120 } }

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        source: "qrc:/resources/img/back2.png"
                        width: 22
                        height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        text: "返回"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#4649E5"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: backMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.dismiss()
                }
            }

            // 标题居中
            Text {
                anchors.centerIn: parent
                text: "识别结果"
                font.pixelSize: 30
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
            }

            // 右上角关闭（close_blue.png 蓝色叉，白底弹窗标准用法；
            // 注意 close.png 是白色图标，仅用于深色底，白底上不可见）
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 60
                height: 60
                radius: 30
                color: closeMA.containsMouse ? "#F1F5F9" : "transparent"

                Behavior on color { ColorAnimation { duration: 120 } }

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/resources/img/close_blue.png"
                    width: parent.width * 0.6
                    height: parent.height * 0.6
                    fillMode: Image.PreserveAspectFit
                }

                MouseArea {
                    id: closeMA
                    anchors.centerIn: parent
                    width: parent.width + 32
                    height: parent.height + 32
                    hoverEnabled: true
                    onClicked: root.dismiss()
                }
            }
        }

        Text {
            text: "根据AI识别的匹配度由高到低列出如下结果，请选择"
            font.pixelSize: 20
            font.family: Theme.fontFamilyUi
            color: "#64748B"
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
        }

        // ===== 结果列表 =====
        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 12
            model: root.candidates

            delegate: Rectangle {
                width: listView.width
                height: 72
                radius: 14
                // 背景与历史记录选中项同色（#E0E7FF），原 #F8FAFC 太浅区分度差
                color: itemMA.containsMouse ? "#C7D2FE" : "#E0E7FF"
                border.color: itemMA.containsMouse ? "#4361EE" : "#A5B4FC"
                border.width: 1

                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on border.color { ColorAnimation { duration: 120 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 12

                    // 序号徽标
                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: "#4361EE"

                        Text {
                            anchors.centerIn: parent
                            text: index + 1
                            font.pixelSize: 20
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#FFFFFF"
                        }
                    }

                    // 食材名称
                    Text {
                        text: modelData["name"] || modelData["code"] || "未知"
                        font.pixelSize: 26
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#1E293B"
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: itemMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        autoSelectTimer.stop()
                        var code = modelData["code"] || ""
                        var name = modelData["name"] || ""
                        root.close()
                        root.resultSelected(code, name)
                    }
                }
            }
        }

        // ===== 底部操作行：左侧倒计时提示，右侧取消按钮 =====
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // 倒计时圆环 + 提示文案（替代原右上角位置）
            Rectangle {
                width: 44
                height: 44
                radius: 22
                color: "#EEF2FF"
                border.color: "#4361EE"
                border.width: 2

                Text {
                    anchors.centerIn: parent
                    text: root.countdown
                    font.pixelSize: 22
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#4361EE"
                }
            }

            Text {
                text: root.countdown + " 秒后自动选择第 1 个"
                font.pixelSize: 20
                font.family: Theme.fontFamilyUi
                color: "#64748B"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // 取消按钮
            Rectangle {
                width: 160
                height: 60
                radius: 15
                color: cancelMA.containsMouse ? "#F1F5F9" : "#E2E8F0"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "取消"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#475569"
                }

                MouseArea {
                    id: cancelMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.dismiss()
                }
            }
        }
    }
}
