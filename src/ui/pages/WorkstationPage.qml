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
    property bool savingInProgress: false     // 保存流程进行中（防抖：阻止保存按钮狂按重复触发拍照）
    property double pendingSaveWeight: 0
    property string pendingSaveLabel: ""
    property string currentIngrId: ""        // 当前选中食材的 ingrId (上传用)
    property string pendingSaveIngrId: ""    // 手动保存待写入的 ingrId
    property bool aiRecognizing: false       // 是否正在执行 AI 识别（控制"识别"按钮 loading 状态）
    property bool currentAiDetected: false   // 当前品类是否由 AI 识别接口得出 (上传 aiDet 字段用)
    property bool pendingSaveAiDetected: false // 手动保存待写入的 aiDetected
    property double pendingUnitPrice: 0         // 手动保存待写入的单价（元/kg，与 addRecord/DB/上传约定一致）
    property real currentUnitPrice: 0           // 食材卡片当前输入的单价（元/kg），保存后清空
    readonly property real currentAmount: currentUnitPrice * (Math.round(WeightManager.netWeight * 100) / 100)   // 金额（元）= 单价×四舍五入2位净重（与显示重量一致）
    property var aiCandidates: CameraController.aiCandidateList  // AI 识别候选列表

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
        root.currentUnitPrice = 0   // 清空食材卡片单价（金额随绑定自动归零）
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
            //anchors.margins: 10

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 44
                anchors.rightMargin: 44
                //anchors.bottomMargin: 70

                // ================================================================
                // 左侧区域 (60%) — 历史记录列表 + 蔬菜拍摄区域
                // ================================================================
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width * 0.62
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

                                // 标题行：历史记录 + 表格 + 更多>
                                RowLayout {
                                    Layout.fillWidth: true

                                    Row {
                                        spacing: 16
                                        Text {
                                            text: "历史记录"
                                            font.pixelSize: 28
                                            font.bold: true
                                            color: "#1E293B"
                                        }

                                        Text {
                                            text: "表格"
                                            font.pixelSize: 24
                                            color: "#6366F1"
                                            MouseArea {
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                // [入口] 点击打开称重记录表格弹窗
                                                onClicked: tableDialog.open()
                                            }
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: "更多 >"
                                        font.pixelSize: 24
                                        color: "#3B82F6"
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
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
                        color: "#FFFFFF"
                        radius: 30
                        border.color: "#33FFFFFF"
                        border.width: 10

                        // 阴影面板：与历史记录区块一致
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: "#002A75"
                            shadowOpacity: 0.1
                            shadowBlur: 1.0
                            shadowHorizontalOffset: 0
                            shadowVerticalOffset: 0
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 20
                            spacing: 20

                            // ========== 左侧卡片：操作人员拍摄区域 ==========
                            Rectangle {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 35
                                color: "#FFFFFF"
                                radius: 24

                                // 阴影面板
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

                                    // 标题行：操作人员拍摄区域
                                    Row {
                                        spacing: 6
                                        Text {
                                            text: "操作人员拍摄区域"
                                            font.pixelSize: 28
                                            font.bold: true
                                            color: "#1E293B"
                                        }
                                    }

                                    // 副摄像头视频区 — 暖灰主题（辅助观察区）
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 20
                                        color: "#F1F0EF"
                                        border.color: "#D6D3D1"
                                        border.width: 2
                                        clip: true

                                        VideoOutput {
                                            id: subVideo
                                            anchors.fill: parent
                                            fillMode: VideoOutput.PreserveAspectCrop
                                            Component.onCompleted: {
                                                CameraController.setSubVideoSink(subVideo.videoSink)
                                            }
                                        }
                                    }
                                }
                            }

                            // ========== 右侧卡片：食材拍摄区域 ==========
                            Rectangle {
                                Layout.fillHeight: true
                                Layout.fillWidth: true
                                Layout.preferredWidth: 65
                                color: "#FFFFFF"
                                radius: 24

                                // 阴影面板
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

                                    // 标题行：食材拍摄区域
                                    Row {
                                        spacing: 6
                                        Text {
                                            text: "食材拍摄区域"
                                            font.pixelSize: 28
                                            font.bold: true
                                            color: "#1E293B"
                                        }
                                    }


                                    // 主摄像头视频区 — 蓝调主题（核心工作区）
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: 20
                                        color: "#DBEAFE"
                                        border.color: "#93C5FD"
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
                                    }
                                }
                            }
                        }                       // RowLayout (左右两卡片)
                    }                           // 外层容器
                }                               // ColumnLayout (左侧60%)

                // ================================================================
                // 右侧区域 (40%) — 自然流式布局（顶部紧凑/中部弹性/底部固定）
                // ================================================================
                // ============ 右侧区域 (40%) — 白底卡片（与历史记录区块同款） ============
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: parent.width * 0.38
                    color: "#FFFFFF"
                    radius: 30
                    border.color: "#33FFFFFF"
                    border.width: 10

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 44
                        spacing: 24


                    // ==================== 中部区（弹性）：称重 + 物品名称 ====================
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            

                            // 名称卡片区域（含浮标标签）
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 227
                                Layout.minimumHeight: 180
                                Layout.topMargin: 2

                                Rectangle {
                                    id: categoryCard
                                    anchors.fill: parent
                                    radius: 24
                                    color: "#195DD9"
                                    border.color: "#195DD9"
                                    border.width: 10

                                    // 点卡片任意空白处都能打开品类选择弹窗（与下方"选择食材"按钮功能一致）
                                    MouseArea {
                                        id: categoryCardMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        z: -1   // 置于 RowLayout 内容之下，避免拦截 RowLayout 内部交互
                                        onClicked: {
                                            CategoryService.fetchIngrCategories()
                                            root.categorySelectMode = true
                                            correctionDialog.recommendCandidates = root.aiCandidates
                                            //correctionDialog.open()
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 0
                                        spacing: 0

                                        // ===== 左侧：食材标签 + 食材名（价格开启时固定 180，价格关闭时撑满整卡）=====
                                        Item {
                                            Layout.preferredWidth: AppSettings.priceInputEnabled ? 350 : 0
                                            Layout.fillWidth: !AppSettings.priceInputEnabled
                                            Layout.fillHeight: true

                                            // 左上角"食材"标签
                                            Text {
                                                text: "食材"
                                                font.pixelSize: 28
                                                font.family: "PingFang SC"
                                                font.bold: true
                                                color: "#FFFFFF"
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.leftMargin: 24
                                                anchors.topMargin: 20
                                            }

                                            // 食材名（垂直居中）
                                            Text {
                                                id: ingredientNameText
                                                anchors.fill: parent
                                                anchors.leftMargin: 24
                                                anchors.rightMargin: 24
                                                anchors.topMargin: 64
                                                anchors.bottomMargin: 20
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                                text: {
                                                    var pred = root.currentPrediction;
                                                    if (!PState.isValid(pred))
                                                        return PState.label(pred);
                                                    var translated = Translator.translate(pred);
                                                    return (translated === pred) ? "--" : translated;
                                                }
                                                font.pixelSize: AppSettings.priceInputEnabled ? 40 : 68
                                                font.bold: true
                                                color: "#FFFFFF"
                                                elide: Text.ElideRight
                                            }
                                        }

                                        // ===== 竖直分隔线（仅价格输入开启时显示）=====
                                        Rectangle {
                                            Layout.preferredWidth: 1
                                            Layout.fillHeight: true
                                            Layout.topMargin: 24
                                            Layout.bottomMargin: 24
                                            color: "#FFFFFF"
                                            visible: AppSettings.priceInputEnabled
                                        }

                                        // ===== 右侧：单价 + 金额 两段式（与左侧固定 180 对称）=====
                                        ColumnLayout {
                                            Layout.preferredWidth: 240
                                            Layout.fillWidth: true
                                            Layout.maximumWidth: 220
                                            Layout.fillHeight: true
                                            Layout.leftMargin: 14
                                            Layout.rightMargin: 14
                                            Layout.topMargin: 20
                                            Layout.bottomMargin: 20
                                            spacing: 6
                                            visible: AppSettings.priceInputEnabled

                                            // ---- 单价标签 ----
                                            Text {
                                                text: "单价（元/kg）"
                                                font.pixelSize: 18
                                                font.bold:true
                                                font.family: "PingFang SC"
                                                color: "#FFFFFF"
                                            }

                                            // ---- 单价输入框（点击弹出9宫格键盘）----
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 64
                                                radius: 12
                                                color: priceMA.pressed ? "#FFFFF" : "transparent"
                                                border.color: "#FFFFFF"
                                                border.width: 2
                                                Behavior on color { ColorAnimation { duration: 120 } }

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 16
                                                    anchors.rightMargin: 16
                                                    spacing: 8

                                                    Text {
                                                        Layout.alignment: Qt.AlignVCenter
                                                        text: root.currentUnitPrice > 0
                                                              ? root.currentUnitPrice.toFixed(2)
                                                              : "—"
                                                        font.pixelSize: 36
                                                        font.bold: true
                                                        font.family: "PingFang SC"
                                                        color: "#FFFFFF"
                                                    }
                                                    
                                                }

                                                MouseArea {
                                                    id: priceMA
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    onClicked: numberPad.openPad(root.currentUnitPrice)
                                                }
                                            }

                                            // ---- 水平分隔线 ----
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 1
                                                Layout.topMargin: 4
                                                Layout.bottomMargin: 4
                                                color: "#FFFFFF"
                                            }

                                            // ---- 金额标签 ----
                                            Text {
                                                text: "金额（元）"
                                                font.pixelSize: 18
                                                font.family: "PingFang SC"
                                                color: "#FFFFFF"
                                            }
                                           
                                            // ---- 金额大显示区（深色半透明背景）----
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                radius: 12
                                                color: "#00000033"           // 深色半透明背景（与设计稿一致）

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.currentAmount > 0
                                                          ? root.currentAmount.toFixed(2)
                                                          : "—"
                                                    font.pixelSize: 42
                                                    font.bold: true
                                                    font.family: "PingFang SC"
                                                    color: "#FFFFFF"
                                                }
                                            }
                                        }
                                    }
                                } // categoryCard
                            }   // 名称卡片区域 Item
                            // ===== AI识别 + 选择食材按钮行 =====
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 99
                                spacing: 16
                                Layout.alignment: Qt.AlignHCenter

                                // ----- 按钮：AI辅助识别 -----
                                Rectangle {
                                    id: recognizeBtn
                                    width: 283
                                    height: 99
                                    radius: 20
                                    clip: true

                                    color: "transparent"

                                    Image {
                                        anchors.fill: parent
                                        source: "qrc:/resources/img/ai.png"
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    Row {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 103
                                        spacing: 10

                                        BusyIndicator {
                                            id: recognizeSpinner
                                            running: root.aiRecognizing
                                            visible: root.aiRecognizing
                                            width: 32
                                            height: 32
                                            contentItem: Item {
                                                implicitWidth: 32; implicitHeight: 32
                                                Canvas {
                                                    anchors.fill: parent
                                                    onPaint: {
                                                        var ctx = getContext("2d")
                                                        ctx.clearRect(0, 0, width, height)
                                                        ctx.strokeStyle = "#6366F1"
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

                                        Text {
                                            text: root.aiRecognizing ? "识别中..." : "智能识别"
                                            font.pixelSize: 30
                                            font.bold: true
                                            font.family: "PingFang SC"
                                            color: "#4338CA"
                                            visible: !root.aiRecognizing
                                        }
                                        Text {
                                            text: "识别中..."
                                            font.pixelSize: 30
                                            font.bold: true
                                            font.family: "PingFang SC"
                                            color: "#4338CA"
                                            visible: root.aiRecognizing
                                        }
                                    }

                                    MouseArea {
                                        id: recognizeMA
                                        anchors.fill: parent
                                        onClicked: {
                                            // 防抖：识别进行中忽略重复点击，避免狂按触发多次拍照
                                            // 导致工作线程写 cp0.jpg 与主线程读 cp0.jpg 竞争崩溃
                                            if (root.aiRecognizing) {
                                                console.log("[WSP] AI 识别进行中，忽略重复点击")
                                                return
                                            }
                                            console.log("[WSP] 点击识别按钮，手动触发 AI 识别")
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
                                            aiLoadingOverlay.open()
                                            CameraController.aiOnlyMode = true
                                            CameraController.captureVegetable(WeightManager.netWeight, root.currentPrediction)
                                        }
                                    }
                                }

                                // ----- 按钮：选择食材 -----
                                Rectangle {
                                    id: selectFoodBtn
                                    width: 283
                                    height: 99
                                    radius: 20
                                    clip: true
                                    color: "transparent"

                                    Image {
                                        anchors.fill: parent
                                        source: "qrc:/resources/img/ingr.png"
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.left: parent.left
                                        anchors.leftMargin: 114
                                        text: "选择食材"
                                        font.pixelSize: 30
                                        font.bold: true
                                        font.family: "PingFang SC"
                                        color: "#166534"
                                    }

                                    MouseArea {
                                        id: selectFoodMA
                                        anchors.fill: parent
                                        onClicked: {
                                            console.log("[WSP] 点击选择食材按钮，打开品类选择弹窗")
                                            CategoryService.fetchIngrCategories()
                                            root.categorySelectMode = true
                                            correctionDialog.recommendCandidates = root.aiCandidates
                                            correctionDialog.open()
                                        }
                                    }
                                }
                            }

                            // 称重卡片区域（含浮标标签）
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 227
                                Layout.maximumHeight: 227
                                Layout.topMargin: 2

                               

                                Rectangle {  // weightCard
                                    id: weightCard
                                    anchors.fill: parent
                                    radius: 24
                                    color: "#195DD9"

                                    // 左上角标签
                                    Text {
                                        id: weightLabel
                                        text: "重量"
                                        font.pixelSize: 28
                                        font.family: "PingFang SC"
                                        font.bold: true
                                        color: "#FFFFFF"
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.leftMargin: 24
                                        anchors.topMargin: 20
                                    }

                                    // 居中重量数值
                                    Row {
                                        anchors.centerIn: parent
                                        Text {
                                            text: WeightManager.netWeight.toFixed(2)
                                            font.pixelSize: 100
                                            font.bold: true
                                            color: "#FFFFFF"
                                            font.family: "DIN"
                                        }
                                    }

                                    // 单位显示在容器右侧
                                    Text {
                                        text: "kg"
                                        font.pixelSize: 48
                                        font.bold: true
                                        color: "#FFFFFF"
                                        anchors.right: parent.right
                                        anchors.rightMargin: 24
                                        anchors.verticalCenter: parent.verticalCenter
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
                        Layout.minimumHeight: 192
                        Layout.maximumHeight: 192
                        //Layout.bottomMargin: 24  // 与屏幕底部保持安全距离，防止贴边
                        spacing: 16

                        // 归零按钮
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: root.tareButtonLocked ? "#CCCCCC" : "#FE9819"
                            radius: 24

                            Text {
                                anchors.centerIn: parent
                                text: "归零"
                                color: "#FFFFFF"
                                font.pixelSize: 50
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.tareButtonLocked
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
                        }

                        // 去皮按钮
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: root.tareButtonLocked ? "#CCCCCC" : "#0DC218"
                            radius: 24

                            Text {
                                anchors.centerIn: parent
                                text: "去皮"
                                color: "#FFFFFF"
                                font.pixelSize: 50
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !root.tareButtonLocked
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
                        }

                        // 保存按钮
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            color: "#D42D0B"
                            radius: 24

                            Text {
                                anchors.centerIn: parent
                                text: "保存"
                                color: "#FFFFFF"
                                font.pixelSize: 50
                                font.bold: true
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    // 防抖：保存流程进行中忽略重复点击，避免狂按触发多次拍照
                                    // 导致 CaptureTask 堆积产出大量 WLC200A 水印照片
                                    if (root.savingInProgress) {
                                        console.log("[WSP] 保存流程进行中，忽略重复点击")
                                        return
                                    }
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
                                    // 称重稳定性校验：硬件 status word Bit0，未稳定时禁止保存
                                    if (!WeightManager.isStable) {
                                        console.warn("[WSP] 称重未稳定，拦截保存, netWeight=", currentWeight)
                                        window.toast("称重未稳定，请稍候", "warning", 2500)
                                        return
                                    }
                                    // ingrId 校验：雪花 ID 必须有效，否则上传会落库孤儿记录
                                    if (!root.currentIngrId || root.currentIngrId === "") {
                                        console.warn("[WSP] ingrId 为空，拦截保存, prediction=", root.currentPrediction)
                                        window.toast("食材数据异常，请重新选择", "warning", 2500)
                                        return
                                    }
                                    let chineseLabel = Translator.translate(root.currentPrediction)
                                    // 缓存待保存数据（等弹窗确认后再用）
                                    root.pendingSaveWeight = currentWeight
                                    root.pendingSaveLabel = chineseLabel
                                    root.pendingSaveIngrId = root.currentIngrId
                                    root.pendingSaveAiDetected = root.currentAiDetected
                                    // 校验全部通过，锁定保存流程（覆盖重复弹窗等待 + 拍照 + 上传全周期）
                                    root.savingInProgress = true
                                    // 检测重复称重：有重复弹窗提醒，无重复直接保存
                                    var dupInfo = WeightHistoryService.checkDuplicate(chineseLabel, currentWeight)
                                    if (dupInfo && dupInfo["duplicate"] === true) {
                                        duplicateWeightDialog.openDialog(dupInfo)
                                    } else {
                                        root._executeSave()
                                    }
                                }
                            }
                        }
                    }
                    }
                }
            }
        }

    // ==========================================
    //  执行保存（无重复直接调用 / 重复弹窗确认后调用）
    // ==========================================
    function _executeSave() {
        console.log("[SAVE-TIMER]", Qt.formatDateTime(new Date(), "HH:mm:ss.zzz"), "| ①_executeSave 开始")
        console.log(">> 执行保存，重量:", root.pendingSaveWeight, "食材:", root.pendingSaveLabel)
        root.pendingUnitPrice = root.currentUnitPrice   // 读取食材卡片输入的单价（元/kg）
        root.pendingManualSave = true
        saveLoadingOverlay.open()
        CameraController.captureVegetable(root.pendingSaveWeight, root.currentPrediction)
        // 启动保存超时兜底：覆盖拍照+上传全程，防止相机异常/网络无响应导致永久卡死
        saveTimeout.restart()
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
                    saveTimeout.stop()   // 拍照已完成，进入上传阶段（由 onCloudSyncFailed 兜底）
                    console.log("[SAVE-TIMER]", Qt.formatDateTime(new Date(), "HH:mm:ss.zzz"), "| ⑤b QML收到photoSaved")
                    let w = root.pendingSaveWeight
                    let label = root.pendingSaveLabel
                    let up = root.pendingUnitPrice
                    console.log(">> 图片保存完成，立即执行记录:", label, w.toFixed(2) + "kg", "单价:", up)
                    // 清空当前选中，让 historyChanged 触发时自动选中刚写入的最新记录
                    root.currentDetailRecord = null
                    WeightHistoryService.addRecord(w, label, BackendAuth.currentUser, filePath, "", root.pendingSaveIngrId, root.pendingSaveAiDetected, up)   // 元/kg（与 addRecord/DB/上传约定一致）
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
                aiLoadingOverlay.close()
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
            console.log("[SAVE-TIMER]", Qt.formatDateTime(new Date(), "HH:mm:ss.zzz"), "| ⑩ QML收到cloudSyncSuccess 关overlay")
            console.log("[Toast] 上传成功 id=", localId)
            root.savingInProgress = false
            saveLoadingOverlay.close()
            saveTimeout.stop()
            saveSuccessDialog.openDialog()
            clearIngredientCard()
        }
        function onCloudSyncFailed(localId, errorMsg) {
            console.warn("[Alert] 上传失败 id=", localId, "err=", errorMsg)
            root.savingInProgress = false
            saveTimeout.stop()
            // 方案A：overlay 已在 cloudSyncSuccess(DB写入) 关闭；上传失败用 toast 非阻塞提示
            window.toast("记录已保存，云端同步失败将自动重试", "warning", 3000)
        }
        function onUserRecordCreated(success, msg) {
            if (success) {
                window.toast("记录已创建", "info")
            } else {
                console.warn("[Alert] 创建记录失败:", msg)
                root.savingInProgress = false
                saveLoadingOverlay.close()
                saveTimeout.stop()
                window.alert("创建记录失败：" + msg, "error", "保存失败")
            }
        }
    }

    // === 去皮结果反馈 ===
    Connections {
        target: WeightManager
        function onTareDone(ok) {
            // 成功不弹 toast（静默），仅失败时提醒
            if (!ok) {
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
                aiLoadingOverlay.close()
                CameraController.aiOnlyMode = false
                window.alert("AI 识别超时（15秒无响应）", "warning", "识别超时")
            }
        }
    }

    // 保存超时兜底：10秒内未完成拍照则自动重置状态，
    // 防止相机异常（重启中 captureVegetable 直接 return 不发 photoSaved）
    // 导致 savingInProgress + saveLoadingOverlay 永久卡死。
    // 仅覆盖拍照阶段（onPhotoSaved 收到即停止）；上传阶段由 onCloudSyncFailed 兜底。
    Timer {
        id: saveTimeout
        interval: 10000
        repeat: false
        onTriggered: {
            if (root.savingInProgress) {
                console.warn("[WSP] 保存超时（10s），自动重置状态")
                root.savingInProgress = false
                root.pendingManualSave = false
                saveLoadingOverlay.close()
                window.alert("保存超时（10秒无响应），请重试", "warning", "保存超时")
            }
        }
    }

    // ==========================================
    //  品类选择弹窗（手动选择 + AI纠错 双模式）
    // ==========================================

    // 品类弹窗外部遮罩（替代 modal:true，避免 Qt 内部 modal 层遮挡虚拟键盘）
    // parent 提升到窗口 contentItem：撑满整窗，覆盖顶部 StatusBar 与底部 BottomStatusBar
    // （原 anchors.fill: parent 仅覆盖 StackView 区域，盖不到状态栏）
    // z:40 < 键盘(99)，不遮挡虚拟键盘；correctionDialog 浮于 overlay 层，在遮罩之上
    Rectangle {
        id: categoryOverlay
        parent: window.contentItem
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
    //  称重记录表格弹窗（独立组件，云端分页）
    // ==========================================
    // 入口：历史记录区域右上角"表格"按钮 (tableDialog.open())
    WeightRecordTableDialog {
        id: tableDialog
    }

    // ==========================================
    //  重复称重提醒弹窗（取消=拦截保存，确认=继续保存）
    // ==========================================
    DuplicateWeightDialog {
        id: duplicateWeightDialog

        onConfirmed: {
            console.log(">> 用户确认重复保存，继续执行")
            root._executeSave()
        }
        onCancelled: {
            console.log(">> 用户取消保存（重复称重）")
            root.savingInProgress = false
        }
    }

    // ==========================================
    //  保存中全屏遮罩 Loading
    // ==========================================
    SaveLoadingOverlay {
        id: saveLoadingOverlay
    }

    // AI 识别中全屏遮罩 Loading（复用 SaveLoadingOverlay，文案"识别中..."）
    SaveLoadingOverlay {
        id: aiLoadingOverlay
        loadingText: "识别中..."
    }

    // ==========================================
    //  保存成功全屏遮罩弹窗
    // ==========================================
    SaveSuccessDialog {
        id: saveSuccessDialog
    }

    // ==========================================
    //  底部9宫格数字键盘（单价输入用）
    // ==========================================
    NumberPadPopup {
        id: numberPad
        onConfirmed: function(value) {
            root.currentUnitPrice = value
            console.log("[WSP] 单价输入完成:", value, "金额:", root.currentAmount.toFixed(2))
        }
    }

}
