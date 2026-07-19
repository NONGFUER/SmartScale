// ============================================================
// SmartScale 明亮虚拟键盘风格 (light)
//
// 纯白背景 + 黑字 + 浅灰边框的现代 iOS 风格。
// 通过 QT_VIRTUALKEYBOARD_STYLE=light 启用。
//
// Qt6.8 自定义样式查找规则（实测 + 源码确认）：
//   搜索 <QML导入路径>/QtQuick/VirtualKeyboard/Styles/<风格名>/style.qml
//   入口文件名必须是 style.qml（不是 KeyboardStyle.qml），根元素为 KeyboardStyle。
// 本文件通过 app.qrc alias 嵌入到
//   :/qt-project.org/imports/QtQuick/VirtualKeyboard/Styles/light/style.qml
// 同时也拷贝到系统目录（免重编译即可生效）：
//   /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Styles/light/style.qml
//
// 关键实现约束（对照 Qt6.8.2 内置 default 样式）：
//   1. KeyboardStyle 是 QtObject，必须设置 keyboardDesignWidth/Height，
//      否则 scaleHint = keyboardHeight/0 = NaN，全部尺寸失效键盘不可见！
//   2. SelectionListItem 只是带 MouseArea 的 Item（无 background/text/highlight
//      属性），候选词 Text 直接放里面；display/wordCompletionLength 是上下文属性。
//   3. control（BaseKey）属性：key/text/displayText/smallText/smallTextVisible/
//      alternativeKeys/enabled/pressed/uppercased/highlighted/functionKey。
//      不存在 control.mode（仅 ModeKey 有）；Shift 激活态用 control.uppercased。
// ============================================================

import QtQuick
import QtQuick.VirtualKeyboard.Styles

KeyboardStyle {
    id: currentStyle

    // 设计尺寸：scaleHint = 实际键盘高 / 800（与 Qt 内置样式同基准）
    keyboardDesignWidth: 2560
    keyboardDesignHeight: 800

    readonly property real keyBackgroundMargin: Math.round(6 * scaleHint)

    // ---- 键盘整体背景：纯白 ----
    keyboardBackground: Rectangle {
        color: "#FFFFFF"
    }

    // ---- 普通字符键 ----
    keyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 48 * scaleHint
                font.family: "PingFang SC"
                color: control.enabled ? "#1F2937" : "#9CA3AF"
                font.bold: control.uppercased
            }
        }
    }

    // ---- 空格键 ----
    spaceKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#D1D5DB" : "#F3F4F6"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 36 * scaleHint
                font.family: "PingFang SC"
                color: "#6B7280"
            }
        }
    }

    // ---- 回车/完成键 ----
    enterKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#2563EB" : "#3B82F6"

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 36 * scaleHint
                font.family: "PingFang SC"
                font.bold: true
                color: "#FFFFFF"
            }
        }
    }

    // ---- 退格键 ----
    backspaceKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: "⌫"
                font.pixelSize: 44 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- Shift 键（激活态用 uppercased：Shift 按下后 BaseKey.uppercased 为 true）----
    shiftKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.uppercased ? "#DBEAFE" : "#FFFFFF")
            border.color: control.uppercased ? "#93C5FD" : "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 44 * scaleHint
                color: control.uppercased ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 符号/数字切换键 (?123)（SymbolModeKey 无激活态属性，仅用按下态）----
    symbolKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 32 * scaleHint
                font.family: "PingFang SC"
                color: "#374151"
            }
        }
    }

    // ---- 隐藏键盘键 ----
    hideKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: "⏏"
                font.pixelSize: 40 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- 模式键（ModeKey 有 mode 属性，可显示激活态）----
    modeKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.mode ? "#DBEAFE" : "#FFFFFF")
            border.color: control.mode ? "#93C5FD" : "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 40 * scaleHint
                color: control.mode ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 语言切换键 ----
    languageKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 32 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- 字符预览弹窗（手指按下时放大显示；flick* 属性由键盘运行时赋值，必须声明）----
    characterPreviewMargin: 0
    characterPreviewDelegate: Item {
        property string text
        property string flickLeft
        property string flickTop
        property string flickRight
        property string flickBottom
        id: charPreview

        Rectangle {
            anchors.fill: parent
            radius: 12 * scaleHint
            color: "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, Math.round(2 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: charPreview.text
                font.pixelSize: 64 * scaleHint
                font.family: "PingFang SC"
                color: "#1F2937"
            }
        }
    }

    // ---- 长按备选字符弹窗（尺寸默认 0 必须显式设置，否则弹窗不可见）----
    alternateKeysListItemWidth: 120 * scaleHint
    alternateKeysListItemHeight: 170 * scaleHint
    alternateKeysListDelegate: Item {
        id: alternateKeysListItem
        width: alternateKeysListItemWidth
        height: alternateKeysListItemHeight

        Text {
            anchors.centerIn: parent
            text: model.text
            font.pixelSize: 48 * scaleHint
            font.family: "PingFang SC"
            color: "#1F2937"
            opacity: 0.8
        }
        states: State {
            name: "current"
            when: alternateKeysListItem.ListView.isCurrentItem
            PropertyChanges { target: alternateKeysListItem; opacity: 1 }
        }
    }
    alternateKeysListHighlight: Rectangle {
        color: "#DBEAFE"
        radius: 8 * scaleHint
    }
    alternateKeysListBackground: Item {
        Rectangle {
            readonly property real margin: 20 * scaleHint
            x: -margin
            y: -margin
            width: parent.width + 2 * margin
            height: parent.height + 2 * margin
            radius: 12 * scaleHint
            color: "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: 1
        }
    }

    // ---- 候选词列表（拼音候选栏；高度默认 0 必须显式设置）----
    selectionListHeight: 85 * scaleHint
    selectionListDelegate: SelectionListItem {
        id: selectionListItem
        width: Math.round(selectionListLabel.width + selectionListLabel.anchors.leftMargin * 2)

        Text {
            id: selectionListLabel
            anchors.left: parent.left
            anchors.leftMargin: Math.round(50 * scaleHint)
            anchors.verticalCenter: parent.verticalCenter
            text: display
            font.pixelSize: 44 * scaleHint
            font.family: "PingFang SC"
            color: "#1F2937"
            opacity: 0.85
        }
        states: State {
            name: "current"
            when: selectionListItem.ListView.isCurrentItem
            PropertyChanges { target: selectionListLabel; color: "#2563EB"; opacity: 1 }
        }
    }
    selectionListHighlight: Rectangle {
        color: "#DBEAFE"
        radius: 8 * scaleHint
    }
    selectionListBackground: Rectangle {
        color: "#F9FAFB"
    }

    // ---- 弹出式候选列表（ShadowInputControl 用）----
    popupListDelegate: SelectionListItem {
        id: popupListItem
        width: popupListLabel.width + popupListLabel.anchors.leftMargin * 2
        height: popupListLabel.height + popupListLabel.anchors.topMargin * 2

        Text {
            id: popupListLabel
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: Math.round(24 * scaleHint)
            anchors.topMargin: Math.round(16 * scaleHint)
            text: display
            font.pixelSize: 40 * scaleHint
            font.family: "PingFang SC"
            color: "#1F2937"
            opacity: 0.8
        }
        states: State {
            name: "current"
            when: popupListItem.ListView.isCurrentItem
            PropertyChanges { target: popupListLabel; opacity: 1; color: "#2563EB" }
        }
    }
    popupListHighlight: Rectangle {
        color: "#DBEAFE"
        radius: 8 * scaleHint
    }
    popupListBackground: Rectangle {
        color: "#FFFFFF"
        border.color: "#E5E7EB"
        border.width: 1
        radius: 12 * scaleHint
    }
}
