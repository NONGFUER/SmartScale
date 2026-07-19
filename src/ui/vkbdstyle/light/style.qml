// ============================================================
// SmartScale 明亮虚拟键盘风格 (light)
//
// 浅灰蓝底 + 白色键帽 + 清晰边框的现代 iOS 风格。
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
//
// 字号换算（本机 1920 宽屏）：键盘高 = 1920×(800/2560) = 600 → scaleHint = 0.75；
//   InputPanel 再经 scale:0.62 视觉缩放。键帽文字统一 80*scaleHint
//   = 80×0.75×0.62 ≈ 视觉 37px（2026-07-20 由 64 加大，提升可读性）。
//   改屏幕宽度或 InputPanel.scale 后需重算：字号 = 目标px / (0.3125宽比×scale)。
//
// 键帽轮廓（2026-07-19 增强）：键盘底 #E9EEF4（与 Main.qml keyboardContainer
//   一致），白色键帽 + #CBD5E1 加粗边框（3px 设计单位 ≈ 视觉 1.9px），
//   底/帽对比 + 粗边框共同强化按键边界感。边框改色需全局统一，勿单独改。
// ============================================================

import QtQuick
import QtQuick.VirtualKeyboard
import QtQuick.VirtualKeyboard.Styles

KeyboardStyle {
    id: currentStyle

    // 设计尺寸：scaleHint = 实际键盘高 / 800（与 Qt 内置样式同基准）
    keyboardDesignWidth: 2560
    keyboardDesignHeight: 800

    readonly property real keyBackgroundMargin: Math.round(6 * scaleHint)

    // ---- 键盘整体背景：浅灰蓝（衬托白色键帽，强化轮廓）----
    keyboardBackground: Rectangle {
        color: "#E9EEF4"
    }

    // ---- 普通字符键 ----
    keyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 80 * scaleHint
                font.family: "PingFang SC"
                font.bold: true
                color: control.enabled ? "#1F2937" : "#9CA3AF"
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
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 80 * scaleHint
                font.family: "PingFang SC"
                font.bold: true
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
            color: control.pressed ? "#1D4ED8" : "#2563EB"

            Text {
                anchors.centerIn: parent
                text: "回车"
                font.pixelSize: 80 * scaleHint
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
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: "⌫"
                font.pixelSize: 80 * scaleHint
                font.bold: true
                color: "#374151"
            }
        }
    }

    // ---- Shift 键（Qt6.8 的 ShiftKey displayText 为空，内置样式用 SVG 图标；
    //      这里用 Canvas 画上箭头，激活态用 uppercased 判断并变蓝色）----
    shiftKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.uppercased ? "#DBEAFE" : "#FFFFFF")
            border.color: control.uppercased ? "#60A5FA" : "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Canvas {
                id: shiftArrow
                anchors.centerIn: parent
                width: 84 * scaleHint
                height: 84 * scaleHint
                property color arrowColor: control.uppercased ? "#2563EB" : "#374151"
                onArrowColorChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.fillStyle = arrowColor
                    var w = width, h = height
                    ctx.beginPath()
                    ctx.moveTo(w * 0.5,  h * 0.08)  // 箭头尖
                    ctx.lineTo(w * 0.92, h * 0.52)
                    ctx.lineTo(w * 0.68, h * 0.52)
                    ctx.lineTo(w * 0.68, h * 0.92)
                    ctx.lineTo(w * 0.32, h * 0.92)
                    ctx.lineTo(w * 0.32, h * 0.52)
                    ctx.lineTo(w * 0.08, h * 0.52)
                    ctx.closePath()
                    ctx.fill()
                }
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
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 80 * scaleHint
                font.family: "PingFang SC"
                font.bold: true
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
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: "收起"
                font.pixelSize: 80 * scaleHint
                font.bold: true
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
            border.color: control.mode ? "#60A5FA" : "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 80 * scaleHint
                font.bold: true
                color: control.mode ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 语言切换键（默认 displayText 是 "zh"/"en" 语言码，改为中文名显示）----
    languageKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            anchors.margins: keyBackgroundMargin
            radius: 12 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: InputContext.locale.substring(0, 2) === "zh" ? "中文" : "英文"
                font.pixelSize: 80 * scaleHint
                font.family: "PingFang SC"
                font.bold: true
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
            border.color: "#CBD5E1"
            border.width: Math.max(2, Math.round(3.5 * scaleHint))

            Text {
                anchors.centerIn: parent
                text: charPreview.text
                font.pixelSize: 100 * scaleHint
                font.family: "PingFang SC"
                color: "#1F2937"
            }
        }
    }

    // ---- 长按备选字符弹窗（尺寸默认 0 必须显式设置，否则弹窗不可见）----
    alternateKeysListItemWidth: 132 * scaleHint
    alternateKeysListItemHeight: 180 * scaleHint
    alternateKeysListDelegate: Item {
        id: alternateKeysListItem
        width: alternateKeysListItemWidth
        height: alternateKeysListItemHeight

        Text {
            anchors.centerIn: parent
            text: model.text
            font.pixelSize: 68 * scaleHint
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
            border.color: "#CBD5E1"
            border.width: 1
        }
    }

    // ---- 候选词列表（拼音候选栏；高度默认 0 必须显式设置）----
    // 触摸友好：栏高 ≈ 视觉 60px，字号 ≈ 视觉 30px，每项两侧留白 ≈ 视觉 37px
    selectionListHeight: 130 * scaleHint
    selectionListDelegate: SelectionListItem {
        id: selectionListItem
        width: Math.round(selectionListLabel.width + selectionListLabel.anchors.leftMargin * 2)

        Text {
            id: selectionListLabel
            anchors.left: parent.left
            anchors.leftMargin: Math.round(80 * scaleHint)
            anchors.verticalCenter: parent.verticalCenter
            text: display
            font.pixelSize: 80 * scaleHint
            font.family: "PingFang SC"
            font.bold: true
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
        color: "#F4F7FA"
        // 与键区分隔：顶部 1px 分割线
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Math.max(1, Math.round(1.5 * scaleHint))
            color: "#CBD5E1"
        }
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
            anchors.leftMargin: Math.round(48 * scaleHint)
            anchors.topMargin: Math.round(32 * scaleHint)
            text: display
            font.pixelSize: 80 * scaleHint
            font.family: "PingFang SC"
            font.bold: true
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
        border.color: "#CBD5E1"
        border.width: 1
        radius: 12 * scaleHint
    }
}
