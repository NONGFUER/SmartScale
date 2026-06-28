import QtQuick
import QtQuick.Controls

// 全局非阻塞提示组件（Toast 风格）
// 使用 Popup 实现真正的浮层，天然在所有内容之上，不受 z-order 影响
//
// 用法：
//   toast.show("保存成功")          // 默认 success
//   toast.show("保存失败", "error")
//   toast.show("网络异常", "warning")
//   toast.show("提示信息", "info")
Popup {
    id: root

    // Popup 核心属性：非模态、不自动关闭、无内边距、背景透明
    modal: false
    closePolicy: Popup.NoAutoClose
    padding: 0
    background: Item {} // 透明背景，内容自绘

    // 顶部居中显示
    x: (parent ? parent.width : 0) / 2 - implicitWidth / 2
    y: 120
    implicitWidth: bubble.width
    implicitHeight: bubble.height

    // 队列长度上限
    readonly property int maxQueue: 5
    // 默认显示时长
    readonly property int defaultDuration: 2500

    // 队列模型：[{ message, type, duration }]
    property var _queue: []
    property bool _busy: false

    /**
     * 显示一条提示
     * @param message  文本内容
     * @param type     "success" | "error" | "warning" | "info"（默认 "success"）
     * @param duration 显示时长（毫秒），默认 2500
     */
    function show(message, type, duration) {
        if (!type) type = "success"
        if (!duration || duration <= 0) duration = defaultDuration

        if (_queue.length >= maxQueue) _queue.shift()
        _queue.push({ message: String(message), type: type, duration: duration })

        if (!_busy) _next()
    }

    function _next() {
        if (_queue.length === 0) {
            _busy = false
            return
        }
        _busy = true
        var item = _queue.shift()
        _present(item.message, item.type, item.duration)
    }

    function _present(message, type, duration) {
        // 颜色映射
        var color = "#3B82F6"  // 默认 info 蓝
        if (type === "success") color = "#22C55E"
        else if (type === "error") color = "#EF4444"
        else if (type === "warning") color = "#F59E0B"
        bubble.color = color

        bubbleText.text = message

        var icon = "i"
        if (type === "error") icon = "\u2715"  // ✕
        else if (type === "warning") icon = "!"
        else if (type === "success") icon = "\u2713"  // ✓
        // iconText 已移除（纯文字 toast），此处保留 icon 变量以备后续扩展

        hideTimer.interval = duration
        // 打开 Popup 触发入场
        root.open()
    }

    function _dismiss() {
        root.close()
    }

    onAboutToShow: {
        hideTimer.restart()
    }

    onClosed: {
        dequeueTimer.start()
    }

    // 入场/退场动画
    enter: Transition {
        NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250; easing.type: Easing.OutCubic }
        NumberAnimation { property: "y"; from: -80; to: 120; duration: 250; easing.type: Easing.OutCubic }
    }
    exit: Transition {
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
        NumberAnimation { property: "y"; from: y; to: y - 40; duration: 200; easing.type: Easing.InCubic }
    }

    Rectangle {
        id: bubble
        width: Math.min(Math.max(bubbleText.implicitWidth + 40, 200),
                        root.parent ? root.parent.width - 80 : 600)
        height: 56
        radius: 12

        border.width: 1
        border.color: "#33000000"

        Row {
            anchors.centerIn: parent
            spacing: 10

            // Text {
            //     id: iconText
            //     font.pixelSize: 18
            //     font.bold: true
            //     color: "#FFFFFF"
            //     anchors.verticalCenter: parent.verticalCenter
            // }

            Text {
                id: bubbleText
                font.pixelSize: 18
                font.bold: true
                color: "#FFFFFF"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // 自动隐藏计时器
    Timer {
        id: hideTimer
        repeat: false
        onTriggered: root.close()
    }

    // 退场动画结束后再取下一条，避免视觉重叠
    Timer {
        id: dequeueTimer
        interval: 280
        repeat: false
        onTriggered: root._next()
    }
}
