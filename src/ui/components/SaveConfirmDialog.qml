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
        root.weight = Number(w.toFixed(2))          // 统一2位小数，保证显示与计算完全一致
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

    onOpened: {
        // 把焦点从价格输入框移走，防止虚拟键盘自动弹出
        Qt.callLater(function() { cancelMA.forceActiveFocus() })
    }

    // Dialog 基础配置
    modal: true
    width: 680
    height: 630
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
            Layout.preferredHeight: 76

            Text {
                anchors.centerIn: parent
                text: "确认保存"
                font.pixelSize: 30
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

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                // ========== 行：食材 ==========
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 10
                    color: "#F8FAFC"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0

                        Text {
                            text: "食材"
                            font.pixelSize: 22
                            font.family: Theme.fontFamilyUi
                            color: "#1B2955"
                            Layout.preferredWidth: 80
                        }
                        Item { Layout.preferredWidth: 20 } // 间距
                        Text {
                            text: root.ingredientName
                            font.pixelSize: 22
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#1E293B"
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideMiddle
                        }
                    }
                }

                // ========== 行：重量 ==========
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 10
                    color: "#F8FAFC"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0

                        Text {
                            text: "重量"
                            font.pixelSize: 22
                            font.family: Theme.fontFamilyUi
                            color: "#1B2955"
                            Layout.preferredWidth: 80
                        }
                        Item { Layout.preferredWidth: 20 }
                        Text {
                            text: root.weight.toFixed(2) + " kg"
                            font.pixelSize: 22
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#1E293B"
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                // ========== 行：单价（含输入框）==========
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 10
                    color: priceInput.activeFocus ? "#FFFFFF" : "#F8FAFC"
                    border.color: priceInput.activeFocus ? "#4361EE" : "#CBD5E1"
                    border.width: priceInput.activeFocus ? 2 : 1

                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0

                        Text {
                            text: "单价"
                            font.pixelSize: 22
                            font.family: Theme.fontFamilyUi
                            color: "#1B2955"
                            Layout.preferredWidth: 80
                        }
                        Item { Layout.preferredWidth: 20 }

                        // 输入框区域
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 44
                            clip: true

                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: "transparent"
                                border.color: priceInput.activeFocus ? "#4361EE" : "#CBD5E1"
                                border.width: 1
                            }

                            TextInput {
                                id: priceInput
                                focus: false          // 禁止打开弹窗时自动聚焦（避免虚拟键盘弹出）
                                anchors.fill: parent
                                anchors.margins: 4
                                verticalAlignment: TextInput.AlignVCenter
                                text: "0"
                                font.pixelSize: 20
                                font.family: Theme.fontFamilyUi
                                color: "#1E293B"
                                clip: true
                                selectByMouse: true
                                validator: DoubleValidator {
                                    decimals: 2; bottom: 0; notation: DoubleValidator.StandardNotation
                                }
                                onTextEdited: {
                                    var val = Number((parseFloat(text) || 0).toFixed(2))
                                    root._unitPrice = val
                                    root._amount = Number((val * root.weight * 2).toFixed(2))
                                }

                                // placeholder 效果
                                Text {
                                    anchors.fill: parent
                                    verticalAlignment: Text.AlignVCenter
                                    text: priceInput.text.length > 0 ? "" : "选填，请输入单价"
                                    font.pixelSize: 20
                                    font.family: Theme.fontFamilyUi
                                    color: "#94A3B8"
                                    visible: !priceInput.activeFocus && priceInput.text.length === 0
                                }

                                // 右侧单位提示
                                Text {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.rightMargin: 4
                                    text: "元/斤"
                                    font.pixelSize: 18
                                    font.family: Theme.fontFamilyUi
                                    color: "#94A3B8"
                                }
                            }
                        }
                    }
                }

                // ========== 行：金额 ==========
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 60
                    radius: 10
                    color: "#F8FAFC"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 20
                        anchors.rightMargin: 20
                        spacing: 0

                        Text {
                            text: "金额"
                            font.pixelSize: 22
                            font.family: Theme.fontFamilyUi
                            color: "#1B2955"
                            Layout.preferredWidth: 80
                        }
                        Item { Layout.preferredWidth: 20 }
                        Text {
                            text: root._amount.toFixed(2) + " 元"
                            font.pixelSize: 22
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#4361EE"
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            } // ColumnLayout
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
            Layout.preferredHeight: 90

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
                        font.bold:true
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
                    width: 180
                    height: 60
                    radius: 15

                    color: confirmMA.containsMouse ? "#4649E5" : "#4361EE"

                    Text {
                        anchors.centerIn: parent
                        text: "确认保存"
                        font.pixelSize: 24
                        font.bold: true
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
