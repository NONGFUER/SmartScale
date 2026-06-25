import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0
import SmartScale.Tools 1.0

Dialog {
    id: dialogRoot
    property string currentPrediction: ""
    property string currentImagePath: ""
    property bool categorySelectMode: false

    signal labelConfirmed(string confirmedLabel, string ingrId)
    signal selectModeToggled(bool isActive)

    x: (parent.width - width) / 2
    // 键盘弹出时上移避让，避免搜索框被键盘遮挡
    y: Math.min((parent.height - height) / 2,
                parent.height - height - (inputPanel.active ? inputPanel.height + 20 : 0))
    width: Math.min(parent.width * 0.92, 1200)
    height: Math.min(parent.height * 0.88, 780)
    padding: 0

    // 非模态 + 外部遮罩（Main.qml 的 categoryOverlay），避免 Qt 内部 modal 层遮挡虚拟键盘
    modal: false
    closePolicy: Popup.NoAutoClose
    title: ""
    z: 50

    background: Rectangle {
        color: "#FFFFFF"
        radius: 48
        layer.enabled: true
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 30
            shadowOpacity: 0.25
            shadowVerticalOffset: 10
        }
    }

    property string selectedLabel: ""
    property string selectedIngrId: ""
    property int activeCategoryIndex: 0

    function getActiveCategories() {
        if (categorySelectMode)
            return UserIngredientService.categories
        return CategoryService.categories
    }
    function getActiveItems() {
        var cats = getActiveCategories()
        if (activeCategoryIndex >= 0 && activeCategoryIndex < cats.length)
            return cats[activeCategoryIndex].items || []
        return []
    }
    function getSelectedCn() {
        var items = getActiveItems()
        for (var i = 0; i < items.length; i++) {
            if (items[i].en === selectedLabel)
                return items[i].cn || items[i].en || selectedLabel
        }
        return selectedLabel
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ====== 顶部栏：返回 + 搜索框 + 搜索按钮 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 24
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            spacing: 12

            // 返回按钮
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: 10
                color: backMouse.containsMouse ? "#EEF1F6" : "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "\u2039"
                    font.pixelSize: 38
                    font.bold: true
                    color: "#333333"
                }
                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: dialogRoot.reject()
                }
            }

            // 搜索胶囊容器
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 52
                radius: 21
                color: "#FFFFFF"
                border.color: catSearchInput.activeFocus ? "#4361EE" : "#E8EAED"
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 4
                    spacing: 8

                    // // 搜索图标
                    // Text {
                    //     font.pixelSize: 18
                    //     color: "#9CA3AF"
                    //     Layout.preferredWidth: 20
                    //     Layout.preferredHeight: 38
                    //     Layout.alignment: Qt.AlignVCenter
                    //     verticalAlignment: Text.AlignVCenter
                    //     text: "\u{1F50D}"
                    // }

                    TextField {
                        id: catSearchInput
                        Layout.fillWidth: true
                        Layout.preferredHeight: 42
                        placeholderText: "请输入搜索内容"
                        font.pixelSize: 24
                        color: "#1B263B"
                        verticalAlignment: TextInput.AlignVCenter
                        background: null
                    }

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 42
                        radius: 17
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: "#3B82F6" }
                            GradientStop { position: 1.0; color: "#1D4ED8" }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "搜索"
                            font.pixelSize: 24
                            font.bold: true
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: console.log("[CategoryDialog] 搜索:", catSearchInput.text)
                        }
                    }
                }
            }
        }

        // ====== 分类标签 + 品类网格容器（统一背景，与顶部栏产生隔离感）=====
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.topMargin: 16
            color: '#F2F7FF'
            radius: 16
            border.color: "#E2E8F0"
            border.width: 1
            clip: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

        // ====== 分类标签行（可横向滚动）=====
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 22
            Layout.bottomMargin: 12
            spacing: 28

            Flickable {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                contentWidth: catTagRow.width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Row {
                    id: catTagRow
                    spacing: 28

                    Repeater {
                        model: dialogRoot.getActiveCategories()

                        Item {
                            width: catLabelTxt.implicitWidth + 4
                            height: 36

                            Text {
                                id: catLabelTxt
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.cateNm || modelData.name
                                font.pixelSize: 24
                                font.bold: (dialogRoot.activeCategoryIndex === index)
                                color: (dialogRoot.activeCategoryIndex === index) ? "#4361EE" : "#666666"
                            }

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: catLabelTxt.width * 0.7
                                height: 3
                                visible: (dialogRoot.activeCategoryIndex === index)
                                radius: 1.5
                                color: "#4361EE"
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    dialogRoot.activeCategoryIndex = index
                                    dialogRoot.selectedLabel = ""
                                }
                            }
                        }
                    }

                    // "更多 ▼" 展开项（固定末尾）
                    Item {
                        width: moreCatTxt.implicitWidth + 4
                        height: 36
                        visible: false

                        Text {
                            id: moreCatTxt
                            anchors.centerIn: parent
                            text: "更多 \u25BC"
                            font.pixelSize: 16
                            color: "#999999"
                        }
                    }
                }
            }
        }

        // ====== 品类网格区域 ======
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: 16
            clip: true

            GridView {
                id: foodGridView
                anchors.fill: parent
                cellWidth: (foodGridView.width - 40) / 5
                cellHeight: 160
                clip: true

                model: dialogRoot.getActiveItems()

                delegate: Rectangle {
                    id: foodCard
                    width: foodGridView.cellWidth - 16
                    height: foodGridView.cellHeight - 16
                    radius: 12
                    border.width: 1
                    border.color: dialogRoot.selectedLabel === modelData.en
                                  ? "#4361EE" : (cardHover.containsHover ? "#9DBBFF" : "#E2E8F0")
                    Behavior on border.color { ColorAnimation { duration: 140 } }

                    // 卡片背景垂直渐变（顶亮底暗，模拟顶光照射）
                    gradient: Gradient {
                        GradientStop {
                            position: 0.0
                            color: dialogRoot.selectedLabel === modelData.en ? "#F0F6FF" : "#FFFFFF"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                        GradientStop {
                            position: 1.0
                            color: dialogRoot.selectedLabel === modelData.en ? "#D6E4FF" : "#EEF2F7"
                            Behavior on color { ColorAnimation { duration: 140 } }
                        }
                    }

                    // hover 时卡片轻微上浮
                    transform: Translate {
                        id: cardLift
                        y: cardHover.containsHover ? -2 : 0
                        Behavior on y { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }

                    // 顶部高光带（水平渐变：两端透明→中间白，呈弧面反光）
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
                        opacity: (cardHover.containsHover
                                  || dialogRoot.selectedLabel === modelData.en) ? 1.0 : 0.7
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    // 底部暗影带（水平渐变：两端透明→中间深）
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
                        opacity: (cardHover.containsHover
                                  || dialogRoot.selectedLabel === modelData.en) ? 0.3 : 0.16
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    // 底部散光投影（随卡片上浮显现，模拟悬浮阴影）
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -3
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width - 14
                        height: 6
                        radius: 3
                        color: "#1B263B"
                        opacity: cardHover.containsHover ? 0.18
                                : (dialogRoot.selectedLabel === modelData.en ? 0.10 : 0.04)
                        Behavior on opacity { NumberAnimation { duration: 140 } }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: modelData.cn
                        font.pixelSize: 32
                        font.family: "Microsoft YaHei"
                        color: dialogRoot.selectedLabel === modelData.en ? "#4361EE" : "#1B263B"
                    }

                    HoverHandler { id: cardHover }

                    TapHandler {
                        onTapped: {
                            dialogRoot.selectedLabel = modelData.en
                            dialogRoot.selectedIngrId = (modelData.id !== undefined) ? String(modelData.id) : ""
                        }
                    }
                }
            }
        }
            }
        }

        // ====== 底部按钮栏 ======
        RowLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignRight
            Layout.leftMargin: 22
            Layout.rightMargin: 22
            Layout.bottomMargin: 22
            Layout.topMargin: 14
            spacing: 14

            // 取消按钮
            Rectangle {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 52
                radius: 10
                color: cancelHover.hovered ? "#F1F5F9" : "#FFFFFF"
                border.color: "#D1D5DB"
                border.width: 1.2

                HoverHandler { id: cancelHover }

                Text {
                    anchors.centerIn: parent
                    text: "取消"
                    font.pixelSize: 24
                    font.bold: true
                    color: "#64748B"
                }

                TapHandler { onTapped: dialogRoot.reject() }
            }

            // 确认按钮
            Rectangle {
                Layout.preferredWidth: 110
                Layout.preferredHeight: 52
                radius: 10
                enabled: dialogRoot.selectedLabel !== ""
                opacity: enabled ? 1.0 : 0.45
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: dialogRoot.selectedLabel === "" ? "#94A3B8" : "#4361EE" }
                    GradientStop { position: 1.0; color: dialogRoot.selectedLabel === "" ? "#CBD5E1" : "#6BA3FF" }
                }

                Text {
                    anchors.centerIn: parent
                    text: "确认"
                    font.pixelSize: 24
                    font.bold: true
                    color: "white"
                }

                TapHandler {
                    enabled: dialogRoot.selectedLabel !== ""
                    onTapped: dialogRoot.accept()
                }
            }
        }
    }

    onOpened: {
        selectedLabel = ""
        selectedIngrId = ""
        activeCategoryIndex = 0
        catSearchInput.text = ""

        if (categorySelectMode)
            UserIngredientService.fetchIngredients()
        else
            CategoryService.fetchCategories()
    }

    onAccepted: {
        var selItems = getActiveItems()
        for (var i = 0; i < selItems.length; i++) {
            if (selItems[i].en === selectedLabel) {
                var m = selItems[i]
                console.log("[CategoryDialog] \u9009\u4E2D\u98DF\u6750 \u25B6"
                            + " ingrId=" + (m.id !== undefined ? m.id : "")
                            + " ingrCd=" + (m.en !== undefined ? m.en : "")
                            + " ingrNm=" + (m.cn !== undefined ? m.cn : "")
                            + " cateId=" + (m.cateId !== undefined ? m.cateId : "")
                            + " emsId="  + (m.emsId !== undefined ? m.emsId : "")
                            + " emsCd="  + (m.emsCd !== undefined ? m.emsCd : "")
                            + " cateNm=" + (m.cateNm !== undefined ? m.cateNm : ""))
                break
            }
        }

        let correctLabel = selectedLabel
        if (categorySelectMode) {
            labelConfirmed(correctLabel, selectedIngrId)
            selectModeToggled(false)
        } else {
            VisionAI.submitCorrection(currentImagePath, currentPrediction, correctLabel)
            labelConfirmed(correctLabel, selectedIngrId)
        }
    }

    onRejected: {
        if (categorySelectMode)
            selectModeToggled(false)
    }
}
