#!/usr/bin/env bash
#
# SmartScale 更新包打包脚本
# 用法:
#   ./make_update_package.sh <版本号> [build目录]
# 例:
#   ./make_update_package.sh 2.13.3.24
#   ./make_update_package.sh 2.13.3.24 /home/sjwu/SmartScale/build
#
# 产出:
#   ./smartscale-<版本号>.tar.gz   更新包(内含 appSmartScale + AI/ 模型 + manifest.json)
#   manifest.json 同时承载版本号/说明/文件校验信息, 不单独生成外置 json
#
# 说明:
#   build/AI 目录存在时会整目录打进更新包(手写识别 rec.onnx 等模型随包分发),
#   由 apply_update.sh 在刷写时同步到应用目录。若只需增量分发, 可先清理 build/AI。
#
set -euo pipefail

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "用法: $0 <版本号> [build目录]" >&2
  exit 1
fi

BUILD_DIR="${2:-/home/sjwu/SmartScale/build}"
APP_BIN="${BUILD_DIR}/appSmartScale"

if [ ! -f "$APP_BIN" ]; then
  echo "错误: 未找到二进制文件 ${APP_BIN}" >&2
  exit 1
fi

OUT_DIR="$(pwd)"
PKG_NAME="smartscale-${VERSION}.tar.gz"
PKG_PATH="${OUT_DIR}/${PKG_NAME}"

# 1. 计算二进制自身的 sha256(用于解压后校验)
BIN_SHA="$(sha256sum "$APP_BIN" | awk '{print $1}')"

# 2. 在 build 目录生成临时 manifest(版本元信息 + 文件清单), 打包后清理
cd "$BUILD_DIR"

# 资源目录(可选): 存在则随包分发(appSmartScale 之外的文件)
#   注意（2026-09-19 起）：键盘样式与手写模型（AI/rec.onnx、AI/ppocrv5_dict.txt）
#   已改为**内嵌进 appSmartScale**（app.qrc → EmbeddedAssets 启动时按需释放），
#   默认不再随包分发：一是缩小包体，二是老设备第一次 OTA 时执行的旧脚本只 cp 一个
#   appSmartScale，包内其它目录会被忽略（AI/ 与 keyboard_styles/ 都到不了设备）。
#   如需临时用包分发某个目录（例如做模型 A/B 验证），把它加进下面的 ASSET_DIRS 即可。
ASSET_DIRS=()
TAR_ITEMS=(appSmartScale manifest.json)
FILE_ENTRIES="    { \"name\": \"appSmartScale\", \"sha256\": \"${BIN_SHA}\" }"
for asset_dir in ${ASSET_DIRS[@]+"${ASSET_DIRS[@]}"}; do
  abs_asset="${BUILD_DIR}/${asset_dir}"
  [ -d "$abs_asset" ] || continue
  while IFS= read -r abs_path; do
    rel_path="${abs_path#${BUILD_DIR}/}"
    file_sha="$(sha256sum "$abs_path" | awk '{print $1}')"
    FILE_ENTRIES="${FILE_ENTRIES},
    { \"name\": \"${rel_path}\", \"sha256\": \"${file_sha}\" }"
  done < <(find "$abs_asset" -type f | LC_ALL=C sort)
  TAR_ITEMS+=("$asset_dir")
  echo "已包含资源目录 ${asset_dir}: $(find "$abs_asset" -type f | wc -l) 个文件"
done

cat > manifest.json <<EOF
{
  "version": "${VERSION}",
  "notes": "SmartScale ${VERSION} 更新包",
  "force": false,
  "url": "https://<YOUR_SERVER>/update/${PKG_NAME}",
  "files": [
${FILE_ENTRIES}
  ]
}
EOF
tar -czf "$PKG_PATH" "${TAR_ITEMS[@]}"
rm -f manifest.json

# 3. 计算包自身的 sha256 与大小(供服务器/下载方记录)
PKG_SHA="$(sha256sum "$PKG_PATH" | awk '{print $1}')"
PKG_SIZE="$(stat -c%s "$PKG_PATH")"
PKG_HUMAN="$(du -h "$PKG_PATH" | cut -f1)"

echo "================ 打包完成 ================"
echo "更新包      : ${PKG_PATH}"
echo "包大小      : ${PKG_HUMAN} (${PKG_SIZE} bytes)"
echo "包 SHA256   : ${PKG_SHA}"
echo ""
echo "下一步:"
echo "  1. 将 ${PKG_NAME} 上传到静态文件服务器"
echo "  2. 修改包内 manifest.json 的 url 为实际可访问地址(或解压改后重打包)"
echo "=========================================="
