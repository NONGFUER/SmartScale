import QtQuick
import QtQuick.Layouts

// ============================================================
// ActionButton — 仿品类网格卡片质感的操作按钮
// 用法：
//   ActionButton { text: "归零"; onClicked: ... }           // 次要（灰）
//   ActionButton { text: "保存"; primary: true; onClicked: ... }  // 主色（蓝）
// ============================================================
Rectangle {
    id: btnRoot

    // ---- 对外属性 ----
    property string text: ""
    property bool primary: false       // true=蓝色主按钮，false=灰色次要按钮
    property bool buttonEnabled: true  // 启用状态（避免与 Item.enabled 冲突）
    signal clicked()

    // ---- 色板 ----
    // 主色（蓝）
    readonly property color _pTop:    "#3B82F6"
    readonly property color _pBottom: "#1D4ED8"
    readonly property color _pBorder: "#1E40AF"
    readonly property color _pBorderHover: "#60A5FA"
    readonly property color _pText:   "#FFFFFF"

    // 次要（灰）
    readonly property color _sTop:    "#FFFFFF"
    readonly property color _sBottom: "#EEF2F7"
    readonly property color _sBorder: "#E2E8F0"
    readonly property color _sBorderHover: "#9DBBFF"
    readonly property color _sText:   "#475569"

    // 当前生效色
    readonly property color _topColor:    primary ? _pTop    : _sTop
    readonly property color _bottomColor: primary ? _pBottom : _sBottom
    readonly property color _borderColor: !buttonEnabled ? (primary ? "#1E40AF" : "#E2E8F0")
                                       : (hoverHandler.hovered
                                          ? (primary ? _pBorderHover : _sBorderHover)
                                          : (primary ? _pBorder : _sBorder))
    readonly property color _textColor:   primary ? _pText : _sText

    // hover 上浮（按下时回落，模拟按压）
    readonly property real _liftY: buttonEnabled && hoverHandler.hovered && !tapHandler.pressed ? -2 : 0

    radius: 12
    border.width: 1
    border.color: _borderColor
    opacity: buttonEnabled ? 1.0 : 0.45
    clip: false

    Behavior on border.color { ColorAnimation { duration: 140 } }
    Behavior on opacity { NumberAnimation { duration: 140 } }

    // hover 上浮变换
    transform: Translate {
        y: btnRoot._liftY
        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    // 垂直渐变背景（顶亮底暗，模拟顶光照射）
    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: btnRoot._topColor
            Behavior on color { ColorAnimation { duration: 140 } }
        }
        GradientStop {
            position: 1.0
            color: btnRoot._bottomColor
            Behavior on color { ColorAnimation { duration: 140 } }
        }
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
        opacity: (hoverHandler.hovered || btnRoot.primary) ? 1.0 : 0.7
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
        opacity: hoverHandler.hovered ? 0.3 : 0.16
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
        opacity: hoverHandler.hovered ? 0.18
                : (btnRoot.primary ? 0.10 : 0.04)
        Behavior on opacity { NumberAnimation { duration: 140 } }
    }

    // 按钮文字
    Text {
        anchors.centerIn: parent
        text: btnRoot.text
        font.pixelSize: 32
        font.bold: true
        color: btnRoot._textColor
    }

    HoverHandler {
        id: hoverHandler
        enabled: btnRoot.buttonEnabled
    }

    TapHandler {
        id: tapHandler
        enabled: btnRoot.buttonEnabled
        onTapped: btnRoot.clicked()
    }
}
