# 🚀 Handwriting 快速开始指南（5分钟上手）

## 当前状态检查

运行以下命令查看系统是否已安装 Handwriting 插件：

```bash
# 检查插件是否存在
ls -lh /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/ 2>/dev/null || echo "❌ 插件目录不存在"

# 检查中文模型是否存在
ls -lh /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat 2>/dev/null || echo "❌ 中文模型不存在"
```

---

## ⚡ 快速部署（3种方式）

### 方式 1️⃣：一键脚本（最简单）

```bash
cd /home/sjwu/SmartScale
sudo ./scripts/setup_handwriting.sh
```

### 方式 2️⃣：如果你有 Qt 完整安装

```bash
# 从你的 Qt 安装目录复制文件（示例路径）
cp ~/Qt/6.x.x/gcc_64/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/libqtvkbhandwritingplugin.so \
   /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/

cp ~/Qt/6.x.x/gcc_64/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat \
   /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/

# 设置权限
sudo chmod 755 /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/libqtvkbhandwritingplugin.so
sudo chmod 644 /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat
```

### 方式 3️⃣：从其他设备复制

如果你有另一台已经配置好的设备：

```bash
# 在已配置的设备上打包
tar czvf handwriting_plugin.tar.gz \
    /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/ \
    /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/

# 复制到目标设备并解压
scp handwriting_plugin.tar.gz user@target_device:/tmp/
ssh user@target_device "cd / && sudo tar xzvf /tmp/handwriting_plugin.tar.gz"
```

---

## 🔨 编译与测试

### 1. 编译项目

```bash
cd /home/sjwu/SmartScale/build
cmake ..
make -j$(nproc)
```

### 2. 运行测试

```bash
cd /home/sjwu/SmartScale/build
./appSmartScale
```

### 3. 测试手写功能

1. 登录后进入主界面
2. 点击任意文本输入框 → 键盘弹出
3. 点击键盘右上角的 **"中"** 按钮 → 切换到中文模式
4. 此时你应该能看到 **"✍手写" 按钮**（在"中"按钮左侧）
5. 点击 **"✍手写"** → 键盘变为手写面板
6. 用手指/触摸笔书写中文字符 ✍️
7. 点击 **"拼音"** 可切回拼音模式

---

## ❓ 如果遇到问题？

### 问题：看不到"✍手写"按钮

✅ **解决**: 确保你先点击了 **"中"** 按钮切换到中文模式（按钮只在中文模式下显示）

---

### 问题：点击手写按钮提示"插件未安装"

✅ **解决**: 说明 Handwriting 插件未正确安装，请运行：
```bash
sudo ./scripts/setup_handwriting.sh
```
按照脚本输出的指南操作。

---

### 问题：手写面板出现但无法识别中文

✅ **原因**: 缺少中文识别模型 `handwriting-zh_CN.dat`

**验证**:
```bash
file /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat
```

应该输出类似：`handwriting-zh_CN.dat: data` （二进制数据文件）

---

### 问题：想获取 Handwriting 插件但不知道从哪下载？

📦 **推荐方式**:

1. **Qt Online Installer** (官方免费)
   - 下载: https://www.qt.io/download-qt-installer-oss
   - 安装时勾选: `Qt Virtual Keyboard` 组件
   - 安装完成后按上述"方式 2" 复制文件

2. **从源码编译** (需要 Qt 开发环境)
   ```bash
   git clone https://code.qt.org/qt/qtvirtualkeyboard --branch v6.5.3
   cd qtvirtualkeyboard
   qmake CONFIG+=handwriting
   make -j$(nproc)
   # 产物在 plugins/ 和 qml/ 目录
   ```

3. **联系项目维护者**
   - 如果你使用的是预编译的 SmartScale 设备，
     可以联系设备提供商要求包含 Handwriting 插件的固件版本

---

## 🎯 下一步

如果测试成功，你可以考虑：

- [ ] 调整手写面板大小（修改 `InputPanel.scale` 属性）
- [ ] 默认启用手写模式（设置 `useHandwritingMode: true`）
- [ ] 添加更多语言支持（放入对应的 `.dat` 模型文件）
- [ ] 自定义手写按钮外观和位置
- [ ] 收集用户反馈优化识别准确率

详细文档请参阅：`docs/HANDWRITING_INPUT_GUIDE.md`

---

**祝使用愉快！** 🎉
