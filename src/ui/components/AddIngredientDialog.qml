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
    property int selectedCategoryIndex: -1       // 当前选中二级品类的下标（兼容旧信号）
    property string selectedCategoryId: ""        // 当前选中二级品类的 cateId
    property string selectedCategoryName: ""       // 当前选中二级品类的 cateNm
    property string selectedTopCateId: ""          // 当前选中一级品类的 cateId
    property string selectedTopCateName: ""        // 当前选中一级品类的 cateNm

    x: (parent.width - width) / 2
    y: Math.min((parent.height - height) / 2, parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    width: Math.min(parent.width * 0.85, 680)
    height: Math.min(parent.height * 0.75, 480)
    modal: false
    closePolicy: Popup.NoAutoClose

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘 z:99，避让虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: dialogRoot.visible
        MouseArea {
            anchors.fill: parent
            onClicked: {}  // NoAutoClose：点击外部不关闭，仅拦截防点穿
        }
    }
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

            // 关闭按钮 — 使用 close_blue.png 图片图标
            Rectangle {
                width: 46; height: 46; radius: 23
                color: closeMouse.containsMouse ? "#F1F5F9" : "transparent"

                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    height: parent.height * 0.6
                    fillMode: Image.PreserveAspectFit
                    source: "qrc:/resources/img/close_blue.png"
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
                    focus: false          // 禁止打开弹窗时自动聚焦（避免虚拟键盘弹出）
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

        // ====== 选择分类（两级：先选一级品类，再选二级品类）======
        ColumnLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 24
            spacing: 12

            RowLayout {
                spacing: 4
                Text { text: "*"; font.pixelSize: 20; color: "#EF4444"; font.bold: true }
                Text { text: "选择分类"; font.pixelSize: 20; color: "#334155"; font.bold: true }
            }

            // 两级联动：一级品类 → 二级品类
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // ---- 一级品类下拉 ----
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52

                    Rectangle {
                        id: topComboBg
                        anchors.fill: parent
                        radius: 10
                        color: "#FFFFFF"
                        border.color: topCombo.popup.visible || topCombo.hovered ? "#93C5FD" : "#E2E8F0"
                        border.width: topCombo.popup.visible ? 1.5 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    ComboBox {
                        id: topCombo
                        anchors.fill: parent
                        anchors.margins: 1
                        flat: true
                        model: CategoryService.categoryTree
                        textRole: "cateNm"
                        indicator: null
                        // displayText 在 ComboBox 根作用域求值，modelData 不可用；
                        // 用 currentText（已按 textRole=cateNm 解析）配合占位文案
                        displayText: currentIndex >= 0
                                    ? currentText
                                    : "请选择一级品类"

                        contentItem: Text {
                            leftPadding: 14
                            rightPadding: 30
                            text: topCombo.displayText
                            font.pixelSize: 18
                            color: topCombo.currentIndex >= 0 ? "#1E293B" : "#94A3B8"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        popup: Popup {
                            y: topCombo.height + 4
                            width: topCombo.width - 2
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
                                implicitHeight: Math.min(contentHeight, 220)
                                model: topCombo.popup.visible ? topCombo.delegateModel : null
                                currentIndex: topCombo.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }

                        delegate: ItemDelegate {
                            width: topCombo.width - 10
                            height: 42
                            highlighted: topCombo.highlightedIndex === index
                            background: Rectangle {
                                radius: 6
                                color: hovered ? "#EFF6FF" : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            contentItem: Text {
                                leftPadding: 10
                                text: (modelData.cateNm !== undefined) ? modelData.cateNm : ""
                                font.pixelSize: 18
                                color: topCombo.currentIndex === index ? "#2563EB" : "#334155"
                                font.bold: topCombo.currentIndex === index
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                topCombo.currentIndex = index
                                var t = CategoryService.categoryTree[index]
                                dialogRoot.selectedTopCateId = (t && t.cateId !== undefined) ? String(t.cateId) : ""
                                dialogRoot.selectedTopCateName = (t && t.cateNm !== undefined) ? t.cateNm : ""
                                // 切换一级时清空二级选择
                                subCombo.currentIndex = -1
                                dialogRoot.selectedCategoryId = ""
                                dialogRoot.selectedCategoryName = ""
                                topCombo.popup.close()
                            }
                        }

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0) {
                                var t = CategoryService.categoryTree[currentIndex]
                                dialogRoot.selectedTopCateId = (t && t.cateId !== undefined) ? String(t.cateId) : ""
                                dialogRoot.selectedTopCateName = (t && t.cateNm !== undefined) ? t.cateNm : ""
                            }
                        }
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u25BC"
                        font.pixelSize: 13
                        color: "#94A3B8"
                    }
                }

                // ---- 二级品类下拉 ----
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52

                    Rectangle {
                        id: subComboBg
                        anchors.fill: parent
                        radius: 10
                        color: dialogRoot.selectedTopCateId === "" ? "#F8FAFC" : "#FFFFFF"
                        border.color: subCombo.popup.visible || subCombo.hovered ? "#93C5FD" : "#E2E8F0"
                        border.width: subCombo.popup.visible ? 1.5 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                    }

                    ComboBox {
                        id: subCombo
                        anchors.fill: parent
                        anchors.margins: 1
                        flat: true
                        enabled: dialogRoot.selectedTopCateId !== ""
                        // 选中一级后，二级 model 取其 children
                        property var subList: (dialogRoot.selectedTopCateId !== ""
                                               && topCombo.currentIndex >= 0)
                                              ? (CategoryService.categoryTree[topCombo.currentIndex].children || []) : []
                        model: subCombo.subList
                        textRole: "cateNm"
                        indicator: null
                        displayText: currentIndex >= 0
                                    ? currentText
                                    : (enabled ? "请选择二级品类" : "请先选一级")

                        contentItem: Text {
                            leftPadding: 14
                            rightPadding: 30
                            text: subCombo.displayText
                            font.pixelSize: 18
                            color: subCombo.currentIndex >= 0 ? "#1E293B" : "#94A3B8"
                            verticalAlignment: Text.AlignVCenter
                            elide: Text.ElideRight
                        }

                        popup: Popup {
                            y: subCombo.height + 4
                            width: subCombo.width - 2
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
                                implicitHeight: Math.min(contentHeight, 220)
                                model: subCombo.popup.visible ? subCombo.delegateModel : null
                                currentIndex: subCombo.highlightedIndex
                                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                            }
                        }

                        delegate: ItemDelegate {
                            width: subCombo.width - 10
                            height: 42
                            highlighted: subCombo.highlightedIndex === index
                            background: Rectangle {
                                radius: 6
                                color: hovered ? "#EFF6FF" : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            contentItem: Text {
                                leftPadding: 10
                                text: (modelData.cateNm !== undefined) ? modelData.cateNm : ""
                                font.pixelSize: 18
                                color: subCombo.currentIndex === index ? "#2563EB" : "#334155"
                                font.bold: subCombo.currentIndex === index
                                verticalAlignment: Text.AlignVCenter
                            }
                            onClicked: {
                                subCombo.currentIndex = index
                                var c = subCombo.subList[index]
                                dialogRoot.selectedCategoryId = (c && c.cateId !== undefined) ? String(c.cateId) : ""
                                dialogRoot.selectedCategoryName = (c && c.cateNm !== undefined) ? c.cateNm : ""
                                subCombo.popup.close()
                            }
                        }

                        onCurrentIndexChanged: {
                            if (currentIndex >= 0) {
                                var c = subCombo.subList[currentIndex]
                                dialogRoot.selectedCategoryId = (c && c.cateId !== undefined) ? String(c.cateId) : ""
                                dialogRoot.selectedCategoryName = (c && c.cateNm !== undefined) ? c.cateNm : ""
                            } else {
                                dialogRoot.selectedCategoryId = ""
                                dialogRoot.selectedCategoryName = ""
                            }
                        }
                    }

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
                enabled: ingredientName.trim() !== "" && selectedCategoryId !== ""
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
        selectedTopCateId = ""
        selectedTopCateName = ""
        nameInput.text = ""
        topCombo.currentIndex = -1
        subCombo.currentIndex = -1
        // 确保食材品类两级树已加载（无网络时也可用本地缓存）
        CategoryService.fetchIngrCategories()
        // 把焦点从名称输入框移走，防止虚拟键盘自动弹出
        Qt.callLater(function() { closeMouse.forceActiveFocus() })
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
