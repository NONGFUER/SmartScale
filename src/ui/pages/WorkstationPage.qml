import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import App.Backend 1.0
import SmartScale.Tools 1.0

Item {
    id: root
    
    // ==========================================
    // 用于缓存 AI 状态的全局属性
    // ==========================================
    property string currentPrediction: PState.IDLE
    property string currentImagePath: ""
    property var currentDetailRecord: null
    property bool categorySelectMode: false  // 是否为手动品类选择模式
    property bool pendingManualSave: false    // 手动保存等待拍照完成
    property double pendingSaveWeight: 0
    property string pendingSaveLabel: ""
    property string currentIngrId: ""        // 当前选中食材的 ingrId (上传用)
    property string pendingSaveIngrId: ""    // 手动保存待写入的 ingrId
    
    // 推理耗时相关属性
    property string lastInferenceTime: PState.NONE + " ms"

    // 若未选中任何记录，自动选中最新一条（页面加载 + 历史刷新时）
    function _selectLatestRecord() {
        if (!root.currentDetailRecord
            && WeightHistoryService
            && WeightHistoryService.historyEntries.length > 0) {
            root.currentDetailRecord = WeightHistoryService.historyEntries[0]
            console.log("[WSP] 默认选中最新记录:", JSON.stringify(root.currentDetailRecord).substring(0, 100))
        }
    }

    Component.onCompleted: _selectLatestRecord()

    // 历史记录变化时（首次加载/新增/刷新）若未选中任何记录，自动选中最新一条
    Connections {
        target: WeightHistoryService
        function onHistoryChanged() { _selectLatestRecord() }
    }

        // ===== 白色圆角主卡片 =====
        Rectangle {
            id: mainCard
            anchors.fill: parent
            anchors.margins: 24
            radius: 20
            color: "#FFFFFF"

            RowLayout {
                anchors.fill: parent
                anchors.margins: 24
                spacing: 24

                // ================================================================
                // 左侧区域 (60%) — 历史记录列表 + 蔬菜拍摄区域
                // ================================================================
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width * 0.6
                    spacing: 16

                    // ========== 历史记录区块 ==========
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height * 0.42
                        color: "#F8FAFC"
                        radius: 12
                        border.color: "#E2E8F0"
                        border.width: 1
                        clip: true

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 16

                            // ---- 左侧：历史记录列表 ----
                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 35
                                spacing: 10

                                // 标题行：历史记录 + 更多>
                                RowLayout {
                                    Layout.fillWidth: true

                                    Row {
                                        spacing: 6
                                        Text {
                                            text: "历史记录"
                                            font.pixelSize: 18
                                            font.bold: true
                                            color: "#1E293B"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "更多 >"
                                        font.pixelSize: 14
                                        color: "#3B82F6"
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            onClicked: console.log("查看更多历史记录...")
                                        }
                                    }
                                }

                                // 分隔线
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: "#E2E8F0"
                                }

                                // 历史记录列表（ListView 单列）
                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                                    ListView {
                                        id: historyListView
                                        width: parent.width
                                        model: WeightHistoryService ? WeightHistoryService.historyEntries : []
                                        spacing: 8

                                        delegate: Rectangle {
                                            id: historyDelegate
                                            width: historyListView.width
                                            height: 60
                                            radius: 10

                                            // 通过 recordTime 唯一标识比较，避免数组刷新后引用失效
                                            property bool isSelected: root.currentDetailRecord
                                                                     && root.currentDetailRecord.recordTime === modelData.recordTime
                                            property bool isHovered: delegateMouseArea.containsMouse && !isSelected

                                            // 背景：选中=品牌色淡填充，悬停=极浅灰，默认=纯白
                                            color: isSelected ? "#E0E7FF"
                                                              : (isHovered ? "#F5F7FB" : "#FFFFFF")
                                            border.color: isSelected ? "#4361EE"
                                                                     : (isHovered ? "#C7D2FE" : "#E5E7EB")
                                            border.width: isSelected ? 2 : 1

                                            Behavior on color { ColorAnimation { duration: 150 } }
                                            Behavior on border.color { ColorAnimation { duration: 150 } }
                                            Behavior on border.width { NumberAnimation { duration: 120 } }

                                            // 左侧选中指示条（4px 品牌色实心条，强对比）
                                            Rectangle {
                                                x: 0
                                                y: 4
                                                width: 4
                                                height: parent.height - 8
                                                color: "#4361EE"
                                                visible: historyDelegate.isSelected
                                                radius: 2
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 16
                                                anchors.rightMargin: 12
                                                spacing: 10

                                                // 品类名（选中=品牌色，否则=深灰）
                                                Text {
                                                    text: modelData.categoryName || "未识别"
                                                    font.pixelSize: 24
                                                    font.bold: true
                                                    color: historyDelegate.isSelected ? "#4361EE" : "#334155"
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                // 重量（选中=品牌色，否则=绿色）
                                                Text {
                                                    text: modelData.weight ? modelData.weight.toFixed(2) + " kg" : "0.00 kg"
                                                    font.pixelSize: 24
                                                    font.bold: true
                                                    color: historyDelegate.isSelected ? "#4361EE" : "#16A34A"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }

                                                // 时间（选中=品牌色辅助色，否则=浅灰）
                                                Text {
                                                    text: (modelData.recordTime || "").substring(5, 16)
                                                    font.pixelSize: 12
                                                    color: historyDelegate.isSelected ? "#6B82D9" : "#94A3B8"
                                                    Behavior on color { ColorAnimation { duration: 150 } }
                                                }
                                            }

                                            // 点击切换水印预览（不再直接弹窗，弹窗改为点水印预览图片触发）
                                            MouseArea {
                                                id: delegateMouseArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.currentDetailRecord = modelData
                                                }
                                            }
                                        }

                                        // 空状态提示
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: parent.width * 0.9
                                            height: 120
                                            visible: historyListView.count === 0
                                            color: "transparent"

                                            Column {
                                                anchors.centerIn: parent
                                                spacing: 10

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "暂无称重记录"
                                                    font.pixelSize: 18
                                                    font.bold: true
                                                    color: "#94A3B8"
                                                }

                                                Text {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    text: "开始称重后，记录将显示在这里"
                                                    font.pixelSize: 13
                                                    color: "#CBD5E1"
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- 垂直分隔线 ----
                            Rectangle {
                                Layout.fillHeight: true
                                width: 1
                                color: "#E2E8F0"
                            }

                            // ---- 右侧：水印图片预览 ----
                            ColumnLayout {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 35
                                spacing: 10

                                Text {
                                    text: "水印预览"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#1E293B"
                                }

                                Rectangle {
                                    id: watermarkPreview
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: "#E2E8F0"
                                    radius: 8
                                    clip: true

                                    // 优先显示当前选中记录，否则回退到最新一条记录
                                    // 用显式条件而非 || 短路，确保 currentDetailRecord 变化时绑定一定重新求值
                                    property var _displayRecord: {
                                        if (root.currentDetailRecord) return root.currentDetailRecord
                                        if (WeightHistoryService && WeightHistoryService.historyEntries.length > 0)
                                            return WeightHistoryService.historyEntries[0]
                                        return null
                                    }
                                    property string _imgPath: _displayRecord && _displayRecord.mainImagePath
                                        ? (_displayRecord.mainImagePath.startsWith("file://")
                                           ? _displayRecord.mainImagePath
                                           : "file://" + _displayRecord.mainImagePath)
                                        : ""

                                    Image {
                                        anchors.fill: parent
                                        source: parent._imgPath
                                        fillMode: Image.PreserveAspectCrop
                                        cache: false
                                    }

                                    // 点击水印预览图片打开详情弹窗
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: parent._imgPath !== ""
                                        onClicked: {
                                            if (parent._displayRecord) {
                                                root.currentDetailRecord = parent._displayRecord
                                                detailDialog.open()
                                            }
                                        }
                                    }

                                    // 无图时显示占位文字
                                    Text {
                                        anchors.centerIn: parent
                                        text: "暂无图片"
                                        font.pixelSize: 14
                                        color: "#94A3B8"
                                        visible: parent._imgPath === ""
                                    }
                                }
                            }
                        }
                    }

                    // ========== 蔬菜拍摄区块 — 双摄像头并排 ==========
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: "#ECEFF4"
                        radius: 14
                        clip: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0

                            // 区域标题栏
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 40

                                Row {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 14
                                    spacing: 6
                                    
                                    Text { text: "实时监控"; font.pixelSize: 24; font.bold: true; color: "#334155" }
                                }

                                Row {
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.rightMargin: 14
                                    spacing: 5
                                    Rectangle { width: 10; height: 10; radius: 4; color: "#22C55E" }
                                    Text { text: "2路在线"; font.pixelSize: 18; color: "#22C55E"; font.bold: true }
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    anchors.topMargin: 6
                                    spacing: 10

                            // ========== 主摄像头 — 蓝调主题（核心工作区） ==========
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 12
                                color: "#DBEAFE"       // 浅蓝背景，暗示主要区域
                                border.color: "#93C5FD" // 柔和蓝边框
                                border.width: 2
                                clip: true

                                VideoOutput {
                                    id: mainVideo
                                    anchors.fill: parent
                                    fillMode: VideoOutput.PreserveAspectCrop
                                    Component.onCompleted: {
                                        CameraController.setMainVideoSink(mainVideo.videoSink)
                                    }
                                }

                                // ========== 取景引导框 — 对齐 AI 裁剪区域 ==========
                                // C++ 裁剪参数 (CameraController._processCommon):
                                //   边长: min(w,h) * 0.35, 中心: 水平45%, 垂直53%
                                Item {
                                    anchors.fill: parent
                                    clip: true
                                    Rectangle {
                                        id: guideBox
                                        width: Math.min(parent.width, parent.height) * 0.35
                                        height: width
                                        x: parent.width * 0.45 - width / 2
                                        y: parent.height * 0.53 - height / 2
                                        color: "transparent"
                                        radius: 8
                                        border.width: 2
                                        border.color: "#3B82F6"
                                        Rectangle {
                                            anchors.fill: parent
                                            anchors.margins: parent.border.width
                                            radius: 6
                                            color: "#3B82F6"
                                            opacity: 0.08
                                        }
                                        property real cLen: Math.min(width, height) * 0.2
                                        Canvas {
                                            anchors.fill: parent
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                var cl = parent.cLen
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = "#2563EB"
                                                ctx.lineWidth = 3
                                                ctx.lineCap = "square"
                                                ctx.beginPath(); ctx.moveTo(0, cl); ctx.lineTo(0, 0); ctx.lineTo(cl, 0); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(width - cl, 0); ctx.lineTo(width, 0); ctx.lineTo(width, cl); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(0, height - cl); ctx.lineTo(0, height); ctx.lineTo(cl, height); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(width - cl, height); ctx.lineTo(width, height); ctx.lineTo(width - cl, height - cl); ctx.stroke()
                                            }
                                            Component.onCompleted: requestPaint()
                                        }
                                    }
                                    Rectangle {
                                        x: guideBox.x + (guideBox.width - width) / 2
                                        y: guideBox.y - 28
                                        width: guideTextLabel.width + 16
                                        height: 24
                                        radius: 4
                                        color: "#2563EB"
                                        visible: guideBox.y > 30
                                        Text {
                                            id: guideTextLabel
                                            anchors.centerIn: parent
                                            text: "\u8BF7\u5C06\u83DC\u83D0\u653E\u7F6E\u4E8E\u6B64\u533A\u57DF"
                                            font.pixelSize: 12
                                            color: "#FFFFFF"
                                        }
                                    }
                                }

                                // 左上角标签 — 蓝色调，醒目
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    width: auto_width.width + 24
                                    height: 30
                                    radius: 6
                                    color: "#2563EB"        // 蓝色实心底

                                    Row {
                                        id: auto_width
                                        spacing: 5
                                        anchors.centerIn: parent
                                       
                                        Text { text: "食材拍摄"; font.pixelSize: 13; font.bold: true; color: "#FFFFFF" }
                                    }
                                }

                                // 右下角实时状态指示
                                Row {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    spacing: 5
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#22C55E" }  // 绿点=在线
                                    Text { text: "LIVE"; font.pixelSize: 10; font.bold: true; color: "#22C55E" }
                                }
                            }

                            // ========== 副摄像头 — 暖灰主题（辅助观察区） ==========
                            Rectangle {
                                Layout.preferredWidth: Math.min(parent.width * 0.38, 280)
                                Layout.fillHeight: true
                                Layout.minimumWidth: 160
                                radius: 12
                                color: "#F1F0EF"        
                                border.color: "#D6D3D1" 
                                border.width: 2
                                clip: true

                                VideoOutput {
                                    id: subVideo
                                    anchors.fill: parent
                                    fillMode: VideoOutput.PreserveAspectCrop  // 填满容器，超出部分自动裁切（外层 clip:true 生效）
                                    Component.onCompleted: {
                                        CameraController.setSubVideoSink(subVideo.videoSink)
                                    }
                                }

                                // 左上角胶囊标签 — 暖色调
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: 10
                                    width: aux_label_w.width + 24
                                    height: 30
                                    radius: 6
                                    color: "#78716C"        // 暖灰实心底

                                    Row {
                                        id: aux_label_w
                                        spacing: 5
                                        anchors.centerIn: parent
                                        
                                        Text { text: "操作员视角"; font.pixelSize: 12; font.bold: true; color: "#FFFFFF" }
                                    }
                                }

                                // 右下角状态指示
                                Row {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    spacing: 5
                                    Rectangle { width: 7; height: 7; radius: 3; color: "#F97316" }
                                    Text { text: "AUX"; font.pixelSize: 9; font.bold: true; color: "#78716C" }
                                }
                            }
                        } 
                        } 
                    } 
                    } 
                    } 

                // ================================================================
                // 右侧区域 (40%) — 自然流式布局（顶部紧凑/中部弹性/底部固定）
                // ================================================================
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width * 0.4
                    spacing: 16

                    // ==================== 顶部区（紧凑）：用户信息 ====================
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        spacing: 12

                        // 圆形头像
                        Rectangle {
                            width: 48; height: 48; radius: 24
                            color: "#3B82F6"

                            Text {
                                anchors.centerIn: parent
                                text: BackendAuth.currentUser ? BackendAuth.currentUser.charAt(0).toUpperCase() : "?"
                                font.pixelSize: 24
                                font.bold: true
                                color: "#FFFFFF"
                            }
                        }

                        // 用户名称 + 岗位标签
                        ColumnLayout {
                            spacing: 4
                            Layout.alignment: Qt.AlignVCenter

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: {
                                    if (BackendAuth.currentUser) {
                                        logoutConfirmDialog.open()
                                    } else {
                                        window.showLogin()
                                    }
                                }
                            }

                            Text {
                                text: BackendAuth.currentUser || "未登录"
                                font.pixelSize: 22
                                font.bold: true
                                color: "#1E293B"
                            }

                            // 蓝色背景岗位标签
                            Rectangle {
                                width: 60; height: 24; radius: 4
                                color: "#DBEAFE"
                                visible: BackendAuth.currentUser !== "" && BackendAuth.currentUser !== undefined

                                Text {
                                    anchors.centerIn: parent
                                    text: "操作员"
                                    font.pixelSize: 12
                                    color: "#2563EB"
                                }
                            }
                        }

                        // 弹性 spacer 把内容推顶部对齐
                        Item { Layout.fillWidth: true }
                    }

                    // ==================== 中部区（弹性）：称重 + 物品名称 ====================
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 12

                            Row {
                                spacing: 8
                                Text {
                                    text: "食材名称"
                                    font.pixelSize: 24
                                    color: "#64748B"
                                }
                            }

                            // 名称卡片 — 虚线边框 + 文字（可点击选择品类）
                            Rectangle {
                                id: categoryCard
                                Layout.fillWidth: true
                                Layout.preferredHeight: 220
                                Layout.minimumHeight: 180
                                radius: 12
                                color: root.currentPrediction === PState.IDLE || root.currentPrediction === PState.NOT_READY
                                       ? "#F8FAFC" : "#EFF6FF"
                                border.width: 0

                                // 点击选择品类
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        console.log("打开品类选择...")
                                        root.categorySelectMode = true
                                        correctionDialog.open()
                                    }
                                }

                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.strokeStyle = "#1E40AF"
                                        ctx.lineWidth = 3
                                        ctx.setLineDash([8, 5])
                                        ctx.strokeRect(1, 1, width - 2, height - 2)
                                    }
                                    Component.onCompleted: requestPaint()
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 10

                                    // 左侧：文字展示
                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: PState.isValid(root.currentPrediction)
                                            ? Translator.translate(root.currentPrediction)
                                            : PState.label(root.currentPrediction)  
                                        font.pixelSize: 88
                                        font.bold: true
                                        color: PState.isValid(root.currentPrediction)
                                               ? "#1E40AF" : "#94A3B8"
                                    }

                                                                 
                                    }
                            }

                            // 弹性占位 — 把称重标签+卡片挤到列底
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }

                            // "称重克数" 独立标签 — 在卡片外部上方
                            Text {
                                text: "称重克数"
                                font.pixelSize:24
                                color: "#64748B"
                            }

                            // 称重卡片 — 蓝色圆角色块，白色大字（只放数字），固定高度不撑满
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 240
                                Layout.maximumHeight: 280
                                radius: 16
                                color: "#3B82F6"

                                Row {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        text: WeightManager.netWeight.toFixed(2)
                                        font.pixelSize: 148
                                        font.bold: true
                                        color: "#FFFFFF"
                                        font.family: "Monospace"
                                    }

                                    Text {
                                        text: "/kg"
                                        font.pixelSize: 28
                                        color: "#DBEAFE"
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }

                           
                            
                        }
                    }

                    // ==================== 底部区（固定高度）：操作按钮（三等分）====================
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.minimumHeight: 70
                        Layout.maximumHeight: 80
                        spacing: 12

                        // 可复用的次要按钮样式组件
                        Component {
                            id: secondaryButton
                            Button {
                                font.pixelSize: 32
                                font.bold: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                background: Rectangle {
                                    radius: 12
                                    color: parent.down ? "#E2E8F0" : "#F1F5F9"
                                    border.color: "#CBD5E1"
                                    border.width: 1
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "#475569"
                                    font: parent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }

                            // 归零按钮
                            Loader {
                                sourceComponent: secondaryButton
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                onLoaded: {
                                    item.text = "归零"; 
                                    item.clicked.connect(function() { WeightManager.zero() })
                                    }
                            }

                            // 去皮按钮
                            Loader {
                                sourceComponent: secondaryButton
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                onLoaded: {
                                    item.text = "去皮";
                                    item.clicked.connect(function() {
                                        console.log("[WSP] 点击去皮按钮, 触发硬件去皮")
                                        WeightManager.tare()
                                        if (typeof window !== "undefined" && window.toast) {
                                            window.toast("去皮执行中...", "info", 1500)
                                        }
                                    })
                                }
                            }

                            // 保存按钮（蓝色渐变主按钮）
                            Button {
                                text: "保存"
                                enabled: WeightManager.netWeight > 0.01 && 
                                         PState.isValid(root.currentPrediction)
                                font.pixelSize: 32
                                font.bold: true
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                onClicked: {
                                    let currentWeight = WeightManager.netWeight
                                    if (currentWeight > 0.01) {
                                        let chineseLabel = Translator.translate(root.currentPrediction)
                                        console.log(">> 手动保存，触发拍照:", chineseLabel, currentWeight.toFixed(2) + "kg")
                                        root.pendingManualSave = true
                                        root.pendingSaveWeight = currentWeight
                                        root.pendingSaveLabel = chineseLabel
                                        root.pendingSaveIngrId = root.currentIngrId
                                        // 传入当前已知品类标签，水印立即绘制，保存/上传独立执行
                                        CameraController.captureVegetable(currentWeight, root.currentPrediction)
                                    } else {
                                        console.warn("重量不足，无法提交记录")
                                    }
                                }
                                background: Rectangle {
                                    radius: 12
                                    gradient: Gradient {
                                        orientation: Gradient.Horizontal
                                        GradientStop { position: 0.0; color: parent.parent.enabled ? "#3B82F6" : "#CBD5E1" }
                                        GradientStop { position: 1.0; color: parent.parent.enabled ? "#1D4ED8" : "#94A3B8" }
                                    }
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: parent.enabled ? "#FFFFFF" : "#FFFFFF"
                                    font: parent.font
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }
                }
            }

    // ===== 白屏闪光动画效果 =====
    Rectangle {
        id: flashEffect
        anchors.fill: parent
        color: "white"
        opacity: 0.0
        z: 99 
        Behavior on opacity { NumberAnimation { duration: 150 } }
    }


    // ==========================================
    // 信号拦截区：处理后端事件
    // ==========================================
    // 自动称重触发已移除，AI 识别改为手动按钮触发

    Connections {
        target: CameraController
        function onPhotoSaved(cameraIndex, filePath) { 
            if (cameraIndex === 0) {
                flashEffect.opacity = 0.8
                fadeTimer.start()
                console.log("照片落盘:", filePath)
                root.currentImagePath = filePath

                // 手动保存：图片已落盘，立即写记录 + 上传（不等 AI）
                if (root.pendingManualSave) {
                    root.pendingManualSave = false
                    let w = root.pendingSaveWeight
                    let label = root.pendingSaveLabel
                    console.log(">> 图片保存完成，立即执行记录:", label, w.toFixed(2) + "kg")
                    // 清空当前选中，让 historyChanged 触发时自动选中刚写入的最新记录
                    root.currentDetailRecord = null
                    WeightHistoryService.addRecord(w, label, BackendAuth.currentUser, filePath, "", root.pendingSaveIngrId)
                    root.currentPrediction = PState.IDLE
                    root.currentImagePath = ""
                    root.currentIngrId = ""
                    root.pendingSaveIngrId = ""
                } else {
                    // 自动模式：照片已保存，独立触发 AI 识别（不阻塞保存管线）
                    CameraController.recognizeLastCapture()
                }
            }
        }
    }

    Connections {
        target: CameraController
        function onAiRecognitionCompleted(predictedLabel, imagePath, inferenceTimeMs) {
            console.log(">> QML收到AI分类结果:", predictedLabel)
            root.currentPrediction = predictedLabel
            root.currentImagePath = imagePath

            // AI 返回 emsCd，查 ingredients 缓存取 ingrId (上传用)
            var aiItem = UserIngredientService.findByEmsCd(predictedLabel)
            root.currentIngrId = (aiItem && aiItem["id"]) ? aiItem["id"] : ""
            
            if (inferenceTimeMs !== undefined) {
                root.lastInferenceTime = inferenceTimeMs + " ms"
            } else {
                root.lastInferenceTime = PState.NONE + " ms"
            }
            // 注意：手动保存的 addRecord 已在 onPhotoSaved 中立即执行
            // 此处仅更新 UI 品类显示，不再绑定保存/上传逻辑
        }
    }

    // === 上传结果反馈：全局 Toast ===
    // window 是 Main.qml 中 ApplicationWindow 的 id，QML 全局可见
    Connections {
        target: WeightHistoryService
        function onCloudSyncSuccess(localId) {
            console.log("[Toast] 上传成功 id=", localId)
            window.toast("保存成功", "success")
        }
        function onCloudSyncFailed(localId, errorMsg) {
            console.warn("[Toast] 上传失败 id=", localId, "err=", errorMsg)
            window.toast("保存失败：" + errorMsg, "error", 4000)
        }
        function onUserRecordCreated(success, msg) {
            window.toast(success ? "记录已创建" : "创建失败：" + msg,
                         success ? "info" : "error")
        }
    }

    // === 去皮结果反馈 ===
    Connections {
        target: WeightManager
        function onTareDone(ok) {
            if (ok) {
                window.toast("去皮成功", "success", 1500)
            } else {
                window.toast("去皮失败：请检查秤通信", "error", 3000)
            }
        }
    }

    Timer {
       id: fadeTimer
       interval: 100
       onTriggered: flashEffect.opacity = 0.0
    }

    // ==========================================
    //  品类选择弹窗（手动选择 + AI纠错 双模式）
    // ==========================================
    CategoryCorrectionDialog {
        id: correctionDialog

        // 绑定 root 属性到组件
        currentPrediction: root.currentPrediction
        currentImagePath: root.currentImagePath
        categorySelectMode: root.categorySelectMode

        // 监听组件发出的信号，更新 root
        onLabelConfirmed: function(newPred, ingrId) {
            root.currentPrediction = newPred
            if (ingrId) {
                root.currentIngrId = ingrId
            } else {
                // 纠错模式无 ingrId，按 emsCd/ingrCd 反查
                var item = UserIngredientService.findByEmsCd(newPred)
                root.currentIngrId = (item && item["id"]) ? item["id"] : ""
            }
        }
        onSelectModeToggled: function(mode) {
            root.categorySelectMode = mode
        }
    }

    // ==========================================
    //  称重记录详情查看弹窗
    // ==========================================
    Dialog {
        id: detailDialog
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        // 放大默认尺寸，确保所有内容完整可见
        width: Math.min(parent.width * 0.90, 1400)
        height: Math.min(parent.height * 0.90, 980)

        modal: true
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
                    onClicked: detailDialog.close()
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

            // ========== 图片区域 ==========
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

                Image {
                    id: detailImage
                    anchors.fill: parent
                    anchors.margins: 10
                    fillMode: Image.PreserveAspectFit
                    source: root.currentDetailRecord && root.currentDetailRecord.mainImagePath ? (root.currentDetailRecord.mainImagePath.startsWith("file://") ? root.currentDetailRecord.mainImagePath : "file://" + root.currentDetailRecord.mainImagePath) : ""
                    visible: source !== ""
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
                            text: root.currentDetailRecord ? root.currentDetailRecord.recordTime : "--"
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
                            text: root.currentDetailRecord ? root.currentDetailRecord.categoryName : "--"
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
                            text: root.currentDetailRecord ? (root.currentDetailRecord.weight ? root.currentDetailRecord.weight.toFixed(2) + " kg" : "--") : "--"
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
                                text: root.currentDetailRecord && root.currentDetailRecord.mainImagePath ? "已保存" : "无图片"
                                color: root.currentDetailRecord && root.currentDetailRecord.mainImagePath ? "#67C23A" : "#909399"
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
                        onClicked: detailDialog.close()
                    }
                }
            }
        }

        onClosed: {
            root.currentDetailRecord = null
        }
    }

    // ==========================================
    //  退出登录确认弹窗
    // ==========================================
    Dialog {
        id: logoutConfirmDialog
        title: "退出登录"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2
        width: 360
        height: 180
        modal: true
        standardButtons: Dialog.NoButton

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 20

            Text {
                text: "确定要退出当前账号吗？"
                font.pixelSize: 18
                color: "#1E293B"
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 30
                Layout.rightMargin: 30
                spacing: 16

                Rectangle {
                    width: 100; height: 38; radius: 8
                    color: cancelLogoutMouse.containsMouse ? "#F1F5F9" : "#FFFFFF"
                    border.color: "#D1D5DB"
                    border.width: 1

                    Text { anchors.centerIn: parent; text: "取消"; font.pixelSize: 15; color: "#64748B" }
                    MouseArea {
                        id: cancelLogoutMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: logoutConfirmDialog.close()
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 38; radius: 8
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#EF4444" }
                        GradientStop { position: 1.0; color: "#DC2626" }
                    }

                    Text { anchors.centerIn: parent; text: "退出登录"; font.pixelSize: 15; font.bold: true; color: "white" }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            logoutConfirmDialog.close()
                            window.appLogout()
                        }
                    }
                }
            }
        }
    }
}
