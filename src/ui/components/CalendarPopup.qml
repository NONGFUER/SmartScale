import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import SmartScale

// ============================================================
// CalendarPopup — 日期选择日历弹窗
//
// 基于 Qt6 内置 MonthGrid 组件，触摸友好，风格与项目统一。
//
// 用法：
//   CalendarPopup {
//       id: cal
//       initialDate: new Date()
//       onDateSelected: function(d) { /* 选中某日期 */ }
//       onCleared: function() { /* 清除选择 */ }
//   }
//   cal.open()
//
// 交互：点击日期格子即选中并关闭；底部"今天"跳到今日并选中；
//       "清除"发出 cleared 信号并关闭。
// ============================================================
Dialog {
    id: root

    // ---- 对外接口 ----
    property date initialDate: new Date()
    property date selectedDate: new Date()
    signal dateSelected(date picked)
    signal cleared()

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: 480
    height: 580
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // 当前显示的月份/年份（0-11）
    property int viewMonth: initialDate.getMonth()
    property int viewYear: initialDate.getFullYear()

    // 用 en_US 确保周日为第一列，与星期表头 "日一二三四五六" 对齐
    readonly property var _dayNames: ["日", "一", "二", "三", "四", "五", "六"]

    background: Rectangle {
        radius: 20
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

    // 面板打开时的透明遮罩：点 picker 外部区域关闭它。
    // 注意：必须挂在 Dialog 自身而非 contentItem —— contentItem 是 Control 的
    // 内容区域（padding 内），子项命中区域与视觉错位会导致点击全部落到遮罩上，
    // 表现为"年月面板一点就关、无法选择"。挂在 root 上则覆盖整个 480×580 弹窗。
    MouseArea {
        parent: root
        anchors.fill: parent
        z: 10              // 高于 contentItem(日历)，低于 picker
        visible: yearMonthPicker.visible
        // 点击穿透：picker 覆盖区域由 picker 自己处理，其余区域关闭面板
        onClicked: yearMonthPicker.close()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- 标题栏 ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            color: "transparent"

            Text {
                anchors.centerIn: parent
                text: "选择日期"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextPrimary
            }

            Rectangle {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                width: 40; height: 40; radius: 20
                color: closeMA.containsMouse ? "#FEE2E2" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    font.pixelSize: 20
                    color: closeMA.containsMouse ? "#EF4444" : "#94A3B8"
                }
                MouseArea {
                    id: closeMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.close()
                }
            }
        }

        // ---- 月份导航：< 2026年7月 > ----
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 56
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            spacing: 0

            Rectangle {
                width: 44; height: 44; radius: 10
                color: prevMonthMA.containsMouse ? "#F1F5F9" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u2039"
                    font.pixelSize: 30
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
                MouseArea {
                    id: prevMonthMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root._prevMonth()
                }
            }

            Item { Layout.fillWidth: true }

            // 年月文本 → 点击弹出年月选择器
            Rectangle {
                width: yearMonthText.implicitWidth + 20
                height: 44
                radius: 10
                color: yearMonthMA.containsMouse ? "#F1F5F9" : "transparent"

                Text {
                    id: yearMonthText
                    anchors.centerIn: parent
                    text: root.viewYear + "年" + (root.viewMonth + 1) + "月"
                    font.pixelSize: 24
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextPrimary
                }

                MouseArea {
                    id: yearMonthMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: yearMonthPicker.open()
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                width: 44; height: 44; radius: 10
                color: nextMonthMA.containsMouse ? "#F1F5F9" : "transparent"
                Text {
                    anchors.centerIn: parent
                    text: "\u203A"
                    font.pixelSize: 30
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
                MouseArea {
                    id: nextMonthMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root._nextMonth()
                }
            }
        }

        // ---- 星期表头（手动，与 MonthGrid 列对齐）----
        Row {
            id: weekHeader
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.preferredHeight: 36
            spacing: 6

            Repeater {
                model: root._dayNames
                Item {
                    width: (weekHeader.width - 6 * weekHeader.spacing) / 7
                    height: 36
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.pixelSize: 20
                        font.family: Theme.fontFamilyUi
                        color: Theme.colorTextSecondary
                    }
                }
            }
        }

        // ---- 月历网格 ----
        MonthGrid {
            id: monthGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 8
            month: root.viewMonth
            year: root.viewYear
            locale: Qt.locale("en_US")
            spacing: 6

            delegate: Rectangle {
                radius: 10
                color: {
                    if (root._sameDay(model.date, root.selectedDate)) return "#3B82F6"
                    if (model.today) return "#EFF6FF"
                    if (cellMA.containsMouse && model.month === monthGrid.month) return "#F1F5F9"
                    return "transparent"
                }

                Text {
                    anchors.centerIn: parent
                    text: model.day
                    font.pixelSize: 22
                    font.family: Theme.fontFamilyUi
                    color: {
                        if (model.month !== monthGrid.month) return "#CBD5E1"
                        if (root._sameDay(model.date, root.selectedDate)) return "#FFFFFF"
                        if (model.today) return "#2563EB"
                        return Theme.colorTextPrimary
                    }
                    font.bold: model.today || root._sameDay(model.date, root.selectedDate)
                }

                MouseArea {
                    id: cellMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.selectedDate = model.date
                        root.dateSelected(model.date)
                        root.close()
                    }
                }
            }
        }

        // ---- 底部按钮：今天 / 清除 ----
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 20
            Layout.topMargin: 4
            spacing: 12

            Rectangle {
                Layout.preferredHeight: 46
                Layout.fillWidth: true
                radius: 10
                color: todayMA.containsMouse ? "#F1F5F9" : "#FFFFFF"
                border.color: "#E2E8F0"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "今天"
                    font.pixelSize: 20
                    font.family: Theme.fontFamilyUi
                    color: Theme.colorTextPrimary
                }
                MouseArea {
                    id: todayMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        var t = new Date()
                        root.selectedDate = t
                        root.viewMonth = t.getMonth()
                        root.viewYear = t.getFullYear()
                        root.dateSelected(t)
                        root.close()
                    }
                }
            }

            Rectangle {
                Layout.preferredHeight: 46
                Layout.fillWidth: true
                radius: 10
                color: clearMA.containsMouse ? "#FEE2E2" : "#FFFFFF"
                border.color: "#E2E8F0"
                border.width: 1
                Text {
                    anchors.centerIn: parent
                    text: "清除"
                    font.pixelSize: 20
                    font.family: Theme.fontFamilyUi
                    color: clearMA.containsMouse ? "#EF4444" : Theme.colorTextSecondary
                }
                MouseArea {
                    id: clearMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.cleared()
                        root.close()
                    }
                }
            }
        }
    }

    // ============================================================
    // 年月选择面板（两阶段：月份视图 / 年份视图）
    //
    // 用普通 Item 而非 Popup，避免非 modal Popup 的 CloseOnPressOutside
    // 透明 overlay 拦截内部鼠标事件。
    //
    // 默认打开显示【月份视图】：顶部 "2026年" + ▲▼ 翻年，
    //   中间 4×3 月份网格(1-12)，选中月蓝圆高亮。
    // 点击顶部年份文字 → 切到【年份视图】：顶部十年范围 + ▲▼，
    //   中间 4列年份网格，当前年蓝圆，范围外灰色。
    // 选中年份自动切回月份；选月份关闭面板。
    // ============================================================
    Item {
        id: yearMonthPicker
        // 与遮罩同理：挂 Dialog 自身，坐标相对整个弹窗（480×580）
        parent: root
        x: 16
        y: 122
        width: 448
        height: 340
        z: 20              // 高于遮罩，保证面板可点
        visible: false

        // 0=月份视图, 1=年份视图
        property int pickerMode: 0
        property int pickerYear: root.viewYear
        property int decadeStart: Math.floor(root.viewYear / 10) * 10

        function open() { visible = true }
        function close() { visible = false }

        onVisibleChanged: {
            if (visible) {
                pickerMode = 0
                pickerYear = root.viewYear
                decadeStart = Math.floor(pickerYear / 10) * 10
            }
        }

        // 背景（纯装饰，不加 MouseArea 避免拦截事件）
        Rectangle {
            id: pickerBg
            anchors.fill: parent
            radius: 20
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
                shadowVerticalOffset: 4
            }
        }

        // 内容层（放在背景之后 → z 更高）
        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 16
            anchors.bottomMargin: 16
            anchors.leftMargin: 20
            anchors.rightMargin: 20
            spacing: 12

            // ===== 栏标题 + ▲▼ 导航 =====
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                spacing: 0

                // 年份标题（可点，切到年份网格）。用固定尺寸 Rectangle 包裹，
                // 避免 Text 在 RowLayout 中宽度塌缩导致 MouseArea 命中区为 0 点不中。
                Rectangle {
                    Layout.preferredWidth: yearTitleTxt.implicitWidth + 24
                    Layout.preferredHeight: 44
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    radius: 8
                    color: yearTitleMA.containsMouse ? "#F1F5F9" : "transparent"

                    Text {
                        id: yearTitleTxt
                        anchors.centerIn: parent
                        font.pixelSize: 22
                        font.bold: true
                        font.family: Theme.fontFamilyUi
                        color: Theme.colorTextPrimary
                        text: {
                            if (yearMonthPicker.pickerMode === 0)
                                return yearMonthPicker.pickerYear + "年 ▾"
                            else
                                return yearMonthPicker.decadeStart + " – " + (yearMonthPicker.decadeStart + 9)
                        }
                    }

                    MouseArea {
                        id: yearTitleMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("[Calendar] 点年份标题, 当前 pickerMode=", yearMonthPicker.pickerMode)
                            if (yearMonthPicker.pickerMode === 0) {
                                // 月份模式：点年份 → 切换到年份模式
                                yearMonthPicker.decadeStart = Math.floor(yearMonthPicker.pickerYear / 10) * 10
                                yearMonthPicker.pickerMode = 1
                                console.log("[Calendar] 已切到年份模式, pickerMode=", yearMonthPicker.pickerMode, "decadeStart=", yearMonthPicker.decadeStart)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // ▲ 上翻（Layout.preferredWidth/Height 防 RowLayout 塌缩）
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 44
                    radius: 6
                    color: upMA.containsMouse ? "#F1F5F9" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u25B2"   // ▲
                        font.pixelSize: 16
                        color: Theme.colorTextSecondary
                    }
                    MouseArea {
                        id: upMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("[Calendar] 上翻, pickerMode=", yearMonthPicker.pickerMode)
                            if (yearMonthPicker.pickerMode === 0) {
                                yearMonthPicker.pickerYear--
                            } else {
                                yearMonthPicker.decadeStart -= 10
                            }
                        }
                    }
                }

                Item { Layout.preferredWidth: 8; Layout.preferredHeight: 1 }

                // ▼ 下翻（Layout.preferredWidth/Height 防 RowLayout 塌缩）
                Rectangle {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 44
                    radius: 6
                    color: downMA.containsMouse ? "#F1F5F9" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u25BC"   // ▼
                        font.pixelSize: 16
                        color: Theme.colorTextSecondary
                    }
                    MouseArea {
                        id: downMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            console.log("[Calendar] 下翻, pickerMode=", yearMonthPicker.pickerMode)
                            if (yearMonthPicker.pickerMode === 0) {
                                yearMonthPicker.pickerYear++
                            } else {
                                yearMonthPicker.decadeStart += 10
                            }
                        }
                    }
                }

                // X 关闭按钮
                Item { width: 12; height: 1 }

                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: pickerCloseMA.containsMouse ? "#FEE2E2" : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: "\u2715"
                        font.pixelSize: 16
                        color: pickerCloseMA.containsMouse ? "#EF4444" : "#94A3B8"
                    }
                    MouseArea {
                        id: pickerCloseMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: yearMonthPicker.close()
                    }
                }
            }

            // ===== 内容区域（月份/年份视图用 visible 互斥显隐）=====
            // 不用 StackLayout：其非首项子视图在某些情况下拿不到尺寸导致内容空白。
            Item {
                id: pickerContent
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ===== 模式 0：月份视图（Repeater + Grid）=====
                Grid {
                    id: monthGridInner
                    anchors.fill: parent
                    visible: yearMonthPicker.pickerMode === 0
                    columns: 4
                    spacing: 6
                    verticalItemAlignment: Grid.AlignVCenter
                    horizontalItemAlignment: Grid.AlignHCenter

                    Repeater {
                        model: 12
                        Rectangle {
                            width: (monthGridInner.width - 18) / 4
                            height: 52
                            radius: 22
                            color: {
                                if (index === root.viewMonth) return "#2563EB"
                                if (monthMA.containsMouse) return "#F1F5F9"
                                return "transparent"
                            }
                            border.color: index === root.viewMonth ? "#2563EB" : "transparent"
                            border.width: index === root.viewMonth ? 0 : 1

                            Text {
                                anchors.centerIn: parent
                                text: (index + 1) + "月"
                                font.pixelSize: 20
                                font.family: Theme.fontFamilyUi
                                font.bold: (index === root.viewMonth)
                                color: (index === root.viewMonth) ? "#FFFFFF" : Theme.colorTextPrimary
                            }

                            MouseArea {
                                id: monthMA
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    console.log("[Calendar] 选月份:", index + 1)
                                    root.viewYear = yearMonthPicker.pickerYear
                                    root.viewMonth = index
                                    yearMonthPicker.close()
                                }
                            }
                        }
                    }
                }

                // ===== 模式 1：年份视图（Repeater + Grid）=====
                Grid {
                    id: yearGridInner
                    anchors.fill: parent
                    visible: yearMonthPicker.pickerMode === 1
                    onVisibleChanged: console.log("[Calendar] 年份视图 visible=", visible, "宽=", width, "高=", height)
                    columns: 4
                    spacing: 6
                    verticalItemAlignment: Grid.AlignVCenter
                    horizontalItemAlignment: Grid.AlignHCenter

                    Repeater {
                        model: 12
                        Rectangle {
                            readonly property int yr: yearMonthPicker.decadeStart - 1 + index

                            width: (yearGridInner.width - 18) / 4
                            height: 52
                            radius: 22
                            color: {
                                if (yr === root.viewYear) return "#2563EB"
                                if (yr >= yearMonthPicker.decadeStart && yr <= yearMonthPicker.decadeStart + 9 && yearMA.containsMouse) return "#F1F5F9"
                                return "transparent"
                            }
                            border.color: yr === root.viewYear ? "#2563EB" : "transparent"
                            border.width: yr === root.viewYear ? 0 : 1

                            Text {
                                anchors.centerIn: parent
                                text: parent.yr
                                font.pixelSize: 20
                                font.family: Theme.fontFamilyUi
                                font.bold: (parent.yr === root.viewYear)
                                color: {
                                    if (parent.yr < yearMonthPicker.decadeStart || parent.yr > yearMonthPicker.decadeStart + 9)
                                        return "#CBD5E1"
                                    if (parent.yr === root.viewYear) return "#FFFFFF"
                                    return Theme.colorTextPrimary
                                }
                            }

                            MouseArea {
                                id: yearMA
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: parent.yr >= yearMonthPicker.decadeStart && parent.yr <= yearMonthPicker.decadeStart + 9
                                onClicked: {
                                    console.log("[Calendar] 选年份:", parent.yr)
                                    yearMonthPicker.pickerYear = parent.yr
                                    yearMonthPicker.pickerMode = 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- 工具函数 ----
    function _sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function _prevMonth() {
        if (root.viewMonth === 0) {
            root.viewMonth = 11
            root.viewYear--
        } else {
            root.viewMonth--
        }
    }

    function _nextMonth() {
        if (root.viewMonth === 11) {
            root.viewMonth = 0
            root.viewYear++
        } else {
            root.viewMonth++
        }
    }

    onOpened: {
        root.viewMonth = root.initialDate.getMonth()
        root.viewYear = root.initialDate.getFullYear()
    }
}
