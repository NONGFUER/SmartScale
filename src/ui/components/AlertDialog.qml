import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// AlertDialog — 通用错误/确认弹窗
//
// 用法 — 纯信息模式（单按钮"我知道了"）:
//   alertDialog.show("网络连接失败", "error")
//   alertDialog.show("Token 已过期", "error", "登录失败", "原始错误: HTTP 401")
//
// 用法 — 确认模式（双按钮 取消/确认）:
//   alertDialog.confirm("确定退出登录？", function() { /* 确认回调 */ }, "提示")
//
// 内部模式切换:
//   alertDialog.mode = "confirm"   // 切换到双按钮确认模式
//   alertDialog.mode = "alert"     // 切回单按钮信息模式（默认）
//
// 信号:
//   confirmed()  — 用户点击了确认按钮
//   cancelled()  — 用户点击了取消按钮
//   dismissed()  — 弹窗关闭（任何方式）
// ============================================================
Dialog {
    id: root

    // ---- 对外接口 ----
    signal confirmed()
    signal cancelled()
    signal dismissed()

    // 模式: "alert" = 单按钮(我知道了) | "confirm" = 双按钮(取消/确定)
    property string mode: "alert"

    // 内容属性（注意：Dialog.title 是 Qt FINAL 属性，不能覆盖，改用 alertTitle）
    property string alertTitle: ""
    property string message: ""
    property string detail: ""          // 详情文本（为空时不显示展开按钮）
    property bool showDetail: false      // 详情是否已展开

    // 类型: "error" | "warning" | "success" | "info"
    property string type: "info"

    // 按钮文字（可自定义）
    property string confirmText: "我知道了"
    property string cancelText: "取消"
    property string actionText: "确定"    // confirm 模式下的主操作按钮文字

    // confirm 模式下，是否使用危险按钮样式（红色渐变）
    property bool dangerMode: false

    // 布局
    x: (parent ? parent.width : 0) / 2 - width / 2
    y: (parent ? parent.height : 0) / 2 - height / 2
    width: 480
    height: 300
    modal: true
    Overlay.modal: Rectangle {
        color: "#80000000"
        // 点击遮罩不关闭弹窗（重要错误需用户主动处理）
        // 如需支持点击遮罩关闭，可在此加 MouseArea + root.close()
    }
    standardButtons: Dialog.NoButton

    // 圆角背景
    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
    }

    // ---- 类型颜色映射 ----
    readonly property var typeColors: ({
        "error":   { icon: "\u2715", iconBg: "#FEE2E2", iconColor: "#EF4444", accent: "#EF4444", accentDark: "#DC2626" },
        "warning": { icon: "!",   iconBg: "#FEF3C7", iconColor: "#F59E0B", accent: "#F59E0B", accentDark: "#D97706" },
        "success": { icon: "\u2713", iconBg: "#DCFCE7", iconColor: "#22C55E", accent: "#22C55E", accentDark: "#16A34A" },
        "info":    { icon: "i",   iconBg: "#DBEAFE", iconColor: "#3B82F6", accent: "#3B82F6", accentDark: "#2563EB" }
    })

    function _color(key) { return typeColors[type] ? typeColors[type][key] : typeColors["info"][key] }

    // ---- 公共方法 ----

    /**
     * 显示信息弹窗（单按钮）
     * @param msg     正文消息
     * @param t       类型 "error"|"warning"|"success"|"info"（默认 "info"）
     * @param tlt     标题（可选）
     * @param dtl     详细信息（可选，显示在可展开区域）
     */
    function show(msg, t, tlt, dtl) {
        mode = "alert"
        message = msg || ""
        type = t || "info"
        alertTitle = tlt || ""
        detail = dtl || ""
        showDetail = false  // 默认收起详情，避免技术错误直接外露，用户按需展开
        dangerMode = false
        root.open()
    }

    /**
     * 显示确认弹窗（双按钮）
     * @param msg         正文消息
     * @param onConfirm   确认回调函数
     * @param tlt         标题（可选）
     * @param cancelTxt   取消按钮文字（可选）
     * @param actionTxt   确认按钮文字（可选）
     */
    function confirm(msg, onConfirm, tlt, cancelTxt, actionTxt) {
        mode = "confirm"
        message = msg || ""
        alertTitle = tlt || ""
        detail = ""
        showDetail = false
        if (cancelTxt !== undefined) cancelText = cancelTxt
        if (actionTxt !== undefined) actionText = actionTxt

        // 断开旧连接，重新绑定
        _confirmCallback = onConfirm
        root.open()
    }

    // 内部：保存确认回调
    property var _confirmCallback: null

    onConfirmed: {
        if (_confirmCallback && typeof _confirmCallback === "function") {
            _confirmCallback()
        }
    }

    onDismissed: {
        _confirmCallback = null
    }

    // ---- 内容布局 ----
    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 24
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        width: parent.width - 40
        spacing: 12

        // ===== 返回按钮栏 =====
        RowLayout {
            Layout.fillWidth: true
            Layout.bottomMargin: 8
            spacing: 0

            // 返回按钮 — back2.png + "返回"（圆角胶囊）
            Rectangle {
                width: 116; height: 44; radius: 22
                color: backMouse.containsMouse ? "#F1F5F9" : "transparent"

                Row {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 22; height: 22
                        fillMode: Image.PreserveAspectFit
                        source: "qrc:/resources/img/back2.png"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "返回"
                        font.pixelSize: 24
                        font.bold: true
                        color: "#4649E5"
                    }
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: {
                        root.dismissed()
                        root.close()
                    }
                }
            }

            Item { Layout.fillWidth: true }
        }

        // ===== 图标 + 标题行 =====
        // RowLayout {
        //     Layout.fillWidth: true
        //     spacing: 10
        //     visible: root.alertTitle !== ""

        //     // 类型图标
        //     Rectangle {
        //         width: 40; height: 40; radius: 10
        //         color: root._color("iconBg")

        //         Text {
        //             anchors.centerIn: parent
        //             text: root._color("icon")
        //             font.pixelSize: 22
        //             font.bold: true
        //             color: root._color("iconColor")
        //         }
        //     }

        //     Text {
        //         text: root.alertTitle
        //         font.pixelSize: 24
        //         font.bold: true
        //         color: "#1E293B"
        //         Layout.fillWidth: true
        //     }
        // }

        // ===== 消息正文 =====
        Text {
            id: messageText
            text: root.message
            font.pixelSize: 24
            color: "#334155"
            wrapMode: Text.Wrap
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            Layout.topMargin: root.alertTitle === "" ? 4 : 0
            Layout.bottomMargin: 4
            // 限制最大行数，超出时截断
            maximumLineCount: root.detail !== "" && !root.showDetail ? 2 : 99
            elide: root.detail !== "" && !root.showDetail ? Text.ElideRight : Text.ElideNone
        }

        // ===== 详情区域（可折叠）=====
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            visible: root.detail !== ""

            // 展开/收起按钮
            RowLayout {
                spacing: 6
                Layout.alignment: Qt.AlignHCenter

                Text {
                    text: root.showDetail ? "收起详情 \u25B2" : "查看详情 \u25BC"
                    font.pixelSize: 24
                    color: root._color("accent")

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showDetail = !root.showDetail
                    }
                }
            }

            // 详情内容
            Rectangle {
                Layout.fillWidth: true
                visible: root.showDetail
                radius: 8
                color: "#F8FAFC"
                border.color: "#E2E8F0"
                border.width: 1
                implicitHeight: detailContent.implicitHeight + 20

                Flickable {
                    id: detailFlickable
                    anchors.fill: parent
                    anchors.margins: 10
                    clip: true
                    contentHeight: detailContent.implicitHeight
                    interactive: detailContent.implicitHeight > height

                    Text {
                        id: detailContent
                        text: root.detail
                        font.pixelSize: 24
                        font.family: "monospace"
                        color: "#64748B"
                        wrapMode: Text.Wrap
                        width: detailFlickable.width
                    }
                }
            }
        }

        // ===== 按钮区 =====
        Item {
            Layout.fillWidth: true
            Layout.topMargin: root.detail !== "" ? 12 : 20
            height: 44

            // ----- alert 模式: 单按钮（居中） -----
            Rectangle {
                anchors.centerIn: parent
                visible: root.mode === "alert"
                width: 180
                height: 44
                radius: 8

                gradient: Gradient {
                    GradientStop { position: 0.0; color: root._color("accent") }
                    GradientStop { position: 1.0; color: root._color("accentDark") }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.confirmText
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.dismissed()
                        root.close()
                    }
                }
            }

            // ----- confirm 模式: 双按钮（等宽） -----
            Row {
                anchors.fill: parent
                visible: root.mode === "confirm"
                spacing: 16

                // 取消按钮
                Rectangle {
                    width: (parent.width - 16) / 2
                    height: 44
                    radius: 8
                    color: cancelBtnMouse.containsMouse ? "#F1F5F9" : "#FFFFFF"
                    border.color: "#D1D5DB"
                    border.width: 1

                    Text { anchors.centerIn: parent; text: root.cancelText; font.pixelSize: 24; font.bold: true; color: "#475569" }
                    MouseArea {
                        id: cancelBtnMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.cancelled()
                            root.dismissed()
                            root.close()
                        }
                    }
                }

                // 确认/操作按钮
                Rectangle {
                    width: (parent.width - 16) / 2
                    height: 44
                    radius: 8

                    gradient: root.dangerMode ? dangerGradient : normalGradient

                    Gradient {
                        id: dangerGradient
                        GradientStop { position: 0.0; color: "#EF4444" }
                        GradientStop { position: 1.0; color: "#DC2626" }
                    }
                    Gradient {
                        id: normalGradient
                        GradientStop { position: 0.0; color: root._color("accent") }
                        GradientStop { position: 1.0; color: root._color("accentDark") }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root.actionText
                        font.pixelSize: 24
                        font.bold: true
                        color: "white"
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.confirmed()
                            root.dismissed()
                            root.close()
                        }
                    }
                }
            }
        }
    }

    // 入场动画: 淡入 + 缩放
    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.92; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        }
    }

    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150; easing.type: Easing.InCubic }
    }
}
