#!/bin/bash
#
# Qt VirtualKeyboard Handwriting 中文手写输入插件部署脚本
# 用于 SmartScale 项目集成中文手写识别功能
#
# 使用方法：
#   chmod +x setup_handwriting.sh
#   sudo ./setup_handwriting.sh
#

set -e  # 遇到错误立即退出

echo "========================================="
echo "  Qt VKB Handwriting 部署脚本"
echo "  SmartScale 项目 - 中文手写输入"
echo "========================================="
echo ""

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检测系统架构
ARCH=$(uname -m)
echo "[INFO] 系统架构: $ARCH"

# Qt6 安装路径（Debian/Ubuntu 默认）
QT6_PREFIX="/usr/lib/${ARCH}-linux-gnu/qt6"
QT6_PLUGINS="${QT6_PREFIX}/plugins"
QT6_QML="${QT6_PREFIX}/qml"

# 目标目录
VKB_DIR="${QT6_QML}/QtQuick/VirtualKeyboard"
HANDWRITING_PLUGIN_DIR="${VKB_DIR}/Plugins/Handwriting"
HANDWRITING_3RDPARTY_DIR="${VKB_DIR}/3rdparty/handwriting"

echo "[INFO] Qt6 路径: ${QT6_PREFIX}"
echo "[INFO] VKB 目录: ${VKB_DIR}"
echo ""

# ============================================================
# 步骤 1: 检查是否已安装 Handwriting 插件
# ============================================================
echo "[步骤 1] 检查 Handwriting 插件状态..."

if [ -f "${HANDWRITING_PLUGIN_DIR}/libqtvkbhandwritingplugin.so" ]; then
    echo -e "${GREEN}[OK]${NC} Handwriting 插件已存在"
    echo "      位置: ${HANDWRITING_PLUGIN_DIR}"
else
    echo -e "${YELLOW}[WARN]${NC} Handwriting 插件未安装，需要从源码编译或复制"
fi

if [ -f "${HANDWRITING_3RDPARTY_DIR}/handwriting-zh_CN.dat" ]; then
    echo -e "${GREEN}[OK]${NC} 中文手写识别模型已存在"
    echo "      位置: ${HANDWRITING_3RDPARTY_DIR}/handwriting-zh_CN.dat"
else
    echo -e "${RED}[MISSING]${NC} 中文手写识别模型 (handwriting-zh_CN.dat) 未找到！"
    echo "      这是实现中文手写输入的关键文件！"
fi

echo ""

# ============================================================
# 步骤 2: 尝试从系统包安装（如果可用）
# ============================================================
echo "[步骤 2] 检查系统包管理器..."

if command -v apt-get &> /dev/null; then
    echo "[INFO] 检测到 apt 包管理器，搜索 Handwriting 相关包..."
    
    # 搜索包含 handwriting 的包
    HANDWRITING_PACKAGES=$(apt-cache search qt6-virtualkeyboard | grep -i hand || true)
    
    if [ -n "$HANDWRITING_PACKAGES" ]; then
        echo -e "${GREEN}[FOUND]${NC} 找到以下相关包:"
        echo "$HANDWRITING_PACKAGES"
        echo ""
        read -p "是否尝试安装这些包？(y/N): " INSTALL_CHOICE
        if [ "$INSTALL_CHOICE" = "y" ] || [ "$INSTALL_CHOICE" = "Y" ]; then
            sudo apt-get update
            sudo apt-get install -y $(echo "$HANDWRITING_PACKAGES" | awk '{print $1}')
            echo -e "${GREEN}[OK]${NC} 包安装完成"
        fi
    else
        echo -e "${YELLOW}[WARN]${NC} 未找到 Handwriting 相关的系统包"
        echo "      需要手动从源码编译或从其他位置复制"
    fi
else
    echo -e "${YELLOW}[WARN]${NC} 非 Debian/Ubuntu 系统，跳过包管理器检查"
fi

echo ""

# ============================================================
# 步骤 3: 创建目录结构（如果不存在）
# ============================================================
echo "[步骤 3] 创建必要的目录结构..."

mkdir -p "${HANDWRITING_PLUGIN_DIR}"
mkdir -p "${HANDWRITING_3RDPARTY_DIR}"

echo -e "${GREEN}[OK]${NC} 目录已创建:"
echo "      ${HANDWRITING_PLUGIN_DIR}"
echo "      ${HANDWRITING_3RDPARTY_DIR}"
echo ""

# ============================================================
# 步骤 4: 从用户指定路径复制插件文件（可选）
# ============================================================
echo "[步骤 4] 复制 Handwriting 插件文件（如果已有）..."

# 常见的手写插件源路径（Qt 安装器安装的完整版 Qt）
COMMON_SOURCE_PATHS=(
    "$HOME/Qt/Tools/QtVirtualKeyboard/plugins/platforminputcontexts/libqtvkbhandwritingplugin.so"
    "$HOME/Qt/*/gcc_64/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/libqtvkbhandwritingplugin.so"
    "/opt/Qt*/Tools/QtVirtualKeyboard/plugins/platforminputcontexts/libqtvkbhandwritingplugin.so"
    "./plugins/handwriting/libqtvkbhandwritingplugin.so"
)

PLUGIN_FOUND=false
MODEL_FOUND=false

for SOURCE_PATH in "${COMMON_SOURCE_PATHS[@]}"; do
    # 展开 glob
    for EXPANDED_PATH in $SOURCE_PATH; do
        if [ -f "$EXPANDED_PATH" ] && [ ! -L "$EXPANDED_PATH" ]; then
            echo -e "${GREEN}[FOUND]${NC} 找到 Handwriting 插件: ${EXPANDED_PATH}"
            cp "$EXPANDED_PATH" "${HANDWRITING_PLUGIN_DIR}/"
            chmod 755 "${HANDWRITING_PLUGIN_DIR}/libqtvkbhandwritingplugin.so"
            PLUGIN_FOUND=true
            echo -e "${GREEN}[OK]${NC] 已复制到: ${HANDWRITING_PLUGIN_DIR}/"
            break 2
        fi
    done
done

# 查找中文手写识别模型
MODEL_SOURCE_PATHS=(
    "$HOME/Qt/*/gcc_64/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat"
    "$HOME/Qt/Tools/QtVirtualKeyboard/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat"
    "./resources/handwriting-zh_CN.dat"
)

for MODEL_PATH in "${MODEL_SOURCE_PATHS[@]}"; do
    for EXPANDED_MODEL in $MODEL_PATH; do
        if [ -f "$EXPANDED_MODEL" ] && [ ! -L "$EXPANDED_MODEL" ]; then
            echo -e "${GREEN}[FOUND]${NC} 找到中文手写模型: ${EXPANDED_MODEL}"
            cp "$EXPANDED_MODEL" "${HANDWRITING_3RDPARTY_DIR}/"
            chmod 644 "${HANDWRITING_3RDPARTY_DIR}/handwriting-zh_CN.dat"
            MODEL_FOUND=true
            echo -e "${GREEN}[OK]${NC} 已复制到: ${HANDWRITING_3RDPARTY_DIR}/"
            break 2
        fi
    done
done

echo ""

# ============================================================
# 步骤 5: 验证安装结果
# ============================================================
echo "[步骤 5] 验证安装结果..."
echo ""

INSTALL_SUCCESS=true

echo "-----------------------------------------"
echo "安装结果汇总:"
echo "-----------------------------------------"

if [ -f "${HANDWRITING_PLUGIN_DIR}/libqtvkbhandwritingplugin.so" ]; then
    echo -e "✅ Handwriting 插件:     ${GREEN}已安装${NC}"
    ls -lh "${HANDWRITING_PLUGIN_DIR}/libqtvkbhandwritingplugin.so"
else
    echo -e "❌ Handwriting 插件:     ${RED}未安装${NC}"
    INSTALL_SUCCESS=false
fi

if [ -f "${HANDWRITING_3RDPARTY_DIR}/handwriting-zh_CN.dat" ]; then
    echo -e "✅ 中文识别模型:       ${GREEN}已安装${NC}"
    ls -lh "${HANDWRITING_3RDPARTY_DIR}/handwriting-zh_CN.dat"
else
    echo -e "❌ 中文识别模型:       ${RED}未安装${NC}"
    INSTALL_SUCCESS=false
fi

echo ""

# ============================================================
# 步骤 6: 显示后续操作指南
# ============================================================
echo "========================================="
echo "  部署完成"
echo "========================================="

if [ "$INSTALL_SUCCESS" = true ]; then
    echo -e "${GREEN}[SUCCESS]${NC} 所有必需文件已安装成功！"
    echo ""
    echo "下一步操作:"
    echo "  1. 重新编译 SmartScale 项目:"
    echo "     cd build && cmake .. && make -j\$(nproc)"
    echo ""
    echo "  2. 运行程序并测试手写功能:"
    echo "     ./appSmartScale"
    echo ""
    echo "  3. 在中文模式下，点击键盘上的'✍手写'按钮切换到手写模式"
else
    echo -e "${WARNING}[PARTIAL]${NC} 部分文件缺失，请参考下方指南手动安装"
    echo ""
fi

echo ""
echo "========================================="
echo "  手动安装指南（如果自动安装失败）"
echo "========================================="
echo ""
echo "方案 A: 从 Qt 官方安装器获取（推荐）"
echo "----------------------------------------"
echo "1. 下载并运行 Qt Online Installer:"
echo "   https://www.qt.io/download-qt-installer"
echo ""
echo "2. 选择安装 Qt 6.x 版本"
echo ""
echo "3. 在组件选择界面，勾选:"
echo "   □ Qt Virtual Keyboard (完整版，非精简版)"
echo ""
echo "4. 安装完成后，从以下路径复制文件:"
echo "   插件: <Qt安装路径>/Tools/QtVirtualKeyboard/"
echo "         plugins/platforminputcontexts/"
echo "         → libqtvkbhandwritingplugin.so"
echo ""
echo "   模型: <Qt安装路径>/Tools/QtVirtualKeyboard/"
echo "         qml/QtQuick/VirtualKeyboard/3rdparty/"
echo "         handwriting/handwriting-zh_CN.dat"
echo ""
echo "方案 B: 从源码编译（高级）"
echo "----------------------------------------"
echo "# 克隆 Qt VirtualKeyboard 源码"
echo "git clone https://code.qt.org/qt/qtvirtualkeyboard"
echo "cd qtvirtualkeyboard"
echo ""
echo "# 配置（启用 Handwriting 支持）"
echo "qmake CONFIG+=handwriting"
echo ""
echo "# 编译"
echo "make -j\$(nproc)"
echo ""
echo "# 编译产物位于:"
echo "# plugins/platforminputcontexts/libqtvkbhandwritingplugin.so"
echo "# qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/"
echo ""
echo "方案 C: 从其他系统复制"
echo "----------------------------------------"
echo "如果你在其他机器上已经安装了完整版 Qt VirtualKeyboard，"
echo "可以直接复制以下文件到目标设备:"
echo ""
echo "  文件 1: libqtvkbhandwritingplugin.so"
echo "  目标: ${HANDWRITING_PLUGIN_DIR}/"
echo ""
echo "  文件 2: handwriting-zh_CN.dat (关键！)"
echo "  目标: ${HANDWRITING_3RDPARTY_DIR}/"
echo ""
echo "========================================="
echo ""
echo "常见问题排查:"
echo "----------------------------------------"
echo "Q: 切换到手写模式后没有反应?"
echo "A: 检查插件文件权限: ls -l ${HANDWRITING_PLUGIN_DIR}/"
echo "   确保是 755 权限且不是符号链接"
echo ""
echo "Q: 手写后无法识别中文字符?"
echo "A: 确认 handwriting-zh_CN.dat 文件存在且可读"
echo "   该文件包含中文手写识别的神经网络模型"
echo ""
echo "Q: 手写面板显示异常?"
echo "A: 检查 Qt 版本兼容性，Handwriting 插件需要匹配的 Qt6 版本"
echo "   当前 Qt6 版本: \$(qmake6 --query QT_VERSION 2>/dev/null || echo '未知')"
echo ""
echo "========================================="
echo "  脚本执行完毕"
echo "========================================="
