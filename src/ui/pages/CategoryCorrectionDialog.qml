import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import App.Backend 1.0
import SmartScale.Tools 1.0

Dialog {
    id: dialogRoot

    // ====== 对外暴露的属性接口（替代原来的 root.xxx）======
    property string currentPrediction: ""
    property string currentImagePath: ""
    property bool categorySelectMode: false

    // ====== 对外暴露的信号（通知父组件状态变化）======
    // 注意：不能命名为 xxxChanged，会与 property 自动生成的属性变更信号冲突！
    signal labelConfirmed(string confirmedLabel)
    signal selectModeToggled(bool isActive)

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width * 0.9, 1920)
    height: Math.min(parent.height * 0.88, 1080)
    modal: true
    padding: 0

    // 隐藏默认标题栏和按钮，完全自定义内容
    title: ""
    background: Rectangle {
        radius: 20
        color: "#E8F0FE"
        border.color: "#B8D4FF"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 3
            radius: 17
            color: "#FFFFFF"
        }
    }

    property string selectedLabel: ""
    property int activeCategoryIndex: 0

    function getActiveItems() {
        var cats = CategoryService.categories
        if (activeCategoryIndex >= 0 && activeCategoryIndex < cats.length) {
            return cats[activeCategoryIndex].items || []
        }
        return []
    }

    function getSelectedCn() {
        var items = getActiveItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].en === selectedLabel)
                return items[i].cn
        }
        return selectedLabel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ===== 顶部栏：返回 + 搜索 + 按钮 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 14
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            spacing: 12

            Rectangle {
                width: 34; height: 34; radius: 8
                color: closeMouse.containsMouse ? "#E8EEF3" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#333333"
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialogRoot.reject()
                }
            }

            TextField {
                id: catSearchInput
                Layout.fillWidth: true
                Layout.preferredHeight: 38
                leftPadding: 32
                placeholderText: "请输入搜索内容"
                font.pixelSize: 14
                color: "#1B263B"
                verticalAlignment: TextInput.AlignVCenter
                background: Rectangle {
                    radius: 8
                    color: "#FFFFFF"
                    border.color: catSearchInput.activeFocus ? "#4361EE" : "#D1D5DB"
                    border.width: 1
                }
            }

            Rectangle {
                Layout.preferredWidth: 68
                Layout.preferredHeight: 38
                radius: 8
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#4C72F9" }
                    GradientStop { position: 1.0; color: "#4BC8F6" }
                }

                Text {
                    anchors.centerIn: parent
                    text: "搜索"
                    font.pixelSize: 14
                    font.bold: true
                    color: "white"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: console.log("[CategoryDialog] 搜索:", catSearchInput.text)
                }
            }
        }

        // ===== 分类标签行 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 16
            Layout.leftMargin: 22
            Layout.bottomMargin: 10
            spacing: 26

            Repeater {
                model: CategoryService.categories

                Item {
                    width: catLabelText.implicitWidth + (dialogRoot.activeCategoryIndex === index ? 0 : 2)
                    height: 28
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: catLabelText
                        text: modelData.name
                        font.pixelSize: 15
                        font.bold: (dialogRoot.activeCategoryIndex === index)
                        color: (dialogRoot.activeCategoryIndex === index) ? "#4C72F9" : "#666666"
                    }

                    Rectangle {
                        anchors.top: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width
                        height: 2
                        visible: (dialogRoot.activeCategoryIndex === index)
                        radius: 1
                        color: "#4C72F9"
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dialogRoot.activeCategoryIndex = index
                            dialogRoot.selectedLabel = ""
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ===== 品类网格区域 =====
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            clip: true

            GridView {
                id: foodGridView
                anchors.fill: parent
                cellWidth: (foodGridView.width - 48) / 5
                cellHeight: 52
                clip: true

                model: dialogRoot.getActiveItems()

                delegate: Rectangle {
                    id: foodCard
                    width: foodGridView.cellWidth - 10
                    height: foodGridView.cellHeight - 6
                    radius: 8
                    color: dialogRoot.selectedLabel === modelData.en
                           ? "#EBF2FF" : "#FAFAFA"
                    border.width: 1.2
                    border.color: dialogRoot.selectedLabel === modelData.en
                                  ? "#4C72F9"
                                  : (cardArea.containsMouse ? "#B8D4FF" : "#E5E7EB")

                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on border.color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.cn
                        font.pixelSize: 15
                        font.family: "Microsoft YaHei"
                        color: dialogRoot.selectedLabel === modelData.en ? "#4C72F9" : "#1B263B"
                    }

                    MouseArea {
                        id: cardArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            dialogRoot.selectedLabel = modelData.en
                        }
                    }
                }
            }
        }
    }  // end ColumnLayout

    onOpened: {
        selectedLabel = ""
        activeCategoryIndex = 0
        catSearchInput.text = ""

        // 触发云端数据刷新
        CategoryService.fetchCategories()
    }

    onAccepted: {
        let correctLabel = selectedLabel
        if (categorySelectMode) {
            labelConfirmed(correctLabel)
            selectModeToggled(false)
        } else {
            VisionAI.submitCorrection(currentImagePath, currentPrediction, correctLabel)
            labelConfirmed(correctLabel)
        }
    }

    onRejected: {
        if (categorySelectMode) {
            selectModeToggled(false)
        }
    }
}
