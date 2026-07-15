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

        // 推荐模式：把候选 {code,name} 适配为 FoodCard 期望的 {cn,en,id,img,imgLocal}
        // 优先通过 emsCd 反查完整食材信息（含图片），反查不到则用候选基本信息（无图，卡片显示占位文字）
        if (dialogRoot.selectedTopIndex === -999) {
            var recs = dialogRoot.recommendCandidates
            var adapted = []
            for (var i = 0; i < recs.length; i++) {
                var r = recs[i]
                var code = r.code || ""
                var full = UserIngredientService.findByEmsCd(code)
                if (full && full["id"]) {
                    adapted.push(full)
                } else {
                    adapted.push({
                        cn: r.name || "",
                        en: code,
                        id: "",
                        img: "",
                        imgLocal: "",
                        cateId: ""
                    })
                }
            }
            return adapted
        }

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
        //  顶部导航栏：返回(左) + 标题(中) + 添加食材(右) + 搜索框(右)
        // ============================================================
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 64

            // ← 返回按钮（左）— 使用 back.png（原为宽矩形盛放"← 返回"文字，现改为方形圆形图标按钮与其他两个一致）
            Rectangle {
                id: backBtn
                x: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 44; height: 44
                radius: 22
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                Image {
                    anchors.centerIn: parent
                    width: parent.width * 0.6
                    height: parent.height * 0.6
                    fillMode: Image.PreserveAspectFit
                    source: "qrc:/resources/img/back.png"
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

            // 添加食材按钮（搜索框左侧，文字按钮无图标）
            Rectangle {
                id: addFoodBtn
                anchors.right: searchBox.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 130; height: 44
                radius: 16
                color: addFoodMouse.containsMouse ? "#3651D4" : "#4361EE"

                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "添加食材"
                    font.pixelSize: 20
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "white"
                }

                MouseArea {
                    id: addFoodMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: addIngredientDialog.open()
                }
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
                        focus: false          // 禁止打开弹窗时自动聚焦（避免虚拟键盘弹出）
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

                        // ===== AI 推荐标签（仅在有候选时显示）=====
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 56
                            radius: 8
                            visible: dialogRoot.recommendCandidates.length > 0
                            color: dialogRoot.selectedTopIndex === -999
                                    ? "#FFF7ED" : (recTagMouse.containsHover ? "#F5F7FA" : "transparent")

                            Behavior on color { ColorAnimation { duration: 120 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                Text {
                                    text: "推荐"
                                    font.pixelSize: 22
                                    font.family: Theme.fontFamilyUi
                                    font.bold: (dialogRoot.selectedTopIndex === -999)
                                    color: dialogRoot.selectedTopIndex === -999 ? "#F59E0B" : "#475569"
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // 右箭头（选中时显示）
                                Text {
                                    text: "\u25B6"
                                    font.pixelSize: 22
                                    color: dialogRoot.selectedTopIndex === -999 ? "#F59E0B" : "#CBD5E1"
                                    visible: dialogRoot.selectedTopIndex === -999
                                    Layout.alignment: Qt.AlignVCenter
                                }
                            }

                            MouseArea {
                                id: recTagMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    dialogRoot.selectedTopIndex = -999
                                    dialogRoot.selectedSubCateId = ""
                                    dialogRoot.selectedSubCateName = ""
                                    dialogRoot.selectedLabel = ""
                                }
                            }
                        }

                        // 推荐标签与分类列表之间的分隔线（仅在有推荐时显示）
                        Rectangle {
                            Layout.fillWidth: true
                            height: 1
                            color: "#EEF2F6"
                            Layout.leftMargin: 8
                            Layout.rightMargin: 8
                            visible: dialogRoot.recommendCandidates.length > 0
                        }

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

                    // ===== 食材网格（GridView）=====
                    // 推荐模式 / 正常分类模式 / 搜索模式 统一复用 GridView + FoodCard delegate
                    // 推荐模式下 getDisplayItems() 会把候选 {code,name} 适配为卡片期望的 {cn,en,id,img,imgLocal}
                    GridView {
                        id: foodGridView
                        anchors.fill: parent
                        anchors.margins: 20
                        cellWidth: (foodGridView.width - 24) / 3
                        cellHeight: 250
                        clip: true
                        model: dialogRoot.getDisplayItems()

                        delegate: Rectangle {
                            id: cardWrapper
                            width: foodGridView.cellWidth - 18
                            height: cardColumn.implicitHeight + 20
                            radius: 16
                            color: "#FFFFFF"
                            clip: true

                            // 关键细节1：极细浅灰边框 + 极微弱阴影，显得更干净
                            // 选中蓝 2px，未选中浅灰 1px（替代纯透明，给每张卡一个精致描边）
                            border.width: dialogRoot.selectedLabel === modelData.en ? 2 : 1
                            border.color: dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "#F3F4F6"
                            Behavior on border.color { ColorAnimation { duration: 120 } }
                            Behavior on border.width { NumberAnimation { duration: 120 } }

                            // 极微弱阴影（项目标准：blur 1.0 / opacity 0.1）
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
                                // 关键细节2：四周 10px 纯白内边距，形成"相框"效果
                                anchors.margins: 10
                                spacing: 12

                                // 上半部：图片专属容器（内层独立圆角）
                                Rectangle {
                                    id: imageContainer
                                    width: parent.width
                                    height: foodGridView.cellHeight - 80
                                    // 关键细节3：内层圆角比外层(16)略小，视觉协调
                                    radius: 12
                                    // 关键细节4：极柔和浅灰底，与白底形成对比，统一灰/白底图
                                    color: "#F7F8FA"

                                    // 悬浮时整个图片瓦微微放大（圆角随之缩放，不出现直角）
                                    scale: foodHover.hovered ? 1.05 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

                                    // 源图片（隐藏，仅作 MultiEffect 的 source）
                                    Image {
                                        id: foodImg
                                        anchors.fill: parent
                                        fillMode: Image.PreserveAspectCrop
                                        cache: false
                                        visible: false
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

                                    // 圆角遮罩：白色圆角矩形提供 Alpha 模板（隐藏，仅作 maskSource）
                                    Rectangle {
                                        id: imgMask
                                        anchors.fill: parent
                                        radius: 12
                                        color: "#FFFFFF"
                                        visible: false
                                        layer.enabled: true
                                    }

                                    // 实际显示的图片：对源图应用圆角遮罩
                                    // （Rectangle.clip 不跟随 radius，必须用 MultiEffect mask 才能裁出圆角）
                                    MultiEffect {
                                        anchors.fill: foodImg
                                        source: foodImg
                                        maskEnabled: true
                                        maskSource: imgMask
                                    }

                                    // 无图片时的占位文字：灰底容器即为占位背景，字色加深显正式
                                    Text {
                                        anchors.centerIn: parent
                                        visible: foodImg.status !== Image.Ready
                                        text: modelData.cn
                                        font.pixelSize: 22
                                        font.bold: true
                                        font.family: Theme.fontFamilyUi
                                        color: "#64748B"
                                    }
                                }

                                // 下半部：食材名称
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
        // 有推荐候选时优先展示推荐，否则默认第一个一级分类
        selectedTopIndex = (dialogRoot.recommendCandidates.length > 0) ? -999 : 0
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
        // 把焦点从搜索框移走，防止虚拟键盘自动弹出
        Qt.callLater(function() { backMouse.forceActiveFocus() })
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
            if (CategoryService.categoryTree.length === 0)
                return
            // 推荐模式 → 不覆盖
            if (dialogRoot.selectedTopIndex === -999)
                return
            // 二级品类已选（用户手动点击过）→ 不覆盖默认选中
            if (dialogRoot.selectedSubCateId !== "")
                return
            // 默认选中第一级 + 第二级首个分类
            dialogRoot.selectedTopIndex = 0
            var kids = CategoryService.categoryTree[0].children || []
            if (kids.length > 0) {
                dialogRoot.selectedSubCateId = String(kids[0].cateId)
                dialogRoot.selectedSubCateName = kids[0].cateNm || ""
            } else {
                dialogRoot.selectedSubCateId = ""
                dialogRoot.selectedSubCateName = ""
            }
        }
    }
}
