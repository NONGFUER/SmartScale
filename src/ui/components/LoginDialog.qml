import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import App.Backend 1.0

Dialog {
    id: loginDialog
    width: 600
    height: 560
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
        x: (loginDialog.width - implicitWidth) / 2
        y: loginDialog.height + 8
        font.family: "Microsoft YaHei"
        font.pixelSize: 24
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
            loginLoadingOverlay.close()
            loginDialog.close()
        }
        function onLoginFailed(errorMsg) {  // 登录失败时显示错误提示
            loginLoadingOverlay.close()
            console.log("!!! onLogin Fired, msg=", errorMsg)
            // 脱敏兜底：与 window.alert() 保持一致，避免技术错误（URL/HTTP/SSL 等）直接外露给用户
            errorText.text = sanitizeLoginError(errorMsg)
            errorAnim.start()
            errorText.opacity = 1

        }
    }

    // 登录错误脱敏（与 Main.qml window.alert() 同规则）：
    // - URL 替换为 <接口地址>
    // - 含技术错误特征（Error transferring / server replied / QNetworkReply / HTTP / SSL / 网络请求失败 等）
    //   替换为统一友好提示，避免在登录弹窗内联错误文本显示"Error transferring <URL> - server replied: Bad Gateway"等。
    function sanitizeLoginError(msg) {
        if (!msg) return ""
        var s = String(msg).replace(/https?:\/\/[^\s]+/g, "<接口地址>")
        var techPatterns = ["Error transferring", "server replied", "QNetworkReply",
                            "Host ", "Connection ", "timeout", "HTTP ", "SSL",
                            "网络请求失败", "JSON 解析失败", "数据解析失败"]
        for (var i = 0; i < techPatterns.length; i++) {
            if (s.indexOf(techPatterns[i]) >= 0) {
                return "网络连接失败，请稍后重试"
            }
        }
        return s
    }

    // 登录逻辑（按钮点击 / Enter 快捷键共用）
    function doLogin() {
        errorText.opacity = 0

        // 快捷登录模式：使用选中的历史账号 + 记住的密码直接登录
        if (loginMode === 1) {
            if (selectedHistoryIndex < 0) {
                errorText.text = "请选择要登录的账号"
                errorAnim.start()
                errorText.opacity = 1
                return
            }
            var item = BackendAuth.loginHistory[selectedHistoryIndex]
            if (BackendAuth.hasRememberedPassword(item.userCode)) {
                loginLoadingOverlay.open()
                BackendAuth.loginByHistory(selectedHistoryIndex)
            } else {
                // 该账号未记住密码 → 切回账号登录并预填，提示输密码
                loginMode = 0
                selectedHistoryIndex = -1
                userIn.text = item.userCode
                pwdIn.text = ""
                errorText.text = "请输入密码"
                errorText.opacity = 1
                pwdIn.forceActiveFocus()
            }
            return
        }


        // 前端输入校验
        if (!userIn.text.trim()) {
            errorText.text = "请输入账号"
            errorAnim.start()
            errorText.opacity = 1
            return
        }
        // 仅当用户【未输入密码】且账号与已保存账号一致时，才使用保存的凭据自动登录。
        // 否则（用户主动输入了密码）必须以用户输入为准，
        // 否则后台改密后用户填新密码仍会被旧密码覆盖，导致反复登录失败。
        if (BackendAuth.hasSavedLogin && userIn.text === BackendAuth.lastUserCode
                && !pwdIn.text.trim()) {
            console.log("[LoginDialog] 使用记住的凭据登录")
            loginLoadingOverlay.open()
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

        loginLoadingOverlay.open()
        BackendAuth.login(userIn.text, pwdIn.text)
    }

    // 登录中全屏遮罩（参照 SaveLoadingOverlay 样式：modal 全屏半透明遮罩 + 居中旋转动画卡片）
    Popup {
        id: loginLoadingOverlay
        modal: true
        closePolicy: Popup.NoAutoClose
        padding: 0
        anchors.centerIn: parent
        width: 300
        height: 300

        Overlay.modal: Rectangle { color: "#80000000" }

        background: Rectangle {
            radius: 24
            color: "#FFFFFF"
            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: "#002A75"
                shadowOpacity: 0.1
                shadowBlur: 1.0
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
            }
        }

        enter: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 }
            NumberAnimation { property: "scale"; from: 0.9; to: 1.0; duration: 200; easing.type: Easing.OutCubic }
        }
        exit: Transition {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 150 }
        }

        Column {
            anchors.centerIn: parent
            spacing: 30

            Item {
                width: 80; height: 80
                anchors.horizontalCenter: parent.horizontalCenter

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "#4361EE"
                        ctx.lineWidth = 5
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, width / 2 - 4, 0, Math.PI * 1.4)
                        ctx.stroke()
                    }
                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: 800
                        loops: Animation.Infinite
                        running: loginLoadingOverlay.visible
                    }
                }
            }

            Text {
                text: "登录中..."
                font.pixelSize: 28
                font.bold: true
                font.family: "PingFang SC"
                color: "#1E293B"
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // 登录模式：0 = 账号登录，1 = 快捷登录
    property int loginMode: 0
    // 快捷登录中选中的历史记录索引（-1 表示未选）
    property int selectedHistoryIndex: -1

    contentItem: ColumnLayout {
        spacing: 16
        // 头像 + 欢迎登录标题
        Item {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredHeight: 44
            Layout.fillWidth: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "欢迎登录"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 34
                    font.bold: true
                    color: "#1B263B"
                }
            }
        }

        // 登录模式切换 Tab（账号登录 | 快捷登录）
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 454
            Layout.preferredHeight: 52
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: loginMode === 0 ? "#4361EE" : "#F1F5F9"
                Text {
                    anchors.centerIn: parent
                    text: "账号登录"
                    font.family: "PingFang SC"
                    font.pixelSize: 24
                    font.bold: true
                    color: loginMode === 0 ? "#FFFFFF" : "#64748B"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { loginMode = 0; selectedHistoryIndex = -1 }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 12
                color: loginMode === 1 ? "#4361EE" : "#F1F5F9"
                Text {
                    anchors.centerIn: parent
                    text: "快捷登录"
                    font.family: "PingFang SC"
                    font.pixelSize: 24
                    font.bold: true
                    color: loginMode === 1 ? "#FFFFFF" : "#64748B"
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: { loginMode = 1; selectedHistoryIndex = -1 }
                }
            }
        }

        // 内容区：根据 loginMode 切换
        StackLayout {
            id: loginStack
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 454
            Layout.preferredHeight: 230
            currentIndex: loginMode

            // ===== Page 0: 账号登录 =====
            ColumnLayout {
                spacing: 14

                // 账号输入框（仅允许 9 位数字）
                TextField {
                    id: userIn
                    Layout.preferredWidth:  454
                    Layout.preferredHeight: 60
                    leftPadding: 24
                    placeholderText: "请输入9位数字账号"
                    font.family: "PingFang SC"
                    font.pixelSize: 24
                    color: "#1B263B"
                    verticalAlignment: TextInput.AlignVCenter
                    inputMethodHints: Qt.ImhDigitsOnly
                    maximumLength: 9
                    validator: RegularExpressionValidator { regularExpression: /^\d{0,9}$/ }

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
                    Layout.preferredHeight: 36
                    Layout.topMargin: -4

                    RowLayout {
                        anchors.left: parent.left
                        spacing: 6

                        CheckBox {
                            id: showPwdCheck
                            text: ""
                            implicitWidth: 28
                            implicitHeight: 28

                            indicator: Rectangle {
                                implicitWidth: 28
                                implicitHeight: 28
                                x: 0; y: parent.height / 2 - height / 2
                                radius: 4
                                color: showPwdCheck.checked ? "#4361EE" : "#FFFFFF"
                                border.color: showPwdCheck.checked ? "#4361EE" : "#CBD5E1"
                                border.width: 1.5

                                Text {
                                    visible: showPwdCheck.checked
                                    anchors.centerIn: parent
                                    text: "\u2713"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#FFFFFF"
                                }
                            }
                            contentItem: null
                        }

                        Text {
                            text: "显示密码"
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 24
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

                    RowLayout {
                        anchors.left: parent.left
                        spacing: 8

                        CheckBox {
                            id: rememberCheck
                            text: ""
                            implicitWidth: 28
                            implicitHeight: 28
                            checked: false

                            onCheckedChanged: {
                                BackendAuth.rememberLogin = checked
                            }

                            indicator: Rectangle {
                                implicitWidth: 28
                                implicitHeight: 28
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
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: "#FFFFFF"
                                }
                            }

                            contentItem: null
                        }

                        Text {
                            text: "记住登录"
                            font.family: "Microsoft YaHei"
                            font.pixelSize: 24
                            color: "#64748B"
                            verticalAlignment: Text.AlignVCenter

                            MouseArea {
                                anchors.fill: parent
                                onClicked: rememberCheck.toggle()
                            }
                        }
                    }
                }
            }

            // ===== Page 1: 快捷登录（最近登录历史） =====
            ColumnLayout {
                spacing: 10

                Text {
                    visible: BackendAuth.loginHistory.length === 0
                    Layout.alignment: Qt.AlignHCenter
                    Layout.fillHeight: true
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    text: "暂无最近登录记录"
                    font.family: "Microsoft YaHei"
                    font.pixelSize: 22
                    color: "#94A3B8"
                }

                ListView {
                    id: historyList
                    visible: BackendAuth.loginHistory.length > 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: BackendAuth.loginHistory
                    spacing: 10
                    clip: true
                    // 历史变化时刷新（loginHistoryChanged 触发 model 更新）
                    delegate: Rectangle {
                        width: historyList.width
                        height: 80
                        radius: 14
                        color: (selectedHistoryIndex === index) ? "#E0E7FF" : "#F7F7F7"
                        border.color: (selectedHistoryIndex === index) ? "#4361EE" : "#E2E8F0"
                        border.width: (selectedHistoryIndex === index) ? 2 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 14

                            // 头像占位（昵称首字）
                            Rectangle {
                                Layout.preferredWidth: 50
                                Layout.preferredHeight: 50
                                radius: 25
                                color: "#4361EE"
                                Text {
                                    anchors.centerIn: parent
                                    text: (modelData.userNm || "").charAt(0)
                                    font.family: "PingFang SC"
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: "#FFFFFF"
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                Text {
                                    text: modelData.userNm || ""
                                    font.family: "PingFang SC"
                                    font.pixelSize: 24
                                    font.bold: true
                                    color: "#1B263B"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                                Text {
                                    text: ((modelData.custNm || "") ? (modelData.custNm + "   ") : "")
                                          + "账号 ****" + String(modelData.userCode).slice(-4)
                                    font.family: "Microsoft YaHei"
                                    font.pixelSize: 18
                                    color: "#64748B"
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }

                        // 整行点击（选中该账号，登录由"登录"按钮触发）
                        MouseArea {
                            id: historyMA
                            anchors.fill: parent
                            onClicked: selectedHistoryIndex = index
                        }

                        // 删除按钮（覆盖在 historyMA 之上，z 更高）
                        Rectangle {
                            width: 40; height: 40; radius: 20
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.rightMargin: 10
                            color: delMA.pressed ? "#FEE2E2" : "transparent"
                            z: 2
                            Text {
                                anchors.centerIn: parent
                                text: "\u2715"
                                font.pixelSize: 20
                                color: "#94A3B8"
                            }
                            MouseArea {
                                id: delMA
                                anchors.fill: parent
                                z: 2
                                onClicked: BackendAuth.removeLoginHistory(index)
                            }
                        }
                    }
                }
            }
        }

        // 错误提示（绝对定位，不占 ColumnLayout 空间，避免挤压上方内容）
        Text {
            id: errorText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: loginStack.bottom
            anchors.topMargin: 4
            horizontalAlignment: Text.AlignHCenter
            font.family: "Microsoft YaHei"
            font.pixelSize: 24
            color: "#EF4444"

            visible: opacity > 0
            opacity: 0

            Behavior on opacity { NumberAnimation { duration: 200 } }

            SequentialAnimation on color {
                id: errorAnim
                running: false
                loops: 2
                ColorAnimation { from: "#EF4444"; to: "#F87171"; duration: 200 }
                ColorAnimation { from: "#F87171"; to: "#EF4444"; duration: 200 }
            }
        }

        // 按钮行：跳过 | 登录（左右并排，参照 SaveConfirmDialog 按钮样式）
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 60
            Layout.topMargin: 4

            RowLayout {
                anchors.centerIn: parent
                spacing: 20

                // 跳过按钮（左侧，浅蓝底）
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15
                    color: skipMA.containsMouse ? "#FFFFFF" : "#ECF1FE"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "跳过"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: "PingFang SC"
                        color: "#4649E5"
                    }

                    MouseArea {
                        id: skipMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: loginDialog.close()
                    }
                }

                // 登录按钮（右侧，蓝色实底；两种模式均显示）
                Rectangle {
                    width: 180
                    height: 60
                    radius: 15
                    visible: true
                    color: loginMA.containsMouse ? "#4649E5" : "#4361EE"

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Text {
                        anchors.centerIn: parent
                        text: "登录"
                        font.pixelSize: 24
                        font.bold: true
                        font.family: "PingFang SC"
                        color: "#FFFFFF"
                    }

                    MouseArea {
                        id: loginMA
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: doLogin()
                    }
                }
            }
        }
    }

    // 打开时初始化，自动填充保存的账号密码
    onOpened: {
        errorText.opacity = 0
        selectedHistoryIndex = -1
        // 有最近登录历史时默认进入快捷登录，方便直接选昵称登录
        loginMode = (BackendAuth.loginHistory.length > 0) ? 1 : 0
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
        onActivated: if (loginDialog.visible) doLogin()
    }

    // 外部遮罩层点击时调用（由 Main.qml 中的 loginOverlay 触发）
    function onOverlayClicked() {
        shakeAnim.start()
        hintText.text = "请登录或选择跳过"
        hintText.opacity = 1
        hintHideTimer.restart()
    }
}
