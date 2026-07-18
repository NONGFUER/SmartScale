// ============================================================
// SmartScale 明亮虚拟键盘风格 (light)
//
// 纯白背景 + 黑字 + 浅灰边框的现代 iOS 风格。
// 通过 QT_VIRTUALKEYBOARD_STYLE=light 启用。
// ============================================================

import QtQuick
import QtQuick.VirtualKeyboard.Styles

KeyboardStyle {
    // ---- 键盘整体背景：纯白 ----
    keyboardBackground: Rectangle {
        color: "#FFFFFF"
    }

    // ---- 普通字符键 ----
    keyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 22 * scaleHint
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
            radius: 8 * scaleHint
            color: control.pressed ? "#D1D5DB" : "#F3F4F6"
            border.color: "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 18 * scaleHint
                font.family: "PingFang SC"
                color: "#6B7280"
            }
        }
    }

    // ---- 回车/完成键 ----
    enterKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#2563EB" : "#3B82F6"

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 16 * scaleHint
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
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: "\u232B"  // ⌫
                font.pixelSize: 20 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- Shift 键 ----
    shiftKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.mode ? "#DBEAFE" : "#FFFFFF")
            border.color: control.mode ? "#93C5FD" : "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 20 * scaleHint
                color: control.mode ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 符号/数字切换键 (?123) ----
    symbolKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.mode ? "#DBEAFE" : "#FFFFFF")
            border.color: control.mode ? "#93C5FD" : "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 14 * scaleHint
                font.family: "PingFang SC"
                color: control.mode ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 隐藏键盘键 ----
    hideKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: "\u23CF"  // ⏏
                font.pixelSize: 18 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- 模式键（大小写锁定等）----
    modeKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : (control.mode ? "#DBEAFE" : "#FFFFFF")
            border.color: control.mode ? "#93C5FD" : "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 18 * scaleHint
                color: control.mode ? "#2563EB" : "#374151"
            }
        }
    }

    // ---- 语言切换键 ----
    languageKeyPanel: KeyPanel {
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: control.pressed ? "#E2E8F0" : "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: Math.max(1, scaleHint)

            Text {
                anchors.centerIn: parent
                text: control.displayText
                font.pixelSize: 14 * scaleHint
                color: "#374151"
            }
        }
    }

    // ---- 字符预览弹窗（手指按下时放大显示）----
    characterPreviewDelegate: Item {
        property string text
        id: charPreview
        Rectangle {
            anchors.fill: parent
            radius: 8 * scaleHint
            color: "#FFFFFF"
            border.color: "#E5E7EB"
            border.width: 1

            Text {
                anchors.centerIn: parent
                text: charPreview.text
                font.pixelSize: 28 * scaleHint
                font.family: "PingFang SC"
                color: "#1F2937"
            }
        }
    }

    // ---- 候选词列表背景 ----
    selectionListBackground: Rectangle {
        color: "#F9FAFB"
        border.color: "#E5E7EB"
        border.width: 1
        radius: 8 * scaleHint
    }

    // ---- 候选词项 ----
    selectionListDelegate: SelectionListItem {
        background: Rectangle {
            color: control.selected ? "#EFF6FF" : "transparent"
            radius: 4 * scaleHint
        }
        text: Text {
            anchors.verticalCenter: parent.verticalCenter
            text: control.display
            font.pixelSize: 18 * scaleHint
            font.family: "PingFang SC"
            color: control.selected ? "#2563EB" : "#1F2937"
        }
        highlight: Rectangle {
            color: "#DBEAFE"
            radius: 4 * scaleHint
        }
    }
}
