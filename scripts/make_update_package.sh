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
#   ./smartscale-<版本号>.tar.gz   更新包(内含 appSmartScale + manifest.json)
#   manifest.json 同时承载版本号/说明/文件校验信息, 不单独生成外置 json
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
cat > manifest.json <<EOF
{
  "version": "${VERSION}",
  "notes": "SmartScale ${VERSION} 更新包",
  "force": false,
  "url": "https://<YOUR_SERVER>/update/${PKG_NAME}",
  "files": [
    { "name": "appSmartScale", "sha256": "${BIN_SHA}" }
  ]
}
EOF
tar -czf "$PKG_PATH" appSmartScale manifest.json
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
