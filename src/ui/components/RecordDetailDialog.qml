import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import SmartScale

// ============================================================
// RecordDetailDialog — 称重记录图片浏览弹窗
//
// 视觉风格与称重记录查询弹窗（WeightRecordSearchDialog）保持一致：
//   白色卡片背景 + 圆角阴影 / 标题栏(返回+标题+关闭) /
//   浅灰内容容器 / 蓝色系翻页控件
//
// 功能：
//   单张/多张图片查看 / 触摸左右滑动翻页 / 键盘 ← → 翻页
//
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
    height: Math.min(parent.height * 0.92, 860)

    modal: true
    Overlay.modal: Rectangle { color: "#C0000000" }
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    // ---- 白色卡片背景 + 圆角 + 阴影（与搜索弹窗一致）----
    background: Rectangle {
        radius: 24
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 25
            shadowOpacity: 0.18
            shadowVerticalOffset: 8
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ==========================================
        // 标题栏：返回按钮 + 标题 + 关闭按钮
        // （布局与 WeightRecordSearchDialog 完全一致）
        // ==========================================
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 28
            Layout.leftMargin: 32
            Layout.rightMargin: 32
            Layout.bottomMargin: 16
            spacing: 0


            Item { Layout.fillWidth: true }

            // 居中标题
            Text {
                text: "图片查看"
                font.family: Theme.fontFamilyTitle
                font.pixelSize: 26
                font.bold: true
                color: Theme.colorTextPrimary
            }

            Item { Layout.fillWidth: true }

            // 关闭按钮 — 透明底，hover 变红（与搜索弹窗关闭钮同款）
            Rectangle {
                width: 52; height: 52; radius: 21
                color: closeMA.containsMouse ? "#FEE2E2" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2715"
                    font.pixelSize: 42
                    color: closeMA.containsMouse ? "#EF4444" : "#94A3B8"
                }
                MouseArea {
                    id: closeMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: dialogRoot.close()
                }
            }
        }

        

        // ==========================================
        // 图片展示区域（浅灰圆角容器，与搜索弹窗结果区一致）
        // ==========================================
        Rectangle {
            id: imageContainer
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.bottomMargin: 16
            color: "#F8FAFC"
            radius: 14
            border.color: "#E2E8F0"
            border.width: 1
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
                        text: "\u{1F4CF}"
                        font.pixelSize: 48
                        color: "#CBD5E1"
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "暂无图片"
                        font.pixelSize: 18
                        color: Theme.colorTextTertiary
                    }
                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: "该称重记录未拍摄照片"
                        font.pixelSize: 15
                        color: Theme.colorTextTertiary
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
                            imageContainer.switching = true
                            dragOffset = 0
                            isDragging = false
                            switchTimer.direction = -1
                            switchTimer.start()
                        } else if (dragOffset < -threshold && dialogRoot.hasNext) {
                            imageContainer.switching = true
                            dragOffset = 0
                            isDragging = false
                            switchTimer.direction = 1
                            switchTimer.start()
                        } else {
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
                interval: 200
                onTriggered: {
                    if (direction < 0 && dialogRoot.hasPrev)
                        dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
                    else if (direction > 0 && dialogRoot.hasNext)
                        dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
                    imageContainer.switching = false
                }
            }

            // 拖拽进度指示条
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: imageContainer.width * 0.3
                height: 3
                radius: 1.5
                color: Qt.rgba(59, 130, 246, 0.25)
                visible: swipeArea.isDragging

                Rectangle {
                    anchors.centerIn: parent
                    height: parent.height
                    radius: parent.radius
                    color: "#3B82F6"
                    width: parent.width * Math.min(1.0, Math.abs(swipeArea.dragOffset) / (imageContainer.width * 0.5))
                    Behavior on width { NumberAnimation { duration: 50 } }
                }
            }
        }

        // ==========================================
        // 翻页导航栏（居中对称，大号按钮，位于底部居中）
        // ==========================================
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: 8
            Layout.bottomMargin: 16
            spacing: 20
            visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
                      && dialogRoot.currentIndex >= 0

            // 上一张 — 大号圆角按钮
            Rectangle {
                id: prevBtnRect
                Layout.preferredWidth: 80
                Layout.preferredHeight: 52
                radius: 14
                color: dialogRoot.hasPrev ? (prevHover.hovered ? "#3B82F6" : "#EFF6FF") : "#F1F5F9"
                border.color: dialogRoot.hasPrev ? (prevHover.hovered ? "#2563EB" : "#BFDBFE") : "#E2E8F0"
                border.width: 1.5
                enabled: dialogRoot.hasPrev
                opacity: enabled ? 1.0 : 0.4
                scale: enabled && prevHover.hovered ? 1.03 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        source: "qrc:/resources/img/pageUp.png"
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "上一张"
                        font.pixelSize: 12
                        font.family: Theme.fontFamilyUi
                        color: dialogRoot.hasPrev ? (prevHover.hovered ? "#FFFFFF" : "#2563EB") : "#94A3B8"
                    }
                }
                HoverHandler { id: prevHover }
                TapHandler {
                    enabled: dialogRoot.hasPrev
                    onTapped: if (dialogRoot.hasPrev) dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
                }
            }

            // 页码计数 — 大号蓝色胶囊
            Rectangle {
                Layout.preferredWidth: countText.implicitWidth + 48
                Layout.preferredHeight: 52
                radius: 26
                color: "#3B82F6"

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: (dialogRoot.currentIndex + 1) + " / " + dialogRoot.recordList.length
                    font.pixelSize: 18
                    font.bold: true
                    font.family: Theme.fontFamilyUi
                    color: "#FFFFFF"
                }
            }

            // 下一张 — 大号圆角按钮（与上一张对称）
            Rectangle {
                id: nextBtnRect
                Layout.preferredWidth: 80
                Layout.preferredHeight: 52
                radius: 14
                color: dialogRoot.hasNext ? (nextHover.hovered ? "#3B82F6" : "#EFF6FF") : "#F1F5F9"
                border.color: dialogRoot.hasNext ? (nextHover.hovered ? "#2563EB" : "#BFDBFE") : "#E2E8F0"
                border.width: 1.5
                enabled: dialogRoot.hasNext
                opacity: enabled ? 1.0 : 0.4
                scale: enabled && nextHover.hovered ? 1.03 : 1.0
                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on border.color { ColorAnimation { duration: 150 } }
                Behavior on color { ColorAnimation { duration: 150 } }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: "下一张"
                        font.pixelSize: 12
                        font.family: Theme.fontFamilyUi
                        color: dialogRoot.hasNext ? (nextHover.hovered ? "#FFFFFF" : "#2563EB") : "#94A3B8"
                    }
                    Image {
                        Layout.preferredWidth: 24
                        Layout.preferredHeight: 24
                        Layout.alignment: Qt.AlignVCenter
                        source: "qrc:/resources/img/pageDown.png"
                        fillMode: Image.PreserveAspectFit
                    }
                }
                HoverHandler { id: nextHover }
                TapHandler {
                    enabled: dialogRoot.hasNext
                    onTapped: if (dialogRoot.hasNext) dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
                }
            }
        }

    }

    // ---- 键盘支持：← → 翻页 ----
    focus: true
    Keys.onLeftPressed: if (dialogRoot.hasPrev) dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
    Keys.onRightPressed: if (dialogRoot.hasNext) dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)

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
