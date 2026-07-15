---
name: history-table-dialog
overview: 在历史记录区"更多 >"旁新增"表格"入口按钮，点击打开独立弹窗组件 WeightRecordTableDialog.qml，以表格形式展示云端分页称重记录。数据由 POST /api/user/WeightRecord/paged 接口提供，新增 C++ 方法 fetchPagedRecords() 在 WeightHistoryService 中发起请求并解析返回。
design:
  styleKeywords:
    - 现代简约
    - 卡片式
    - 品牌蓝
    - 交替行表格
  fontSystem:
    fontFamily: PingFang SC
    heading:
      size: "26"
      weight: 700
    subheading:
      size: "15"
      weight: 500
    body:
      size: "14"
      weight: 400
  colorSystem:
    primary:
      - "#3B82F6"
      - "#1D4ED8"
    background:
      - "#FFFFFF"
      - "#F8FAFC"
      - "#F1F5F9"
    text:
      - "#1B263B"
      - "#666666"
      - "#94A3B8"
    functional:
      - "#16A34A"
      - "#80000000"
todos:
  - id: add-api-and-service
    content: 在 NetworkUtils.h 新增 USER_WEIGHT_PAGED 常量，在 WeightHistoryService.h/.cpp 新增 fetchPagedRecords 方法、pagedRecordsReady 信号及 onCloudReply 分发逻辑，使用 [skill:id-type-safety] 确保 ID 字段类型安全
    status: completed
  - id: create-table-dialog
    content: 创建 src/ui/components/WeightRecordTableDialog.qml 独立弹窗组件，含表格展示、服务端分页、关键字搜索、加载/空状态
    status: completed
    dependencies:
      - add-api-and-service
  - id: wire-up-entry
    content: 在 CMakeLists.txt QML_FILES 注册新文件，在 WorkstationPage.qml 历史记录标题行新增"表格"按钮并实例化弹窗
    status: completed
    dependencies:
      - create-table-dialog
  - id: lint-verify
    content: 用 read_lints 检查所有修改文件的语法错误
    status: completed
    dependencies:
      - wire-up-entry
---


## 产品概述
在历史记录区域新增一个表格展示弹窗，作为独立 QML 组件（不内嵌 WorkstationPage），通过云端 API `/api/user/WeightRecord/paged` 获取分页称重记录数据，以表格形式展示。

## 核心功能
- 在历史记录标题行"更多 >"旁新增"表格"入口按钮，点击打开独立弹窗
- 弹窗以表格形式展示称重记录，列包括：序号、食材名称、重量(kg)、单价(元/kg)、金额(元)、单号、AI检测、时间
- 服务端分页：每页 10 条，底部显示页码导航（上一页/下一页/页码按钮），总条数来自 `data.total`
- 支持关键字搜索（按食材名称或单号过滤），搜索时重置到第一页
- 加载中显示 loading 指示器，无数据显示空状态提示
- 雪花 ID（recoId/ingrId/custId/devId/userId）全部用 QString/qint64 传递，禁止 toInt()



## 技术栈
- C++ 服务层：WeightHistoryService（已有，新增分页查询方法）
- 网络层：NetworkUtils（已有，新增 API 路径常量）
- QML UI：Qt Quick Controls Dialog + ListView 模拟表格（与项目现有弹窗模式一致）
- 数据源：POST `/api/user/WeightRecord/paged`（USER 域 user.shxgs.cn:5196）

## 实现方案

### 1. NetworkUtils 新增 API 常量
在 `src/core/NetworkUtils.h` 的 `namespace Api` 中新增：
```cpp
inline constexpr const char *USER_WEIGHT_PAGED = "/api/user/WeightRecord/paged";
```

### 2. WeightHistoryService 新增分页查询方法
**头文件** (`WeightHistoryService.h`) 新增：
- `Q_INVOKABLE void fetchPagedRecords(int page, int pageSize, const QString &keyword, const QString &dateS, const QString &dateE)` — QML 可调用，构造请求体 POST 到云端
- 信号 `pagedRecordsReady(bool success, int total, const QVariantList &items, const QString &errorMsg)` — 查询结果回调

**实现** (`WeightHistoryService.cpp`)：
- 从 `m_authService` 获取 custId/devId/userId（均为 qint64），构造 JSON 请求体（与用户提供的报文结构一致）
- 用 `NetworkUtils::createUserApiRequest(NetworkUtils::Api::USER_WEIGHT_PAGED, token)` 创建请求
- `m_networkMgr->post(request, bodyData)`，`reply->setProperty("_isPaged", true)` 标记
- 在 `onCloudReply()` 开头（`_isRevoke` 判断之后、`localId` 判断之前）新增 `_isPaged` 分支：解析 `data.total`（字符串转 int）和 `data.items` 数组，每条 item 转为 QVariantMap 保留全部字段，emit `pagedRecordsReady`
- 401 处理：检测 `AuthService::isUnauthorizedError`，触发 `requestTokenRefresh()`，用 `m_refreshingToken` 锁防竞态，刷新完成后重发请求（需缓存当前请求参数到成员变量 `m_pendingPagedParams`）

### 3. 新建 WeightRecordTableDialog.qml 独立组件
**文件**：`src/ui/components/WeightRecordTableDialog.qml`

参照 WeightRecordSearchDialog.qml 的 Dialog 模式：
- `Dialog` 根节点：`modal:true` + `Overlay.modal:Rectangle{color:"#80000000"}` + `padding:0` + 圆角白色背景 + MultiEffect 标准阴影
- 标题栏：返回箭头(back.png) + "称重记录表格" + 关闭按钮（与 SearchDialog 完全一致）
- 搜索栏：关键字输入框 + 搜索按钮（蓝色渐变，复用 SearchDialog 搜索按钮样式）
- 表格区：
  - 表头行（固定，浅灰背景 #F1F5F9）：序号 | 食材 | 重量 | 单价 | 金额 | 单号 | AI | 时间
  - 表体：`ListView` inside `ScrollView`，delegate 为 `Rectangle{Row{...}}` 固定列宽，隔行交替色（#FFFFFF/#F8FAFC）
  - AI检测列用标签样式：绿色圆角标签"AI"或灰色"人工"
- 底部分页栏：总条数 + 上一页/页码/下一页（复用 SearchDialog 分页栏样式），服务端分页（翻页时调用 `WeightHistoryService.fetchPagedRecords`）
- Loading 转圈覆盖层（BusyIndicator）+ 空状态提示
- `onOpened`：初始化参数（keyword=""、page=1、dateS=30天前、dateE=今天），调用首次查询
- `Connections` 监听 `WeightHistoryService.pagedRecordsReady` 信号更新表格数据和分页状态
- 所有 MouseArea **不写 cursorShape**（触摸屏约束）
- 所有颜色/字体引用 Theme.qml 常量

### 4. WorkstationPage.qml 接入
- 在第 148-159 行"更多 >"Text 旁新增"表格"Text 按钮（同 RowLayout 内，`onClicked: tableDialog.open()`）
- 在第 1266-1273 行 WeightRecordSearchDialog 实例之后新增 `WeightRecordTableDialog { id: tableDialog }`
- 顶部 `import "../components"` 已存在（WorkstationPage 引用 components 组件），无需新增 import

### 5. CMakeLists.txt 注册
在第 81 行 `SaveConfirmDialog.qml` 之后追加：
```
src/ui/components/WeightRecordTableDialog.qml      # 称重记录表格弹窗
```

## 实现注意事项
- **雪花 ID 安全**：onCloudReply 解析 items 时，recoId/ingrId/custId/devId/userId 均为字符串，用 `toString()` 保持，禁止 `toInt()`；使用 [skill:id-type-safety] 确保类型安全
- **Token 刷新竞态**：fetchPagedRecords 的 401 重试需缓存 (page, pageSize, keyword, dateS, dateE) 到成员变量，`onTokenReadyForUpload` 回调时重发；与现有 upload 重试队列独立
- **性能**：服务端分页避免一次性拉取全量数据；ListView 仅渲染可见行 delegate，内存占用可控
- **日期格式**：请求体 dateS/dateE 用 ISO 8601 格式（如 "2026-07-15T14:04:07.697Z"），QML 侧用 `Qt.formatDateTime` 生成
- **弹窗遮罩**：严格遵循 `modal:true` + `Overlay.modal:Rectangle{color:"#80000000"}`，不写 `dim:false`
- **向后兼容**：不修改现有 WeightHistoryService 任何已有方法签名，仅新增方法和信号


## 设计风格
采用与现有 WeightRecordSearchDialog 一致的现代简约卡片风格，白色圆角弹窗 + 半透明遮罩。表格区使用浅灰表头(#F1F5F9) + 白色/极浅灰交替行，蓝色品牌色(#3B82F6)用于页码选中态和搜索按钮。AI检测列用绿色(#16A34A)圆角小标签区分。Loading 使用半透明白底覆盖 + 居中转圈。整体视觉与 WorkstationPage 历史记录卡片区域保持品牌一致性。

## Agent Extensions
### Skill
- **id-type-safety**
  - Purpose: 确保新增 fetchPagedRecords 方法及 onCloudReply 解析中，雪花 ID 字段（recoId/ingrId/custId/devId/userId）全部用 QString 传递，不使用 toInt() 导致溢出
  - Expected outcome: 所有 ID 字段在 C++ JSON 解析和 QVariantMap 构造中保持字符串类型，无截断风险
