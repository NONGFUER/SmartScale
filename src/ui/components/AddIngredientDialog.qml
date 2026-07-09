import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0

// ============================================================
// AddIngredientDialog — 添加食材弹窗
// 用法：
//   AddIngredientDialog {
//       id: addIngredientDialog
//       onConfirmed: function(name, categoryIndex) { /* 处理 */ }
//   }
//   addIngredientDialog.open()
// ============================================================
Dialog {
    id: dialogRoot

    // ---- 对外接口 ----
    // categoryIndex: 分类在列表中的下标（用于定位）
    // categoryId:   分类的 cateId（唯一标识，传给后端用）
    signal confirmed(string ingredientName, int categoryIndex, string categoryId)

    property int maxNameLength: 20
    property string ingredientName: ""
    property int selectedCategoryIndex: -1       // 当前选中分类的下标
    property string selectedCategoryId: ""        // 当前选中分类的 cateId
    property string selectedCategoryName: ""       // 当前选中分类的 cateNm

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width * 0.85, 680)
    height: Math.min(parent.height * 0.75, 480)
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.NoAutoClose
    title: ""

    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 28
        spacing: 0

        // ====== 标题栏：添加食材 + 关闭按钮 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 0

            Text {
                text: "添加食材"
                font.pixelSize: 26
                font.bold: true
                color: "#1E293B"
            }

            Item { Layout.fillWidth: true }

            // 关闭 × 按钮
            Rectangle {
                width: 32; height: 32; radius: 16
                color: closeMouse.containsMouse ? "#F1F5F9" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    font.pixelSize: 22
                    color: "#94A3B8"
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialogRoot.close()
                }
            }
        }

        // ====== 食材名称 ======
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 18
            spacing: 10

            RowLayout {
                spacing: 4

                Text { text: "*"; font.pixelSize: 20; color: "#EF4444"; font.bold: true }
                Text { text: "食材名称"; font.pixelSize: 20; color: "#334155"; font.bold: true }
            }

            // 输入框容器（带字数统计）
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52

                Rectangle {
                    id: nameInputBg
                    anchors.fill: parent
                    radius: 10
                    color: "#FFFFFF" 
                    border.color: nameInput.activeFocus ? "#3B82F6" : "#E2E8F0"
                    border.width: nameInput.activeFocus ? 1.5 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                TextField {
                    id: nameInput
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.rightMargin: 50
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 14
                    height: 36
                    placeholderText: "请输入食材名称"
                    placeholderTextColor: "#CBD5E1"
                    font.pixelSize: 20
                    color: "#1E293B"
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase
                    maximumLength: dialogRoot.maxNameLength
                    background: null
                    onTextChanged: dialogRoot.ingredientName = text
                }

                // 字数计数器
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: nameInput.text.length + "/" + dialogRoot.maxNameLength
                    font.pixelSize: 16
                    color: nameInput.text.length >= dialogRoot.maxNameLength ? "#EF4444" : "#94A3B8"
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
            }
        }

        // ====== 选择分类 ======
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 10

            RowLayout {
                spacing: 4

                Text { text: "*"; font.pixelSize: 20; color: "#EF4444"; font.bold: true }
                Text { text: "选择分类"; font.pixelSize: 20; color: "#334155"; font.bold: true }
            }

            // 下拉选择框
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 52

                Rectangle {
                    id: catSelectBg
                    anchors.fill: parent
                    radius: 10
                    color:  "#FFFFFF"
                    border.color: catCombo.popup.visible || catCombo.hovered ? "#93C5FD" : "#E2E8F0"
                    border.width: catCombo.popup.visible ? 1.5 : 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                }

                ComboBox {
                    id: catCombo
                    anchors.fill: parent
                    anchors.margins: 1
                    flat: true
                    // 保持原始 QVariantMap 对象，不映射为字符串（保留 cateId/cateNm 完整字段）
                    model: UserIngredientService.categories
                    textRole: "cateNm"   // 显示值绑定到 cateNm 字段
                    indicator: null       // 自定义箭头
                    displayText: currentIndex >= 0
                                ? (model.cateNm !== undefined ? model.cateNm : currentText)
                                : "请选择分类"

                    contentItem: Text {
                        leftPadding: 14
                        rightPadding: 30
                        text: catCombo.displayText
                        font.pixelSize: 20
                        color: catCombo.currentIndex >= 0 ? "#1E293B" : "#94A3B8"
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    popup: Popup {
                        y: catCombo.height + 4
                        width: catCombo.width - 2
                        implicitHeight: contentItem.implicitHeight
                        padding: 4

                        background: Rectangle {
                            radius: 10
                            color: "#FFFFFF"
                            border.color: "#E2E8F0"
                            border.width: 1
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#000000"
                                shadowBlur: 15
                                shadowOpacity: 0.12
                                shadowVerticalOffset: 4
                            }
                        }

                        contentItem: ListView {
                            clip: true
                            implicitHeight: Math.min(contentHeight, 260)

                            model: catCombo.popup.visible ? catCombo.delegateModel : null
                            currentIndex: catCombo.highlightedIndex

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                            }
                        }
                    }

                    delegate: ItemDelegate {
                        width: catCombo.width - 10
                        height: 42
                        highlighted: catCombo.highlightedIndex === index

                        background: Rectangle {
                            radius: 6
                            color: hovered ? "#EFF6FF" : "transparent"
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        contentItem: Text {
                            leftPadding: 10
                            // model 是 QVariantMap，直接取 cateNm 字段作为显示文本
                            text: (model.cateNm !== undefined) ? model.cateNm : (model.modelData !== undefined ? model.modelData.cateNm || "" : "")
                            font.pixelSize: 18
                            color: catCombo.currentIndex === index ? "#2563EB" : "#334155"
                            font.bold: catCombo.currentIndex === index
                            verticalAlignment: Text.AlignVCenter
                        }

                        onClicked: {
                            catCombo.currentIndex = index
                            dialogRoot.selectedCategoryIndex = index
                            var cat = UserIngredientService.categories[index]
                            dialogRoot.selectedCategoryId = (cat && cat.cateId !== undefined) ? String(cat.cateId) : ""
                            dialogRoot.selectedCategoryName = (cat && cat.cateNm !== undefined) ? cat.cateNm : ""
                            catCombo.popup.close()
                        }
                    }

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) {
                            dialogRoot.selectedCategoryIndex = currentIndex
                            var cat = UserIngredientService.categories[currentIndex]
                            dialogRoot.selectedCategoryId = (cat && cat.cateId !== undefined) ? String(cat.cateId) : ""
                            dialogRoot.selectedCategoryName = (cat && cat.cateNm !== undefined) ? cat.cateNm : ""
                        } else {
                            dialogRoot.selectedCategoryId = ""
                            dialogRoot.selectedCategoryName = ""
                        }
                    }
                }

                // 自定义下拉箭头
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: "\u25BC"
                    font.pixelSize: 13
                    color: "#94A3B8"
                }
            }
        }

        Item { Layout.fillHeight: true }

        // ====== 底部按钮栏 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            spacing: 14

            // 取消按钮
            Rectangle {
                Layout.preferredWidth: 120
                Layout.preferredHeight: 48
                radius: 10
                color: cancelBtnMA.containsMouse ? "#F1F5F9" : "#FFFFFF"
                border.color: "#D1D5DB"
                border.width: 1.2

                Text {
                    anchors.centerIn: parent
                    text: "取消"
                    font.pixelSize: 20
                    font.bold: true
                    color: "#64748B"
                }

                MouseArea {
                    id: cancelBtnMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dialogRoot.close()
                }
            }

            // 确认添加按钮
            Rectangle {
                id: confirmBtn
                Layout.preferredWidth: 140
                Layout.preferredHeight: 48
                radius: 10
                enabled: ingredientName.trim() !== "" && selectedCategoryIndex >= 0
                opacity: enabled ? 1.0 : 0.45
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: enabled ? "#3B82F6" : "#94A3B8" }
                    GradientStop { position: 1.0; color: enabled ? "#1D4ED8" : "#CBD5E1" }
                }
                Behavior on opacity { NumberAnimation { duration: 150 } }

                Text {
                    anchors.centerIn: parent
                    text: "确认添加"
                    font.pixelSize: 20
                    font.bold: true
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: confirmBtn.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (!confirmBtn.enabled) return
                        // 调用 C++ 服务创建食材（ingrCd 由后端/服务端随机生成）
                        UserIngredientService.createIngredient(
                            ingredientName.trim(), selectedCategoryId,
                            selectedCategoryName || "")
                    }
                }
            }
        }
    }

    onOpened: {
        ingredientName = ""
        selectedCategoryIndex = -1
        selectedCategoryId = ""
        selectedCategoryName = ""
        nameInput.text = ""
        catCombo.currentIndex = -1
    }

    Connections {
        target: UserIngredientService
        function onCreateSuccess(ingrId, ingrNm) {
            console.log("[AddIngredient] 创建成功:", ingrNm, "ingrId=", ingrId)
            dialogRoot.close()
        }
        function onCreateFailed(errorMsg) {
            console.log("[AddIngredient] 创建失败:", errorMsg)
            window.alert(errorMsg, "error", "创建食材失败")
        }
    }
}
