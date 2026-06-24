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
    signal labelConfirmed(string confirmedLabel, string ingrId)
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
    property string selectedIngrId: ""
    property int activeCategoryIndex: 0

    function getActiveCategories() {
        if (categorySelectMode) {
            // 手动选择模式：使用 UserIngredientService 按分类分组的食材
            return UserIngredientService.categories
        }
        return CategoryService.categories
    }

    function getActiveItems() {
        var cats = getActiveCategories()
        if (activeCategoryIndex >= 0 && activeCategoryIndex < cats.length) {
            return cats[activeCategoryIndex].items || []
        }
        return []
    }

    function getSelectedCn() {
        var items = getActiveItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].en === selectedLabel)
                return items[i].cn || items[i].en || selectedLabel
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
                model: dialogRoot.getActiveCategories()

                Item {
                    width: catLabelText.implicitWidth + (dialogRoot.activeCategoryIndex === index ? 0 : 2)
                    height: 28
                    Layout.alignment: Qt.AlignVCenter

                    Text {
                        id: catLabelText
                        text: modelData.cateNm || modelData.name
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
                        onClicked: {
                            dialogRoot.selectedLabel = modelData.en
                            dialogRoot.selectedIngrId = (modelData.id !== undefined) ? String(modelData.id) : ""
                        }
                        }
                    }
                }
            }

            // ===== 底部按钮栏 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                Layout.bottomMargin: 18
                Layout.topMargin: 10
                spacing: 12

                Item { Layout.fillWidth: true }

                // 取消按钮
                Rectangle {
                    width: 100; height: 38; radius: 8
                    color: cancelBtnMouse.containsMouse ? "#F1F5F9" : "#FFFFFF"
                    border.color: "#D1D5DB"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "取消"
                        font.pixelSize: 15
                        font.bold: true
                        color: "#64748B"
                    }
                    MouseArea {
                        id: cancelBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: dialogRoot.reject()
                    }
                }

                // 确认按钮
                Rectangle {
                    width: 100; height: 38; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: dialogRoot.selectedLabel === "" ? "#94A3B8" : "#4C72F9" }
                        GradientStop { position: 1.0; color: dialogRoot.selectedLabel === "" ? "#CBD5E1" : "#4BC8F6" }
                    }
                    opacity: dialogRoot.selectedLabel === "" ? 0.5 : 1.0

                    Text {
                        anchors.centerIn: parent
                        text: "确认"
                        font.pixelSize: 15
                        font.bold: true
                        color: "white"
                    }
                    MouseArea {
                        id: confirmBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: dialogRoot.selectedLabel !== ""
                        onClicked: dialogRoot.accept()
                    }
                }
            }
    }  // end ColumnLayout

    onOpened: {
        selectedLabel = ""
        selectedIngrId = ""
        activeCategoryIndex = 0
        catSearchInput.text = ""

        if (categorySelectMode) {
            // 手动选择模式：从 USER 域拉取食材列表
            UserIngredientService.fetchIngredients()
        } else {
            // AI 纠错模式：拉取原有品类
            CategoryService.fetchCategories()
        }
    }

    onAccepted: {
        // 打印选中项的全部业务字段
        var selItems = getActiveItems()
        for (var i = 0; i < selItems.length; i++) {
            if (selItems[i].en === selectedLabel) {
                var m = selItems[i]
                console.log("[CategoryDialog] 选中食材 ▶"
                            + " ingrId=" + (m.id !== undefined ? m.id : "")
                            + " ingrCd=" + (m.en !== undefined ? m.en : "")
                            + " ingrNm=" + (m.cn !== undefined ? m.cn : "")
                            + " cateId=" + (m.cateId !== undefined ? m.cateId : "")
                            + " emsId="  + (m.emsId !== undefined ? m.emsId : "")
                            + " emsCd="  + (m.emsCd !== undefined ? m.emsCd : "")
                            + " cateNm=" + (m.cateNm !== undefined ? m.cateNm : ""))
                break
            }
        }

        let correctLabel = selectedLabel
        if (categorySelectMode) {
            labelConfirmed(correctLabel, selectedIngrId)
            selectModeToggled(false)
        } else {
            VisionAI.submitCorrection(currentImagePath, currentPrediction, correctLabel)
            labelConfirmed(correctLabel, selectedIngrId)
        }
    }

    onRejected: {
        if (categorySelectMode) {
            selectModeToggled(false)
        }
    }
}
