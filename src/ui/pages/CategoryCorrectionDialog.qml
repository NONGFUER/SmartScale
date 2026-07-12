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

    x: (parent.width - width) / 2
    // 键盘弹出时上移避让，避免搜索框被键盘遮挡
    y: Math.min((parent.height - height) / 2,
                parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    width: Math.min(parent.width * 0.92, 1200)
    height: Math.min(parent.height * 0.88, 780)
    padding: 0

    // 非模态 + 外部遮罩（Main.qml 的 categoryOverlay），避免 Qt 内部 modal 层遮挡虚拟键盘
    modal: false
    closePolicy: Popup.NoAutoClose
    title: ""
    z: 50

    background: Rectangle {
        color: "#FFFFFF"
        radius: 48
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 30
            shadowOpacity: 0.25
            shadowVerticalOffset: 10
        }
    }

    property string selectedLabel: ""
    property string selectedIngrId: ""
    property int activeCategoryIndex: 0   // categorySelectMode 下的单级分类下标
    property int selectedTopIndex: -1     // 一级品类下标（categoryTree）
    property string selectedSubCateId: "" // 二级品类 cateId
    property string selectedSubCateName: "" // 二级品类 cateNm
    property string searchText: ""        // 当前搜索关键词
    property var searchResults: []        // 搜索结果列表（跨分类）

    // 扁平化分类列表为食材项数组
    function flattenItems(cats) {
        var all = []
        for (var c = 0; c < cats.length; c++) {
            var items = cats[c].items || []
            for (var i = 0; i < items.length; i++)
                all.push(items[i])
        }
        return all
    }

    // 当前模式下全部食材项
    function getAllItems() {
        if (dialogRoot.categorySelectMode)
            return dialogRoot.flattenItems(UserIngredientService.categories)
        return dialogRoot.flattenItems(CategoryService.categories)
    }

    // 本地搜索：跨全部食材按 cn/en 模糊匹配
    function doSearch(key) {
        var trimmed = key.trim()
        if (trimmed === "") {
            dialogRoot.searchResults = []
            return
        }
        var lower = trimmed.toLowerCase()
        var results = []
        var items = dialogRoot.getAllItems()
        for (var i = 0; i < items.length; i++) {
            var cn = (items[i].cn || "").toLowerCase()
            var en = (items[i].en || "").toLowerCase()
            if (cn.indexOf(lower) >= 0 || en.indexOf(lower) >= 0) {
                results.push(items[i])
            }
        }
        dialogRoot.searchResults = results
        console.log("[CategoryDialog] 搜索 '", trimmed, "' 命中", results.length, "项")
    }

    // 在 categoryTree 中定位某个二级 cateId 对应的一级下标与二级 id
    function findCategoryTreePosition(cateId) {
        var tree = CategoryService.categoryTree
        for (var i = 0; i < tree.length; i++) {
            var children = tree[i].children || []
            for (var j = 0; j < children.length; j++) {
                if (String(children[j].cateId) === String(cateId)) {
                    return { topIndex: i, subCateId: String(cateId) }
                }
            }
        }
        return null
    }

    // GridView 当前应显示的数据源
    function getDisplayItems() {
        if (dialogRoot.searchText.trim() !== "")
            return dialogRoot.searchResults
        // 食材选择/纠错模式统一按二级品类 cateId 过滤
        var subId = dialogRoot.selectedSubCateId
        if (subId === "")
            return []
        var all = dialogRoot.getAllItems()
        var filtered = []
        for (var i = 0; i < all.length; i++) {
            if (String(all[i].cateId) === subId)
                filtered.push(all[i])
        }
        return filtered
    }

    // 根据当前选中标签取完整食材项
    function getSelectedItem() {
        var items = dialogRoot.getAllItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].en === dialogRoot.selectedLabel)
                return items[i]
        }
        return null
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ====== 顶部栏：返回 + 搜索框 + 搜索按钮 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 24
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            spacing: 12

            // 返回按钮
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 10
                color: backMouse.containsMouse ? "#EEF1F6" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"
                    font.pixelSize: 38
                    font.bold: true
                    color: "#333333"
                }
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: dialogRoot.reject()
                }
            }

            // 搜索胶囊容器
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 21
                color: "#FFFFFF"
                border.color: catSearchInput.activeFocus ? "#4361EE" : "#E8EAED"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 4
                    spacing: 8

                    // // 搜索图标
                    // Text {
                    //     font.pixelSize: 18
                    //     color: "#9CA3AF"
                    //     Layout.preferredWidth: 20
                    //     Layout.preferredHeight: 38
                    //     Layout.alignment: Qt.AlignVCenter
                    //     verticalAlignment: Text.AlignVCenter
                    //     text: "\u{1F50D}"
                    // }

                    TextField {
                        id: catSearchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        placeholderText: "请输入搜索内容"
                        font.pixelSize: 24
                        color: "#1B263B"
                        verticalAlignment: TextInput.AlignVCenter
                        inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase  // 不自动大写首字母
                        background: null
                        // 实时本地搜索：输入即过滤
                        onTextChanged: {
                            dialogRoot.searchText = text
                            dialogRoot.doSearch(text)
                        }
                        // 清空快捷
                        Keys.onEscapePressed: {
                            text = ""
                            dialogRoot.searchText = ""
                            dialogRoot.searchResults = []
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 80
                        Layout.preferredHeight: 42
                        radius: 17
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#3B82F6" }
                            GradientStop { position: 1.0; color: "#1D4ED8" }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            // 搜索图标（放大镜）
                            Item {
                                width: 18; height: 18
                                anchors.verticalCenter: parent.verticalCenter
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.clearRect(0, 0, width, height)
                                        ctx.strokeStyle = "#FFFFFF"
                                        ctx.lineWidth = 2
                                        ctx.lineCap = "round"
                                        // 圆圈部分（放大镜头部）
                                        ctx.beginPath()
                                        ctx.arc(7, 7, 5.5, 0, Math.PI * 2)
                                        ctx.stroke()
                                        // 手柄部分
                                        ctx.beginPath()
                                        ctx.moveTo(11, 11)
                                        ctx.lineTo(16.5, 16.5)
                                        ctx.stroke()
                                    }
                                    Component.onCompleted: requestPaint()
                                }
                            }

                            Text {
                                text: "搜索"
                                font.pixelSize: 22
                                font.bold: true
                                color: "white"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            // 已是实时搜索，点击按钮只做焦点切换 + 日志
                            onClicked: {
                                dialogRoot.searchText = catSearchInput.text
                                dialogRoot.doSearch(catSearchInput.text)
                                console.log("[CategoryDialog] 搜索:", catSearchInput.text)
                            }
                        }
                    }

                    // 添加食材按钮（与搜索按钮同风格）
                    Rectangle {
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 42
                        radius: 17
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#3B82F6" }
                            GradientStop { position: 1.0; color: "#1D4ED8" }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 4

                            // 添加图标（圆圈内 +）
                            Rectangle {
                                width: 18; height: 18; radius: 9
                                color: "transparent"
                                border.width: 2
                                border.color: "#FFFFFF"
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "+"
                                    font.pixelSize: 14
                                    font.bold: true
                                    color: "#FFFFFF"
                                }
                            }

                            Text {
                                text: "添加食材"
                                font.pixelSize: 20
                                font.bold: true
                                color: "white"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: addIngredientDialog.open()
                        }
                    }
                }
            }
        }

        // ====== 分类标签 + 品类网格容器（统一背景，与顶部栏产生隔离感）=====
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.topMargin: 16
            color: '#F2F7FF'
            radius: 16
            border.color: "#E2E8F0"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

        // ====== 一级品类标签行（食材纠错模式，使用 categoryTree 两级）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 4
            spacing: 12
            visible: dialogRoot.searchText.trim() === ""

            Text {
                text: "一级:"
                font.pixelSize: 18
                color: "#999999"
                verticalAlignment: Text.AlignVCenter
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                contentWidth: topTagRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: topTagRow
                    spacing: 28

                    Repeater {
                        model: CategoryService.categoryTree

                        Item {
                            width: tTxt.implicitWidth + 4
                            height: 36

                            Text {
                                id: tTxt
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.cateNm || ""
                                font.pixelSize: 22
                                font.bold: (dialogRoot.selectedTopIndex === index)
                                color: (dialogRoot.selectedTopIndex === index) ? "#4361EE" : "#666666"
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: tTxt.width * 0.7
                                height: 3
                                visible: (dialogRoot.selectedTopIndex === index)
                                radius: 1.5
                                color: "#4361EE"
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    dialogRoot.selectedTopIndex = index
                                    dialogRoot.selectedSubCateId = ""
                                    dialogRoot.selectedSubCateName = ""
                                    dialogRoot.selectedLabel = ""
                                }
                            }
                        }
                    }
                }
            }
        }

        // ====== 二级品类标签行（食材纠错模式）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 10
            spacing: 12
            visible: dialogRoot.selectedTopIndex >= 0
                      && dialogRoot.searchText.trim() === ""

            Text {
                text: "二级:"
                font.pixelSize: 18
                color: "#999999"
                verticalAlignment: Text.AlignVCenter
            }

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                contentWidth: subTagRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: subTagRow
                    spacing: 28

                    Repeater {
                        model: (dialogRoot.selectedTopIndex >= 0
                                && dialogRoot.selectedTopIndex < CategoryService.categoryTree.length)
                               ? (CategoryService.categoryTree[dialogRoot.selectedTopIndex].children || [])
                               : []

                        Item {
                            width: sTxt.implicitWidth + 4
                            height: 36

                            Text {
                                id: sTxt
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.cateNm || ""
                                property string myId: (modelData.cateId !== undefined) ? String(modelData.cateId) : ""
                                font.pixelSize: 22
                                font.bold: (dialogRoot.selectedSubCateId === sTxt.myId)
                                color: (dialogRoot.selectedSubCateId === sTxt.myId) ? "#4361EE" : "#666666"
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: sTxt.width * 0.7
                                height: 3
                                visible: (dialogRoot.selectedSubCateId === sTxt.myId)
                                radius: 1.5
                                color: "#4361EE"
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    dialogRoot.selectedSubCateId = sTxt.myId
                                    dialogRoot.selectedSubCateName = (modelData.cateNm !== undefined) ? modelData.cateNm : ""
                                    dialogRoot.selectedLabel = ""
                                }
                            }
                        }
                    }
                }
            }
        }

        // ====== 分类标签行（categorySelectMode 单级，保留旧逻辑）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 12
            spacing: 28
            visible: false

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                contentWidth: catTagRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: catTagRow
                    spacing: 28

                    Repeater {
                        model: UserIngredientService.categories

                        Item {
                            width: catLabelTxt.implicitWidth + 4
                            height: 36

                            Text {
                                id: catLabelTxt
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.cateNm || modelData.name
                                font.pixelSize: 24
                                font.bold: (dialogRoot.activeCategoryIndex === index)
                                color: (dialogRoot.activeCategoryIndex === index) ? "#4361EE" : "#666666"
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: catLabelTxt.width * 0.7
                                height: 3
                                visible: (dialogRoot.activeCategoryIndex === index)
                                radius: 1.5
                                color: "#4361EE"
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
                }
            }
        }

        // ====== 品类网格区域 ======
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            clip: true

            // 搜索无结果时的空状态提示
            Text {
                anchors.centerIn: parent
                visible: dialogRoot.searchText.trim() !== "" && dialogRoot.searchResults.length === 0
                text: "未找到匹配的食材"
                font.pixelSize: 24
                color: "#9CA3AF"
            }

            // 搜索结果计数提示（顶部居中）
            Text {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                visible: dialogRoot.searchText.trim() !== "" && dialogRoot.searchResults.length > 0
                text: "找到 " + dialogRoot.searchResults.length + " 个结果"
                font.pixelSize: 16
                color: "#6B7280"
            }

            GridView {
                id: foodGridView
                anchors.fill: parent
                cellWidth: (foodGridView.width - 40) / 5
                cellHeight: 160
                clip: true

                model: dialogRoot.getDisplayItems()

                delegate: Rectangle {
                    id: foodCard
                    width: foodGridView.cellWidth - 16
                    height: foodGridView.cellHeight - 16
                    radius: 12
                    border.width: 1
                    border.color: dialogRoot.selectedLabel === modelData.en
                                  ? "#4361EE" : (cardHover.containsHover ? "#9DBBFF" : "#E2E8F0")
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    // 卡片背景垂直渐变（顶亮底暗，模拟顶光照射）
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: dialogRoot.selectedLabel === modelData.en ? "#F0F6FF" : "#FFFFFF"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        GradientStop {
                            position: 1.0
                            color: dialogRoot.selectedLabel === modelData.en ? "#D6E4FF" : "#EEF2F7"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                    }

                    // hover 时卡片轻微上浮
                    transform: Translate {
                        id: cardLift
                        y: cardHover.containsHover ? -2 : 0
                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    // 顶部高光带（水平渐变：两端透明→中间白，呈弧面反光）
                    Rectangle {
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 20
                        height: 2
                        radius: 1
                        gradient: Gradient {
                            orientation: Qt.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
                            GradientStop { position: 0.5; color: "#FFFFFF" }
                            GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
                        }
                        opacity: (cardHover.containsHover
                                  || dialogRoot.selectedLabel === modelData.en) ? 1.0 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    // 底部暗影带（水平渐变：两端透明→中间深）
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 2
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 20
                        height: 2
                        radius: 1
                        gradient: Gradient {
                            orientation: Qt.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(0.106, 0.149, 0.231, 0) }
                            GradientStop { position: 0.5; color: "#1B263B" }
                            GradientStop { position: 1.0; color: Qt.rgba(0.106, 0.149, 0.231, 0) }
                        }
                        opacity: (cardHover.containsHover
                                  || dialogRoot.selectedLabel === modelData.en) ? 0.3 : 0.16
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    // 底部散光投影（随卡片上浮显现，模拟悬浮阴影）
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -3
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 14
                        height: 6
                        radius: 3
                        color: "#1B263B"
                        opacity: cardHover.containsHover ? 0.18
                                : (dialogRoot.selectedLabel === modelData.en ? 0.10 : 0.04)
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    // 食材图片：本地缓存优先，缺失/损坏时回退远程 URL
                    Image {
                        id: foodImg
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        cache: false
                        source: {
                            var local = modelData.imgLocal || ""
                            if (local !== "")
                                return "file://" + local
                            return modelData.img || ""
                        }
                        onStatusChanged: {
                            // 本地缓存缺失或损坏时回退到远程 URL
                            if (status === Image.Error && modelData.imgLocal && modelData.img)
                                source = modelData.img
                        }
                    }

                    // 图片就绪时的整体暗化遮罩，保证文字可读
                    Rectangle {
                        anchors.fill: parent
                        color: "#000000"
                        opacity: foodImg.status === Image.Ready ? 0.28 : 0
                        visible: foodImg.status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.cn
                        font.pixelSize: 28
                        font.family: "Microsoft YaHei"
                        font.bold: true
                        color: foodImg.status === Image.Ready ? "#FFFFFF"
                               : (dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "#1B263B")
                    }

                    HoverHandler { id: cardHover }

                    TapHandler {
                        onTapped: {
                            dialogRoot.selectedLabel = modelData.en
                            dialogRoot.selectedIngrId = (modelData.id !== undefined) ? String(modelData.id) : ""
                        }
                    }
                }
            }
        }
            }
        }

        // ====== 底部按钮栏 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 22
            Layout.topMargin: 14
            spacing: 14

            // 取消按钮
            Rectangle {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 52
                radius: 10
                color: cancelHover.hovered ? "#F1F5F9" : "#FFFFFF"
                border.color: "#D1D5DB"
                border.width: 1.2

                HoverHandler { id: cancelHover }

                Text {
                    anchors.centerIn: parent
                    text: "取消"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#64748B"
                }

                TapHandler { onTapped: dialogRoot.reject() }
            }

            // 确认按钮
            Rectangle {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 52
                radius: 10
                enabled: dialogRoot.selectedLabel !== ""
                opacity: enabled ? 1.0 : 0.45
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: dialogRoot.selectedLabel === "" ? "#94A3B8" : "#4361EE" }
                    GradientStop { position: 1.0; color: dialogRoot.selectedLabel === "" ? "#CBD5E1" : "#6BA3FF" }
                }

                Text {
                    anchors.centerIn: parent
                    text: "确认"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }

                TapHandler {
                    enabled: dialogRoot.selectedLabel !== ""
                    onTapped: dialogRoot.accept()
                }
            }
        }
    }

    onOpened: {
        selectedLabel = ""
        selectedIngrId = ""
        activeCategoryIndex = 0
        selectedTopIndex = -1
        selectedSubCateId = ""
        selectedSubCateName = ""
        catSearchInput.text = ""
        searchText = ""            // 清空搜索状态
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
            console.log("[CategoryDialog] \u9009\u4E2D\u98DF\u6750 \u25B6"
                        + " ingrId=" + (m.id !== undefined ? m.id : "")
                        + " ingrCd=" + (m.en !== undefined ? m.en : "")
                        + " ingrNm=" + (m.cn !== undefined ? m.cn : "")
                        + " cateId=" + (m.cateId !== undefined ? m.cateId : "")
                        + " emsId="  + (m.emsId !== undefined ? m.emsId : "")
                        + " emsCd="  + (m.emsCd !== undefined ? m.emsCd : "")
                        + " cateNm=" + (m.cateNm !== undefined ? m.cateNm : ""))
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
        onConfirmed: function(name, categoryIndex, categoryId) {
            // 此信号已不再由确认按钮触发（改用 C++ API），
            // 保留兼容以防外部手动调用 confirmed
        }
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

    // 两级品类树加载完成后，默认选中第一个一级 + 第一个二级，避免网格空白
    Connections {
        target: CategoryService
        function onCategoryTreeChanged() {
            if (dialogRoot.selectedTopIndex >= 0
                || CategoryService.categoryTree.length === 0)
                return
            dialogRoot.selectedTopIndex = 0
            var kids = CategoryService.categoryTree[0].children || []
            if (kids.length > 0) {
                dialogRoot.selectedSubCateId = String(kids[0].cateId)
                dialogRoot.selectedSubCateName = (kids[0].cateNm !== undefined) ? kids[0].cateNm : ""
            }
        }
    }
}
