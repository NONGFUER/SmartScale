import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale.Tools 1.0
import "../components"

Dialog {
    id: dialogRoot
    property string currentPrediction: ""
    property string currentImagePath: ""
    property bool categorySelectMode: false

    signal labelConfirmed(string confirmedLabel, string ingrId)
    signal selectModeToggled(bool isActive)

    // AI 候选列表（从 WorkstationPage 注入，用于"推荐"标签展示）
    property var recommendCandidates: []

    x: (parent.width - width) / 2
    y: Math.min((parent.height - height) / 2,
                parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    width: Math.min(parent.width * 0.95, 1280)
    height: Math.min(parent.height * 0.90, 820)
    padding: 0

    // 非模态 + 外部遮罩（Main.qml 的 categoryOverlay）
    modal: false
    closePolicy: Popup.NoAutoClose
    title: ""
    z: 50

    background: Rectangle {
        color: "#FFFFFF"
        radius: 24
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 48
            shadowOpacity: 0.25
            shadowVerticalOffset: 12
        }
    }

    // ===== 状态属性 =====
    property string selectedLabel: ""
    property string selectedIngrId: ""
    property int activeCategoryIndex: 0
    property int selectedTopIndex: 0          // 一级品类下标（categoryTree）
    property string selectedSubCateId: ""     // 二级品类 cateId
    property string selectedSubCateName: ""   // 二级品类 cateNm
    property string searchText: ""
    property var searchResults: []


    // ===== 数据方法 =====
    function flattenItems(cats) {
        var all = []
        for (var c = 0; c < cats.length; c++) {
            var items = cats[c].items || []
            for (var i = 0; i < items.length; i++)
                all.push(items[i])
        }
        return all
    }

    function getAllItems() {
        if (dialogRoot.categorySelectMode)
            return dialogRoot.flattenItems(UserIngredientService.categories)
        return dialogRoot.flattenItems(CategoryService.categories)
    }

    function doSearch(key) {
        var trimmed = key.trim()
        if (trimmed === "") { dialogRoot.searchResults = []; return }
        var lower = trimmed.toLowerCase()
        var results = []
        var items = dialogRoot.getAllItems()
        for (var i = 0; i < items.length; i++) {
            var cn = (items[i].cn || "").toLowerCase()
            var en = (items[i].en || "").toLowerCase()
            if (cn.indexOf(lower) >= 0 || en.indexOf(lower) >= 0)
                results.push(items[i])
        }
        dialogRoot.searchResults = results
    }

    function findCategoryTreePosition(cateId) {
        var tree = CategoryService.categoryTree
        for (var i = 0; i < tree.length; i++) {
            var children = tree[i].children || []
            for (var j = 0; j < children.length; j++) {
                if (String(children[j].cateId) === String(cateId))
                    return { topIndex: i, subCateId: String(cateId) }
            }
        }
        return null
    }

    function getDisplayItems() {
        if (dialogRoot.searchText.trim() !== "")
            return dialogRoot.searchResults
        var subId = dialogRoot.selectedSubCateId
        if (subId === "") return []
        var all = dialogRoot.getAllItems()
        var filtered = []
        for (var i = 0; i < all.length; i++) {
            if (String(all[i].cateId) === subId)
                filtered.push(all[i])
        }
        return filtered
    }

    function getSelectedItem() {
        var items = dialogRoot.getAllItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].en === dialogRoot.selectedLabel)
                return items[i]
        }
        return null
    }

    // 获取当前一级分类的子列表
    function getCurrentChildren() {
        if (dialogRoot.selectedTopIndex >= 0 && dialogRoot.selectedTopIndex < CategoryService.categoryTree.length)
            return CategoryService.categoryTree[dialogRoot.selectedTopIndex].children || []
        return []
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ============================================================
        //  顶部导航栏：返回(左) + 标题(中) + 搜索框(右)
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            // ← 返回按钮（左）
            Rectangle {
                id: backBtn
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 80; height: 40
                radius: 10
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Text { text: "\u2190"; font.pixelSize: 30; color: "#4361EE"; font.bold: true }
                    Text { text: "返回"; font.pixelSize: 30; color: "#4361EE" }
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: dialogRoot.reject()
                }
            }

            // 标题（居中）
            Text {
                anchors.centerIn: parent
                text: "选择食材"
                font.pixelSize: 30
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: "#1E293B"
            }

            // 搜索框（右侧）
            Rectangle {
                id: searchBox
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 280; height: 44
                radius: 16
                color: "#F8FAFC"
                border.color: catSearchInput.activeFocus ? "#4649E5" : "#E2E8F0"
                border.width: 3

                Behavior on border.color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 14
                    anchors.topMargin: 4
                    anchors.bottomMargin: 4
                    spacing: 8

                    Text {
                        text: "\uD83D\uDD0D"
                        font.pixelSize: 18
                        color: "#94A3B8"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: catSearchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        placeholderText: "搜索食材名称"
                        font.pixelSize: 17
                        font.family: Theme.fontFamilyUi
                        color: "#1E293B"
                        verticalAlignment: TextInput.AlignVCenter
                        background: null
                        onTextChanged: {
                            dialogRoot.searchText = text
                            dialogRoot.doSearch(text)
                        }
                        Keys.onEscapePressed: {
                            text = ""; dialogRoot.searchText = ""; dialogRoot.searchResults = []
                        }
                    }
                }
            }
        }

        // 底部分隔线
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: "#EEF2F6"
        }

        // ============================================================
        //  三栏主体区域
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
                anchors.fill: parent
                spacing: 12
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 16
                anchors.bottomMargin: 16

                // =============================================
                //  左侧栏：一级分类导航
                // =============================================
                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.fillHeight: true
                    radius: 16
                    color: "#FFFFFF"
                    
                    // 阴影面板
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#002A75"
                        shadowOpacity: 0.1
                        shadowBlur: 1.0
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        Repeater {
                            model: CategoryService.categoryTree

                            // 分类项容器
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 56
                                radius: 8
                                color: dialogRoot.selectedTopIndex === index
                                        ? "#EFF6FF" : (catMouse.containsHover ? "#F5F7FA" : "transparent")

                                Behavior on color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Text {
                                        text: modelData.cateNm || ""
                                        font.pixelSize: 22
                                        font.family: Theme.fontFamilyUi
                                        font.bold: (dialogRoot.selectedTopIndex === index)
                                        color: dialogRoot.selectedTopIndex === index ? "#4361EE" : "#475569"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        Layout.alignment: Qt.AlignVCenter
                                    }

                                    // 右箭头（选中时显示）
                                    Text {
                                        text: "\u25B6"
                                        font.pixelSize: 22
                                        color: dialogRoot.selectedTopIndex === index ? "#4361EE" : "#CBD5E1"
                                        visible: dialogRoot.selectedTopIndex === index
                                        Layout.alignment: Qt.AlignVCenter
                                    }
                                }

                                MouseArea {
                                    id: catMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        dialogRoot.selectedTopIndex = index
                                        var kids = modelData.children || []
                                        if (kids.length > 0) {
                                            dialogRoot.selectedSubCateId = String(kids[0].cateId)
                                            dialogRoot.selectedSubCateName = kids[0].cateNm || ""
                                        } else {
                                            dialogRoot.selectedSubCateId = ""
                                            dialogRoot.selectedSubCateName = ""
                                        }
                                        dialogRoot.selectedLabel = ""
                                    }
                                }
                            }
                        } // Repeater 一级分类

                        Item { Layout.preferredHeight: 8 } // 间距

                        // 分隔线
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#EEF2F6"
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                        }

                    } // ColumnLayout 左侧内容
                } // Rectangle 左侧栏

                // =============================================
                //  中间面板：二级品类列表
                // =============================================
                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.fillHeight: true
                    radius: 16
                    color: "#FFFFFF"
                    
                    visible: dialogRoot.selectedTopIndex >= 0
                              && dialogRoot.searchText.trim() === ""

                    // 阴影面板
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: "#002A75"
                        shadowOpacity: 0.1
                        shadowBlur: 1.0
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 2
                        anchors.topMargin: 12
                        anchors.bottomMargin: 12
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12

                        // 面板标题
                        Text {
                            text: dialogRoot.getCurrentChildren().length > 0
                                  ? CategoryService.categoryTree[dialogRoot.selectedTopIndex].cateNm || ""
                                  : ""
                            font.pixelSize: 24
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#64748B"
                            Layout.bottomMargin: 6
                        }

                        // 二级品类列表
                        ListView {
                            id: subList
                            Layout.fillWidth: true
                            Layout.preferredHeight: subList.count * 50 + (subList.count - 1) * 2
                            clip: true
                            model: dialogRoot.getCurrentChildren()

                            delegate: Rectangle {
                                id: subDelegate
                                width: subList.width
                                height: 48
                                radius: 8
                                property string sMyId: (modelData.cateId !== undefined)
                                                        ? String(modelData.cateId) : ""
                                color: dialogRoot.selectedSubCateId === sMyId
                                        ? "#EFF6FF" : "transparent"

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.cateNm || ""
                                    font.pixelSize: 20
                                    font.family: Theme.fontFamilyUi
                                    font.bold: (dialogRoot.selectedSubCateId === subDelegate.sMyId)
                                    color: dialogRoot.selectedSubCateId === subDelegate.sMyId
                                           ? "#4361EE" : "#475569"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        dialogRoot.selectedSubCateId
                                            = (modelData.cateId !== undefined)
                                              ? String(modelData.cateId) : ""
                                        dialogRoot.selectedSubCateName = modelData.cateNm || ""
                                        dialogRoot.selectedLabel = ""
                                    }
                                }
                            }
                        }
                    } // ColumnLayout 中间内容
                } // Rectangle 中间面板

                // =============================================
                //  右侧区域：食材网格 / 推荐列表 / 搜索结果
                // =============================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 16
                    color: "#FFFFFF"
                    border.color: "#EEF2F6"
                    border.width: 1
                    clip: true

                    // 搜索无结果空状态
                    Column {
                        anchors.centerIn: parent
                        spacing: 12
                        visible: dialogRoot.searchText.trim() !== "" && dialogRoot.searchResults.length === 0

                        Text { text: "\uD83D\uDD0D"; font.pixelSize: 48; anchors.horizontalCenter: parent.horizontalCenter }
                        Text {
                            text: "未找到匹配的食材"
                            font.pixelSize: 24
                            font.family: Theme.fontFamilyUi
                            color: "#94A3B8"
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    // ===== AI 推荐模式（ListView）=====
                    ListView {
                        visible: dialogRoot.selectedTopIndex === -999 && dialogRoot.recommendCandidates.length > 0
                                  && dialogRoot.searchText.trim() === ""
                        anchors.fill: parent
                        anchors.margins: 16
                        clip: true
                        model: dialogRoot.recommendCandidates

                        delegate: Rectangle {
                            width: parent ? parent.width : 0
                            height: 72
                            radius: 14
                            color: recMouse.containsHover ? "#FEF3C7" : "#FFFBEB"
                            border.width: dialogRoot.selectedLabel === modelData.code ? 2 : 1
                            border.color: dialogRoot.selectedLabel === modelData.code ? "#F59E0B" : "#FDE68A"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 20
                                anchors.rightMargin: 16
                                spacing: 14

                                // 序号徽章
                                Rectangle {
                                    width: 32; height: 32; radius: 16
                                    color: dialogRoot.selectedLabel === modelData.code ? "#F59E0B" : "#FCD34D"
                                    visible: index < 3

                                    Text {
                                        anchors.centerIn: parent
                                        text: (index + 1).toString()
                                        font.pixelSize: 15
                                        font.bold: true
                                        color: dialogRoot.selectedLabel === modelData.code ? "#FFFFFF" : "#92400E"
                                    }
                                }

                                Text {
                                    text: modelData.name || ""
                                    font.pixelSize: 20
                                    font.family: Theme.fontFamilyUi
                                    color: "#1E293B"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: modelData.code || ""
                                    font.pixelSize: 15
                                    color: "#9CA3AF"
                                }
                            }

                            MouseArea {
                                id: recMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: { dialogRoot.selectedLabel = modelData.code || "" }
                            }
                        }
                    }

                    // ===== 食材网格（GridView）=====
                    GridView {
                        id: foodGridView
                        visible: dialogRoot.selectedTopIndex !== -999
                                  || dialogRoot.searchText.trim() !== ""
                        anchors.fill: parent
                        anchors.margins: 20
                        cellWidth: (foodGridView.width - 24) / 3
                        cellHeight: 160
                        clip: true
                        model: dialogRoot.getDisplayItems()

                        delegate: Rectangle {
                            id: cardWrapper
                            width: foodGridView.cellWidth - 12
                            height: cardColumn.implicitHeight + 16
                            radius: 16
                            color: "#FFFFFF"
                            clip: true

                            // 选中边框：包裹整张卡片（图片+文字）
                            border.width: dialogRoot.selectedLabel === modelData.en ? 2 : 0
                            border.color: dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "transparent"
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on border.width { NumberAnimation { duration: 120 } }

                            // 阴影覆盖整个卡片（图片+文字）
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: "#002A75"
                                shadowOpacity: 0.1
                                shadowBlur: 1.0
                                shadowHorizontalOffset: 0
                                shadowVerticalOffset: 0
                            }

                            HoverHandler { id: foodHover }

                            TapHandler {
                                onTapped: {
                                    dialogRoot.selectedLabel = modelData.en
                                    dialogRoot.selectedIngrId = (modelData.id !== undefined) ? String(modelData.id) : ""
                                }
                            }

                            Column {
                                id: cardColumn
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8

                                // 图片卡片
                                Rectangle {
                                    width: parent.width
                                    height: foodGridView.cellHeight - 62
                                    radius: 14
                                    color: foodHover.hovered ? "#F8FAFC" : "#F5F7FA"
                                    clip: true

                                    Image {
                                        id: foodImg
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectFit
                                        cache: false
                                        source: {
                                            var local = modelData.imgLocal || ""
                                            if (local !== "") return "file://" + local
                                            return modelData.img || ""
                                        }
                                        onStatusChanged: {
                                            if (status === Image.Error && modelData.imgLocal && modelData.img)
                                                source = modelData.img
                                        }
                                    }

                                    // 无图片时的文字回退
                                    Text {
                                        anchors.centerIn: parent
                                        visible: foodImg.status !== Image.Ready
                                        text: modelData.cn
                                        font.pixelSize: 22
                                        font.bold: true
                                        font.family: Theme.fontFamilyUi
                                        color: "#94A3B8"
                                    }
                                }

                                // 名称文字
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: modelData.cn
                                    font.pixelSize: 24
                                    font.family: Theme.fontFamilyUi
                                    font.bold: (dialogRoot.selectedLabel === modelData.en)
                                    color: dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "#374151"
                                    elide: Text.ElideMiddle
                                }
                            }
                        } // Rectangle cardWrapper
                    }
                } // Rectangle 右侧网格区
            } // RowLayout 三栏
        } // Item 主体
        // ===== 底部按钮栏：取消 + 确认 =====
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 82

            Rectangle {
                anchors.fill: parent
                color: "#FFFFFF"
                radius: 10

                // 顶部分隔线
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: "#EEF2F6"
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 20

                    // 取消按钮
                    Rectangle {
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: 60
                        radius: 12
                        color: cancelMouse.containsMouse ? "#F1F5F9" : "#FFFFFF"
                        border.color: "#D1D5DB"
                        border.width: 1.2

                        Text {
                            anchors.centerIn: parent
                            text: "取消"
                            font.pixelSize: 24
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "#4361EE"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: dialogRoot.reject()
                        }
                    }

                    // 确认按钮（需选中食材才可用）
                    Rectangle {
                        id: confirmBtn
                        Layout.preferredWidth: 180
                        Layout.preferredHeight: 60
                        radius: 12
                        enabled: dialogRoot.selectedLabel !== "" && dialogRoot.selectedIngrId !== ""
                        opacity: enabled ? 1.0 : 0.45
                        color: enabled ? "#4361EE" : "#D1D5DB"
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Text {
                            anchors.centerIn: parent
                            text: "确认选择"
                            font.pixelSize: 24
                            font.bold: true
                            font.family: Theme.fontFamilyUi
                            color: "white"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!confirmBtn.enabled) return
                                dialogRoot.accept()
                            }
                        }
                    }
                }
            }
        }
    } // ColumnLayout 根

    // ============================================================
    //  生命周期 & 信号处理
    // ============================================================
    onOpened: {
        selectedLabel = ""
        selectedIngrId = ""
        activeCategoryIndex = 0
        selectedTopIndex = 0
        selectedSubCateId = ""
        selectedSubCateName = ""
        catSearchInput.text = ""
        searchText = ""
        searchResults = []

        if (categorySelectMode) {
            UserIngredientService.fetchIngredients()
            CategoryService.fetchIngrCategories()
        } else {
            CategoryService.fetchCategories()
            CategoryService.fetchIngrCategories()
        }
    }

    onAccepted: {
        var m = dialogRoot.getSelectedItem()
        if (m) {
            console.log("[CategoryDialog] 选中食材 \u25B6"
                        + " ingrId=" + (m.id !== undefined ? m.id : "")
                        + " ingrCd=" + (m.en !== undefined ? m.en : "")
                        + " ingrNm=" + (m.cn !== undefined ? m.cn : ""))
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
        if (categorySelectMode)
            selectModeToggled(false)
    }

    // ==========================================
    //  添加食材弹窗（独立组件）
    // ==========================================
    AddIngredientDialog {
        id: addIngredientDialog
        onConfirmed: function(name, categoryIndex, categoryId) {}
    }

    Connections {
        target: UserIngredientService
        function onCreateSuccess(ingrId, ingrNm) {
            console.log("[CategoryDialog] 食材创建成功:", ingrNm, "ingrId=", ingrId)
            var cats = UserIngredientService.categories
            for (var i = 0; i < cats.length; i++) {
                var items = cats[i].items || []
                for (var j = 0; j < items.length; j++) {
                    if (String(items[j].id) === String(ingrId)) {
                        var pos = dialogRoot.findCategoryTreePosition(items[j].cateId)
                        if (pos) {
                            dialogRoot.selectedTopIndex = pos.topIndex
                            dialogRoot.selectedSubCateId = pos.subCateId
                        }
                        dialogRoot.selectedLabel = items[j].en || ""
                        dialogRoot.selectedIngrId = ingrId
                        return
                    }
                }
            }
        }
    }

    Connections {
        target: CategoryService
        function onCategoryTreeChanged() {
            if (dialogRoot.selectedTopIndex >= 0 || CategoryService.categoryTree.length === 0)
                return
            dialogRoot.selectedTopIndex = 0
            var kids = CategoryService.categoryTree[0].children || []
            if (kids.length > 0) {
                dialogRoot.selectedSubCateId = String(kids[0].cateId)
                dialogRoot.selectedSubCateName = kids[0].cateNm || ""
            }
        }
    }
}
