import QtQuick
import QtQuick.Controls

// ============================================================
// LogoutConfirmDialog — 退出登录确认弹窗
//
// 内部委托给 AlertDialog 实现，保持原有 API 完全不变：
//   signal logoutConfirmed()
//   .open()
//   .close()
//
// 用法（与之前完全一致）:
//   LogoutConfirmDialog {
//       id: logoutConfirmDialog
//       onLogoutConfirmed: window.appLogout()
//   }
//   logoutConfirmDialog.open()
// ============================================================
Item {
    id: wrapper

    // ---- 对外接口（保持不变） ----
    signal logoutConfirmed()

    function open() {
        _alert.confirm(
            "确定要退出当前账号吗？",
            function() { wrapper.logoutConfirmed(); },
            "退出登录",     // title
            "取消",         // cancelText
            "退出登录"      // actionText
        )
        _alert.dangerMode = true
    }

    function close() {
        _alert.close()
    }

    // ---- 委托给 AlertDialog ----
    AlertDialog {
        id: _alert
        parent: wrapper.parent || null  // 使用与 wrapper 相同的父级，确保层级正确
    }
}
