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
 *
 * 存储：QSettings INI 格式，UserScope，组织 "SmartScale" / 应用 "AppSettings"
 *       路径通常为 ~/.config/SmartScale/AppSettings.conf
 *
 * QML 访问：AppSettings.priceInputEnabled / AppSettings.cellularEnabled /
 *          AppSettings.wifiEnabled / AppSettings.networkAutoSwitch（读 / 写均触发持久化 + 信号）
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

public:
    explicit AppSettingsService(QObject *parent = nullptr);

    bool priceInputEnabled() const { return m_priceInputEnabled; }
    void setPriceInputEnabled(bool enabled);

    bool cellularEnabled() const { return m_cellularEnabled; }
    void setCellularEnabled(bool enabled);

    bool wifiEnabled() const { return m_wifiEnabled; }
    void setWifiEnabled(bool enabled);

    bool networkAutoSwitch() const { return m_networkAutoSwitch; }
    void setNetworkAutoSwitch(bool enabled);

Q_SIGNALS:
    void priceInputEnabledChanged();
    void cellularEnabledChanged();
    void wifiEnabledChanged();
    void networkAutoSwitchChanged();

private:
    QSettings m_settings;   // IniFormat, UserScope, "SmartScale"/"AppSettings"
    bool m_priceInputEnabled;
    bool m_cellularEnabled;
    bool m_wifiEnabled;
    bool m_networkAutoSwitch;
};
