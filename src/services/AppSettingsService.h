#pragma once

#include <QObject>
#include <QSettings>

/**
 * @brief 应用设置服务 — 持久化用户可配置的应用级开关
 *
 * 当前管理：
 *   - priceInputEnabled   : 是否在工作台显示价格输入区（默认 false）
 *   - cellularEnabled     : 4G 移动数据开关记忆（默认 true），重启后恢复上次状态
 *   - wifiEnabled         : WiFi 射频开关记忆（默认 true），重启后恢复上次状态
 *   - networkAutoSwitch   : 网络自动切换开关记忆（默认 true），重启后恢复上次状态
 *   - networkMode         : 网络模式记忆（默认 -1 未设置；取值见 NetworkManagerService::NetworkMode），
 *                            重启后恢复上次选择的模式（全开优先4G 等）
 *   - weightUnit          : 重量显示单位（0=kg 默认，1=斤）。仅影响前端展示/输入换算，
 *                            数据库、上传接口、计算逻辑一律保持 kg（见 QML 单例 WeightUnit）
 *
 * 存储：QSettings INI 格式，UserScope，组织 "SmartScale" / 应用 "AppSettings"
 *       路径通常为 ~/.config/SmartScale/AppSettings.conf
 *
 * QML 访问：AppSettings.priceInputEnabled / AppSettings.cellularEnabled /
 *          AppSettings.wifiEnabled / AppSettings.networkAutoSwitch / AppSettings.networkMode /
 *          AppSettings.weightUnit
 *          （读 / 写均触发持久化 + 信号）
 */
class AppSettingsService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool priceInputEnabled READ priceInputEnabled
               WRITE setPriceInputEnabled NOTIFY priceInputEnabledChanged)
    Q_PROPERTY(bool cellularEnabled READ cellularEnabled
               WRITE setCellularEnabled NOTIFY cellularEnabledChanged)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled
               WRITE setWifiEnabled NOTIFY wifiEnabledChanged)
    Q_PROPERTY(bool networkAutoSwitch READ networkAutoSwitch
               WRITE setNetworkAutoSwitch NOTIFY networkAutoSwitchChanged)
    Q_PROPERTY(int networkMode READ networkMode
               WRITE setNetworkMode NOTIFY networkModeChanged)
    Q_PROPERTY(int weightUnit READ weightUnit
               WRITE setWeightUnit NOTIFY weightUnitChanged)

public:
    /** 重量显示单位取值（必须 public，否则 moc 生成的代码无法访问） */
    enum WeightUnit { UnitKg = 0, UnitJin = 1 };
    Q_ENUM(WeightUnit)

    explicit AppSettingsService(QObject *parent = nullptr);

    bool priceInputEnabled() const { return m_priceInputEnabled; }
    void setPriceInputEnabled(bool enabled);

    bool cellularEnabled() const { return m_cellularEnabled; }
    void setCellularEnabled(bool enabled);

    bool wifiEnabled() const { return m_wifiEnabled; }
    void setWifiEnabled(bool enabled);

    bool networkAutoSwitch() const { return m_networkAutoSwitch; }
    void setNetworkAutoSwitch(bool enabled);

    int networkMode() const { return m_networkMode; }
    void setNetworkMode(int mode);

    int weightUnit() const { return m_weightUnit; }
    void setWeightUnit(int unit);

Q_SIGNALS:
    void priceInputEnabledChanged();
    void cellularEnabledChanged();
    void wifiEnabledChanged();
    void networkAutoSwitchChanged();
    void networkModeChanged();
    void weightUnitChanged();

private:
    QSettings m_settings;   // IniFormat，显式路径 <AppPaths::configDir()>/AppSettings.ini
    bool m_priceInputEnabled;
    bool m_cellularEnabled;
    bool m_wifiEnabled;
    bool m_networkAutoSwitch;
    int  m_networkMode;     // -1 表示用户尚未选择过网络模式
    int  m_weightUnit;      // 0=kg（默认）, 1=斤
};
