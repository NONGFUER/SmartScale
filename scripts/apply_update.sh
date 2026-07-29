#!/usr/bin/env bash
#
# SmartScale OTA 刷写脚本（由 OtaService::install() 以 startDetached 调用）
#
# 用法:
#   apply_update.sh <更新包路径> <应用目录> [systemd服务名]
#
# 流程:
#   权限探测(sudo -n) → 解压 → manifest 二次校验 → 探测 systemd service
#   → 停应用 → 备份 appSmartScale.bak.<ts> → 新版就位 → 拉起
#   → 30s 存活验证 → 成功写 result.success / 失败恢复 .bak 并写 result.rolledback
#
# 退出码:
#   0 成功 | 1 参数/包/备份错误 | 2 解压/manifest 校验失败 | 3 权限不足
#   4 拉起失败(已回滚) | 5 存活验证失败(已回滚)
#
set -uo pipefail

log() { echo "[apply_update] $(date '+%H:%M:%S') $*"; }

PKG="${1:-}"
APP_DIR="${2:-}"
SVC_OVERRIDE="${3:-${SMARTSCALE_SERVICE:-}}"

if [ -z "$PKG" ] || [ -z "$APP_DIR" ]; then
  echo "用法: $0 <更新包路径> <应用目录> [systemd服务名]" >&2
  exit 1
fi

APP_BIN="${APP_DIR}/appSmartScale"
OTA_DIR="${APP_DIR}/data/ota"
mkdir -p "$OTA_DIR"

# 目标版本（写入 result 标记用）：优先 pending.json，回退包文件名
VERSION="$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "${OTA_DIR}/pending.json" 2>/dev/null \
           | head -1 | sed 's/.*"\([^"]*\)"$/\1')"
[ -z "$VERSION" ] && VERSION="$(basename "$PKG" .tar.gz)"

# ---------- 1. 权限：非 root 时用 sudo -n 重新执行本脚本（防死循环用 OTA_SUDO 标记） ----------
if [ "$(id -u)" != "0" ]; then
  if [ "${OTA_SUDO:-0}" = "1" ]; then
    log "错误: sudo -n 提权失败（需要免密 sudo 或 root 运行）"
    exit 3
  fi
  log "非 root 运行，尝试 sudo -n 提权"
  # 先预检 sudo -n 可用性，再 exec（退出码自然透传；env 传标记兼容 env_reset）
  if ! sudo -n true 2>/dev/null; then
    log "错误: sudo -n 提权失败（需要免密 sudo 或 root 运行）"
    exit 3
  fi
  OTA_SUDO=1 exec sudo -n env OTA_SUDO=1 bash "$0" "$PKG" "$APP_DIR" "$SVC_OVERRIDE"
fi

if [ ! -f "$PKG" ]; then
  log "错误: 更新包不存在: $PKG"
  exit 1
fi
if [ ! -f "$APP_BIN" ]; then
  log "错误: 应用二进制不存在: $APP_BIN"
  exit 1
fi

# ---------- 2. 解压到临时目录 ----------
TMP_DIR="$(mktemp -d /tmp/ota_extract.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
if ! tar -xzf "$PKG" -C "$TMP_DIR"; then
  log "错误: 解压失败: $PKG"
  exit 2
fi
if [ ! -f "${TMP_DIR}/appSmartScale" ]; then
  log "错误: 包内缺少 appSmartScale"
  exit 2
fi

# ---------- 3. manifest 二次校验（files[].sha256 对照实际文件） ----------
if [ -f "${TMP_DIR}/manifest.json" ]; then
  EXPECT_SHA="$(grep -o '"sha256"[[:space:]]*:[[:space:]]*"[a-fA-F0-9]\{64\}"' \
                "${TMP_DIR}/manifest.json" | head -1 | grep -o '[a-fA-F0-9]\{64\}')"
  if [ -n "$EXPECT_SHA" ]; then
    ACTUAL_SHA="$(sha256sum "${TMP_DIR}/appSmartScale" | awk '{print $1}')"
    if [ "${ACTUAL_SHA,,}" != "${EXPECT_SHA,,}" ]; then
      log "错误: manifest 校验失败 actual=$ACTUAL_SHA expect=$EXPECT_SHA"
      exit 2
    fi
    log "manifest 校验通过: $ACTUAL_SHA"
  fi
fi

# ---------- 4. 探测 systemd service（可用第 3 参数/环境变量覆盖） ----------
SVC="$SVC_OVERRIDE"
if [ -z "$SVC" ]; then
  SVC="$(systemctl list-units --type=service --all --no-legend 2>/dev/null \
         | awk '{print $1}' | grep -i 'smartscale' | head -1)"
fi
if [ -n "$SVC" ]; then
  log "使用 systemd service: $SVC"
else
  log "未探测到 systemd service，使用 kill + 直接拉起兜底"
fi

# ---------- 5. 给用户看到"正在安装"的缓冲时间 ----------
sleep 2

# ---------- 6. 停应用（必须等待进程真正退出，否则旧进程仍持有 /dev/ttyAMA0 的 flock 锁，
#              新进程拉起时会报 "Permission error while locking the device" 而无法开串口） ----------
log "停止应用..."
if [ -n "$SVC" ]; then
  systemctl stop "$SVC"
else
  pkill -x appSmartScale 2>/dev/null
fi

# 等待应用进程彻底退出（最多 15s）；SIGTERM 未生效则升级 SIGKILL
for _ in $(seq 1 15); do
  pgrep -x appSmartScale >/dev/null 2>&1 || break
  sleep 1
done
if pgrep -x appSmartScale >/dev/null 2>&1; then
  log "应用 15s 内未退出，发送 SIGKILL"
  pkill -9 -x appSmartScale 2>/dev/null
  sleep 1
fi

# ---------- 7. 备份（保留最近 2 份 .bak，滚动清理） ----------
BAK="${APP_BIN}.bak.$(date +%Y%m%d%H%M%S)"
if ! cp -a "$APP_BIN" "$BAK"; then
  log "错误: 备份失败"
  # 备份失败未做任何替换，直接拉起原应用
  if [ -n "$SVC" ]; then systemctl start "$SVC"; fi
  exit 1
fi
log "已备份: $BAK"
# shellcheck disable=SC2012
ls -1t "${APP_BIN}.bak."* 2>/dev/null | tail -n +3 | xargs -r rm -f

# ---------- 8. 新版就位 ----------
if ! cp "${TMP_DIR}/appSmartScale" "$APP_BIN"; then
  log "错误: 新二进制写入失败，恢复原备份"
  cp -a "$BAK" "$APP_BIN"
  if [ -n "$SVC" ]; then systemctl start "$SVC"; fi
  echo "$VERSION" > "${OTA_DIR}/result.rolledback"
  exit 4
fi
chmod 755 "$APP_BIN"
sync

# ---------- 9. 拉起应用 ----------
log "拉起应用..."
if [ -n "$SVC" ]; then
  systemctl start "$SVC"
else
  (cd "$APP_DIR" && nohup "$APP_BIN" >/dev/null 2>&1 &)
fi

# ---------- 10. 存活验证：60s 内等进程出现，出现后 30s 稳定性观察 ----------
rollback_and_exit() {
  local code="$1" reason="$2"
  log "回滚: $reason"
  cp -a "$BAK" "$APP_BIN"
  sync
  if [ -n "$SVC" ]; then
    systemctl restart "$SVC"
  else
    pkill -x appSmartScale 2>/dev/null
    # 同样等待旧进程退出，避免残留占用串口锁/二进制
    for _ in $(seq 1 15); do pgrep -x appSmartScale >/dev/null 2>&1 || break; sleep 1; done
    (cd "$APP_DIR" && nohup "$APP_BIN" >/dev/null 2>&1 &)
  fi
  echo "$VERSION" > "${OTA_DIR}/result.rolledback"
  exit "$code"
}

NEW_PID=""
for _ in $(seq 1 30); do
  sleep 2
  NEW_PID="$(pgrep -x appSmartScale | head -1)"
  [ -n "$NEW_PID" ] && break
done
if [ -z "$NEW_PID" ]; then
  rollback_and_exit 4 "60s 内进程未出现"
fi
log "进程已出现: pid=$NEW_PID，开始 30s 稳定性观察"

for _ in $(seq 1 6); do
  sleep 5
  if ! kill -0 "$NEW_PID" 2>/dev/null; then
    rollback_and_exit 5 "进程在 30s 观察期内退出"
  fi
done

# ---------- 11. 成功 ----------
echo "$VERSION" > "${OTA_DIR}/result.success"
rm -f "$PKG"
log "升级成功: $VERSION"
exit 0
