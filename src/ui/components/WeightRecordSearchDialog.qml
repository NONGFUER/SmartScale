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
    y: (parent.height - height) / 2  // 居中（键盘悬浮覆盖，不做避让）
    width: Math.min(parent.width * 0.92, 1300)
    height: Math.min(parent.height * 0.88, 900)
    modal: false
    closePolicy: Popup.CloseOnEscape

    // 外部遮罩（reparent 到 window.contentItem，z:40 低于键盘 z:99，避让虚拟键盘）
    Rectangle {
        parent: window.contentItem
        anchors.fill: parent
        color: "#80000000"
        z: 40
        visible: root.visible
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()  // 原 CloseOnPressOutside 语义：点击外部关闭
        }
    }
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
    property string dateStart: ""            // 起始日期 (yyyy-MM-dd)，空=不限
    property string dateEnd: ""               // 结束日期 (yyyy-MM-dd)，空=不限

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

            // 日期范围过滤（取 recordTime 前 10 位 YYYY-MM-DD 比较）
            if (root.dateStart !== "" || root.dateEnd !== "") {
                var rt = (map.recordTime || "").substring(0, 10)
                if (root.dateStart !== "" && rt < root.dateStart)
                    continue
                if (root.dateEnd !== "" && rt > root.dateEnd)
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

            // 返回按钮 — 使用 back2.png + "返回"文字
            Rectangle {
                width: 120; height: 40; radius: 20
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/resources/img/back2.png"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "返回"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: "#4649E5"
                    }
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

            // 关闭按钮 — 使用 close_blue.png 图片图标
            Rectangle {
                width: 60; height: 60; radius: 30
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
                    anchors.centerIn: parent
                    width: parent.width + 32
                    height: parent.height + 32
                    hoverEnabled: true
                    onClicked: root.close()
                }
            }
        }

        // ==========================================
        // 搜索条件行：类别 + 起止日期（日历） + 清除 + 搜索按钮
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 20
            spacing: 16

            // ---- 类别选择 ----
            Rectangle {
                width: 240; height: 56
                radius: 10
                color: "#FFFFFF"
                border.color: catCombo.containsMouse ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    spacing: 0

                    Text {
                        text: root.filterCategory === "" ? "类别: 全部" : "类别: " + root.filterCategory
                        font.family: Theme.fontFamilyUi
                        font.pixelSize: 24
                        color: root.filterCategory === "" ? Theme.colorTextTertiary : Theme.colorTextPrimary
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text { text: "\u25BC"; font.pixelSize: 24; color: Theme.colorTextTertiary }
                }

                MouseArea {
                    id: catCombo
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: categoryPopup.open()
                }
            }

            // ---- 开始日期 ----
            Rectangle {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 56
                radius: 10
                color: "#FFFFFF"
                border.color: startDateBtnMA.containsMouse ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "\u{1F4C5}"
                        font.pixelSize: 24
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.dateStart.length > 0 ? root.dateStart : "开始日期"
                        font.pixelSize: 24
                        font.family: root.dateStart.length > 0 ? Theme.fontFamilyMono : Theme.fontFamilyUi
                        color: root.dateStart.length > 0 ? Theme.colorTextPrimary : Theme.colorTextTertiary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: startDateBtnMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        startCal.initialDate = root.dateStart.length > 0 ? root._parseDate(root.dateStart) : new Date()
                        startCal.open()
                    }
                }
            }

            Text {
                text: "至"
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextSecondary
                Layout.alignment: Qt.AlignVCenter
            }

            // ---- 结束日期 ----
            Rectangle {
                Layout.preferredWidth: 200
                Layout.preferredHeight: 56
                radius: 10
                color: "#FFFFFF"
                border.color: endDateBtnMA.containsMouse ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Text {
                        text: "\u{1F4C5}"
                        font.pixelSize: 24
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.dateEnd.length > 0 ? root.dateEnd : "结束日期"
                        font.pixelSize: 24
                        font.family: root.dateEnd.length > 0 ? Theme.fontFamilyMono : Theme.fontFamilyUi
                        color: root.dateEnd.length > 0 ? Theme.colorTextPrimary : Theme.colorTextTertiary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: endDateBtnMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        endCal.initialDate = root.dateEnd.length > 0 ? root._parseDate(root.dateEnd) : new Date()
                        endCal.open()
                    }
                }
            }

            // ---- 清除日期筛选 ----
            Rectangle {
                Layout.preferredWidth: 96
                Layout.preferredHeight: 56
                radius: 10
                color: clearDateBtnMA.containsMouse ? "#FEE2E2" : "#FFFFFF"
                border.color: "#E2E8F0"
                border.width: 1
                visible: root.dateStart.length > 0 || root.dateEnd.length > 0

                Text {
                    anchors.centerIn: parent
                    text: "清除"
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: clearDateBtnMA.containsMouse ? "#EF4444" : Theme.colorTextSecondary
                }

                MouseArea {
                    id: clearDateBtnMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.dateStart = ""
                        root.dateEnd = ""
                    }
                }
            }

            // ---- 搜索按钮（紧跟筛选条件，无 spacer）----
            Rectangle {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 56
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
                        width: 28; height: 28
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
                                ctx.arc(12, 12, 7.5, 0, Math.PI * 2)
                                ctx.stroke()
                                ctx.beginPath()
                                ctx.moveTo(17, 17)
                                ctx.lineTo(24, 24)
                                ctx.stroke()
                            }
                            Component.onCompleted: requestPaint()
                        }
                    }
                    Text {
                        text: "搜索"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#FFFFFF"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
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
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextTertiary
                }
            }

            GridView {
                visible: root.pageRecords.length > 0
                anchors.fill: parent
                anchors.margins: 20
                cellWidth: (width - 40) / 3   // 3列
                cellHeight: 320               // 卡片高度（容纳 24px 字体 + 大按钮）
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
                font.pixelSize: 24
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextSecondary
            }

            Item { Layout.preferredWidth: 16 }

            // 上一页
            Rectangle {
                width: 48; height: 48; radius: 8
                color: root.currentPage > 1
                       ? (prevPgHover.hovered ? "#F1F5F9" : "#FFFFFF")
                       : "#F1F5F9"
                border.color: "#E2E8F0"
                border.width: 1
                enabled: root.currentPage > 1
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"; font.pixelSize: 24; font.bold: true
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
                    width: pageNumTxt.text === "..." ? 40 : 48
                    height: 48

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
                            font.pixelSize: 24
                            font.family: Theme.fontFamilyUi
                            font.bold: modelData === root.currentPage
                            color: modelData === root.currentPage
                                   ? "#FFFFFF" : Theme.colorTextPrimary
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        font.pixelSize: 24
                        font.family: Theme.fontFamilyUi
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
                width: 48; height: 48; radius: 8
                color: root.currentPage < root.totalPages
                       ? (nextPgHover.hovered ? "#F1F5F9" : "#FFFFFF")
                       : "#F1F5F9"
                border.color: "#E2E8F0"
                border.width: 1
                enabled: root.currentPage < root.totalPages
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u203A"; font.pixelSize: 24; font.bold: true
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
        y: catCombo.parent.mapToItem(root.contentItem, 0, 0).y + 60
        width: 240
        padding: 6
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            radius: 10
            color: "#FFFFFF"
            border.color: "#E2E8F0"
            border.width: 1
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#002A75"
                shadowOpacity: 0.1
                shadowBlur: 1.0
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }

        contentItem: ListView {
            implicitHeight: Math.min(contentHeight, 360)
            model: ["全部"].concat(root.getCategoryList())
            clip: true

            delegate: Rectangle {
                width: categoryPopup.width - 12
                height: 56
                radius: 6
                color: catItemMouse.containsMouse ? "#F0F6FF" : "transparent"

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData
                    font.pixelSize: 24
                    font.family: Theme.fontFamilyUi
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
    // 日期选择日历弹窗（起止日期各一个，复用 CalendarPopup 组件）
    // ================================================================
    CalendarPopup {
        id: startCal
        parent: Overlay.overlay
        onDateSelected: function(d) {
            root.dateStart = root._fmtDate(d)
        }
        onCleared: {
            root.dateStart = ""
        }
    }

    CalendarPopup {
        id: endCal
        parent: Overlay.overlay
        onDateSelected: function(d) {
            root.dateEnd = root._fmtDate(d)
        }
        onCleared: {
            root.dateEnd = ""
        }
    }

    // Date → "YYYY-MM-DD"
    function _fmtDate(d) {
        var pad = function(n) { return n < 10 ? '0' + n : String(n) }
        return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
    }

    // "YYYY-MM-DD" → Date（失败返回当前日期）
    function _parseDate(s) {
        try {
            var d = new Date(s + "T00:00:00")
            if (!isNaN(d.getTime())) return d
        } catch (e) {}
        return new Date()
    }

    // 打开时初始化数据并执行默认过滤
    onOpened: {
        filterCategory = ""
        dateStart = ""
        dateEnd = ""
        currentPage = 1
        doFilter()
        // 把焦点从输入框移走，防止虚拟键盘自动弹出压缩弹窗
        Qt.callLater(function() { backMouse.forceActiveFocus() })
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

            // 图片区域
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 150
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
                    width: recordLabelTxt.implicitWidth + 18
                    height: 36
                    radius: 6
                    color: Qt.rgba(0, 0, 0, 0.55)

                    Text {
                        id: recordLabelTxt
                        anchors.centerIn: parent
                        text: "记录图像"
                        font.pixelSize: 24
                        font.family: Theme.fontFamilyUi
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
                              //+ (cardRoot.record.operatorName ? "  人员: " + cardRoot.record.operatorName : "")
                        font.pixelSize: 24
                        font.family: Theme.fontFamilyMono
                        color: Theme.colorTextTertiary
                        elide: Text.ElideRight
                    }

                    // 食材名称 + 重量（核心信息加粗）
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                            text: cardRoot.record.categoryName || "未知食材"
                            font.pixelSize: 24
                            font.family: Theme.fontFamilyUi
                            font.bold: true
                            color: Theme.colorTextPrimary
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: (cardRoot.record.weight || 0).toFixed(2) + " kg"
                            font.pixelSize: 24
                            font.family: Theme.fontFamilyUi
                            font.bold: true
                            color: "#2563EB"
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // 按钮行：撤回 + 查看
                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 10

                        // 撤回按钮（红色边框，危险操作）
                        Rectangle {
                            Layout.preferredWidth: 96
                            Layout.preferredHeight: 50
                            radius: 8
                            color: revokeHover.hovered ? "#FEF2F2" : "#F8FAFC"
                            border.color: revokeHover.hovered ? "#FCA5A5" : "#FECACA"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "撤回"
                                font.pixelSize: 24
                                font.family: Theme.fontFamilyUi
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
                            Layout.preferredWidth: 120
                            Layout.preferredHeight: 50
                            radius: 8
                            color: viewBtnHover.hovered ? "#EFF6FF" : "#F8FAFC"
                            border.color: "#BFDBFE"
                            border.width: 1

                            Text {
                                anchors.centerIn: parent
                                text: "查看"
                                font.pixelSize: 24
                                font.family: Theme.fontFamilyUi
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
