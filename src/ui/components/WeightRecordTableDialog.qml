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

    // ---- 列宽定义（固定像素，表格区域宽度须匹配）----
    readonly property real colIndex: 90
    readonly property real colIngr: 260
    readonly property real colWeight: 160
    readonly property real colPrice: 200
    readonly property real colAmount: 160
    readonly property real colTime: 220
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
        // 默认日期范围：近 365 天
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
        WeightHistoryService.fetchPagedRecords(
            root.currentPage, root.pageSize,
            root.lastKeyword, fmt(past), fmt(now))
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

            // 关键字输入框
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

                    Text {
                        text: "\u{1F50D}"
                        font.pixelSize: 18
                        Layout.alignment: Qt.AlignVCenter
                    }

                    TextField {
                        id: searchInput
                        Layout.fillWidth: true
                        placeholderText: "搜索食材名称..."
                        placeholderTextColor: Theme.colorTextTertiary
                        font.pixelSize: 18
                        font.family: Theme.fontFamilyUi
                        color: Theme.colorTextPrimary
                        selectByMouse: true
                        verticalAlignment: TextField.AlignVCenter
                        background: Item {}

                        onAccepted: root.doSearch()
                        onEditingFinished: {}
                    }

                    // 清除按钮
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

            Item { Layout.fillWidth: true }

            // 搜索按钮
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
                        font.pixelSize: 18
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "搜索"
                        font.pixelSize: 20
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
                                // 时间（年月日）
                                TableCell { w: root.colTime; t: _fmtTime(modelData.crdAt); muted: true; mono: true }
                                // 图片（可点击查看大图）
                                ImageCell {
                                    w: root.colImg
                                    imgUrl: modelData.img || ""
                                    showRightBorder: false
                                    onOpenPreview: {
                                        imagePreview.imageUrl = imgUrl
                                        imagePreview.open()
                                    }
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
                font.pixelSize: 16
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
                    text: "\u2039"; font.pixelSize: 20; font.bold: true
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
                            font.pixelSize: 16
                            font.bold: modelData === root.currentPage
                            color: modelData === root.currentPage
                                   ? "#FFFFFF" : Theme.colorTextPrimary
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(modelData)
                        font.pixelSize: 16
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
                    text: "\u203A"; font.pixelSize: 20; font.bold: true
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
    // 图片预览弹窗
    // ==========================================
    Popup {
        id: imagePreview
        parent: Overlay.overlay
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: Math.min(parent.width * 0.8, 900)
        height: Math.min(parent.height * 0.85, 720)
        modal: true
        Overlay.modal: Rectangle { color: "#CC000000" }
        padding: 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        property string imageUrl: ""

        background: Rectangle {
            color: "#1F2937"
            radius: 16
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // 顶部工具栏
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "图片预览"
                    font.pixelSize: 22
                    font.bold: true
                    color: "#FFFFFF"
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40; height: 40; radius: 20
                    color: imgPreviewCloseMouse.containsMouse ? "#374151" : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        font.pixelSize: 22
                        color: "#CBD5E1"
                    }
                    MouseArea {
                        id: imgPreviewCloseMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: imagePreview.close()
                    }
                }
            }

            // 图片显示区
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 12

                Image {
                    id: previewImg
                    anchors.fill: parent
                    source: imagePreview.imageUrl.length > 0 ? imagePreview.imageUrl : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                }

                // 加载中提示
                BusyIndicator {
                    anchors.centerIn: parent
                    running: previewImg.status === Image.Loading
                    visible: previewImg.status === Image.Loading
                }

                // 加载失败提示
                Text {
                    anchors.centerIn: parent
                    visible: previewImg.status === Image.Error
                    text: "图片加载失败"
                    font.pixelSize: 22
                    color: "#FCA5A5"
                }
            }
        }
    }

    // 打开时初始化并查询第一页
    onOpened: {
        searchInput.text = ""
        root.lastKeyword = ""
        root.currentPage = 1
        root.totalRecords = 0
        root.tableItems = []
        root.loading = true
        _fetch()
    }

    // 格式化时间 "2026-07-15T18:57:03" → "2026-07-15"
    function _fmtTime(isoStr) {
        if (!isoStr || isoStr.length === 0) return "—"
        // 兼容空格/T分隔的 ISO 串
        var s = String(isoStr).replace(' ', 'T')
        // 优先用前 10 位 YYYY-MM-DD
        if (s.length >= 10) {
            var ymd = s.substring(0, 10)
            // 简单校验格式
            if (/^\d{4}-\d{2}-\d{2}$/.test(ymd)) return ymd
        }
        // 兜底用 Date 解析
        try {
            var d = new Date(s)
            if (isNaN(d.getTime())) return isoStr
            var pad = function(n) { return n < 10 ? '0' + n : String(n) }
            return d.getFullYear() + '-' + pad(d.getMonth() + 1) + '-' + pad(d.getDate())
        } catch (e) {
            return isoStr
        }
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
    // 内联组件 — 图片单元格（可点击查看大图）
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

        // 缩略图（有图才显示）
        Rectangle {
            anchors.centerIn: parent
            width: 48
            height: 48
            radius: 6
            color: "#F1F5F9"
            border.width: 1
            border.color: imgCellHover.containsMouse ? "#3B82F6" : "#E2E8F0"
            visible: parent.imgUrl.length > 0

            Image {
                id: cellThumb
                anchors.fill: parent
                anchors.margins: 2
                source: parent.parent.imgUrl.length > 0 ? parent.parent.imgUrl : ""
                fillMode: Image.PreserveAspectCrop
                cache: false
            }

            // 悬停遮罩提示
            Rectangle {
                anchors.fill: parent
                color: "#3B82F6"
                opacity: imgCellHover.containsMouse ? 0.5 : 0.0
                radius: 6

                Text {
                    anchors.centerIn: parent
                    text: "\u{1F50C}"  // 放大镜图标
                    font.pixelSize: 22
                    color: "#FFFFFF"
                    visible: parent.opacity > 0
                }
            }
        }

        // 无图占位
        Text {
            anchors.centerIn: parent
            visible: parent.imgUrl.length === 0
            text: "无图"
            font.pixelSize: 20
            color: Theme.colorTextTertiary
        }

        MouseArea {
            id: imgCellHover
            anchors.fill: parent
            hoverEnabled: true
            enabled: parent.imgUrl.length > 0
            onClicked: parent.openPreview()
        }
    }
}
