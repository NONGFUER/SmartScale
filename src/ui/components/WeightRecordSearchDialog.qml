import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

// ============================================================
// WeightRecordSearchDialog — 称重记录查询弹窗
//
// 功能：
//   - 按食材类别 / 时间段 / 操作人员 筛选称重记录
//   - 卡片网格展示搜索结果（图片 + 名称/重量/时间）
//   - 分页浏览
//   - 点击"查看"打开记录详情大图
//
// 用法：
//   WeightRecordSearchDialog { id: searchDialog }
//   searchDialog.open()
//
// 数据源：
//   WeightHistoryService.historyEntries (QVariantList)
//   每条记录字段: id, weight, categoryName, operatorName,
//                recordTime, mainImagePath, hasMainImage, ...
// ============================================================
Dialog {
    id: root

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width * 0.92, 1300)
    height: Math.min(parent.height * 0.88, 900)
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    title: ""
    padding: 0

    // ---- 对外信号 ----
    signal viewRecord(var record)

    // ---- 撤回记录（软删除 + 云端 API）----
    function revokeRecord(rec) {
        if (!rec) return
        var localId = rec.id || -1
        var custId = BackendAuth.custId || 0
        var cloudId = rec.cloudId || ""
        console.log("[SearchDialog] 撤回记录: localId=" + localId, "custId=" + custId, "cloudId=" + cloudId)
        WeightHistoryService.revokeRecord(localId, custId, cloudId)
        // 立即从当前页移除该记录（乐观更新）
        var newList = []
        for (var i = 0; i < root.filteredRecords.length; i++) {
            if (root.filteredRecords[i].id !== localId) {
                newList.push(root.filteredRecords[i])
            }
        }
        root.filteredRecords = newList
        // 如果当前页变空且不是第一页，回退一页
        if (root.pageRecords.length === 0 && root.currentPage > 1) {
            root.currentPage--
        }
    }

    background: Rectangle {
        radius: 24
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 25
            shadowOpacity: 0.18
            shadowVerticalOffset: 8
        }
    }

    // ---- 搜索条件 ----
    property string filterCategory: ""      // 食材类别筛选
    property string filterDate: ""           // 日期筛选 (yyyy-MM-dd)
    property string filterOperator: ""       // 人员筛选

    // ---- 分页状态 ----
    property int currentPage: 1
    property int pageSize: 6                 // 每页显示卡片数 (3列 x 2行)
    property int totalPages: Math.ceil(filteredRecords.length / root.pageSize)

    // ---- 过滤后的记录列表 ----
    property var filteredRecords: []

    // ---- 当前页的记录 ----
    property var pageRecords: {
        var start = (root.currentPage - 1) * root.pageSize
        var end = Math.min(start + root.pageSize, root.filteredRecords.length)
        var result = []
        for (var i = start; i < end; i++) {
            result.push(root.filteredRecords[i])
        }
        return result
    }

    // 执行过滤
    function doFilter() {
        var all = WeightHistoryService.historyEntries || []
        var results = []

        for (var i = 0; i < all.length; i++) {
            var r = all[i]
            var map = (typeof r === "object" && !r.toString) ? r : r

            // 类别过滤
            if (root.filterCategory && root.filterCategory !== "") {
                var cat = map.categoryName || ""
                if (cat.indexOf(root.filterCategory) < 0)
                    continue
            }

            // 日期过滤
            if (root.filterDate && root.filterDate !== "") {
                var rt = map.recordTime || ""
                if (rt.indexOf(root.filterDate) < 0)
                    continue
            }

            // 人员过滤
            if (root.filterOperator && root.filterOperator !== "") {
                var op = map.operatorName || ""
                if (op.indexOf(root.filterOperator) < 0)
                    continue
            }

            results.push(map)
        }

        root.filteredRecords = results
        root.currentPage = 1  // 重置到第一页
        console.log("[WeightRecordSearchDialog] 过滤结果:", results.length, "条")
    }

    // 获取所有不重复的类别列表
    function getCategoryList() {
        var all = WeightHistoryService.historyEntries || []
        var cats = {}
        for (var i = 0; i < all.length; i++) {
            var cat = (all[i].categoryName || "").trim()
            if (cat) cats[cat] = true
        }
        return Object.keys(cats).sort()
    }

    // 获取所有不重复的操作员列表
    function getOperatorList() {
        var all = WeightHistoryService.historyEntries || []
        var ops = {}
        for (var i = 0; i < all.length; i++) {
            var op = (all[i].operatorName || "").trim()
            if (op) ops[op] = true
        }
        return Object.keys(ops).sort()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // 标题栏：返回箭头 + 称重记录查询 + 关闭
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 28
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 20
            spacing: 0

            // 返回按钮 — 使用 back.png（图标自含蓝色，故去掉浅蓝圆底，改透明 + 浅灰悬浮）
            Rectangle {
                width: 46; height: 46; radius: 23
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
                    onClicked: root.close()
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                text: "称重记录查询"
                font.family: Theme.fontFamilyTitle
                font.pixelSize: 26
                font.bold: true
                color: Theme.colorTextPrimary
            }

            Item { Layout.fillWidth: true }

            // 关闭按钮
            Rectangle {
                width: 42; height: 42; radius: 21
                color: closeMouse.containsMouse ? "#FEE2E2" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    font.pixelSize: 20
                    color: closeMouse.containsMouse ? "#EF4444" : "#94A3B8"
                }
                MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.close()
                }
            }
        }

        // ==========================================
        // 搜索条件行
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 20
            spacing: 20

            // 类别选择
            ColumnLayout {
                spacing: 6
                Text {
                    text: "类别:"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 15
                    color: Theme.colorTextSecondary
                }
                Rectangle {
                    width: 180; height: 44
                    radius: 8
                    color: "#FFFFFF"
                    border.color: catCombo.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 0

                        Text {
                            text: root.filterCategory === "" ? "全部" : root.filterCategory
                            font.pixelSize: 15
                            color: root.filterCategory === "" ? Theme.colorTextTertiary : Theme.colorTextPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text { text: "\u25BC"; font.pixelSize: 13; color: Theme.colorTextTertiary }
                    }

                    MouseArea {
                        id: catCombo
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: categoryPopup.open()
                    }
                }
            }

            // 时间选择
            ColumnLayout {
                spacing: 6
                Text {
                    text: "时间:"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 15
                    color: Theme.colorTextSecondary
                }
                Rectangle {
                    width: 190; height: 44
                    radius: 8
                    color: "#FFFFFF"
                    border.color: dateCombo.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 0

                        Text {
                            text: root.filterDate === "" ? "全部" : root.filterDate
                            font.pixelSize: 15
                            color: root.filterDate === "" ? Theme.colorTextTertiary : Theme.colorTextPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text { text: "\u25BC"; font.pixelSize: 13; color: Theme.colorTextTertiary }
                    }

                    MouseArea {
                        id: dateCombo
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: datePopup.open()
                    }
                }
            }

            // 人员选择
            ColumnLayout {
                spacing: 6
                Text {
                    text: "人员:"
                    font.family: Theme.fontFamilyUi
                    font.pixelSize: 15
                    color: Theme.colorTextSecondary
                }
                Rectangle {
                    width: 160; height: 44
                    radius: 8
                    color: "#FFFFFF"
                    border.color: opCombo.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 0

                        Text {
                            text: root.filterOperator === "" ? "全部" : root.filterOperator
                            font.pixelSize: 15
                            color: root.filterOperator === "" ? Theme.colorTextTertiary : Theme.colorTextPrimary
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text { text: "\u25BC"; font.pixelSize: 13; color: Theme.colorTextTertiary }
                    }

                    MouseArea {
                        id: opCombo
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: operatorPopup.open()
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // 搜索按钮
            Rectangle {
                Layout.preferredWidth: 120
                Layout.preferredHeight: 44
                radius: 10
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#3B82F6" }
                    GradientStop { position: 1.0; color: "#1D4ED8" }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Item {
                        width: 22; height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = "#FFFFFF"
                                ctx.lineWidth = 2.5
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.arc(9, 9, 6.5, 0, Math.PI * 2)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(14, 14)
                                ctx.lineTo(20, 20)
                                ctx.stroke()
                            }
                            Component.onCompleted: requestPaint()
                        }
                    }
                    Text {
                        text: "搜索"
                        font.pixelSize: 16
                        font.bold: true
                        color: "#FFFFFF"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.doFilter()
                }
            }
        }

        // ==========================================
        // 结果区域（卡片网格）
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 16
            color: "#F8FAFC"
            radius: 14
            border.color: "#E2E8F0"
            border.width: 1
            clip: true

            // 无结果提示
            Column {
                anchors.centerIn: parent
                visible: root.pageRecords.length === 0
                spacing: 14
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u{1F50D}"
                    font.pixelSize: 48
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "暂无符合条件的称重记录"
                    font.pixelSize: 17
                    color: Theme.colorTextTertiary
                }
            }

            GridView {
                visible: root.pageRecords.length > 0
                anchors.fill: parent
                anchors.margins: 20
                cellWidth: (width - 40) / 3   // 3列
                cellHeight: 280               // 卡片高度增大
                clip: true

                model: root.pageRecords

                delegate: RecordCard {
                    width: GridView.view.cellWidth - 16
                    height: GridView.view.cellHeight - 14
                    record: modelData
                    onViewClicked: function(rec) { root.viewRecord(rec) }
                    onRevokeClicked: function(rec) { root.revokeRecord(rec) }
                }
            }
        }

        // ==========================================
        // 底部分页栏
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: 22
            Layout.topMargin: 10
            spacing: 14

            Text {
                text: "共 " + root.filteredRecords.length + " 条"
                font.pixelSize: 14
                color: Theme.colorTextSecondary
            }

            Item { Layout.preferredWidth: 16 }

            // 上一页
            Rectangle {
                width: 40; height: 40; radius: 8
                color: root.currentPage > 1
                       ? (prevPgHover.hovered ? "#F1F5F9" : "#FFFFFF")
                       : "#F1F5F9"
                border.color: "#E2E8F0"
                border.width: 1
                enabled: root.currentPage > 1
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"; font.pixelSize: 20; font.bold: true
                    color: enabled ? Theme.colorTextPrimary : Theme.colorTextTertiary
                }
                HoverHandler { id: prevPgHover }
                TapHandler {
                    enabled: root.currentPage > 1
                    onTapped: if (root.currentPage > 1) root.currentPage--
                }
            }

            // 页码列表（最多显示5个页码）
            Repeater {
                model: {
                    var pages = []
                    var tp = root.totalPages
                    var cp = root.currentPage
                    if (tp <= 5) {
                        for (var i = 1; i <= tp; i++) pages.push(i)
                    } else if (cp <= 3) {
                        pages = [1, 2, 3, 4, "...", tp]
                    } else if (cp >= tp - 2) {
                        pages = [1, "...", tp - 3, tp - 2, tp - 1, tp]
                    } else {
                        pages = [1, "...", cp - 1, cp, cp + 1, "...", tp]
                    }
                    return pages
                }

                Item {
                    width: pageNumTxt.text === "..." ? 32 : 40
                    height: 40

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        visible: modelData !== "..."
                        color: modelData === root.currentPage
                               ? "#3B82F6"
                               : (pgNumHover.hovered ? "#F1F5F9" : "#FFFFFF")
                        border.color: modelData === root.currentPage
                                      ? "#3B82F6" : "#E2E8F0"
                        border.width: 1

                        Text {
                            id: pageNumTxt
                            anchors.centerIn: parent
                            text: String(modelData)
                            font.pixelSize: 15
                            font.bold: modelData === root.currentPage
                            color: modelData === root.currentPage
                                   ? "#FFFFFF" : Theme.colorTextPrimary
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        font.pixelSize: 15
                        color: Theme.colorTextTertiary
                        visible: modelData === "..."
                    }

                    HoverHandler { id: pgNumHover; enabled: modelData !== "..." }
                    TapHandler {
                        enabled: typeof modelData === "number"
                        onTapped: if (typeof modelData === "number") root.currentPage = modelData
                    }
                }
            }

            // 下一页
            Rectangle {
                width: 40; height: 40; radius: 8
                color: root.currentPage < root.totalPages
                       ? (nextPgHover.hovered ? "#F1F5F9" : "#FFFFFF")
                       : "#F1F5F9"
                border.color: "#E2E8F0"
                border.width: 1
                enabled: root.currentPage < root.totalPages
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u203A"; font.pixelSize: 20; font.bold: true
                    color: enabled ? Theme.colorTextPrimary : Theme.colorTextTertiary
                }
                HoverHandler { id: nextPgHover }
                TapHandler {
                    enabled: root.currentPage < root.totalPages
                    onTapped: if (root.currentPage < root.totalPages) root.currentPage++
                }
            }
        }
    }

    // ================================================================
    // 下拉弹出框 — 类别选择
    // ================================================================
    Popup {
        id: categoryPopup
        x: catCombo.parent.mapToItem(root.contentItem, 0, 0).x
        y: catCombo.parent.mapToItem(root.contentItem, 0, 0).y + 48
        width: 180
        padding: 6
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#FFFFFF"
            border.color: "#E2E8F0"
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 12
                shadowOpacity: 0.15
                shadowVerticalOffset: 4
            }
        }

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 280)
            model: ["全部"].concat(root.getCategoryList())
            clip: true

            delegate: Rectangle {
                width: categoryPopup.width - 12
                height: 42
                radius: 4
                color: catItemMouse.containsMouse ? "#F0F6FF" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    font.pixelSize: 15
                    color: root.filterCategory === modelData
                           || (modelData === "全部" && root.filterCategory === "")
                           ? Theme.colorAccent : Theme.colorTextPrimary
                }

                MouseArea {
                    id: catItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.filterCategory = modelData === "全部" ? "" : modelData
                        categoryPopup.close()
                    }
                }
            }
        }
    }

    // ================================================================
    // 下拉弹出框 — 日期选择
    // ================================================================
    Popup {
        id: datePopup
        x: dateCombo.parent.mapToItem(root.contentItem, 0, 0).x
        y: dateCombo.parent.mapToItem(root.contentItem, 0, 0).y + 48
        width: 220
        padding: 6
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#FFFFFF"
            border.color: "#E2E8F0"
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 12
                shadowOpacity: 0.15
                shadowVerticalOffset: 4
            }
        }

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 300)
            model: root._buildDateModel()
            clip: true

            delegate: Rectangle {
                width: datePopup.width - 12
                height: 42
                radius: 4
                color: dateItemMouse.containsHover ? "#F0F6FF" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    font.pixelSize: 15
                    color: root.filterDate === modelData.value
                           || (modelData.value === "" && root.filterDate === "")
                           ? Theme.colorAccent : Theme.colorTextPrimary
                }

                HoverHandler { id: dateItemMouse }
                TapHandler {
                    onTapped: {
                        root.filterDate = modelData.value
                        datePopup.close()
                    }
                }
            }
        }
    }

    // 构建日期模型：今天、昨天、近7天、自定义日期选项
    function _buildDateModel() {
        var today = new Date()
        var fmt = function(d) {
            return d.getFullYear() + "-"
                   + String(d.getMonth() + 1).padStart(2, '0') + "-"
                   + String(d.getDate()).padStart(2, '0')
        }
        var yesterday = new Date(today)
        yesterday.setDate(yesterday.getDate() - 1)

        return [
            { label: "全部", value: "" },
            { label: "今天 (" + fmt(today) + ")", value: fmt(today) },
            { label: "昨天 (" + fmt(yesterday) + ")", value: fmt(yesterday) },
            { label: "近7天", value: "_recent7" },
            { label: "近30天", value: "_recent30" }
        ]
    }

    // ================================================================
    // 下拉弹出框 — 人员选择
    // ================================================================
    Popup {
        id: operatorPopup
        x: opCombo.parent.mapToItem(root.contentItem, 0, 0).x
        y: opCombo.parent.mapToItem(root.contentItem, 0, 0).y + 48
        width: 160
        padding: 6
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 8
            color: "#FFFFFF"
            border.color: "#E2E8F0"
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#000000"
                shadowBlur: 12
                shadowOpacity: 0.15
                shadowVerticalOffset: 4
            }
        }

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 240)
            model: ["全部"].concat(root.getOperatorList())
            clip: true

            delegate: Rectangle {
                width: operatorPopup.width - 12
                height: 42
                radius: 4
                color: opItemMouse.containsMouse ? "#F0F6FF" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    font.pixelSize: 15
                    color: root.filterOperator === modelData
                           || (modelData === "全部" && root.filterOperator === "")
                           ? Theme.colorAccent : Theme.colorTextPrimary
                }

                MouseArea {
                    id: opItemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.filterOperator = modelData === "全部" ? "" : modelData
                        operatorPopup.close()
                    }
                }
            }
        }
    }

    // 打开时初始化数据并执行默认过滤
    onOpened: {
        filterCategory = ""
        filterDate = ""
        filterOperator = ""
        currentPage = 1
        doFilter()
    }

    // ==========================================
    // 内联组件 — 记录卡片
    // ==========================================
    component RecordCard: Rectangle {
        property var record: ({})
        signal viewClicked(var rec)
        signal revokeClicked(var rec)

        id: cardRoot
        radius: 12
        color: "#FFFFFF"
        border.color: cardHover.hovered ? "#93C5FD" : "#E2E8F0"
        border.width: 1
        Behavior on border.color { ColorAnimation { duration: 150 } }

        // hover 上浮效果
        transform: Translate {
            y: cardHover.hovered ? -3 : 0
            Behavior on y { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8

            // 图片区域（高度增大）
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 155
                radius: 10
                color: "#F1F5F9"
                clip: true

                // 无图占位（z=0 底层）
                Text {
                    id: placeholderIcon
                    anchors.centerIn: parent
                    z: 0
                    text: "\u{1F4CF}"
                    font.pixelSize: 36
                    color: "#CBD5E1"
                    visible: {
                        var src = img.source
                        if (!src || src === "") return true
                        var s = img.status
                        return s === Image.Null || s === Image.Error
                    }
                }

                Image {
                    id: img
                    anchors.fill: parent
                    anchors.margins: 4
                    z: 1
                    fillMode: Image.PreserveAspectCrop
                    source: (cardRoot.record.hasMainImage && cardRoot.record.mainImagePath)
                            ? (cardRoot.record.mainImagePath.startsWith("file://")
                               ? cardRoot.record.mainImagePath
                               : "file://" + cardRoot.record.mainImagePath)
                            : ""
                    visible: source !== ""

                    onStatusChanged: {
                        if (status === Image.Error)
                            console.warn("[RecordCard] 图片加载失败:", source)
                    }
                }

                // "记录图像"标签浮在图片左上角
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 8
                    width: recordLabelTxt.implicitWidth + 14
                    height: 26
                    radius: 5
                    color: Qt.rgba(0, 0, 0, 0.55)

                    Text {
                        id: recordLabelTxt
                        anchors.centerIn: parent
                        text: "记录图像"
                        font.pixelSize: 13
                        color: "#FFFFFF"
                    }
                }
            }

            // 文字信息区
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 4

                    // 日期时间 + 人员
                    Text {
                        Layout.fillWidth: true
                        text: _formatDateTime(cardRoot.record.recordTime)
                              + (cardRoot.record.operatorName ? "  人员: " + cardRoot.record.operatorName : "")
                        font.pixelSize: 13
                        font.family: Theme.fontFamilyMono
                        color: Theme.colorTextTertiary
                        elide: Text.ElideRight
                    }

                    // 食材名称 + 重量（核心信息加粗放大）
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: cardRoot.record.categoryName || "未知食材"
                            font.pixelSize: 17
                            font.bold: true
                            color: Theme.colorTextPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: (cardRoot.record.weight || 0).toFixed(1) + " kg"
                            font.pixelSize: 17
                            font.bold: true
                            color: "#2563EB"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // 按钮行：撤回 + 查看
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8

                        // 撤回按钮（红色边框，危险操作）
                        Rectangle {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 32
                            radius: 8
                            color: revokeHover.hovered ? "#FEF2F2" : "#F8FAFC"
                            border.color: revokeHover.hovered ? "#FCA5A5" : "#FECACA"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "撤回"
                                font.pixelSize: 14
                                font.bold: true
                                color: "#DC2626"
                            }

                            HoverHandler { id: revokeHover }
                            TapHandler {
                                onTapped: cardRoot.revokeClicked(cardRoot.record)
                            }
                        }

                        // 查看按钮
                        Rectangle {
                            Layout.preferredWidth: 72
                            Layout.preferredHeight: 32
                            radius: 8
                            color: viewBtnHover.hovered ? "#EFF6FF" : "#F8FAFC"
                            border.color: "#BFDBFE"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "查看"
                                font.pixelSize: 15
                                color: "#3B82F6"
                            }

                            HoverHandler { id: viewBtnHover }
                            TapHandler {
                                onTapped: cardRoot.onViewClicked(cardRoot.record)
                            }
                        }
                    }
                }
            }
        }

        HoverHandler { id: cardHover }

        // 格式化日期时间
        function _formatDateTime(isoStr) {
            if (!isoStr || isoStr.length === 0) return "\u2014\u2014-\u2014\u2014 \u2014\u2014:\u2014\u2014:\u2014\u2014"
            try {
                var d = new Date(isoStr.replace(' ', 'T'))
                if (isNaN(d.getTime())) return isoStr
                var pad = function(n) { return n < 10 ? '0' + n : String(n) }
                return d.getFullYear() + '-'
                       + pad(d.getMonth()+1) + '-' + pad(d.getDate()) + ' '
                       + pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':'
                       + pad(d.getSeconds())
            } catch(e) {
                return isoStr
            }
        }
    }
}
