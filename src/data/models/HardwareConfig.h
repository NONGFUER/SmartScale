#ifndef HARDWARECONFIG_H
#define HARDWARECONFIG_H

#include <QString>
#include <QVariantMap>
#include <QDateTime>

class HardwareConfig
{
public:
    int id = -1;
    QString key;                 // 配置键名, 如:
                                //   "calibration_offset"     // 称重校准偏移
                                //   "camera_device"          // 摄像头设备路径
                                //   "camera_resolution"      // 分辨率
                                //   "serial_port"            // 串口设备
                                //   "baud_rate"              // 波特率
    QString value;               // 配置值 (字符串存储, 使用时按需转换)

    QDateTime updatedAt;

public:
    QVariantMap toMap() const;
    static HardwareConfig fromMap(const QVariantMap &map);

    // 便捷类型转换方法
    int valueInt(int defaultValue = 0) const;
    double valueDouble(double defaultValue = 0.0) const;
    bool valueBool(bool defaultValue = false) const;

    HardwareConfig() = default;
    HardwareConfig(const QString &key, const QString &value);
};

#endif // HARDWARECONFIG_H
