import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia
import QtQuick.Effects
import App.Backend 1.0
import SmartScale.Tools 1.0
import "../components"

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
    property bool aiRecognizing: false       // 是否正在执行 AI 识别（控制"识别"按钮 loading 状态）
    property bool currentAiDetected: false   // 当前品类是否由 AI 识别接口得出 (上传 aiDet 字段用)
    property bool pendingSaveAiDetected: false // 手动保存待写入的 aiDetected

    // ==========================================
    // 归零/去皮按钮防抖：冷却期内禁止重复点击
    // ==========================================
    property bool tareButtonLocked: false   // 冷却期锁定标志

    Timer {
        id: tareCooldownTimer
        interval: 1000  // 1 秒冷却期
        onTriggered: root.tareButtonLocked = false
    }

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

    // 清空食材卡片：保存完成（成功或失败）后重置所有食材相关状态
    function clearIngredientCard() {
        root.currentPrediction = PState.IDLE
        root.currentImagePath = ""
        root.currentIngrId = ""
        root.currentAiDetected = false
        root.pendingSaveIngrId = ""
        root.pendingSaveAiDetected = false
        root.currentDetailRecord = null
    }

    Component.onCompleted: _selectLatestRecord()

    // 历史记录变化时（首次加载/新增/刷新）若未选中任何记录，自动选中最新一条
    Connections {
        target: WeightHistoryService
        function onHistoryChanged() { _selectLatestRecord() }
    }

        // 主内容容器
        Item {
            id: mainCard
            anchors.fill: parent
            anchors.margins: 10

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
                    spacing: 24

                    // ========== 历史记录区块 ==========
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: parent.height * 0.42
                        color: "#FFFFFF"
                        radius: 30
                        border.color: "#33FFFFFF"
                        border.width: 10

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 20

                            // ---- 左侧：历史记录列表 ----
                            Rectangle {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 35
                                color: "#FFFFFF"
                                radius: 24

                                // 阴影面板：X/Y 0, Blur 50, Spread 0, Color #002A75 10%
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#002A75"
                                    shadowOpacity: 0.1
                                    shadowBlur: 1.0
                                    shadowHorizontalOffset: 0
                                    shadowVerticalOffset: 0
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 10

                                // 标题行：历史记录 + 更多>
                                RowLayout {
                                    Layout.fillWidth: true

                                    Row {
                                        spacing: 6
                                        Text {
                                            text: "历史记录"
                                            font.pixelSize: 28
                                            font.bold: true
                                            color: "#1E293B"
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "更多 >"
                                        font.pixelSize: 18
                                        color: "#3B82F6"
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            // [入口] 点击打开称重记录查询弹窗
                                            onClicked: searchDialog.open()
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
                                                    font.pixelSize: 16
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
                            }                       // inner ColumnLayout
                        }                           // 历史记录卡片 Rectangle

                            // ---- 右侧：水印图片预览 ----
                            Rectangle {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 35
                                color: "#FFFFFF"
                                radius: 24

                                // 阴影面板：与左侧历史记录卡片一致
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: "#002A75"
                                    shadowOpacity: 0.1
                                    shadowBlur: 1.0
                                    shadowHorizontalOffset: 0
                                    shadowVerticalOffset: 0
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 16
                                    spacing: 10

                                    // 标题行：水印预览（与左侧历史记录标题风格一致）
                                    Row {
                                        spacing: 6
                                        Text {
                                            text: "水印预览"
                                            font.pixelSize: 28
                                            font.bold: true
                                            color: "#1E293B"
                                        }
                                    }

                                    // 分隔线
                                    Rectangle {
                                        Layout.fillWidth: true
                                        height: 1
                                        color: "#E2E8F0"
                                    }

                                    Rectangle {
                                        id: watermarkPreview
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        color: "transparent"
                                        radius: 12
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
                        }                       // RowLayout
                    }                           // 外层容器

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

                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 10
                                    anchors.topMargin: 6
                                    spacing: 10

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
                                        
                                        Text { text: "操作员视角"; font.pixelSize: 15; font.bold: true; color: "#FFFFFF" }
                                    }
                                }

                                // 右下角状态指示
                                Row {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    spacing: 5
                                    Rectangle { width: 7; height: 7; radius: 3; color: "#F97316" }
                                    Text { text: "AUX"; font.pixelSize: 12; font.bold: true; color: "#78716C" }
                                }
                            }

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
                                //   边长: min(w,h) * 0.50, 中心: 水平50%, 垂直53%
                                Item {
                                    anchors.fill: parent
                                    clip: true
                                    Rectangle {
                                        id: guideBox
                                        width: Math.min(parent.width, parent.height) * 0.50
                                        height: width
                                        x: parent.width * 0.5 - width / 2
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
                                                text: "请将食材对准框内"
                                                font.pixelSize: 14
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
                                       
                                        Text { text: "食材拍摄"; font.pixelSize: 15; font.bold: true; color: "#FFFFFF" }
                                    }
                                }

                                // 右下角实时状态指示
                                Row {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: 8
                                    spacing: 5
                                    Rectangle { width: 8; height: 8; radius: 4; color: "#22C55E" }  // 绿点=在线
                                    Text { text: "LIVE"; font.pixelSize: 13; font.bold: true; color: "#22C55E" }
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
                        Layout.preferredHeight: 120
                        spacing: 14

                        // 圆形头像（优先显示远程头像，回退到首字母）
                        Rectangle {
                            width: 72; height: 72; radius: 36
                            color: avatarImage.status === Image.Ready ? "transparent" : "#3B82F6"
                            clip: true   // 裁剪子元素为圆形
                            visible: BackendAuth.avatarUrl || BackendAuth.currentUser

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: BackendAuth.avatarUrl || ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                cache: true
                            }

                            Text {
                                anchors.centerIn: parent
                                text: BackendAuth.currentUser ? BackendAuth.currentUser.charAt(0).toUpperCase() : "?"
                                font.pixelSize: 27
                                font.bold: true
                                color: "#FFFFFF"
                                // 有远程头像且加载成功时隐藏首字母
                                visible: avatarImage.status !== Image.Ready || !BackendAuth.avatarUrl
                            }
                        }

                        // 用户名称 + 岗位标签（用普通 Item 包裹，避免内部使用 anchors 时触发 Layout 警告）
                        // 外层 RowLayout 只管理这一个 Item 的布局，内部的 ColumnLayout + MouseArea 用 anchors 定位
                        Item {
                            Layout.preferredHeight: 120
                            implicitWidth: userInfoColumn.implicitWidth

                            ColumnLayout {
                                id: userInfoColumn
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 5

                                Text {
                                    text: BackendAuth.currentUser || "未登录"
                                    font.pixelSize: 35
                                    font.bold: true
                                    color: "#1E293B"
                                }

                            
                            }

                            // 点击区域覆盖整个用户信息区域（Item 不是 Layout，anchors 安全）
                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                hoverEnabled: true
                                onClicked: {
                                    if (BackendAuth.currentUser) {
                                        logoutConfirmDialog.open()
                                    } else {
                                        window.showLogin()
                                    }
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
                            spacing: 8

                            // ===== AI识别 + 选择食材按钮行 =====
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 76
                                spacing: 16

                                Item { Layout.fillWidth: true }

                                // ----- 按钮：识别（蓝色主按钮，专业商务风）-----
                                Rectangle {
                                    id: recognizeBtn
                                    width: 220
                                    height: 76
                                    radius: 12
                                    border.width: 1
                                    border.color: recognizeMA.containsMouse ? "#60A5FA" : "#1E40AF"
                                    opacity: root.aiRecognizing ? 0.75 : 1.0
                                    clip: false

                                    readonly property color topColor: "#3B82F6"
                                    readonly property color bottomColor: "#1D4ED8"

                                    Behavior on border.color { ColorAnimation { duration: 140 } }
                                    Behavior on opacity { NumberAnimation { duration: 150 } }

                                    transform: Translate {
                                        y: recognizeMA.containsMouse && !recognizeMA.pressed ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }

                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: recognizeBtn.topColor }
                                        GradientStop { position: 1.0; color: recognizeBtn.bottomColor }
                                    }

                                    // 顶部高光带（弧面反光）
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
                                    }

                                    // 底部暗影带
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
                                        opacity: recognizeMA.containsMouse ? 0.3 : 0.16
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }

                                    // 底部散光投影
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -3
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 14
                                        height: 6
                                        radius: 3
                                        color: "#1B263B"
                                        opacity: recognizeMA.containsMouse ? 0.18 : 0.10
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }

                                    Row {
                                        id: recognizeRow
                                        anchors.centerIn: parent
                                        spacing: 10

                                        BusyIndicator {
                                            id: recognizeSpinner
                                            running: root.aiRecognizing
                                            visible: root.aiRecognizing
                                            width: 30
                                            height: 30
                                            anchors.verticalCenter: parent.verticalCenter
                                            contentItem: Item {
                                                implicitWidth: 30
                                                implicitHeight: 30
                                                Canvas {
                                                    anchors.fill: parent
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.clearRect(0, 0, width, height)
                                                        ctx.strokeStyle = "#FFFFFF"
                                                        ctx.lineWidth = 3.5
                                                        ctx.lineCap = "round"
                                                        ctx.beginPath()
                                                        ctx.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 1.4)
                                                        ctx.stroke()
                                                    }
                                                    NumberAnimation on rotation {
                                                        from: 0; to: 360; duration: 800
                                                        loops: Animation.Infinite
                                                        running: root.aiRecognizing
                                                    }
                                                    Component.onCompleted: requestPaint()
                                                }
                                            }
                                        }

                                        Canvas {
                                            id: scanIcon
                                            width: 32
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: !root.aiRecognizing
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = "#FFFFFF"
                                                ctx.lineWidth = 2.5
                                                ctx.lineCap = "round"
                                                var s = 8
                                                ctx.beginPath(); ctx.moveTo(5, s); ctx.lineTo(5, 5); ctx.lineTo(s, 5); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(width - s, 5); ctx.lineTo(width - 5, 5); ctx.lineTo(width - 5, s); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(width - 5, height - s); ctx.lineTo(width - 5, height - 5); ctx.lineTo(width - s, height - 5); ctx.stroke()
                                                ctx.beginPath(); ctx.moveTo(s, height - 5); ctx.lineTo(5, height - 5); ctx.lineTo(5, height - s); ctx.stroke()
                                                ctx.beginPath()
                                                ctx.arc(width / 2, height / 2, 5, 0, Math.PI * 2)
                                                ctx.stroke()
                                            }
                                            Component.onCompleted: requestPaint()
                                        }

                                        Text {
                                            text: root.aiRecognizing ? "识别中..." : "AI识别"
                                            font.pixelSize: 36
                                            font.bold: true
                                            color: "#FFFFFF"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: recognizeMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            console.log("[WSP] 点击识别按钮，手动触发 AI 识别")
                                            // 登录拦截：未登录则中止识别并引导登录
                                            if (!BackendAuth.currentUser) {
                                                console.warn("[WSP] 未登录，拦截识别操作，弹出登录窗口")
                                                window.toast("请先登录后再识别", "warning", 2000)
                                                window.showLogin()
                                                return
                                            }
                                            if (WeightManager.netWeight <= 0.05) {
                                                window.toast("请先放置食材再识别", "warning", 2000)
                                                return
                                            }
                                            root.aiRecognizing = true
                                            aiRecognizeTimeout.restart()
                                            window.toast("AI 识别中...", "info", 1500)
                                            // AI-only 模式：仅拍照裁剪给 AI 用，不画水印不落盘
                                            CameraController.aiOnlyMode = true
                                            CameraController.captureVegetable(WeightManager.netWeight, root.currentPrediction)
                                        }
                                    }
                                }

                                // ----- 按钮：选择食材（绿色填充按钮，专业商务风）-----
                                Rectangle {
                                    id: selectFoodBtn
                                    width: 220
                                    height: 76
                                    radius: 12
                                    border.width: 1
                                    border.color: selectFoodMA.containsMouse ? "#4ADE80" : "#166534"
                                    clip: false

                                    readonly property color topColor: "#16A34A"
                                    readonly property color bottomColor: "#15803D"

                                    Behavior on border.color { ColorAnimation { duration: 140 } }

                                    transform: Translate {
                                        y: selectFoodMA.containsMouse && !selectFoodMA.pressed ? -2 : 0
                                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                    }

                                    gradient: Gradient {
                                        GradientStop { position: 0.0; color: selectFoodBtn.topColor }
                                        GradientStop { position: 1.0; color: selectFoodBtn.bottomColor }
                                    }

                                    // 顶部高光带（弧面反光）
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
                                    }

                                    // 底部暗影带
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 2
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 20
                                        height: 2
                                        radius: 1
                                        gradient: Gradient {
                                            orientation: Qt.Horizontal
                                            GradientStop { position: 0.0; color: Qt.rgba(0.024, 0.18, 0.11, 0) }
                                            GradientStop { position: 0.5; color: "#064E3B" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0.024, 0.18, 0.11, 0) }
                                        }
                                        opacity: selectFoodMA.containsMouse ? 0.3 : 0.16
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }

                                    // 底部散光投影
                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -3
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: parent.width - 14
                                        height: 6
                                        radius: 3
                                        color: "#064E3B"
                                        opacity: selectFoodMA.containsMouse ? 0.18 : 0.10
                                        Behavior on opacity { NumberAnimation { duration: 140 } }
                                    }

                                    Row {
                                        id: selectFoodRow
                                        anchors.centerIn: parent
                                        spacing: 10

                                        Canvas {
                                            id: foodIcon
                                            width: 32
                                            height: 32
                                            anchors.verticalCenter: parent.verticalCenter
                                            onPaint: {
                                                var ctx = getContext("2d")
                                                ctx.clearRect(0, 0, width, height)
                                                ctx.strokeStyle = "#FFFFFF"
                                                ctx.lineWidth = 2.5
                                                ctx.lineCap = "round"
                                                ctx.lineJoin = "round"
                                                ctx.beginPath()
                                                ctx.moveTo(16, 4)
                                                ctx.lineTo(4, 15)
                                                ctx.lineTo(8, 15)
                                                ctx.lineTo(8, 25)
                                                ctx.lineTo(24, 25)
                                                ctx.lineTo(24, 15)
                                                ctx.lineTo(28, 15)
                                                ctx.closePath()
                                                ctx.stroke()
                                                ctx.beginPath()
                                                ctx.moveTo(16, 19)
                                                ctx.quadraticCurveTo(11, 16, 16, 11)
                                                ctx.quadraticCurveTo(21, 16, 16, 19)
                                                ctx.fillStyle = "#FFFFFF"
                                                ctx.fill()
                                            }
                                            Component.onCompleted: requestPaint()
                                        }

                                        Text {
                                            text: "选择食材"
                                            font.pixelSize: 36
                                            font.bold: true
                                            color: "#FFFFFF"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }

                                    MouseArea {
                                        id: selectFoodMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            console.log("[WSP] 点击选择食材按钮，打开品类选择弹窗")
                                            // 拉取食材品类全量并写入本地缓存 (~/.cache/smartscale/ingr_categories.json)
                                            CategoryService.fetchIngrCategories()
                                            root.categorySelectMode = true
                                            correctionDialog.open()
                                        }
                                    }
                                }
                            }

                            // 名称卡片区域（含浮标标签）
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 220
                                Layout.minimumHeight: 180
                                Layout.topMargin: 2

                                // "食材名称" 浮标标签 — 定位在卡片左上角外侧
                                Text {
                                    id: categoryNameLabel
                                    anchors.left: parent.left
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: 6
                                    text: "食材名称"
                                    font.pixelSize: 28
                                    font.bold: true
                                    color: "#64748B"
                                }

                                Rectangle {
                                    id: categoryCard
                                    anchors.fill: parent
                                    radius: 12
                                    color: root.currentPrediction === PState.IDLE || root.currentPrediction === PState.NOT_READY
                                       ? "#F8FAFC" : "#EFF6FF"
                                    border.width: 0

                                    // 点击选择品类
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: {
                                            //console.log("打开品类选择...")
                                            //root.categorySelectMode = true
                                            //correctionDialog.open()
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
                                            id: ingredientNameText
                                            Layout.fillWidth: true
                                            horizontalAlignment: Text.AlignHCenter
                                            text: {
                                                var pred = root.currentPrediction;
                                                if (!PState.isValid(pred))
                                                    return PState.label(pred);
                                                var translated = Translator.translate(pred);
                                                // translate 未命中时返回原值，此时显示灰色 "--"
                                                return (translated === pred) ? "--" : translated;
                                            }
                                            font.pixelSize: 68
                                            font.bold: true
                                            color: {
                                                var pred = root.currentPrediction;
                                                if (!PState.isValid(pred)) return "#94A3B8";
                                                var translated = Translator.translate(pred);
                                                return (translated === pred) ? "#94A3B8" : "#1E40AF";
                                            }
                                        }                               
                                    }
                                } // categoryCard
                            }   // 名称卡片区域 Item


                            // 称重卡片区域（含浮标标签）
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 240
                                Layout.maximumHeight: 280
                                Layout.topMargin: 2

                                // "重量" 浮标标签 — 定位在卡片左上角外侧
                                Text {
                                    anchors.left: parent.left
                                    anchors.bottom: parent.top
                                    anchors.bottomMargin: 6
                                    text: "重量"
                                    font.pixelSize: 28
                                    font.bold: true
                                    color: "#64748B"
                                }

                                Rectangle {  // weightCard
                                    id: weightCard
                                    anchors.fill: parent
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
                                            font.pixelSize: 48
                                            font.bold: true
                                            color: "#FFFFFF"
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                } // weightCard
                            } // 称重卡片区域 Item

                           
                            
                        }
                    }

                    // ==================== 底部区（固定高度）：操作按钮（三等分）====================
                    // 底部安全间距：避免按钮贴底边，方便单手操作时轻松触摸
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        Layout.minimumHeight: 96
                        Layout.maximumHeight: 104
                        Layout.bottomMargin: 24  // 与屏幕底部保持安全距离，防止贴边
                        spacing: 16

                        // 归零按钮
                        ActionButton {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "归零"
                            enabled: !root.tareButtonLocked  // 冷却期禁用
                            onClicked: {
                                console.log("[WSP] 点击归零按钮")
                                if (WeightManager.netWeight > 8.0) {
                                    window.toast("无法归零", "error", 2000)
                                    return
                                }
                                // 启动冷却期，防止连击
                                root.tareButtonLocked = true
                                tareCooldownTimer.restart()
                                root.lastScaleOp = "zero"
                                WeightManager.zero()
                                window.toast("归零执行中...", "info", 1500)
                            }
                        }

                        // 去皮按钮
                        ActionButton {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "去皮"
                            enabled: !root.tareButtonLocked  // 冷却期禁用
                            onClicked: {
                                console.log("[WSP] 点击去皮按钮, 触发硬件去皮")
                                // 启动冷却期，防止连击
                                root.tareButtonLocked = true
                                tareCooldownTimer.restart()
                                root.lastScaleOp = "tare"
                                WeightManager.tare()
                                if (typeof window !== "undefined" && window.toast) {
                                    window.toast("去皮执行中...", "info", 1500)
                                }
                            }
                        }

                        // 保存按钮（蓝色主按钮）
                        ActionButton {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            text: "保存"
                            primary: true
                            onClicked: {
                                // 保存需要登录：未登录则弹登录窗口，中止本次保存
                                if (!BackendAuth.currentUser) {
                                    console.warn("[WSP] 未登录，拦截保存操作，弹出登录窗口")
                                    window.toast("请先登录后再保存", "warning", 2000)
                                    window.showLogin()
                                    return
                                }
                                let currentWeight = WeightManager.netWeight
                                if (currentWeight <= 0.01) {
                                    console.warn("重量不足，无法提交记录")
                                    window.toast("重量不足，无法保存", "warning", 2000)
                                    return
                                }
                                // 品类校验：必须先识别成功或手动选择有效食材
                                if (!PState.isValid(root.currentPrediction)) {
                                    console.warn("[WSP] 品类无效，拦截保存:", root.currentPrediction)
                                    window.toast("请先识别或选择食材", "warning", 2500)
                                    return
                                }
                                // ingrId 校验：雪花 ID 必须有效，否则上传会落库孤儿记录
                                if (!root.currentIngrId || root.currentIngrId === "") {
                                    console.warn("[WSP] ingrId 为空，拦截保存, prediction=", root.currentPrediction)
                                    window.toast("食材数据异常，请重新选择", "warning", 2500)
                                    return
                                }
                                let chineseLabel = Translator.translate(root.currentPrediction)
                                console.log(">> 手动保存，触发拍照:", chineseLabel, currentWeight.toFixed(2) + "kg",
                                            "ingrId=", root.currentIngrId)
                                root.pendingManualSave = true
                                root.pendingSaveWeight = currentWeight
                                root.pendingSaveLabel = chineseLabel
                                root.pendingSaveIngrId = root.currentIngrId
                                root.pendingSaveAiDetected = root.currentAiDetected
                                // 传入当前已知品类标签，水印立即绘制，保存/上传独立执行
                                CameraController.captureVegetable(currentWeight, root.currentPrediction)
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
                    WeightHistoryService.addRecord(w, label, BackendAuth.currentUser, filePath, "", root.pendingSaveIngrId, root.pendingSaveAiDetected)
                    clearIngredientCard()
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

            // 识别失败（unknown/idle 等无效结果）：清空残留 ingrId，避免脏数据被保存误用
            if (!PState.isValid(predictedLabel)) {
                console.warn("[WSP] AI 识别结果无效，清空 currentIngrId, label=", predictedLabel)
                root.currentIngrId = ""
                root.currentAiDetected = false
            } else {
                // AI 返回 emsCd，查 ingredients 缓存取 ingrId (上传用)
                var aiItem = UserIngredientService.findByEmsCd(predictedLabel)
                if (aiItem && aiItem["id"]) {
                    root.currentIngrId = aiItem["id"]
                    // 品类由 AI 识别接口直接得出，标记 aiDetected=true
                    root.currentAiDetected = true
                    console.log("[WSP] 食材反查成功, emsCd=", predictedLabel,
                                "ingrId=", root.currentIngrId,
                                "ingrNm=", aiItem["cn"] ? aiItem["cn"] : "",
                                "aiDetected=true")
                } else {
                    console.warn("[WSP] 食材库未匹配到 emsCd=", predictedLabel, "currentIngrId 置空")
                    root.currentIngrId = ""
                    root.currentAiDetected = false
                }
            }
            
            if (inferenceTimeMs !== undefined) {
                root.lastInferenceTime = inferenceTimeMs + " ms"
            } else {
                root.lastInferenceTime = PState.NONE + " ms"
            }
            // 注意：手动保存的 addRecord 已在 onPhotoSaved 中立即执行
            // 此处仅更新 UI 品类显示，不再绑定保存/上传逻辑

            // 手动"识别"按钮触发的流程完成：恢复按钮状态并反馈结果
            if (root.aiRecognizing) {
                root.aiRecognizing = false
                aiRecognizeTimeout.stop()
                // 恢复非 AI-only 模式（下次保存时需要画水印）
                CameraController.aiOnlyMode = false

                var chineseLabel = Translator.translate(predictedLabel)
                if (PState.isValid(predictedLabel)) {
                    window.toast("识别完成：" + chineseLabel, "success", 2000)
                } else {
                    // 区分错误类型弹 alert（网络错误 vs 业务错误）
                    var errMsg = CameraController.lastAiError || "未能识别出食材"
                    var isNetworkErr = errMsg.indexOf("网络") >= 0 || errMsg.indexOf("HTTP") >= 0 || errMsg.indexOf("未登录") >= 0
                    window.alert(errMsg, isNetworkErr ? "error" : "warning", "AI识别失败")
                }
            }
        }
    }

    // === 上传结果反馈：全局 Toast ===
    // window 是 Main.qml 中 ApplicationWindow 的 id，QML 全局可见
    Connections {
        target: WeightHistoryService
        function onCloudSyncSuccess(localId) {
            console.log("[Toast] 上传成功 id=", localId)
            window.toast("保存成功", "success")
            VoiceSpeaker.speak("已保存")
            clearIngredientCard()
        }
        function onCloudSyncFailed(localId, errorMsg) {
            console.warn("[Alert] 上传失败 id=", localId, "err=", errorMsg)
            window.alert("保存失败：" + errorMsg, "error", "云端同步失败", errorMsg)
            clearIngredientCard()
        }
        function onUserRecordCreated(success, msg) {
            if (success) {
                window.toast("记录已创建", "info")
            } else {
                console.warn("[Alert] 创建记录失败:", msg)
                window.alert("创建记录失败：" + msg, "error", "保存失败")
            }
        }
    }

    // === 去皮结果反馈 ===
    Connections {
        target: WeightManager
        function onTareDone(ok) {
            if (ok) {
                window.toast(root.lastScaleOp === "zero" ? "归零成功" : "去皮成功", "success", 1500)
            } else {
                window.toast(root.lastScaleOp === "zero" ? "归零失败" : "去皮失败：请检查秤通信", "error", 3000)
            }
        }
    }

    property string lastScaleOp: ""  // 记录最近一次操作: "zero" | "tare"

    Timer {
       id: fadeTimer
       interval: 100
       onTriggered: flashEffect.opacity = 0.0
    }

    // 识别超时保护：若 15 秒内未收到 onAiRecognitionCompleted 回调，
    // 自动重置 aiRecognizing 状态，防止按钮永久卡在 loading
    Timer {
        id: aiRecognizeTimeout
        interval: 15000
        repeat: false
        onTriggered: {
            if (root.aiRecognizing) {
                console.warn("[WSP] AI 识别超时（15s），自动重置状态")
                root.aiRecognizing = false
                CameraController.aiOnlyMode = false
                window.alert("AI 识别超时（15秒无响应）", "warning", "识别超时")
            }
        }
    }

    // ==========================================
    //  品类选择弹窗（手动选择 + AI纠错 双模式）
    // ==========================================

    // 品类弹窗外部遮罩（替代 modal:true，避免 Qt 内部 modal 层遮挡虚拟键盘）
    // z 低于 correctionDialog(50)，远低于 window 级 inputPanel(99)
    Rectangle {
        id: categoryOverlay
        anchors.fill: parent
        color: "#000000"
        opacity: correctionDialog.visible ? 0.5 : 0
        visible: opacity > 0
        z: 40

        Behavior on opacity { NumberAnimation { duration: 200 } }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                // 点击遮罩不关闭弹窗（与 LoginDialog 行为一致，提示用户操作）
            }
        }
    }


    // 食材选择界面
    CategoryCorrectionDialog {
        id: correctionDialog

        // 绑定 root 属性到组件
        currentPrediction: root.currentPrediction
        currentImagePath: root.currentImagePath
        categorySelectMode: root.categorySelectMode

        // 监听组件发出的信号，更新 root
        onLabelConfirmed: function(newPred, ingrId) {
            root.currentPrediction = newPred
            // 人工选择/纠错：品类非 AI 接口直接得出，aiDetected=false
            root.currentAiDetected = false
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
    //  称重记录详情弹窗（独立组件）
    // ==========================================
    RecordDetailDialog {
        id: detailDialog
        record: root.currentDetailRecord
        // 传入完整记录列表，供弹窗内左右滑动/箭头切换上下记录
        recordList: WeightHistoryService ? WeightHistoryService.historyEntries : []
        // 收到导航信号：切换 currentDetailRecord，详情内容随之刷新
        onNavigateToRecord: function(index) {
            if (index >= 0 && index < recordList.length) {
                root.currentDetailRecord = recordList[index]
            }
        }
        onClosed: root.currentDetailRecord = null
    }

    // ==========================================
    //  称重记录搜索弹窗（独立组件）
    // ==========================================
    // 入口：历史记录区域右上角"更多 >"按钮 (searchDialog.open())
    // 点击卡片"查看"时将记录传给详情弹窗展示大图
    WeightRecordSearchDialog {
        id: searchDialog
        onViewRecord: function(record) {
            // 用户点击搜索结果卡片的"查看"，选中该记录并打开详情弹窗
            root.currentDetailRecord = record
            detailDialog.open()
        }
    }

    // ==========================================
    //  退出登录确认弹窗（独立组件）
    // ==========================================
    LogoutConfirmDialog {
        id: logoutConfirmDialog
        onLogoutConfirmed: window.appLogout()
    }
}
