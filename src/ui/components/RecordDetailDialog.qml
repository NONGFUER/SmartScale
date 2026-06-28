import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// RecordDetailDialog — 称重记录详情弹窗
// 用法：
//   RecordDetailDialog {
//       id: detailDialog
//       record: someRecord        // 传入 WeightRecord 对象
//       onClosed: someRecord = null  // 父组件按需清理
//   }
//   detailDialog.open()
// ============================================================
Dialog {
    id: dialogRoot

    // ---- 对外接口 ----
    property var record: null
    property var recordList: []           // 父组件传入的完整记录列表（用于上下切换）
    signal navigateToRecord(int newIndex) // 请求父组件切换到指定索引的记录

    // 当前记录在 recordList 中的索引（通过 recordTime 匹配，-1 表示未匹配）
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

    // 放大默认尺寸，确保所有内容完整可见
    width: Math.min(parent.width * 0.90, 1400)
    height: Math.min(parent.height * 0.90, 980)

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }   // 显式遮罩
    padding: 0
    // 移除标准按钮，使用自定义顶栏和关闭按钮

    background: Rectangle {
        radius: 16
        color: "#E8F4FD"          // 外层浅蓝底色（与品类弹窗一致）
        border.color: "#B3D8FF"
        border.width: 1.5

        // 内层白色卡片效果
        Rectangle {
            anchors.fill: parent
            anchors.margins: 6
            radius: 12
            color: "#FFFFFF"
            border.color: "#D9ECFF"
            border.width: 1
        }
    }

    // ========== 自定义顶栏 ==========
    Rectangle {
        id: detailHeader
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
        color: "#FFFFFF"
        radius: 12
        // 只保留顶部两个圆角
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: parent.radius
            color: "#FFFFFF"
        }
        // 底部分割线
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: "#EBEEF5"
        }

        Text {
            anchors.centerIn: parent
            text: "称重记录详情"
            font.pixelSize: 60
            font.bold: true
            color: "#303133"
        }

        // 右侧关闭按钮 ✕
        Rectangle {
            id: closeBtn
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            height: 48
            radius: 24
            color: closeBtnArea.containsMouse ? "#F56C6C" : "#FFF0F0"

            Text {
                anchors.centerIn: parent
                text: "✕"
                font.pixelSize: 48
                color: closeBtnArea.containsMouse ? "#FFFFFF" : "#F56C6C"
                font.bold: true
            }

            MouseArea {
                id: closeBtnArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: dialogRoot.close()
            }
        }

        // 左侧装饰竖条
        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 26
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 32
            radius: 2
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#409EFF" }
                GradientStop { position: 1.0; color: "#67C23A" }
            }
        }
    }

    ColumnLayout {
        anchors.top: detailHeader.bottom
        anchors.topMargin: 28
        anchors.left: parent.left
        anchors.leftMargin: 32
        anchors.right: parent.right
        anchors.rightMargin: 32
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28
        spacing: 22

        // ========== 图片区域（支持左右滑动 / 箭头切换上下记录）==========
        Rectangle {
            id: imageContainer
            Layout.fillWidth: true
            Layout.preferredHeight: 460          // 加大图片区高度
            Layout.minimumHeight: 340
            color: "#F5F7FA"
            radius: 12
            border.color: "#E4E7ED"
            border.width: 1
            clip: true

            // 当前记录图片
            Image {
                id: detailImage
                anchors.fill: parent
                anchors.margins: 10
                fillMode: Image.PreserveAspectFit
                source: dialogRoot.record && dialogRoot.record.mainImagePath ? (dialogRoot.record.mainImagePath.startsWith("file://") ? dialogRoot.record.mainImagePath : "file://" + dialogRoot.record.mainImagePath) : ""
                visible: source !== ""
                // 切换记录时淡入动画
                Behavior on opacity { NumberAnimation { duration: 180 } }
                onStatusChanged: {
                    if (status === Image.Error) {
                        console.warn("图片加载失败:", source);
                    }
                }
            }

            // "暂无图片" 占位提示（无emoji）
            Column {
                anchors.centerIn: parent
                spacing: 16
                visible: !detailImage.visible

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "暂无图片"
                    color: "#909399"
                    font.pixelSize: 54
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "该称重记录未拍摄照片"
                    color: "#C0C4CC"
                    font.pixelSize: 39
                }
            }

            // ---- 滑动手势层（覆盖整个图片区，右滑=上一条，左滑=下一条）----
            MouseArea {
                id: swipeArea
                anchors.fill: parent
                enabled: dialogRoot.recordList && dialogRoot.recordList.length > 1
                property real startX: 0
                property real startY: 0
                onPressed: function(mouse) {
                    startX = mouse.x
                    startY = mouse.y
                }
                onReleased: function(mouse) {
                    var dx = mouse.x - startX
                    var dy = Math.abs(mouse.y - startY)
                    // 垂直滑动占主导则忽略，避免误触
                    if (dy > Math.abs(dx) * 0.6) return
                    if (dx > 80 && dialogRoot.hasPrev) {
                        dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
                    } else if (dx < -80 && dialogRoot.hasNext) {
                        dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
                    }
                }
            }

            // ---- 左箭头按钮（上一条记录）----
            Rectangle {
                id: prevBtn
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 56
                radius: 28
                color: prevBtnArea.containsMouse ? Qt.rgba(64/255, 158/255, 255/255, 0.92) : Qt.rgba(1, 1, 1, 0.85)
                border.color: dialogRoot.hasPrev ? "#409EFF" : "#D9D9D9"
                border.width: 1
                visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
                opacity: dialogRoot.hasPrev ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    font.pixelSize: 40
                    font.bold: true
                    color: dialogRoot.hasPrev ? "#409EFF" : "#C0C4CC"
                }

                MouseArea {
                    id: prevBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: dialogRoot.hasPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: dialogRoot.hasPrev
                    onClicked: dialogRoot.navigateToRecord(dialogRoot.currentIndex - 1)
                }
            }

            // ---- 右箭头按钮（下一条记录）----
            Rectangle {
                id: nextBtn
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 56
                height: 56
                radius: 28
                color: nextBtnArea.containsMouse ? Qt.rgba(64/255, 158/255, 255/255, 0.92) : Qt.rgba(1, 1, 1, 0.85)
                border.color: dialogRoot.hasNext ? "#409EFF" : "#D9D9D9"
                border.width: 1
                visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
                opacity: dialogRoot.hasNext ? 1.0 : 0.4

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    font.pixelSize: 40
                    font.bold: true
                    color: dialogRoot.hasNext ? "#409EFF" : "#C0C4CC"
                }

                MouseArea {
                    id: nextBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: dialogRoot.hasNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                    enabled: dialogRoot.hasNext
                    onClicked: dialogRoot.navigateToRecord(dialogRoot.currentIndex + 1)
                }
            }

            // ---- 计数角标（右上角，显示 "当前 / 总数"）----
            Rectangle {
                anchors.top: parent.top
                anchors.topMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: 12
                width: countText.implicitWidth + 28
                height: 36
                radius: 18
                color: Qt.rgba(48/255, 48/255, 48/255, 0.78)
                visible: dialogRoot.recordList && dialogRoot.recordList.length > 1
                            && dialogRoot.currentIndex >= 0

                Text {
                    id: countText
                    anchors.centerIn: parent
                    text: (dialogRoot.currentIndex + 1) + " / " + dialogRoot.recordList.length
                    color: "#FFFFFF"
                    font.pixelSize: 22
                    font.bold: true
                }
            }

            // ---- 滑动提示条（底部居中，仅当有多条记录时显示）----
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: hintRow.implicitWidth + 32
                height: 34
                radius: 17
                color: Qt.rgba(48/255, 48/255, 48/255, 0.62)
                visible: dialogRoot.recordList && dialogRoot.recordList.length > 1

                Row {
                    id: hintRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "‹"
                        color: "#FFFFFF"
                        font.pixelSize: 22
                        font.bold: true
                        opacity: dialogRoot.hasPrev ? 1.0 : 0.4
                    }
                    Text {
                        text: "左右滑动切换记录"
                        color: "#FFFFFF"
                        font.pixelSize: 20
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "›"
                        color: "#FFFFFF"
                        font.pixelSize: 22
                        font.bold: true
                        opacity: dialogRoot.hasNext ? 1.0 : 0.4
                    }
                }
            }
        }

        // ========== 信息卡片区 ==========
        GridLayout {
            Layout.fillWidth: true
            columns: 1
            rowSpacing: 18

            // 时间行
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                height: 58

                // 左侧彩色竖条装饰
                Rectangle { width: 4; height: 30; radius: 2; color: "#409EFF"; Layout.alignment: Qt.AlignVCenter }

                Text {
                    text: "时间"
                    color: "#606266"
                    font.bold: true
                    font.pixelSize: 45
                    Layout.preferredWidth: 150
                    Layout.leftMargin: 14
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 8
                    color: "#F5F7FA"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: dialogRoot.record ? dialogRoot.record.recordTime : "--"
                        color: "#303133"
                        font.pixelSize: 45
                    }
                }
            }

            // 名称行
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                height: 58

                Rectangle { width: 4; height: 30; radius: 2; color: "#E6A23C"; Layout.alignment: Qt.AlignVCenter }
                Text {
                    text: "名称"
                    color: "#606266"
                    font.bold: true
                    font.pixelSize: 45
                    Layout.preferredWidth: 150
                    Layout.leftMargin: 14
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 8
                    color: "#F5F7FA"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: dialogRoot.record ? dialogRoot.record.categoryName : "--"
                        color: "#303133"
                        font.pixelSize: 45
                    }
                }
            }

            // 重量行（绿色高亮）
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                height: 58

                Rectangle { width: 4; height: 30; radius: 2; color: "#67C23A"; Layout.alignment: Qt.AlignVCenter }
                Text {
                    text: "重量"
                    color: "#606266"
                    font.bold: true
                    font.pixelSize: 45
                    Layout.preferredWidth: 150
                    Layout.leftMargin: 14
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 8
                    color: "#F0F9EB"

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: dialogRoot.record ? (dialogRoot.record.weight ? dialogRoot.record.weight.toFixed(2) + " kg" : "--") : "--"
                        color: "#28A745"
                        font.bold: true
                        font.pixelSize: 48
                    }
                }
            }

            // 图片状态行
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                height: 58

                Rectangle { width: 4; height: 30; radius: 2; color: "#909399"; Layout.alignment: Qt.AlignVCenter }
                Text {
                    text: "图片状态"
                    color: "#606266"
                    font.bold: true
                    font.pixelSize: 45
                    Layout.preferredWidth: 150
                    Layout.leftMargin: 14
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 52
                    radius: 8
                    color: "#F5F7FA"

                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        spacing: 12

                        Text {
                            text: dialogRoot.record && dialogRoot.record.mainImagePath ? "已保存" : "无图片"
                            color: dialogRoot.record && dialogRoot.record.mainImagePath ? "#67C23A" : "#909399"
                            font.pixelSize: 45
                        }
                    }
                }
            }
        }

        // 底部间距 + 关闭按钮区域
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60

            // 关闭按钮（右下角）
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 140
                height: 52
                radius: 10
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#409EFF" }
                    GradientStop { position: 1.0; color: "#337ECC" }
                }

                Text {
                    anchors.centerIn: parent
                    text: "关闭"
                    color: "#FFFFFF"
                    font.pixelSize: 24
                    font.bold: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: dialogRoot.close()
                }
            }
        }
    }

    // ========================================================================
    // 工具函数
    // ========================================================================

    /**
     * 将 ISO 8601 格式时间字符串转为可读格式，空值显示"—"
     */
    function formatTime(isoStr) {
        if (!isoStr || isoStr.length === 0) return "\u2014"
        var d = new Date(isoStr)
        if (isNaN(d.getTime())) return isoStr  // 解析失败则原样返回
        return d.toLocaleString(Qt.locale(), "yyyy-MM-dd HH:mm:ss")
    }
}
