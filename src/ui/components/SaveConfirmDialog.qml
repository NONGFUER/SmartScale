import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

/**
 * SaveConfirmDialog — 保存确认弹窗（含价格输入）
 *
 * 触发条件：点击"保存"按钮后弹出
 * 用户可输入单价（元/斤），自动计算金额（元）
 * 单价选填，为 0 时金额也为 0，允许直接保存
 */
Dialog {
    id: root

    // ===== 对外属性 =====
    property string ingredientName: ""   // 食材名称
    property double weight: 0            // 重量 (kg)
    property bool hasDuplicate: false     // 是否检测到重复称重
    property var duplicateRecord: null    // 重复记录信息 { categoryName, weight, recordTime }

    // 内部状态
    property real _unitPrice: 0          // 单价 (元/斤)，双向绑定到输入框
    property real _amount: 0             // 金额 (元) = _unitPrice * weight * 2

    // ===== 信号 =====
    signal saveConfirmed(real unitPrice, real amount)   // 用户点击"确认保存"
    signal cancelled()                                   // 用户点击"取消"

    // ===== 接口 =====
    function openDialog(name, w, dupInfo) {
        root.ingredientName = name
        root.weight = w
        root._unitPrice = 0
        root._amount = 0
        priceInput.text = "0"
        // 处理重复信息
        if (dupInfo && dupInfo["duplicate"] === true) {
            root.hasDuplicate = true
            root.duplicateRecord = dupInfo
        } else {
            root.hasDuplicate = false
            root.duplicateRecord = null
        }
        root.open()
    }

    // Dialog 基础配置
    modal: true
    width: 520
    height: 420
    anchors.centerIn: parent
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

    Overlay.modal: Rectangle {
        color: "#80000000"
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

        // ========== 标题区 ==========
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 56

            Text {
                anchors.centerIn: parent
                text: "确认保存"
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

        // ========== 表格内容区 ==========
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 32
            Layout.topMargin: 28
            Layout.bottomMargin: 20

            GridLayout {
                anchors.fill: parent
                columns: 2
                rowSpacing: 20
                columnSpacing: 16

                // --- 食材 ---
                Text {
                    text: "食材"
                    font.pixelSize: 18
                    font.family: Theme.fontFamilyUi
                    color: "#64748B"
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
                Text {
                    text: root.ingredientName
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#1E293B"
                    Layout.fillWidth: true
                    elide: Text.ElideMiddle
                }

                // --- 重量 ---
                Text {
                    text: "重量"
                    font.pixelSize: 18
                    font.family: Theme.fontFamilyUi
                    color: "#64748B"
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
                Text {
                    text: root.weight.toFixed(2) + " kg"
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#1E293B"
                    Layout.fillWidth: true
                }

                // --- 单价 ---
                Text {
                    text: "单价"
                    font.pixelSize: 18
                    font.family: Theme.fontFamilyUi
                    color: "#64748B"
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 44
                    radius: 8
                    color: priceInput.activeFocus ? "#FFFFFF" : "#F8FAFC"
                    border.color: priceInput.activeFocus ? "#4361EE" : "#CBD5E1"
                    border.width: priceInput.activeFocus ? 2 : 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    TextInput {
                        id: priceInput
                        anchors.fill: parent
                        anchors.margins: 10
                        verticalAlignment: TextInput.AlignVCenter
                        text: "0"
                        font.pixelSize: 20
                        font.family: Theme.fontFamilyUi
                        color: "#1E293B"
                        clip: true
                        validator: DoubleValidator {
                            decimals: 2; bottom: 0; notation: DoubleValidator.StandardNotation
                        }
                        onTextEdited: {
                            var val = parseFloat(text) || 0
                            root._unitPrice = val
                            root._amount = val * root.weight * 2
                        }

                        // 右侧单位提示
                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: 10
                            text: "元 / 斤"
                            font.pixelSize: 14
                            font.family: Theme.fontFamilyUi
                            color: "#94A3B8"
                        }
                    }
                }

                // --- 金额 ---
                Text {
                    text: "金额"
                    font.pixelSize: 18
                    font.family: Theme.fontFamilyUi
                    color: "#64748B"
                    Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                }
                Text {
                    text: root._amount.toFixed(2) + " 元"
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#4361EE"
                    Layout.fillWidth: true
                }
            } // GridLayout
        } // 内容区 Item

        // ========== 重复称重警告 ==========
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.preferredHeight: root.hasDuplicate ? 60 : 0
            visible: root.hasDuplicate
            clip: true

            Behavior on Layout.preferredHeight { NumberAnimation { duration: 200 } }

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: "#FEF3C7"
                border.color: "#F59E0B"
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "\u26A0\uFE0F"  // ⚠️
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Column {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: "检测到重复称重"
                            font.pixelSize: 15
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#B45309"
                        }
                        Text {
                            text: root.duplicateRecord ?
                                  (root.duplicateRecord["categoryName"] + " " +
                                   Number(root.duplicateRecord["weight"]).toFixed(2) + " kg (" +
                                   (root.duplicateRecord["recordTime"] || "").substring(5, 16) + ")") : ""
                            font.pixelSize: 13
                            font.family: Theme.fontFamilyUi
                            color: "#D97706"
                        }
                    }
                }
            }
        }

        // ========== 提示信息 ==========
        Item {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.preferredHeight: 40

            Row {
                spacing: 8
                anchors.centerIn: parent

                Text {
                    text: "\u2139\uFE0F"  // ℹ️ info icon
                    font.pixelSize: 18
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: root.hasDuplicate ?
                          "已存在相同食材且重量相近的记录，确认要继续保存吗？" :
                          "单价为每斤的价格，输入单价后金额将自动计算；不输入单价也可直接确认保存。"
                    font.pixelSize: 13
                    font.family: Theme.fontFamilyUi
                    color: "#64748B"
                    width: 400
                    wrapMode: Text.Wrap
                    anchors.verticalCenter: parent.verticalCenter
                }
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
            Layout.preferredHeight: 72

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 取消按钮
                Rectangle {
                    width: 160
                    height: 48
                    radius: 10
                    color: cancelMA.containsMouse ? "#F1F5F9" : "#FFFFFF"
                    border.color: "#CBD5E1"
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        font.pixelSize: 18
                        font.family: Theme.fontFamilyUi
                        color: "#64748B"
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
                    width: 180
                    height: 48
                    radius: 10

                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: "#4361EE" }
                        GradientStop { position: 1.0; color: "#3A0CA3" }
                    }

                    color: confirmMA.containsMouse ? "#3A56C4" : "#4361EE"

                    Text {
                        anchors.centerIn: parent
                        text: "确认保存"
                        font.pixelSize: 18
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        id: confirmMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.saveConfirmed(root._unitPrice, root._amount)
                            root.close()
                        }
                    }
                }
            } // RowLayout
        } // 按钮区 Item
    } // ColumnLayout
}
