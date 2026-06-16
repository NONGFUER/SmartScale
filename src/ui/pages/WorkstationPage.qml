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
    
    // 推理耗时相关属性
    property string lastInferenceTime: PState.NONE + " ms"

    // ===== 外层：蓝色渐变底色 =====
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#2B7DE9" }
            GradientStop { position: 1.0; color: "#5BA8F5" }
        }

        // ===== 内层：白色圆角主卡片 =====
        Rectangle {
            id: mainCard
            anchors.fill: parent
            anchors.margins: 16
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
                                        text: "\uD83D\uDCCB"
                                        font.pixelSize: 18
                                    }
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
                                        cursorShape: Qt.PointingHandCursor
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
                                        width: historyListView.width
                                        height: 48
                                        radius: 8
                                        color: index % 2 === 0 ? "#FFFFFF" : "#F1F5F9"
                                        border.color: "#E2E8F0"
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            spacing: 12

                                            Text {
                                                text: modelData.categoryName || "未识别"
                                                font.pixelSize: 24
                                                font.bold: true
                                                color: "#334155"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: modelData.weight ? modelData.weight.toFixed(2) + "kg" : "0.00kg"
                                                font.pixelSize: 24
                                                color: "#16A34A"
                                                font.bold: true
                                            }

                                            Text {
                                                text: (modelData.recordTime || "").substring(5, 16)
                                                font.pixelSize: 13
                                                color: "#94A3B8"
                                            }
                                        }

                                        // 点击打开详情弹窗，显示水印图片
                                        MouseArea {
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.currentDetailRecord = modelData
                                                detailDialog.open()
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
                                    Text { text: "\uD83D\uDCF7"; font.pixelSize: 24; color: "#475569" }
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

                            // ========== 单视频主区域 + 画中画 ==========
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // ========== 主摄像头 — 全屏底图 ==========
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
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
                                            Text { text: "\uD83D\uDDCF"; font.pixelSize: 13; color: "#FFFFFF" }
                                            Text { text: "蔬菜拍摄"; font.pixelSize: 13; font.bold: true; color: "#FFFFFF" }
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

                                    // ============================================================
                                    //  副摄像头 — 画中画（PiP，右下角浮动小窗）
                                    // ============================================================
                                    Rectangle {
                                        id: pipContainer
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.margins: 14
                                        width: Math.min(parent.width * 0.26, 220)
                                        height: width * 1.1
                                        radius: 10
                                        color: "#1C1917"           // 深色底，与主摄形成对比
                                        border.color: "#FFFFFF"
                                        border.width: 2
                                        clip: true

                                        VideoOutput {
                                            id: subVideo
                                            anchors.fill: parent
                                            anchors.margins: 2
                                            fillMode: VideoOutput.PreserveAspectFit  //裁剪模式PreserveAspectCrop
                                            Component.onCompleted: {
                                                CameraController.setSubVideoSink(subVideo.videoSink)
                                            }
                                        }

                                        // 左上角胶囊标签 — 暖色
                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.margins: 6
                                            width: pip_label_w.width + 14
                                            height: 22
                                            radius: 4
                                            color: "#CC5500"

                                            Row {
                                                id: pip_label_w
                                                spacing: 4
                                                anchors.centerIn: parent
                                                Text { text: "\uD83D\uDC64"; font.pixelSize: 11; color: "#FFFFFF" }
                                                Text { text: "操作员"; font.pixelSize: 10; font.bold: true; color: "#FFFFFF" }
                                            }
                                        }

                                        // 右下角状态点
                                        Row {
                                            anchors.right: parent.right
                                            anchors.bottom: parent.bottom
                                            anchors.margins: 5
                                            spacing: 4
                                            Rectangle { width: 6; height: 6; radius: 3; color: "#F97316" }
                                            Text { text: "AUX"; font.pixelSize: 8; font.bold: true; color: "#A8A29E" }
                                        }
                                    } // end PiP container
                                } // end main camera rectangle
                            } // end single video area Item
                    } // ColumnLayout
                    } // 蔬菜拍摄区块 Rectangle
                    } // 左侧区域 ColumnLayout

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
                                cursorShape: Qt.PointingHandCursor
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
                            anchors.centerIn: parent
                            width: parent.width
                            spacing: 12

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
                                        font.pixelSize: 192
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

                            // "物品名称" 独立标签 — 在名称卡片上方
                            Row {
                                spacing: 8
                                Text {
                                    text: "物品名称"
                                    font.pixelSize: 24
                                    color: "#64748B"
                                }

                                Rectangle {
                                    width: 78; height: 20; radius: 4
                                    color: "#DBEAFE"
                                   

                                    Text {
                                        anchors.centerIn: parent
                                        text: "AI辅助识别"
                                        font.pixelSize: 18
                                        color: "#2563EB"
                                    }
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
                                    cursorShape: Qt.PointingHandCursor
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

                                    // 右侧：识别按钮（手动演示用）
                                    // Rectangle {
                                    //     width: 44; height: 44; radius: 22
                                    //     color: captureMouseArea.containsMouse ? "#60A5FA" : "#3B82F6"
                                    //     border.color: "#FFFFFF"
                                    //     border.width: 2

                                    //     Text {
                                    //         anchors.centerIn: parent
                                    //         text: "识别"
                                    //         font.pixelSize: 18
                                    //         color: "#FFFFFF"
                                    //     }

                                    //     MouseArea {
                                    //         id: captureMouseArea
                                    //         anchors.fill: parent
                                    //         hoverEnabled: true
                                    //         cursorShape: Qt.PointingHandCursor
                                    //         onClicked: {
                                    //             console.log("手动触发拍照...")
                                    //             root.currentPrediction = PState.BUSY
                                    //             CameraController.captureVegetable(WeightManager.netWeight);
                                    //             captureBtnAnim.start();
                                    //         }
                                    //     }

                                    //     NumberAnimation {
                                    //         id: captureBtnAnim
                                    //         target: parent
                                    //         property: "scale"
                                    //         from: 1.0
                                    //         to: 0.9
                                    //         duration: 100
                                    //         loops: 1
                                    //         easing.type: Easing.InOutQuad
                                    //         onStopped: parent.scale = 1.0
                                    //     }
                                    // }                                
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
                                    item.clicked.connect(function() { WeightManager.tare() })
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
                                        let currentTime = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm")
                                        let chineseLabel = Translator.translate(root.currentPrediction)
                                        console.log(">> 手动提交称重记录:", chineseLabel, currentWeight.toFixed(2) + "kg", "时间:", currentTime, "图片路径:", root.currentImagePath)
                                        WeightHistoryService.addRecord(currentWeight, chineseLabel, BackendAuth.currentUser, root.currentImagePath, "")
                                        root.currentPrediction = PState.IDLE
                                        root.currentImagePath = ""
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
    Connections {
       target: WeightManager
       function onStableTriggered() {
           console.log("重量锁定！拍摄证据照片...")
           root.currentPrediction = PState.BUSY
           CameraController.captureVegetable(WeightManager.netWeight);
       }
    }

    Connections {
        target: CameraController
        function onPhotoSaved(cameraIndex, filePath) { 
            if (cameraIndex === 0) {
                flashEffect.opacity = 0.8
                fadeTimer.start()
                console.log("照片落盘:", filePath)
                root.currentImagePath = filePath
            }
        }
    }

    Connections {
        target: CameraController
        function onAiRecognitionCompleted(predictedLabel, imagePath, inferenceTimeMs) {
            console.log(">> QML收到AI分类结果:", predictedLabel)
            root.currentPrediction = predictedLabel
            root.currentImagePath = imagePath
            
            if (inferenceTimeMs !== undefined) {
                root.lastInferenceTime = inferenceTimeMs + " ms"
            } else {
                root.lastInferenceTime = PState.NONE + " ms"
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
        onLabelConfirmed: function(newPred) {
            root.currentPrediction = newPred
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
                    cursorShape: Qt.PointingHandCursor
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
                        cursorShape: Qt.PointingHandCursor
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
                        cursorShape: Qt.PointingHandCursor
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
                        cursorShape: Qt.PointingHandCursor
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
