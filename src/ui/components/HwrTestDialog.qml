pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import SmartScale.Hwr 1.0
import SmartScale

/**
 * @brief 手写识别测试弹窗（调试用）—— 脱离键盘直接验证 PP-OCRv5 识别率
 *
 * 用途：现场评测真实手指手写的识别效果（首选字是否正确、置信度、耗时、候选是否纠正得回来）。
 * 入口：系统调试信息弹窗 -> "手写识别测试"。
 *
 * 交互与真实手写输入法一致：抬笔后停顿 ~380ms 自动识别；也可点"识别"手动触发。
 */
Popup {
    id: root

    // 全部笔画：[[Qt.point, ...], ...]
    property var strokes: []
    property var currentStroke: null

    property string resultText: "—"
    property real confidence: 0
    property int elapsedMs: 0
    property var candidates: []          // [{text, score}, ...]
    property int pickedIndex: -1

    property string expectChar: ""       // 期望字（参数扫描用）
    property string sweepReport: ""      // 参数扫描结果

    readonly property bool ready: Ppocr.isReady()

    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }
    closePolicy: Popup.CloseOnEscape
    padding: 0
    width: 1500
    height: 920

    enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 150 } }
    exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 120 } }

    // ============================================================
    //  逻辑
    // ============================================================
    function clearAll() {
        strokes = []
        currentStroke = null
        resultText = "—"
        confidence = 0
        elapsedMs = 0
        candidates = []
        pickedIndex = -1
        canvas.requestPaint()
    }

    function undoStroke() {
        if (strokes.length === 0)
            return
        var all = strokes.slice()
        all.pop()
        strokes = all
        canvas.requestPaint()
    }

    function recognize() {
        if (strokes.length === 0) {
            resultText = "（请先手写）"
            return
        }
        var t0 = Date.now()
        var res = Ppocr.recognizeStrokesQml(strokes, 8)
        elapsedMs = Date.now() - t0
        candidates = res
        pickedIndex = -1
        if (res.length > 0) {
            resultText = res[0].text
            confidence = res[0].score
        } else {
            resultText = "（未识别）"
            confidence = 0
        }
    }

    Timer {
        id: recognizeTimer
        interval: 380
        onTriggered: root.recognize()
    }

    /// 参数扫描：对当前笔画遍历「笔宽 × 留白」网格，看哪组能把期望字排到第 1 位。
    /// （每组一次真实推理，约 15ms，20 组约 0.5s；结果同时打到日志 [HWR-SWEEP]）
    function sweep() {
        if (strokes.length === 0) {
            sweepReport = "（请先手写）"
            return
        }
        var pens = [0.04, 0.06, 0.08, 0.10, 0.12]
        var margins = [0.04, 0.07, 0.10, 0.14]
        var lines = ["期望字: " + (expectChar.length > 0 ? expectChar : "（未填，只看首选字）")]
        for (var i = 0; i < pens.length; ++i) {
            for (var j = 0; j < margins.length; ++j) {
                var res = Ppocr.recognizeStrokesQmlWithParams(strokes, 4, pens[i], margins[j])
                var top = res.length > 0 ? res[0].text : "—"
                var scoreTxt = res.length > 0 ? (res[0].score * 100).toFixed(0) + "%" : ""
                var hit = ""
                if (expectChar.length > 0) {
                    hit = "  未命中"
                    for (var k = 0; k < res.length; ++k) {
                        if (res[k].text === expectChar) {
                            hit = "  第" + (k + 1) + "位"
                            break
                        }
                    }
                }
                lines.push("笔宽" + pens[i].toFixed(2) + " 留白" + margins[j].toFixed(2)
                           + " -> " + top + " " + scoreTxt + hit)
            }
        }
        sweepReport = lines.join("\n")
        console.log("[HWR-SWEEP]\n" + sweepReport)
    }

    // ============================================================
    //  界面
    // ============================================================
    background: Rectangle {
        radius: 16
        color: "#FFFFFF"
        border.color: "#E2E8F0"
        border.width: 1
    }

    contentItem: ColumnLayout {
        spacing: 0

        // ---- 标题栏 ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 64
            radius: 16
            color: "#F8FAFC"

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                spacing: 12

                Text {
                    text: "手写识别测试（PP-OCRv5）"
                    font.pixelSize: 22
                    font.bold: true
                    color: Theme.colorTextPrimary
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: root.ready ? "引擎就绪" : "引擎未就绪（模型缺失？）"
                    font.pixelSize: 16
                    color: root.ready ? "#16A34A" : "#DC2626"
                }
            }
        }

        // ---- 主体 ----
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 20
            spacing: 20

            // -------- 左侧：书写区 --------
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: "#FFFFFF"
                border.color: "#CBD5E1"
                border.width: 2

                Canvas {
                    id: canvas
                    anchors.fill: parent
                    anchors.margins: 2
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineWidth = 5
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.strokeStyle = "#1B263B"

                        function drawStroke(s) {
                            if (!s || s.length < 2)
                                return
                            ctx.beginPath()
                            ctx.moveTo(s[0].x, s[0].y)
                            for (var j = 1; j < s.length; ++j)
                                ctx.lineTo(s[j].x, s[j].y)
                            ctx.stroke()
                        }

                        for (var i = 0; i < root.strokes.length; ++i)
                            drawStroke(root.strokes[i])
                        drawStroke(root.currentStroke)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onPressed: (mouse) => {
                        root.currentStroke = [Qt.point(mouse.x, mouse.y)]
                        canvas.requestPaint()
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed || !root.currentStroke)
                            return
                        var s = root.currentStroke.slice()
                        var last = s[s.length - 1]
                        // 抽稀：距离过近的点丢弃，减少噪声
                        if (Math.abs(last.x - mouse.x) + Math.abs(last.y - mouse.y) < 2)
                            return
                        s.push(Qt.point(mouse.x, mouse.y))
                        root.currentStroke = s
                        canvas.requestPaint()
                    }
                    onReleased: {
                        if (root.currentStroke && root.currentStroke.length >= 2) {
                            var all = root.strokes.slice()
                            all.push(root.currentStroke)
                            root.strokes = all
                            recognizeTimer.restart()
                        }
                        root.currentStroke = null
                        canvas.requestPaint()
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.strokes.length === 0 && !root.currentStroke
                    text: "在此手写（可作为整体写多个字）"
                    font.pixelSize: 26
                    color: "#D2DAE5"
                }
            }

            // -------- 右侧：识别结果 --------
            ColumnLayout {
                Layout.preferredWidth: 420
                Layout.fillHeight: true
                spacing: 14

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 150
                    radius: 12
                    color: "#F8FAFC"
                    border.color: "#E2E8F0"

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6
                        Text {
                            text: "识别结果"
                            font.pixelSize: 16
                            color: "#64748B"
                        }
                        Text {
                            text: root.resultText
                            font.pixelSize: 56
                            font.bold: true
                            color: "#1B263B"
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "置信度 " + (root.confidence * 100).toFixed(1) + "%　耗时 "
                                  + root.elapsedMs + " ms　笔画 " + root.strokes.length
                            font.pixelSize: 15
                            color: "#64748B"
                        }
                    }
                }

                Text {
                    text: "候选（点击即认为正确）"
                    font.pixelSize: 16
                    color: "#64748B"
                }

                ListView {
                    id: candidateList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 8
                    model: root.candidates

                    delegate: Rectangle {
                        required property var modelData
                        required property int index

                        width: ListView.view ? ListView.view.width : 0
                        height: 62
                        radius: 10
                        color: root.pickedIndex === index ? "#DBEAFE" : "#FFFFFF"
                        border.color: root.pickedIndex === index ? "#2563EB" : "#CBD5E1"
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 18
                            anchors.rightMargin: 18
                            spacing: 12
                            Text {
                                text: (index + 1) + ".  " + modelData.text
                                font.pixelSize: 28
                                font.bold: true
                                color: "#1B263B"
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                text: (modelData.score * 100).toFixed(1) + "%"
                                font.pixelSize: 16
                                color: "#64748B"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                root.pickedIndex = index
                                root.resultText = modelData.text
                                root.confidence = modelData.score
                            }
                        }
                    }
                }

                // ---- 参数扫描（用真实手写找最优 笔宽/留白）----
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    TextField {
                        id: expectField
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 44
                        placeholderText: "期望字"
                        font.pixelSize: 20
                        maximumLength: 4
                        onTextChanged: root.expectChar = text
                    }

                    Button {
                        id: sweepBtn
                        text: "参数扫描"
                        Layout.preferredWidth: 130
                        Layout.preferredHeight: 44
                        onClicked: root.sweep()
                        background: Rectangle { radius: 8; color: sweepBtn.pressed ? "#0F766E" : "#14B8A6" }
                        contentItem: Text {
                            text: sweepBtn.text
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 18
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }
                }

                TextArea {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 190
                    readOnly: true
                    wrapMode: TextArea.NoWrap
                    font.pixelSize: 13
                    font.family: Theme.fontFamilyMono
                    color: "#334155"
                    text: root.sweepReport
                    background: Rectangle { radius: 8; color: "#F1F5F9"; border.color: "#CBD5E1" }
                }

                Text {
                    Layout.fillWidth: true
                    text: "说明：首选字正确率即真实使用中的自动上屏正确率；\n错误时看候选里能否找到正确字（可纠正率）。\n参数扫描：填入期望字后点扫描，看哪组「笔宽/留白」把期望字排到第 1 位。"
                    wrapMode: Text.WordWrap
                    font.pixelSize: 14
                    color: "#94A3B8"
                }
            }
        }

        // ---- 按钮栏 ----
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            color: "#F8FAFC"

            RowLayout {
                anchors.centerIn: parent
                spacing: 16

                Button {
                    text: "撤销一笔"
                    implicitWidth: 140
                    implicitHeight: 44
                    onClicked: root.undoStroke()
                    background: Rectangle { radius: 8; color: parent.pressed ? "#E2E8F0" : "#FFFFFF"; border.color: "#CBD5E1" }
                    contentItem: Text {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 18
                        color: "#334155"
                    }
                }
                Button {
                    text: "清空"
                    implicitWidth: 140
                    implicitHeight: 44
                    onClicked: root.clearAll()
                    background: Rectangle { radius: 8; color: parent.pressed ? "#E2E8F0" : "#FFFFFF"; border.color: "#CBD5E1" }
                    contentItem: Text {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 18
                        color: "#334155"
                    }
                }
                Button {
                    text: "识别"
                    implicitWidth: 160
                    implicitHeight: 44
                    onClicked: root.recognize()
                    background: Rectangle { radius: 8; color: parent.pressed ? "#1D4ED8" : "#2563EB" }
                    contentItem: Text {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 18
                        font.bold: true
                        color: "#FFFFFF"
                    }
                }
                Button {
                    text: "关闭"
                    implicitWidth: 140
                    implicitHeight: 44
                    onClicked: root.close()
                    background: Rectangle { radius: 8; color: parent.pressed ? "#E2E8F0" : "#FFFFFF"; border.color: "#CBD5E1" }
                    contentItem: Text {
                        text: parent.text
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 18
                        color: "#334155"
                    }
                }
            }
        }
    }
}
