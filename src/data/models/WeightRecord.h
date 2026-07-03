#ifndef WEIGHTRECORD_H
#define WEIGHTRECORD_H

#include <QString>
#include <QVariantMap>
#include <QDate>
#include <QDateTime>

class WeightRecord
{
public:
    int id = -1;

    // === 核心业务字段 ===
    double weight = 0.0;             // 物品重量, 单位: kg
    QString categoryName;            // 物品类别名称 (中文显示名, 如 "大白菜")
    QString ingrId;                  // 食材 ID (上传云端用, 登录拉取食材时选中保存)
    bool aiDetected = false;         // 是否由 AI 识别接口得出 (true=AI识别, false=手动选择/纠错)
    QString recordTime;              // 物品称重时间, 格式: "2026-04-26 14:30"
    QString operatorName;            // 操作人员名称

    // === 摄像头图片 (双摄) ===
    bool hasMainImage = false;       // 是否有正摄像图片
    QString mainImagePath;           // 正摄像图片路径
    bool hasSubImage = false;        // 是否有副摄像图片
    QString subImagePath;            // 副摄像图片路径

    // === 同步预留字段 ===
    bool synced = false;             // 是否已同步到云端
    QString cloudId;                 // 云端记录 ID
    bool deleted = false;            // 软删除（撤回）标记

    // === 内部时间戳 ===
    QDateTime createdAt;             // 本地创建时间
    QDateTime updatedAt;             // 本地更新时间

public:
    QVariantMap toMap() const;
    static WeightRecord fromMap(const QVariantMap &map);
    QDate date() const;

    WeightRecord() = default;
    WeightRecord(double weight,
                 const QString &categoryName,
                 const QString &operatorName = QString(),
                 const QString &recordTime = QString(),
                 const QString &mainImagePath = QString(),
                 const QString &subImagePath = QString());
};

#endif // WEIGHTRECORD_H
