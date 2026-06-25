import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// ============================================================
// LogoutConfirmDialog — 退出登录确认弹窗
// 用法：
//   LogoutConfirmDialog {
//       id: logoutConfirmDialog
//       onLogoutConfirmed: window.appLogout()
//   }
//   logoutConfirmDialog.open()
// ============================================================
Dialog {
    id: dialogRoot

    // ---- 对外接口 ----
    signal logoutConfirmed()

    title: "退出登录"
    x: (parent.width - width) / 2
    y: (parent.height - height) / 2
    width: 360
    height: 180
    modal: true
    Overlay.modal: Rectangle { color: "#80000000" }   // 显式遮罩
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
                    onClicked: dialogRoot.close()
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
                        dialogRoot.close()
                        dialogRoot.logoutConfirmed()
                    }
                }
            }
        }
    }
}
