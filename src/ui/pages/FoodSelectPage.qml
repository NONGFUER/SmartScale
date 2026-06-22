import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    // 浅色背景
    Rectangle {
        anchors.fill: parent
        color: "#F0F4F8"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 16

        // ===== 顶部搜索栏 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 20
            Layout.rightMargin: 20
            spacing: 12

            // 返回按钮
            Rectangle {
                width: 36; height: 36; radius: 8
                color: backMouse.containsMouse ? "#E8EEF3" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"
                    font.pixelSize: 26
                    font.bold: true
                    color: "#333333"
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: stackView.pop()
                }
            }

            // 搜索输入框
            TextField {
                id: searchInput
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                leftPadding: 36
                placeholderText: "请输入搜索内容"
                font.pixelSize: 14
                color: "#1B263B"
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    radius: 8
                    color: "#FFFFFF"
                    border.color: searchInput.activeFocus ? "#4361EE" : "#D1D5DB"
                    border.width: 1
                }
            }

            // 搜索按钮
            Button {
                text: "搜索"
                font.family: "Microsoft YaHei"
                font.pixelSize: 14
                font.bold: true
                Layout.preferredWidth: 70
                Layout.preferredHeight: 40

                background: Rectangle {
                    radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4C72F9" }
                        GradientStop { position: 1.0; color: "#4BC8F6" }
                    }
                }

                contentItem: Text {
                    text: parent.text
                    font: parent.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: console.log("[FoodPage] 搜索:", searchInput.text)
            }
        }

        // ===== 主内容区（蓝色边框圆角卡片）=====
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            radius: 16
            color: "#FFFFFF"
            border.color: "#4A90D9"
            border.width: 2

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 0

                // ===== 分类标签行 =====
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 20
                    spacing: 28

                    Repeater {
                        model: [
                            { name: "叶子菜", active: true },
                            { name: "根茎类", active: false },
                            { name: "肉类", active: false },
                            { name: "水果", active: false },
                            { name: "更多\u25BC", active: false }
                        ]

                        Item {
                            width: catText.implicitWidth + (modelData.active ? 0 : 2)
                            height: 30
                            Layout.alignment: Qt.AlignVCenter

                            Text {
                                id: catText
                                text: modelData.name
                                font.family: "Microsoft YaHei"
                                font.pixelSize: 15
                                font.bold: modelData.active
                                color: modelData.active ? "#4C72F9" : "#666666"

                                // 选中项底部蓝色下划线
                                Rectangle {
                                    anchors.top: parent.bottom
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: parent.width
                                    height: 2
                                    visible: modelData.active
                                    radius: 1
                                    color: "#4C72F9"
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: console.log("[FoodPage] 切换分类:", modelData.name)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // ===== 食品网格（5列）=====
                GridView {
                    id: foodGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    cellWidth: (foodGrid.width - 64) / 5   // 5列 + 4个gap
                    cellHeight: 56
                    clip: true

                    model: [
                        "青菜", "菠菜", "青菜", "菠菜", "青菜",
                        "菠菜", "青菜", "菠菜", "青菜", "菠菜",
                        "青菜", "菠菜", "青菜", "菠菜", "青菜",
                        "菠菜", "青菜", "菠菜", "青菜", "菠菜"
                    ]

                    delegate: FoodItemCard {
                        width: foodGrid.cellWidth - 10
                        height: foodGrid.cellHeight - 8
                        text: modelData
                        onClicked: console.log("[FoodPage] 选择:", modelData)
                    }
                }
            }
        }
    }
}
