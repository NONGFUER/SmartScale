import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// RecordDetailDialog — 称重记录图片浏览弹窗（纯图片模式）
// 无边框、无顶栏，仅显示图片 + 导航控件
// 用法：
//   RecordDetailDialog {
//       id: detailDialog
//       record: someRecord
//       recordList: fullList
//       onNavigateToRecord: function(idx) { ... }
//       onClosed: someRecord = null
//   }
//   detailDialog.open()
// ============================================================
Dialog {
    id: dialogRoot

    // ---- 对外接口 ----
    property var record: null
    property var recordList: []
    signal navigateToRecord(int newIndex)

    // 当前记录在 recordList 中的索引（通过 recordTime 匹配）
    readonly property int currentIndex: {
        if (!dialogRoot.record || !dialogRoot.recordList || dialogRoot.recordList.length === 0)
            return -1
        var t = dialogRoot.record.recordTime
        for (var i = 0; i < dialogRoot.recordList.length; i++) {
            if (dialogRoot.recordList[i].recordTime === t)
                return i
        }
        return -1
    }
    readonly property bool hasPrev: dialogRoot.currentIndex > 0
    readonly property bool hasNext: dialogRoot.currentIndex >= 0
        && dialogRoot.currentIndex < dialogRoot.recordList.length - 1

    x: (parent.width - width) / 2
    y: (parent.height - height) / 2

    width: Math.min(parent.width * 0.92, 1280)
    height: Math.min(parent.height * 0.92, 820)

    modal: true
    Overlay.modal: Rectangle { color: "#70000000" }
    padding: 0

    // 透明背景，无边框
    background: Item {}

    // ========== 图片区域（比弹窗稍小，给控件留出浮动空间）==========
    Rectangle {
        id: imageContainer
        anchors.fill: parent
        anchors.margins: 50
        color: "transparent"
        clip: true

        // 切换状态：true=正在切换（图片淡出中），false=正常显示
        property bool switching: false

        // 图片容器（拖拽平移 + 切换淡入淡出）
        Item {
            id: imageWrapper
            anchors.fill: parent

            // 拖拽中：实时跟随手指；切换中：固定在中心；正常：固定在中心
            x: swipeArea.isDragging ? swipeArea.dragOffset : 0

            // 拖拽中：随距离微变淡；切换中：完全透明；正常：不透明
            opacity: imageContainer.switching ? 0.0
                  : (swipeArea.isDragging
                     ? Math.max(0.5, 1.0 - Math.abs(swipeArea.dragOffset) / (imageContainer.width * 0.8))
                     : 1.0)

            // 回弹 / 淡入淡出动画（仅在非拖拽时生效）
            Behavior on x {
                enabled: !swipeArea.isDragging
                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                enabled: !swipeArea.isDragging
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }

            // 图片
            Image {
                id: detailImage
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                source: dialogRoot.record && dialogRoot.record.mainImagePath
                       ? (dialogRoot.record.mainImagePath.startsWith("file://")
                          ? dialogRoot.record.mainImagePath
                          : "file://" + dialogRoot.record.mainImagePath)
                       : ""
                visible: source !== ""
                onStatusChanged: if (status === Image.Error) console.warn("图片加载失败:", source)
            }

            // 无图占位
            Column {
                anchors.centerIn: parent
                spacing: 14
                visible: !detailImage.visible

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "暂无图片"
                    font.pixelSize: 22
                    color: "#6B7280"
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "该称重记录未拍摄照片"
                    font.pixelSize: 17
                    color: "#9CA3AF"
                }
            }
        }

        // ---- 滑动手势（实时拖拽 + 松手判断）----
        MouseArea {
            id: swipeArea
            anchors.fill: parent
            enabled: dialogRoot.recordList && dialogRoot.recordList.length > 1 && !imageContainer.switching

            property real startX: 0
            property real startY: 0
            property bool isDragging: false
            property real dragOffset: 0

            onPressed: function(mouse) {
                startX = mouse.x
                startY = mouse.y
                isDragging = false
                dragOffset = 0
            }
            onPositionChanged: function(mouse) {
                var dx = mouse.x - startX
                var dy = Math.abs(mouse.y - startY)
                if (!isDragging && Math.abs(dx) > 10 && dy < Math.abs(dx) * 0.6) {
                    isDragging = true
                }
                if (isDragging) {
                    // 边界阻尼
                    if ((dx > 0 && !dialogRoot.hasPrev) || (dx < 0 && !dialogRoot.hasNext)) {
                        dragOffset = dx * 0.2
                    } else {
                        dragOffset = dx
                    }
                }
            }
            onReleased: {
                if (isDragging) {
                    var threshold = imageContainer.width * 0.2
                    if (dragOffset > threshold && dialogRoot.hasPrev) {
                        // 够阈值：淡出 → 切换上一条 → 淡入
                        imageContainer.switching = true
                        dragOffset = 0
                        isDragging = false
                        switchTimer.direction = -1
                        switchTimer.start()
                    } else if (dragOffset < -threshold && dialogRoot.hasNext) {
                        // 够阈值：淡出 → 切换下一条 → 淡入
                        imageContainer.switching = true
                        dragOffset = 0
                        isDragging = false
                        switchTimer.direction = 1
                        switchTimer.start()
                    } else {
                        // 不够阈值：回弹
                        dragOffset = 0
                        isDragging = false
                    }
                }
            }
        }

        // 切换计时器：淡出动画播完后切换记录，然后恢复显示
        Timer {
            id: switchTimer
            property int direction: 0
            interval: 200  // 等淡出动画完成
            onTriggered: {
                if (direction < 0 && dialogRoot.hasPrev)
                    dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
                else if (direction > 0 && dialogRoot.hasNext)
                    dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
                // 切换完成，恢复显示（新图淡入）
                imageContainer.switching = false
            }
        }

        // 拖拽进度指示条（底部细线，实时显示滑动比例）
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: imageContainer.width * 0.3
            height: 3
            radius: 1.5
            color: Qt.rgba(255, 255, 255, 0.15)
            visible: swipeArea.isDragging

            Rectangle {
                anchors.centerIn: parent
                height: parent.height
                radius: parent.radius
                color: "#FFFFFF"
                width: parent.width * Math.min(1.0, Math.abs(swipeArea.dragOffset) / (imageContainer.width * 0.5))
                Behavior on width { NumberAnimation { duration: 50 } }
            }
        }
    }

    // ========== 浮动控件层（锚定到弹窗本身，位于留白区）==========

    // ---- 浮动关闭按钮（右上角）----
    Rectangle {
        id: closeBtn
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 24
        width: 62
        height: 62
        radius: 21
        color: closeBtnMA.containsMouse ? Qt.rgba(239, 226, 226, 0.95) : Qt.rgba(255, 255, 255, 0.15)

        Text {
            anchors.centerIn: parent
            text: "\u2715"
            font.pixelSize: 24
            color: closeBtnMA.containsMouse ? "#EF4444" : "#FFFFFF"
        }

        Behavior on color { ColorAnimation { duration: 120 } }

        MouseArea {
            id: closeBtnMA
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: dialogRoot.close()
        }
    }

    // ---- 左箭头（弹窗左侧留白区）----
    Rectangle {
        id: prevBtn
        anchors.left: parent.left
        anchors.leftMargin: -20
        anchors.verticalCenter: parent.verticalCenter
        width: 58; height: 58; radius: 29
        color: prevMA.containsMouse ? "#EFF6FF" : Qt.rgba(1, 1, 1, 0.12)
        border.color: dialogRoot.hasPrev ? "transparent" : "rgba(255,255,255,0.08)"
        border.width: 1
        visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
        opacity: dialogRoot.hasPrev ? 1.0 : 0.3
        // 按压缩放反馈
        scale: prevMA.pressed ? 0.85 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\u2039"; font.pixelSize: 34; font.bold: true
            color: dialogRoot.hasPrev ? "#FFFFFF" : "rgba(255,255,255,0.3)"
        }
        MouseArea {
            id: prevMA
            anchors.fill: parent; hoverEnabled: true
            enabled: dialogRoot.hasPrev
            cursorShape: dialogRoot.hasPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
        }
    }

    // ---- 右箭头（弹窗右侧留白区）----
    Rectangle {
        id: nextBtn
        anchors.right: parent.right
        anchors.rightMargin: -20
        anchors.verticalCenter: parent.verticalCenter
        width: 58; height: 58; radius: 29
        color: nextMA.containsMouse ? "#EFF6FF" : Qt.rgba(1, 1, 1, 0.12)
        border.color: dialogRoot.hasNext ? "transparent" : "rgba(255,255,255,0.08)"
        border.width: 1
        visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
        opacity: dialogRoot.hasNext ? 1.0 : 0.3
        // 按压缩放反馈
        scale: nextMA.pressed ? 0.85 : 1.0
        Behavior on scale { NumberAnimation { duration: 100; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }

        Text {
            anchors.centerIn: parent
            text: "\u203A"; font.pixelSize: 34; font.bold: true
            color: dialogRoot.hasNext ? "#FFFFFF" : "rgba(255,255,255,0.3)"
        }
        MouseArea {
            id: nextMA
            anchors.fill: parent; hoverEnabled: true
            enabled: dialogRoot.hasNext
            cursorShape: dialogRoot.hasNext ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
        }
    }

    // ---- 计数角标（顶部居中，位于图片上方留白区）----
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        width: countLabel.implicitWidth + 28
        height: 34; radius: 17
        color: Qt.rgba(0, 0, 0, 0.55)
        visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
                    && dialogRoot.currentIndex >= 0

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: (dialogRoot.currentIndex + 1) + " / " + dialogRoot.recordList.length
            font.pixelSize: 16; font.bold: true
            color: "#FFFFFF"
        }
    }

    // ---- 底部滑动提示（位于图片下方留白区）----
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        width: hintContent.implicitWidth + 32
        height: 48; radius: 18
        color: Qt.rgba(0, 0, 0, 0.45)
        visible: dialogRoot.recordList && dialogRoot.recordList.length > 1

        Row {
            id: hintContent
            anchors.centerIn: parent; spacing: 8
            Text { text: "\u2039"; font.pixelSize: 24; font.bold: true;
                    color: "#FFFFFF"; opacity: dialogRoot.hasPrev ? 1.0 : 0.3 }
            Text { text: "左右滑动切换"; font.pixelSize: 18; color: "#FFFFFF" }
            Text { text: "\u203A"; font.pixelSize: 24; font.bold: true;
                    color: "#FFFFFF"; opacity: dialogRoot.hasNext ? 1.0 : 0.3 }
        }
    }

    // ========================================================================
    // 工具函数
    // ========================================================================

    /** 将 ISO 8601 格式时间转为可读格式 */
    function formatTime(isoStr) {
        if (!isoStr || isoStr.length === 0) return "\u2014"
        var d = new Date(isoStr)
        if (isNaN(d.getTime())) return isoStr
        return d.toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm:ss")
    }
}
