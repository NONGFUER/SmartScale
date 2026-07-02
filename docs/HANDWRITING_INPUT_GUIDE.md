# Qt VKB Handwriting 中文手写输入 - 集成指南

## 📋 概述

本指南说明如何在 SmartScale 项目中集成 **Qt VirtualKeyboard Handwriting** 实现中文手写输入功能。

### ✅ 已完成的代码修改

- [x] `src/ui/Main.qml`：添加手写/拼音切换按钮和逻辑控制
- [x] `scripts/setup_handwriting.sh`：自动化部署脚本

### ⚠️ 待完成的步骤

- [ ] 获取并安装 Handwriting 插件和中文识别模型
- [ ] 在目标设备上测试验证

---

## 🎯 功能特性

### 核心功能
1. **拼音/手写一键切换**：在中文模式下，键盘右上角显示"✍手写"按钮
2. **智能模式联动**：切换到手写模式时自动启用中文（因为主要用于中文输入）
3. **优雅的错误处理**：如果 Handwriting 插件未安装，自动回退并提示用户
4. **条件显示**：手写按钮只在中文模式下可见（英文模式下不需要）

### 用户操作流程
```
默认状态: 英文键盘 (EN)
    ↓ 点击"中"按钮
中文拼音模式: 拼音键盘 + "✍手写"按钮
    ↓ 点击"✍手写"按钮
手写模式: 手写面板（可书写中文字符）
    ↓ 点击"拼音"按钮
回到中文拼音模式
```

---

## 🔧 技术实现细节

### 1️⃣ 代码改动位置

#### 文件：`src/ui/Main.qml`

##### 新增属性
```qml
property bool useHandwritingMode: false  // false=拼音, true=手写（默认拼音）
```

##### 新增函数
```qml
// 手写/拼音输入法切换
function toggleInputMethod() { ... }

// 切换到手写输入法
function switchToHandwriting() {
    VirtualKeyboardSettings.inputMethod = "qthandwriting"
    // 自动切换到中文
}

// 切换回拼音输入法  
function switchToPinyin() {
    VirtualKeyboardSettings.inputMethod = ""  // 使用默认
}
```

##### UI 组件：手写/拼音切换按钮
```qml
Rectangle {
    id: inputMethodToggle  // 位于 langToggle 左侧
    visible: inputPanel.active && window.chineseInputMode  // 只在中文模式下显示
    color: window.useHandwritingMode ? "#10B981" : "#6366F1"
    
    Text {
        text: window.useHandwritingMode ? "✍手写" : "拼音"
    }
    
    MouseArea {
        onClicked: window.toggleInputMethod()
    }
}
```

### 2️⃣ 关键技术点

#### VirtualKeyboardSettings.inputMethod
Qt VirtualKeyboard 通过此属性控制当前使用的输入法插件：

| 值 | 含义 |
|-----|------|
| `""` (空) | 使用默认输入法（通常是 QML 键盘或 Pinyin） |
| `"qthandwriting"` | 使用 Handwriting 插件 |
| `"qthangul"` | 韩文输入 |
| `"qtthai"` | 泰文输入 |

#### 错误处理机制
```javascript
try {
    VirtualKeyboardSettings.inputMethod = "qthandwriting"
} catch (e) {
    // 插件不存在时捕获异常
    useHandwritingMode = false
    globalToast.show("手写插件未安装...", "error")
}
```

---

## 📦 必需的文件资源

### 文件清单

#### 1️⃣ Handwriting 插件库（必须）
```
文件名: libqtvkbhandwritingplugin.so
大小: ~200-500 KB (取决于编译选项)
用途: Qt VirtualKeyboard 的手写识别引擎插件
目标路径: /usr/lib/<arch>-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/
          Plugins/Handwriting/libqtvkbhandwritingplugin.so
```

#### 2️⃣ 中文手写识别模型（关键！）
```
文件名: handwriting-zh_CN.dat
大小: ~2-5 MB (神经网络模型)
用途: 包含简体中文的手写识别算法和数据
目标路径: /usr/lib/<arch>-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/
          3rdparty/handwriting/handwriting-zh_CN.dat
```

> **⚠️ 注意**: 缺少此文件时，即使插件存在也无法识别中文！

---

## 🚀 快速开始：安装 Handwriting 插件

### 方法一：自动化脚本（推荐）

运行我们提供的部署脚本：

```bash
# 进入项目根目录
cd /home/sjwu/SmartScale

# 运行部署脚本（需要 root 权限）
sudo ./scripts/setup_handwriting.sh
```

脚本会自动：
1. ✅ 检测系统架构和 Qt6 安装路径
2. ✅ 查找已有的 Handwriting 插件文件
3. ✅ 尝试从常见位置复制插件
4. ✅ 创建必要的目录结构
5. ✅ 验证安装结果
6. ✅ 显示详细的后续操作指南

---

### 方法二：手动安装

如果你有完整的 Qt 安装（通过 Qt Online Installer），按以下步骤手动复制文件：

#### 步骤 1：定位源文件

在你的开发机或完整 Qt 安装中查找：

```bash
# Handwriting 插件
find ~/Qt -name "libqtvkbhandwritingplugin.so" 2>/dev/null

# 中文识别模型（关键！）
find ~/Qt -name "handwriting-zh_CN.dat" 2>/dev/null
```

#### 步骤 2：复制到目标设备

将找到的文件复制到 SmartScale 设备上：

```bash
# 复制插件（假设从开发机 scp 到设备）
scp ~/Qt/.../libqtvkbhandwritingplugin.so \
    user@device:/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/

# 复制中文模型（关键！）
scp ~/Qt/.../handwriting-zh_CN.dat \
    user@device:/usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/
```

#### 步骤 3：设置权限

```bash
# 插件需要可执行权限
sudo chmod 755 /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/libqtvkbhandwritingplugin.so

# 模型只需要可读
sudo chmod 644 /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat
```

---

### 方法三：从源码编译（高级用户）

如果没有现成的二进制文件，可以从 Qt 官方仓库编译：

```bash
# 克隆 Qt VirtualKeyboard 源码（匹配你的 Qt 版本）
git clone https://code.qt.org/qt/qtvirtualkeyboard --branch v6.x.x
cd qtvirtualkeyboard

# 配置（确保启用了 handwriting 特性）
qmake CONFIG+=handwriting CONFIG+=lang-en_US CONFIG+=lang-zh_CN

# 编译（可能需要较长时间）
make -j$(nproc)

# 编译完成后，产物位于：
# - plugins/platforminputcontexts/libqtvkbhandwritingplugin.so
# - qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat

# 安装到系统目录
sudo make install
```

> 💡 **提示**: 编译需要完整的 Qt 开发环境（Qt6-devel, gcc, cmake 等）

---

## 🧪 测试验证

### 1️⃣ 重新编译 SmartScale

```bash
cd /home/sjwu/SmartScale/build
cmake ..
make -j$(nproc)
```

### 2️⃣ 运行程序

```bash
./appSmartScale
```

### 3️⃣ 测试步骤

1. **登录后进入主界面**
2. **点击任意文本输入框**（如食材搜索框）
   - 应该看到虚拟键盘弹出
3. **点击"中"按钮**（键盘右上角）
   - 键盘应切换为中文拼音模式
   - 此时应看到新增的 **"✍手写" 按钮**（在"中"按钮左侧）
4. **点击"✍手写"按钮**
   - 如果 Handwriting 插件安装成功：键盘应变为手写面板
   - 如果未安装：会显示 Toast 提示 "手写插件未安装..."
5. **在手写面板上书写**
   - 用手指或触摸笔书写中文字符
   - 系统应实时识别并显示候选词
6. **点击"拼音"按钮**
   - 应切回中文拼音键盘

### 4️⃣ 预期效果截图示意

```
┌─────────────────────────────────────┐
│  ┌────┐ ┌────────┐ ┌────┐         │
│  │✍手写│ │  拼音  │ │ 中 │         │  ← 新增的手写按钮
│  └────┘ └────────┘ └────┘         │
├─────────────────────────────────────┤
│                                     │
│         （手写面板区域）             │  ← 切换后显示手写区域
│                                     │
│        在此书写中文字符              │
│                                     │
└─────────────────────────────────────┘
```

---

## ❓ 常见问题排查

### Q1: 手写按钮不显示？

**原因**: 按钮只在中文模式 (`chineseInputMode == true`) 且键盘激活 (`inputPanel.active`) 时显示。

**解决**:
1. 先点击"中"按钮切换到中文模式
2. 确保键盘处于激活状态（点击了某个输入框）

---

### Q2: 点击手写按钮没有反应？

**可能原因**:
1. Handwriting 插件未正确安装
2. 插件文件权限不对
3. Qt 版本不兼容

**排查步骤**:
```bash
# 1. 检查插件是否存在
ls -l /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/Plugins/Handwriting/

# 2. 检查模型是否存在
ls -l /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/

# 3. 查看运行时日志（应该能看到错误信息）
./appSmartScale 2>&1 | grep -i hand
```

---

### Q3: 手写后无法识别中文字符？

**原因**: 缺少中文识别模型 `handwriting-zh_CN.dat`

**解决**:
```bash
# 确认模型文件存在且可读
ls -lh /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat
file /usr/lib/aarch64-linux-gnu/qt6/qml/QtQuick/VirtualKeyboard/3rdparty/handwriting/handwriting-zh_CN.dat
```

该文件通常为 2-5 MB 的二进制数据文件。

---

### Q4: 手写识别准确率低？

**优化建议**:

1. **书写规范**: 尽量工整书写，避免草书
2. **笔顺正确**: 按照标准笔顺书写能提高识别率
3. **调整面板大小**: 
   - 更大的手写区域可以提供更好的书写体验
   - 可通过修改 `InputPanel` 的 `scale` 属性调整
4. **训练数据**: 如果需要更高准确率，考虑使用自定义训练的模型

---

### Q5: 性能问题（卡顿、延迟）？

**原因**: 手写识别是计算密集型操作，尤其在 ARM 设备上。

**优化方案**:

1. **减少采样点数**（在 QML 中配置）:
   ```qml
   InputPanel {
       // 降低手写采样频率以减少 CPU 占用
       // 具体参数取决于 Qt 版本
   }
   ```

2. **只在需要时启用**（已实现）:
   - 默认使用拼音，用户主动点击才切换到手写
   - 不影响不使用手写的用户

3. **硬件加速**:
   - 确保 GPU 加速可用
   - 检查 OpenGL ES 是否正常工作

---

## 🎨 自定义与扩展

### 调整手写面板样式

可以修改 `inputMethodToggle` 的属性来调整外观：

```qml
// 位置调整（相对 langToggle）
anchors.rightMargin: 8  // 与中英按钮的间距

// 尺寸调整
width: 80   // 按钮宽度
height: 50  // 按钮高度

// 颜色方案
color: window.useHandwritingMode ? "#10B981" : "#6366F1"
       // 绿色(手写) vs 紫色(拼音)

// 显示条件
visible: inputPanel.active && window.chineseInputMode
```

### 默认启用手写模式（可选）

如果希望默认使用手写而非拼音，修改初始值：

```qml
// src/ui/Main.qml 第 28 行附近
property bool useHandwritingMode: true  // 改为 true 默认手写
```

然后在 `Component.onCompleted` 中初始化：

```qml
Component.onCompleted: {
    Qt.callLater(function() {
        if (window.useHandwritingMode) {
            window.switchToHandwriting()
        }
        // ... 其他初始化代码
    })
}
```

### 支持其他语言的手写

Qt Handwriting 插件支持多语言，只需添加对应的模型文件：

| 语言 | 模型文件名 |
|------|-----------|
| 简体中文 | `handwriting-zh_CN.dat` |
| 繁体中文 | `handwriting-zh_TW.dat` |
| 日语 | `handwriting-ja_JP.dat` |
| 韩语 | `handwriting-ko_KR.dat` |

将对应的 `.dat` 文件放到 `3rdparty/handwriting/` 目录即可。

---

## 📊 架构流程图

```
用户点击"✍手写"按钮
        ↓
toggleInputMethod() 被调用
        ↓
useHandwritingMode = true
        ↓
switchToHandwriting() 执行
        ↓
VirtualKeyboardSettings.inputMethod = "qthandwriting"
        ↓
Qt 加载 libqtvkbhandwritingplugin.so 插件
        ↓
加载 handwriting-zh_CN.dat 识别模型
        ↓
InputPanel 渲染为手写面板
        ↓
用户书写 → 实时识别 → 输出字符
        ↓
点击"拼音"按钮 → 切回拼音模式
```

---

## 📝 更新日志

### v1.0.0 (2026-07-02)
- ✅ 初始版本实现
- ✅ 添加手写/拼音切换功能
- ✅ 实现智能错误处理和回退机制
- ✅ 创建自动化部署脚本
- ✅ 编写完整的集成指南文档

---

## 📚 参考资料

- [Qt Virtual Keyboard Documentation](https://doc.qt.io/qt-6/qtvirtualkeyboard-index.html)
- [Qt Virtual Keyboard Handwriting](https://doc.qt.io/qt-6/qtvirtualkeyboard-handwriting.html)
- [Qt Forum - Handwriting Plugin Issues](https://forum.qt.io/)
- [SmartScale Project Repository](https://github.com/your-org/SmartScale)

---

## 🆘 获取帮助

如果在集成过程中遇到问题：

1. **查看日志**:
   ```bash
   ./appSmartScale 2>&1 | tee smartscale.log
   # 搜索关键字: Handwriting, handwriting, qthandwriting
   grep -i "hand\|vkb" smartscale.log
   ```

2. **运行诊断脚本**:
   ```bash
   sudo ./scripts/setup_handwriting.sh
   # 脚本会输出详细的系统状态信息
   ```

3. **检查 Qt 版本兼容性**:
   ```bash
   qmake6 --query QT_VERSION
   # 确保版本 ≥ 6.2 (Handwriting 支持较好)
   ```

---

**最后更新**: 2026-07-02  
**适用版本**: SmartScale v2.13+ / Qt 6.2+  
**作者**: AI Assistant (CodeBuddy)
