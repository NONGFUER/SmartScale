import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale

// ============================================================
// WeightRecordTableDialog — 称重记录表格弹窗
//
// 功能：
//   - 以表格形式展示云端分页称重记录
//   - 服务端分页（每页 10 条），底部页码导航
//   - 关键字搜索（按食材名称过滤）
//   - 列：序号 | 食材 | 重量(kg) | 单价(元/kg) | 金额(元) | 时间 | 图片
//   - 点击图片列可查看大图
//
// 用法：
//   WeightRecordTableDialog { id: tableDialog }
//   tableDialog.open()
//
// 数据源：
//   WeightHistoryService.fetchPagedRecords() → pagedRecordsReady 信号
//   接口：POST /api/user/WeightRecord/paged
// ============================================================
Dialog {
    id: root

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: Math.min(parent.width * 0.96, 1340)
    height: Math.min(parent.height * 0.92, 940)
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    title: ""
    padding: 0

    // ---- 状态 ----
    property int currentPage: 1
    property int pageSize: 10
    property int totalRecords: 0
    property int totalPages: Math.max(1, Math.ceil(totalRecords / pageSize))
    property var tableItems: []
    property bool loading: false
    property string lastKeyword: ""
    property string dateStart: ""   // 起始日期 YYYY-MM-DD（空=不限）
    property string dateEnd: ""     // 结束日期 YYYY-MM-DD（空=不限）

    // ---- 列宽定义（固定像素，表格区域宽度须匹配）----
    readonly property real colIndex: 90
    readonly property real colIngr: 260
    readonly property real colWeight: 160
    readonly property real colPrice: 200
    readonly property real colAmount: 160
    readonly property real colTime: 260
    readonly property real colImg: 130
    readonly property real tableContentWidth: colIndex + colIngr + colWeight + colPrice + colAmount + colTime + colImg

    // 表格行高（字号 24px，需更宽更高）
    readonly property real rowHeight: 64
    readonly property real headerHeight: 64
    readonly property color gridLineColor: "#CBD5E1"

    background: Rectangle {
        radius: 24
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

    // ---- 监听分页查询结果 ----
    Connections {
        target: WeightHistoryService
        function onPagedRecordsReady(success, total, items, errorMsg) {
            root.loading = false
            if (success) {
                root.totalRecords = total
                root.tableItems = items
            } else {
                root.tableItems = []
                root.totalRecords = 0
                console.warn("[TableDialog] 查询失败:", errorMsg)
            }
        }
    }

    // ---- 发起查询 ----
    function doSearch() {
        root.loading = true
        root.currentPage = 1
        root.lastKeyword = searchInput.text.trim()
        _fetch()
    }

    function _fetch() {
        // 日期范围：优先用用户选择，否则默认近 365 天
        var now = new Date()
        var past = new Date(now)
        past.setDate(past.getDate() - 365)
        var fmt = function(d) {
            return d.getFullYear() + "-"
                   + String(d.getMonth() + 1).padStart(2, '0') + "-"
                   + String(d.getDate()).padStart(2, '0')
                   + "T" + String(d.getHours()).padStart(2, '0') + ":"
                   + String(d.getMinutes()).padStart(2, '0') + ":"
                   + String(d.getSeconds()).padStart(2, '0') + ".000Z"
        }
        var dateS = root.dateStart, dateE = root.dateEnd
        var re = /^\d{4}-\d{2}-\d{2}$/
        dateS = re.test(dateS) ? dateS + "T00:00:00.000Z" : fmt(past)
        dateE = re.test(dateE) ? dateE + "T23:59:59.000Z" : fmt(now)
        WeightHistoryService.fetchPagedRecords(
            root.currentPage, root.pageSize,
            root.lastKeyword, dateS, dateE)
    }

    function goToPage(page) {
        if (page < 1 || page > root.totalPages || page === root.currentPage)
            return
        root.currentPage = page
        root.loading = true
        _fetch()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // 标题栏：返回 + 称重记录表格 + 关闭
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 28
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 20
            spacing: 0

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
                text: "称重记录表格"
                font.family: Theme.fontFamilyTitle
                font.pixelSize: 28
                font.bold: true
                color: Theme.colorTextPrimary
            }

            Item { Layout.fillWidth: true }

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
                    onClicked: root.close()
                }
            }
        }

        // ==========================================
        // 搜索栏
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 16
            spacing: 12

            // ---- 日期范围选择（日历弹窗）----
            Text {
                text: "起止"
                font.pixelSize: 18
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextSecondary
                Layout.alignment: Qt.AlignVCenter
            }

            // 起始日期按钮
            Rectangle {
                Layout.preferredWidth: 180
                Layout.preferredHeight: 48
                radius: 10
                color: "#FFFFFF"
                border.color: startDateBtnMA.containsMouse ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "\u{1F4C5}"
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.dateStart.length > 0 ? root.dateStart : "开始日期"
                        font.pixelSize: 18
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
                font.pixelSize: 18
                color: Theme.colorTextSecondary
                Layout.alignment: Qt.AlignVCenter
            }

            // 结束日期按钮
            Rectangle {
                Layout.preferredWidth: 180
                Layout.preferredHeight: 48
                radius: 10
                color: "#FFFFFF"
                border.color: endDateBtnMA.containsMouse ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                Row {
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        text: "\u{1F4C5}"
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: root.dateEnd.length > 0 ? root.dateEnd : "结束日期"
                        font.pixelSize: 18
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

            // 清除日期筛选
            Rectangle {
                Layout.preferredWidth: 72
                Layout.preferredHeight: 48
                radius: 10
                color: clearDateBtnMA.containsMouse ? "#FEE2E2" : "#FFFFFF"
                border.color: "#E2E8F0"
                border.width: 1
                visible: root.dateStart.length > 0 || root.dateEnd.length > 0

                Text {
                    anchors.centerIn: parent
                    text: "清除"
                    font.pixelSize: 18
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
                        root.doSearch()
                    }
                }
            }

            // ---- 关键字搜索框 ----
            Rectangle {
                Layout.preferredWidth: 340
                Layout.preferredHeight: 48
                radius: 10
                color: "#FFFFFF"
                border.color: searchInput.activeFocus ? Theme.colorAccent : Theme.colorInputBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 10
                    spacing: 8

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        focus: false          // 禁止打开弹窗时自动聚焦（避免虚拟键盘弹出压缩弹窗）
                        placeholderText: "搜索食材名称..."
                        placeholderTextColor: Theme.colorTextTertiary
                        font.pixelSize: 24
                        font.family: Theme.fontFamilyUi
                        color: Theme.colorTextPrimary
                        selectByMouse: true
                        verticalAlignment: TextField.AlignVCenter
                        background: Item {}

                        onAccepted: root.doSearch()
                        onEditingFinished: {}
                    }

                    // 清除关键字按钮
                    Rectangle {
                        visible: searchInput.text.length > 0
                        width: 24; height: 24; radius: 12
                        color: clearKwMouse.containsMouse ? "#E2E8F0" : "#F1F5F9"
                        Text {
                            anchors.centerIn: parent
                            text: "\u2715"
                            font.pixelSize: 13
                            color: Theme.colorTextTertiary
                        }
                        MouseArea {
                            id: clearKwMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                searchInput.text = ""
                                if (root.lastKeyword !== "") root.doSearch()
                            }
                        }
                    }
                }
            }

            // 搜索按钮（紧跟输入框）
            Rectangle {
                Layout.preferredWidth: 130
                Layout.preferredHeight: 48
                radius: 10
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: "#3B82F6" }
                    GradientStop { position: 1.0; color: "#1D4ED8" }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "\u{1F50D}"
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
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
                    onClicked: root.doSearch()
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ==========================================
        // 表格区域
        // ==========================================
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 16
            color: "#FFFFFF"
            radius: 14
            border.color: root.gridLineColor
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // ---- 表头 ----
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.headerHeight
                    color: "#F1F5F9"

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        TableHeaderCell { w: root.colIndex; t: "序号" }
                        TableHeaderCell { w: root.colIngr;  t: "食材" }
                        TableHeaderCell { w: root.colWeight; t: "重量(kg)" }
                        TableHeaderCell { w: root.colPrice;  t: "单价(元/kg)" }
                        TableHeaderCell { w: root.colAmount; t: "金额(元)" }
                        TableHeaderCell { w: root.colTime;   t: "时间" }
                        TableHeaderCell { w: root.colImg;    t: "图片"; showRightBorder: false }
                    }

                    // 底部分隔线（表头与表体之间，颜色加深）
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: 1
                        color: root.gridLineColor
                    }
                }

                // ---- 表体 ----
                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AsNeeded
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    ListView {
                        id: tableList
                        width: Math.max(parent.width, root.tableContentWidth)
                        model: root.tableItems
                        spacing: 0
                        clip: true

                        delegate: Rectangle {
                            width: tableList.width
                            height: root.rowHeight
                            color: "#FFFFFF"  // 无斑马纹，统一背景

                            // 底部行分隔线（鲜明）
                            Rectangle {
                                anchors.bottom: parent.bottom
                                width: parent.width
                                height: 1
                                color: root.gridLineColor
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 0

                                // 序号
                                TableCell { w: root.colIndex; t: String(index + 1 + (root.currentPage - 1) * root.pageSize); muted: true }
                                // 食材名称
                                TableCell { w: root.colIngr; t: modelData.ingrNm || "—"; bold: true }
                                // 重量
                                TableCell { w: root.colWeight; t: modelData.val || "0"; useAccent: true; accent: "#2563EB"; bold: true }
                                // 单价（保留两位小数）
                                TableCell { w: root.colPrice; t: _fmtPrice(modelData.price) }
                                // 金额
                                TableCell { w: root.colAmount; t: _fmtPrice(modelData.amount); bold: true; useAccent: true; accent: "#16A34A" }
                                // 时间（日期 + 时间换行显示）
                                Item {
                                    width: root.colTime
                                    height: root.rowHeight

                                    Rectangle {
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: 1
                                        color: root.gridLineColor
                                    }

                                    Column {
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: _fmtTime(modelData.crdAt).date
                                            font.pixelSize: 24
                                            font.family: Theme.fontFamilyMono
                                            color: Theme.colorTextPrimary
                                        }
                                        Text {
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            text: _fmtTime(modelData.crdAt).time
                                            font.pixelSize: 20
                                            font.family: Theme.fontFamilyMono
                                            color: Theme.colorTextTertiary
                                            visible: text.length > 0
                                        }
                                    }
                                }
                                // 图片（可点击查看大图）
                                ImageCell {
                                    w: root.colImg
                                    imgUrl: modelData.img || ""
                                    showRightBorder: false
                                    onOpenPreview: _openImageBrowser(imgUrl, modelData.crdAt)
                                }
                            }
                        }

                        // 空状态
                        Column {
                            anchors.centerIn: parent
                            visible: root.tableItems.length === 0 && !root.loading
                            spacing: 14

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "\u{1F4CB}"
                                font.pixelSize: 48
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "暂无称重记录"
                                font.pixelSize: 20
                                color: Theme.colorTextTertiary
                            }
                        }
                    }
                }
            }

            // ---- Loading 覆盖层（覆盖整个表格区域，与 ColumnLayout 同级）----
            Rectangle {
                anchors.fill: parent
                visible: root.loading
                color: Qt.rgba(1, 1, 1, 0.85)
                radius: 14

                Column {
                    anchors.centerIn: parent
                    spacing: 16

                    BusyIndicator {
                        anchors.horizontalCenter: parent.horizontalCenter
                        running: true
                        width: 48; height: 48
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "加载中..."
                        font.pixelSize: 18
                        color: Theme.colorTextSecondary
                    }
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
                text: "共 " + root.totalRecords + " 条"
                font.pixelSize: 24
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
                enabled: root.currentPage > 1 && !root.loading
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"; font.pixelSize: 24; font.bold: true
                    color: enabled ? Theme.colorTextPrimary : Theme.colorTextTertiary
                }
                HoverHandler { id: prevPgHover }
                TapHandler {
                    enabled: root.currentPage > 1 && !root.loading
                    onTapped: root.goToPage(root.currentPage - 1)
                }
            }

            // 页码列表
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
                            font.pixelSize: 24
                            font.bold: modelData === root.currentPage
                            color: modelData === root.currentPage
                                   ? "#FFFFFF" : Theme.colorTextPrimary
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        font.pixelSize: 24
                        color: Theme.colorTextTertiary
                        visible: modelData === "..."
                    }

                    HoverHandler { id: pgNumHover; enabled: modelData !== "..." }
                    TapHandler {
                        enabled: typeof modelData === "number" && !root.loading
                        onTapped: if (typeof modelData === "number") root.goToPage(modelData)
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
                enabled: root.currentPage < root.totalPages && !root.loading
                opacity: enabled ? 1.0 : 0.45

                Text {
                    anchors.centerIn: parent
                    text: "\u203A"; font.pixelSize: 24; font.bold: true
                    color: enabled ? Theme.colorTextPrimary : Theme.colorTextTertiary
                }
                HoverHandler { id: nextPgHover }
                TapHandler {
                    enabled: root.currentPage < root.totalPages && !root.loading
                    onTapped: root.goToPage(root.currentPage + 1)
                }
            }
        }
    }

    // ==========================================
    // 图片浏览弹窗（复用 RecordDetailDialog）
    // ==========================================
    RecordDetailDialog {
        id: imageBrowser
        parent: Overlay.overlay
        onNavigateToRecord: function(newIndex) {
            if (imageBrowser.recordList && newIndex >= 0
                    && newIndex < imageBrowser.recordList.length)
                imageBrowser.record = imageBrowser.recordList[newIndex]
        }
    }

    // 构造图片浏览记录列表（仅当前页有图记录）并打开图片浏览弹窗
    function _openImageBrowser(imgUrl, crdAt) {
        var list = []
        for (var i = 0; i < root.tableItems.length; i++) {
            var it = root.tableItems[i]
            if (it.img && String(it.img).length > 0)
                list.push({ mainImagePath: it.img, recordTime: it.crdAt })
        }
        if (list.length === 0) return
        imageBrowser.recordList = list
        imageBrowser.record = ({ mainImagePath: imgUrl, recordTime: crdAt })
        imageBrowser.open()
    }

    // ==========================================
    // 日期选择日历弹窗（起止日期各一个）
    // ==========================================
    CalendarPopup {
        id: startCal
        parent: Overlay.overlay
        onDateSelected: function(d) {
            root.dateStart = root._fmtDate(d)
            root.doSearch()
        }
        onCleared: {
            root.dateStart = ""
            root.doSearch()
        }
    }

    CalendarPopup {
        id: endCal
        parent: Overlay.overlay
        onDateSelected: function(d) {
            root.dateEnd = root._fmtDate(d)
            root.doSearch()
        }
        onCleared: {
            root.dateEnd = ""
            root.doSearch()
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

    // 打开时初始化并查询第一页
    onOpened: {
        searchInput.text = ""
        root.lastKeyword = ""
        var today = root._fmtDate(new Date())
        root.dateStart = today
        root.dateEnd = today
        root.currentPage = 1
        root.totalRecords = 0
        root.tableItems = []
        root.loading = true
        _fetch()
        // 把焦点从输入框移走，防止虚拟键盘自动弹出压缩弹窗
        Qt.callLater(function() { backMouse.forceActiveFocus() })
    }

    // 格式化时间 "2026-07-15T18:57:03" → { date: "2026-07-15", time: "18:57:03" }
    function _fmtTime(isoStr) {
        var empty = { date: "—", time: "" }
        if (!isoStr || isoStr.length === 0) return empty
        // 兼容空格/T分隔的 ISO 串
        var s = String(isoStr).replace(' ', 'T')
        var datePart = "—", timePart = ""
        // 优先用前 10 位 YYYY-MM-DD
        if (s.length >= 10) {
            var ymd = s.substring(0, 10)
            if (/^\d{4}-\d{2}-\d{2}$/.test(ymd)) datePart = ymd
        }
        // 取时间部分 HH:mm:ss
        if (s.length >= 19) {
            var hms = s.substring(11, 19)
            if (/^\d{2}:\d{2}:\d{2}$/.test(hms)) timePart = hms
        }
        // 兜底用 Date 解析
        if (datePart === "—" || timePart === "") {
            try {
                var d = new Date(s)
                if (!isNaN(d.getTime())) {
                    var pad = function(n) { return n < 10 ? '0' + n : String(n) }
                    if (datePart === "—")
                        datePart = d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
                    if (timePart === "")
                        timePart = pad(d.getHours()) + ':' + pad(d.getMinutes()) + ':' + pad(d.getSeconds())
                }
            } catch (e) {}
        }
        return { date: datePart, time: timePart }
    }

    // 价格/金额格式化：保留 2 位小数
    function _fmtPrice(v) {
        if (v === undefined || v === null || v === "") return "0.00"
        var n = Number(v)
        if (isNaN(n)) return String(v)
        return n.toFixed(2)
    }

    // ==========================================
    // 内联组件 — 表头单元格
    // ==========================================
    component TableHeaderCell: Item {
        property real w: 60
        property string t: ""
        property bool showRightBorder: true
        width: w
        height: root.headerHeight

        // 右侧列分隔线（鲜明）
        Rectangle {
            visible: showRightBorder
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: root.gridLineColor
        }

        Text {
            anchors.centerIn: parent
            text: t
            font.pixelSize: 24
            font.bold: true
            font.family: Theme.fontFamilyUi
            color: Theme.colorTextSecondary
        }
    }

    // ==========================================
    // 内联组件 — 表体单元格（文本居中对齐）
    // ==========================================
    component TableCell: Item {
        property real w: 60
        property string t: ""
        property bool bold: false
        property bool muted: false
        property bool mono: false
        property bool useAccent: false
        property color accent: "#000000"
        property bool showRightBorder: true

        width: w
        height: root.rowHeight

        // 右侧列分隔线（鲜明）
        Rectangle {
            visible: showRightBorder
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: root.gridLineColor
        }

        Text {
            anchors.centerIn: parent
            text: parent.t
            font.pixelSize: 24
            font.bold: parent.bold
            font.family: parent.mono ? Theme.fontFamilyMono : Theme.fontFamilyUi
            color: parent.useAccent
                   ? parent.accent
                   : (parent.muted ? Theme.colorTextTertiary : Theme.colorTextPrimary)
            elide: Text.ElideRight
        }
    }

    // ==========================================
    // 内联组件 — 图片单元格（"查看图片"文本按钮）
    // ==========================================
    component ImageCell: Item {
        property real w: 130
        property string imgUrl: ""
        property bool showRightBorder: true
        signal openPreview()

        width: w
        height: root.rowHeight

        // 右侧列分隔线
        Rectangle {
            visible: showRightBorder
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 1
            color: root.gridLineColor
        }

        // "查看图片" 文本按钮（有图才可点击，无图显示"无图"）
        Rectangle {
            anchors.centerIn: parent
            width: 112
            height: 40
            radius: 8
            color: imgUrl.length > 0
                   ? (imgCellHover.containsMouse ? "#3B82F6" : "#EFF6FF")
                   : "transparent"
            border.color: imgUrl.length > 0
                          ? (imgCellHover.containsMouse ? "#3B82F6" : "#BFDBFE")
                          : "transparent"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: imgUrl.length > 0 ? "查看图片" : "无图"
                font.pixelSize: 20
                font.family: Theme.fontFamilyUi
                color: imgUrl.length > 0
                       ? (imgCellHover.containsMouse ? "#FFFFFF" : "#2563EB")
                       : Theme.colorTextTertiary
            }
        }

        MouseArea {
            id: imgCellHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: imgUrl.length > 0
            onClicked: openPreview()
        }
    }
}
