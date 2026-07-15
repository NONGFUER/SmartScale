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

            Text {
                text: root.viewYear + "年" + (root.viewMonth + 1) + "月"
                font.pixelSize: 24
                font.bold: true
                font.family: Theme.fontFamilyUi
                color: Theme.colorTextPrimary
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
