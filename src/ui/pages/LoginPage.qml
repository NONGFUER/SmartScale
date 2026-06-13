import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0

Item {
    id: loginPage
    anchors.fill: parent

    // ==========================================
    // 0. 自动跳过计时器（3秒倒计时）
    // ==========================================
    property int skipCountdown: 3

    Timer {
        id: autoSkipTimer
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            skipCountdown--
            if (skipCountdown <= 0) {
                stop()
                doAutoSkip()
            }
        }
    }

    function doAutoSkip() {
        console.log("[LoginPage] 自动跳过登录（游客模式）")
        stackView.push("WorkstationPage.qml")
    }

    // ==========================================
    // 1. 监听 C++ 的信号（保持不变）
    // ==========================================
    Connections { 
        target: BackendAuth 
        function onLoginSuccess() {
            autoSkipTimer.stop()
            stackView.push("WorkstationPage.qml")
        }
        function onLoginFailed(errorMsg) {
            errorText.text = errorMsg
            errorAnim.start()  // 添加错误提示动画
            errorText.visible = true
        }
    }

    // ==========================================
    // 2. 科技感渐变背景
    // ==========================================
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#0D1B2A" }   // 深蓝黑
            GradientStop { position: 0.3; color: "#1B263B" }   // 中蓝
            GradientStop { position: 1.0; color: "#0D1B2A" }   // 深蓝黑
        }
    }

    // ==========================================
    // 3. 背景科技网格装饰
    // ==========================================
    Canvas {
        anchors.fill: parent
        opacity: 0.1
        
        onPaint: {
            var ctx = getContext("2d")
            ctx.strokeStyle = "#4CC9F0"
            ctx.lineWidth = 1
            
            // 绘制网格
            var gridSize = 40
            for (var x = 0; x < width; x += gridSize) {
                ctx.beginPath()
                ctx.moveTo(x, 0)
                ctx.lineTo(x, height)
                ctx.stroke()
            }
            for (var y = 0; y < height; y += gridSize) {
                ctx.beginPath()
                ctx.moveTo(0, y)
                ctx.lineTo(width, y)
                ctx.stroke()
            }
        }
    }

    // ==========================================
    // 4. 公司品牌头部区域
    // ==========================================
    ColumnLayout {
        id: headerSection
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 80
        spacing: 20

        // 公司Logo容器
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            width: 100
            height: 100
            radius: 50
            color: "#4361EE"
            border.width: 3
            border.color: "#FFFFFF"
            
            // 机器人图标（可用图片替换）
            Text {
                anchors.centerIn: parent
                text: "🤖"
                font.pixelSize: 48
                color: "white"
            }
        }

        // 公司名称
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "上海小管事机器人有限公司"
            font.family: "Microsoft YaHei"
            font.pixelSize: 28
            font.bold: true
            color: "#FFFFFF"
            opacity: 0.95
        }

        // 产品名称和版本
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "智能称重系统 V1.0"
            font.family: "Microsoft YaHei"
            font.pixelSize: 20
            color: "#4CC9F0"
            opacity: 0.8
        }

        // 分隔线
        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 200
            Layout.preferredHeight: 2
            color: "#4CC9F0"
            opacity: 0.5
        }
    }

    // ==========================================
    // 5. 主登录卡片（玻璃拟态效果）
    // ==========================================
    Rectangle {
        id: loginCard
        width: 500
        height: 420
        anchors.centerIn: parent
        radius: 20
        color: "#FFFFFF"
        opacity: 0.95
        
        // 玻璃拟态效果
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 30
            shadowOpacity: 0.2
            shadowVerticalOffset: 10
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width * 0.8
            spacing: 20

            // 登录标题
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "系统登录"
                font.family: "Microsoft YaHei"
                font.pixelSize: 32
                font.bold: true
                color: "#1B263B"
            }

            // 用户名输入框
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 10
                border.width: 2
                border.color: userIn.activeFocus ? "#4361EE" : "#E2E8F0"
                color: "#F8FAFC"
                
                TextField {
                    id: userIn
                    anchors.fill: parent
                    anchors.margins: 5
                    placeholderText: "请输入用户名"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 20
                    color: "#1B263B"
                    verticalAlignment: TextInput.AlignVCenter
                    background: Rectangle { color: "transparent" }
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase     //不自动大写
                   // leftPadding: 15
                    focus: true
                    
                    // 左侧图标
                    leftInset: 40
                    leftPadding: 40
                    
                    Image {
                        source: "qrc:/icons/user.svg"  // 如有图标文件
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        width: 24
                        height: 24
                        visible: false  // 暂时隐藏，如需使用请添加图标文件
                    }
                }
            }

            // 密码输入框
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                radius: 10
                border.width: 2
                border.color: pwdIn.activeFocus ? "#4361EE" : "#E2E8F0"
                color: "#F8FAFC"
                
                TextField {
                    id: pwdIn
                    anchors.fill: parent
                    anchors.margins: 5
                    placeholderText: "请输入密码"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 20
                    color: "#1B263B"
                    echoMode: TextInput.Password
                    verticalAlignment: TextInput.AlignVCenter
                    background: Rectangle { color: "transparent" }
                    inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase //不自动大写
                    // 左侧图标
                    leftInset: 40
                    leftPadding: 40
                    
                    Image {
                        source: "qrc:/icons/lock.svg"  // 如有图标文件
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        width: 24
                        height: 24
                        visible: false  // 暂时隐藏，如需使用请添加图标文件
                    }
                }
            }

            // 错误提示（带动画）
            Text {
                id: errorText
                Layout.alignment: Qt.AlignHCenter
                font.family: "Microsoft YaHei"
                font.pixelSize: 16
                color: "#EF4444"
                height: visible ? implicitHeight : 0
                opacity: visible ? 1 : 0
                visible: false
                
                Behavior on height { NumberAnimation { duration: 200 } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                
                SequentialAnimation on color {
                    id: errorAnim
                    running: false
                    loops: 2
                    ColorAnimation { from: "#EF4444"; to: "#F87171"; duration: 200 }
                    ColorAnimation { from: "#F87171"; to: "#EF4444"; duration: 200 }
                }
            }

            // 登录按钮
            Button {
                id: loginBtn
                Layout.fillWidth: true
                Layout.preferredHeight: 60
                text: "登录系统"
                font.family: "Microsoft YaHei"
                font.pixelSize: 22
                font.bold: true
                
                background: Rectangle {
                    radius: 10
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#4361EE" }
                        GradientStop { position: 1.0; color: "#3A0CA3" }
                    }
                    border.width: 0
                    
                    // 悬停效果
                    states: State {
                        name: "hovered"
                        when: loginBtn.hovered
                        PropertyChanges { 
                            target: loginBtn.background; 
                            scale: 1.03 
                        }
                    }
                    
                    transitions: Transition {
                        NumberAnimation { properties: "scale"; duration: 200 }
                    }
                }
                
                contentItem: Text {
                    text: loginBtn.text
                    font: loginBtn.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                
                onClicked: {
                    autoSkipTimer.stop()  // 手动操作时停止自动跳过
                    // 清空错误提示
                    errorText.text = ""
                    errorText.visible = false
                    
                    // 调用后端登录
                    BackendAuth.login(userIn.text, pwdIn.text)
                }
                
                // 键盘回车事件
                Keys.onReturnPressed: clicked()
                Keys.onEnterPressed: clicked()
            }

            // 自动跳过倒计时提示
            Text {
                Layout.alignment: Qt.AlignHCenter
                font.family: "Microsoft YaHei"
                font.pixelSize: 14
                color: "#94A3B8"

                text: (userIn.text.length > 0 || pwdIn.text.length > 0)
                      ? "已停止自动跳过"
                      : (skipCountdown > 0
                         ? skipCountdown + " 秒后自动跳过登录（游客模式）"
                         : "正在跳过...")

                MouseArea {
                    anchors.fill: parent
                    onClicked: doAutoSkip()
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                }
            }
        }
    }

    // ==========================================
    // 6. 底部版权信息
    // ==========================================
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        text: "© 2026 上海小管事机器人有限公司 版权所有"
        font.family: "Microsoft YaHei"
        font.pixelSize: 14
        color: "#94A3B8"
        opacity: 0.7
    }

    // ==========================================
    // 7. 辅助功能：Enter键登录
    // ==========================================
    Shortcut {
        sequence: "Return"
        onActivated: loginBtn.clicked()
    }
}
