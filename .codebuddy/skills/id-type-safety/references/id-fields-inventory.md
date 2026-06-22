# SmartScale 项目 ID 字段清单

## 云端雪花 ID（64-bit，后端以 string 返回，绝不能用 toInt）

| 字段 | 来源接口 | 正确处理 |
|------|----------|----------|
| `ingrId` | `/api/user/UserIngr/paged` → items[].ingrId | `toVariant().toString()` 存为 QString；上传时 `toLongLong()` + `QJsonValue(qlonglong)` |
| `emsId` | `/api/user/UserIngr/paged` → items[].emsId | `toVariant().toString()` 存为 QString |
| `cateId` | `/api/user/UserIngr/paged` → items[].cateId | `toVariant().toString()` 存为 QString |
| `recoId` | `/api/user/WeightRecord/create` 响应 → data.recoId | `isString() ? toString().toLongLong() : toVariant().toLongLong()`，存 qint64 |
| `userId` | 登录/刷新响应 → data.userId | `isString() ? toString().toLongLong() : toVariant().toLongLong()`，存 qint64；Q_PROPERTY/成员/形参全用 qint64 |
| `productId` | `/api/ems/Product/by-sn` → data.productId | `toVariant().toString()` 存为 QString |

**风险**：17 位雪花 ID（如 `61128584684638212`）远超 `int32` 上限（~21 亿），`toInt()` 溢出为 0 或负数。

## 本地 DB 自增 ID（32-bit，toInt 安全）

| 字段 | 表 | 说明 |
|------|----|------|
| `id` | weight_records | SQLite AUTOINCREMENT，toInt 正确 |
| `id` | users | SQLite AUTOINCREMENT，toInt 正确 |
| `id` | hardware_config | SQLite AUTOINCREMENT，toInt 正确 |

## 业务小整数 ID（通常 int 安全，但后端可能返回 string 需兜底）

| 字段 | 说明 | 推荐处理 |
|------|------|----------|
| `custId` | 客户 ID | `isString() ? toString().toInt() : toInt()` 兜底 |
| `devId` | 设备 ID | 同上 |
| `bill` | 单据号 | Int32，`qHash(QUuid) & 0x7FFFFFFF + 1` |

## 禁止模式

```cpp
// ❌ 雪花 ID 用 toInt — 溢出为 0
json["ingrId"] = record.ingrId.toInt();
json["ingrId"] = obj.value("ingrId").toInt();

// ❌ 直接用 QJsonValue(string) 传给后端期望数字的字段（除非后端明确接受 string）
json["ingrId"] = record.ingrId;  // 后端可能拒绝 string
```

## 正确模式

```cpp
// ✅ 解析：后端 string → 本地 QString
QString ingrId = obj.value("ingrId").toVariant().toString();

// ✅ 上传：QString → qint64 → QJsonValue(qlonglong)
bool ok;
qint64 val = record.ingrId.toLongLong(&ok);
json["ingrId"] = ok ? QJsonValue(qlonglong(val)) : 0;

// ✅ 响应解析：兼容 string/number
QJsonValue c = dataObj.value("custId");
int custId = c.isString() ? c.toString().toInt() : c.toInt();
```
