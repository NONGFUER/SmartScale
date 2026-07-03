import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0

Dialog {
    id: loginDialog
    width: 600
    height: 460
    leftPadding: 73
    rightPadding: 73
    topPadding: 30
    bottomPadding: 30
    // 位置由 Main.qml 统一控制（含键盘避让）
    // 非模态 + 外部遮罩（避免 Qt 内部 modal 层遮挡虚拟键盘）
    modal: false
    closePolicy: Popup.NoAutoClose
    title: ""
    z: 50

    background: Rectangle {
        color: "#FFFFFF"
        radius: 60

        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            shadowEnabled: true
            shadowColor: "#000000"
            shadowBlur: 30
            shadowOpacity: 0.25
            shadowVerticalOffset: 10
        }
    }

    // 遮罩层点击后的提示文字
    Text {
        id: hintText
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.bottom
        anchors.topMargin: 8
        font.family: "Microsoft YaHei"
        font.pixelSize: 20
        color: "#F59E0B"
        opacity: 0

        Behavior on opacity { NumberAnimation { duration: 300 } }

        Timer {
            id: hintHideTimer
            interval: 2000
            onTriggered: hintText.opacity = 0
        }
    }

    // 对话框抖动动画（遮罩点击 / 操作提示时使用）
    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: loginDialog; property: "x"; from: loginDialog.x; to: loginDialog.x - 8; duration: 50 }
        NumberAnimation { target: loginDialog; property: "x"; to: loginDialog.x + 8; duration: 100 }
        NumberAnimation { target: loginDialog; property: "x"; to: loginDialog.x - 6; duration: 100 }
        NumberAnimation { target: loginDialog; property: "x"; to: loginDialog.x + 4; duration: 100 }
        NumberAnimation { target: loginDialog; property: "x"; to: loginDialog.x; duration: 50 }
    }

    // ==========================================
    // 监听 C++ 后端信号
    // ==========================================
    Connections {
        target: BackendAuth
        function onLoginSuccess() {
            // 登录后拉取食材列表并更新翻译器缓存
            UserIngredientService.fetchIngredients()
            loginDialog.close()
        }
        function onLoginFailed(errorMsg) {  // 登录失败时显示错误提示
            console.log("!!! onLogin Fired, msg=", errorMsg)
            errorText.text = errorMsg
            errorAnim.start()
            errorText.opacity = 1 
           
        }
    }

    contentItem: ColumnLayout {
        spacing: 18
        // 头像 + 欢迎登录标题
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 48
            Layout.fillWidth: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "欢迎登录"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 36
                    font.bold: true
                    color: "#1B263B"
                }
            }
        }

        // 账号输入框
        TextField {
            id: userIn
            Layout.preferredWidth:  454
            Layout.preferredHeight: 60
            leftPadding: 24
            placeholderText: "请输入账号"
            font.family: "PingFang SC"
            font.pixelSize: 24
            color: "#1B263B"
            verticalAlignment: TextInput.AlignVCenter
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase

            background: Rectangle {
                radius: 1
                border.color: userIn.activeFocus ? "#4361EE" : "#E2E8F0"
                color: "#F7F7F7"
            }
        }

        // 密码输入框
        TextField {
            id: pwdIn
            Layout.preferredWidth:  454
            Layout.preferredHeight: 60
            leftPadding: 24
            rightPadding: 40
            placeholderText: "请输入登录密码"
            font.family: "PingFang SC"
            font.pixelSize: 24
            color: "#1B263B"
            echoMode: showPwdCheck.checked ? TextInput.Normal : TextInput.Password
            verticalAlignment: TextInput.AlignVCenter
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhPreferLowercase

            background: Rectangle {
                radius: 1
                border.color: pwdIn.activeFocus ? "#4361EE" : "#E2E8F0"
                color: "#F7F7F7"
            }

            // 眼睛图标按钮（切换密码可见性）
            Rectangle {
                id: eyeBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.rightMargin: 6
                width: 34; height: 34; radius: 17
                color: showPwdCheck.checked ? "#E0E7FF" : "transparent"

                Image {
                    anchors.centerIn: parent
                    source: showPwdCheck.checked ? "qrc:/resources/icon/eye-fill.png" : "qrc:/resources/icon/eye-close-fill.png"
                    sourceSize: Qt.size(20, 20)
                    cache: true
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: showPwdCheck.toggle()
                }
            }
        }

        // 显示密码选项
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.topMargin: -6

            RowLayout {
                anchors.left: parent.left
                spacing: 6

                CheckBox {
                    id: showPwdCheck
                    text: ""
                    implicitWidth: 18
                    implicitHeight: 18

                    indicator: Rectangle {
                        implicitWidth: 18
                        implicitHeight: 18
                        x: 0; y: parent.height / 2 - height / 2
                        radius: 3
                        color: showPwdCheck.checked ? "#E0E7FF" : "#FFFFFF"
                        border.color: showPwdCheck.checked ? "#6366F1" : "#D1D5DB"
                        border.width: 1.5

                        Text {
                            visible: showPwdCheck.checked
                            anchors.centerIn: parent
                            text: "\u2713"
                            font.pixelSize: 12
                            font.bold: true
                            color: "#6366F1"
                        }
                    }
                    contentItem: null
                }

                Text {
                    text: "显示密码"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 14
                    color: "#64748B"
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: showPwdCheck.toggle()
                    }
                }
            }
        }

       
        // 记住登录复选框
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.topMargin: 4

            RowLayout {
                anchors.left: parent.left
                spacing: 8

                CheckBox {
                    id: rememberCheck
                    text: ""
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 16
                    checked: false

                    onCheckedChanged: {
                        BackendAuth.rememberLogin = checked
                    }

                    indicator: Rectangle {
                        implicitWidth: 20
                        implicitHeight: 20
                        x: 0
                        y: parent.height / 2 - height / 2
                        radius: 4
                        color: rememberCheck.checked ? "#4361EE" : "#FFFFFF"
                        border.color: rememberCheck.checked ? "#4361EE" : "#CBD5E1"
                        border.width: 1.5

                        Text {
                            visible: rememberCheck.checked
                            anchors.centerIn: parent
                            text: "\u2713"
                            font.pixelSize: 13
                            font.bold: true
                            color: "#FFFFFF"
                        }
                    }

                    contentItem: null
                }

                Text {
                    text: "记住登录"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 16
                    color: "#64748B"
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        onClicked: rememberCheck.toggle()
                    }
                }
            }
        }


        // 错误提示（带动画）
        Text {
            id: errorText
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter // 【新增】确保文字在宽区域内居中
            font.family: "Microsoft YaHei"
            font.pixelSize: 14
            color: "#EF4444"

            visible: opacity > 0
            opacity: 0

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

        // 按钮行：跳过 | 登录（左右并排）
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 48
            Layout.topMargin: 8

            RowLayout {
                anchors.fill: parent
                spacing: 16

                // 跳过按钮（左侧，灰色白底）
                Button {
                    id: skipBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    text: "跳过"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 18

                    background: Rectangle {
                        radius: 10
                        color: skipBtn.hovered ? "#F2F5F7" : "#FFFFFF"
                        border.width: 1.5
                        border.color: "#F2F5F7"

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    contentItem: Text {
                        text: skipBtn.text
                        font: skipBtn.font
                        color: "#333333"
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    onClicked: {
                        loginDialog.close()
                    }
                }

                // 登录按钮（右侧，蓝色）
                Button {
                    id: loginBtn
                    Layout.fillWidth: true
                    Layout.preferredHeight: 48
                    text: "登录"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 18
                    font.bold: true

                    background: Rectangle {
                        radius: 5
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "#4C72F9" }
                            GradientStop { position: 1.0; color: "#4BC8F6" }
                        }

                        states: State {
                            name: "hovered"
                            when: loginBtn.hovered
                            PropertyChanges {
                                target: loginBtn.background
                                scale: 1.02
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
                        errorText.opacity = 0

                        // 前端输入校验
                        if (!userIn.text.trim()) {
                            errorText.text = "请输入账号"
                            errorAnim.start()
                            errorText.opacity = 1
                            return
                        }
                        // 如果有保存的登录信息且用户名匹配，直接使用保存的凭据自动登录
                        if (BackendAuth.hasSavedLogin && userIn.text === BackendAuth.lastUserCode) {
                            console.log("[LoginDialog] 使用记住的凭据登录")
                            BackendAuth.autoLogin()
                            return
                        }
                        // 需要手动输入密码
                        if (!pwdIn.text.trim()) {
                            errorText.text = "请输入密码"
                            errorAnim.start()
                            errorText.opacity = 1
                            return
                        }

                        BackendAuth.login(userIn.text, pwdIn.text)
                    }

                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                }
            }
        }

        
    }

    // 打开时初始化，自动填充保存的账号密码
    onOpened: {
        errorText.opacity = 0
        // 如果有保存的登录信息，自动填充
        if (BackendAuth.hasSavedLogin) {
            userIn.text = BackendAuth.lastUserCode
            // 密码从后端已保存，不需要前端显示（安全考虑）
            rememberCheck.checked = true
            BackendAuth.rememberLogin = true
        } else {
            userIn.text = ""
            pwdIn.text = ""
            // 如果之前勾选过"记住登录"但没有有效数据（如退出时清除）
            rememberCheck.checked = BackendAuth.rememberLogin
        }
    }

    // Enter 快捷键登录
    Shortcut {
        sequence: "Return"
        enabled: loginDialog.visible
        context: Qt.ApplicationShortcut
        onActivated: if (loginDialog.visible) loginBtn.clicked()
    }

    // 外部遮罩层点击时调用（由 Main.qml 中的 loginOverlay 触发）
    function onOverlayClicked() {
        shakeAnim.start()
        hintText.text = "请登录或选择跳过"
        hintText.opacity = 1
        hintHideTimer.restart()
    }
}
