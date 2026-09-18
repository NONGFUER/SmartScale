// pragma Singleton 必须在文件第一行（注释除外）
pragma Singleton

import QtQuick
import App.Backend 1.0

// ============================================================================
// 重量/单价 显示单位换算单例
// ============================================================================
//
// 设计约定（重要）：
//   - 数据库、上传接口（val/price/amount）、WeightSensor、所有称重计算 一律使用 kg / 元每kg
//   - 本单例只负责「显示」与「输入」两端的单位换算，切换单位不改变任何存储数据
//   - 换算关系：1 斤 = 0.5 kg  ⇒  斤 = kg × 2，元/斤 = (元/kg) ÷ 2
//   - 金额为不变量：(元/kg)×(kg) == (元/斤)×(斤)
//
// 使用方式：
//   1. 引用：WeightUnit.text(modelData.weight) / WeightUnit.unit
//   2. 单价输入：打开键盘前 WeightUnit.price(kgPrice)，确认后 WeightUnit.priceToKg(input)
//
// 注册方式：pragma Singleton + CMakeLists.txt QML_FILES + QT_QML_SINGLETON_TYPE
// ============================================================================

QtObject {
    // 当前是否按斤显示（AppSettings.weightUnit: 0=kg, 1=斤）
    readonly property bool jin: AppSettings.weightUnit === 1

    // 换算系数：kg → 显示单位
    readonly property real factor: jin ? 2.0 : 1.0

    // 重量单位文案
    readonly property string unit: jin ? "斤" : "kg"

    // 单价单位文案
    readonly property string priceUnit: jin ? "元/斤" : "元/kg"

    // kg → 显示单位数值
    function disp(kg) {
        return (Number(kg) || 0) * factor
    }

    // kg → "2.50 kg" / "5.00 斤"
    function text(kg) {
        return disp(kg).toFixed(2) + " " + unit
    }

    // 元/kg → 当前显示单位的单价
    function price(perKg) {
        return (Number(perKg) || 0) / factor
    }

    // 当前显示单位单价 → 元/kg（回写存储用）
    function priceToKg(displayPrice) {
        return (Number(displayPrice) || 0) * factor
    }
}
