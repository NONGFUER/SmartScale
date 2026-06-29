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
    property int activeCategoryIndex: 0
    property string searchText: ""        // 当前搜索关键词
    property var searchResults: []        // 搜索结果列表（跨分类）

    // 本地搜索：在所有分类的所有 item 里按 cn/en 模糊匹配
    function doSearch(key) {
        var trimmed = key.trim()
        if (trimmed === "") {
            dialogRoot.searchResults = []
            return
        }
        var lower = trimmed.toLowerCase()
        var results = []
        var cats = getActiveCategories()
        for (var c = 0; c < cats.length; c++) {
            var items = cats[c].items || []
            for (var i = 0; i < items.length; i++) {
                var cn = (items[i].cn || "").toLowerCase()
                var en = (items[i].en || "").toLowerCase()
                if (cn.indexOf(lower) >= 0 || en.indexOf(lower) >= 0) {
                    results.push(items[i])
                }
            }
        }
        dialogRoot.searchResults = results
        console.log("[CategoryDialog] 搜索 '", trimmed, "' 命中", results.length, "项")
    }

    // GridView 当前应显示的数据源：搜索时用结果，否则用当前分类
    function getDisplayItems() {
        if (dialogRoot.searchText.trim() !== "")
            return dialogRoot.searchResults
        return getActiveItems()
    }

    function getActiveCategories() {
        if (categorySelectMode)
            return UserIngredientService.categories
        return CategoryService.categories
    }
    function getActiveItems() {
        var cats = getActiveCategories()
        if (activeCategoryIndex >= 0 && activeCategoryIndex < cats.length)
            return cats[activeCategoryIndex].items || []
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
                            cursorShape: Qt.PointingHandCursor
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

        // ====== 分类标签行（可横向滚动）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 22
            Layout.bottomMargin: 12
            spacing: 28
            // 搜索中隐藏分类标签（避免与跨分类搜索结果混淆）
            visible: dialogRoot.searchText.trim() === ""

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
                        model: dialogRoot.getActiveCategories()

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
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dialogRoot.activeCategoryIndex = index
                                    dialogRoot.selectedLabel = ""
                                }
                            }
                        }
                    }

                    // "更多 ▼" 展开项（固定末尾）
                    Item {
                        width: moreCatTxt.implicitWidth + 4
                        height: 36
                        visible: false

                        Text {
                            id: moreCatTxt
                            anchors.centerIn: parent
                            text: "更多 \u25BC"
                            font.pixelSize: 16
                            color: "#999999"
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

                    Text {
                        anchors.centerIn: parent
                        text: modelData.cn
                        font.pixelSize: 32
                        font.family: "Microsoft YaHei"
                        color: dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "#1B263B"
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
        catSearchInput.text = ""
        searchText = ""            // 清空搜索状态
        searchResults = []

        if (categorySelectMode)
            UserIngredientService.fetchIngredients()
        else
            CategoryService.fetchCategories()
    }

    onAccepted: {
        var selItems = getActiveItems()
        for (var i = 0; i < selItems.length; i++) {
            if (selItems[i].en === selectedLabel) {
                var m = selItems[i]
                console.log("[CategoryDialog] \u9009\u4E2D\u98DF\u6750 \u25B6"
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
            // 切换到新食材所在的分类
            var cats = UserIngredientService.categories
            for (var i = 0; i < cats.length; i++) {
                var items = cats[i].items || []
                for (var j = 0; j < items.length; j++) {
                    if (String(items[j].id) === String(ingrId)) {
                        dialogRoot.activeCategoryIndex = i
                        dialogRoot.selectedLabel = items[j].en || ""
                        dialogRoot.selectedIngrId = ingrId
                        return
                    }
                }
            }
        }
    }
}
