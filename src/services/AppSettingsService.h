#pragma once

#include <QObject>
#include <QSettings>

/**
 * @brief 应用设置服务 — 持久化用户可配置的应用级开关
 *
 * 当前管理：
 *   - priceInputEnabled : 是否在工作台显示价格输入区（默认 false）
 *
 * 存储：QSettings INI 格式，UserScope，组织 "SmartScale" / 应用 "AppSettings"
 *       路径通常为 ~/.config/SmartScale/AppSettings.conf
 *
 * QML 访问：AppSettings.priceInputEnabled（读 / 写均触发持久化 + 信号）
 */
class AppSettingsService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool priceInputEnabled READ priceInputEnabled
               WRITE setPriceInputEnabled NOTIFY priceInputEnabledChanged)

public:
    explicit AppSettingsService(QObject *parent = nullptr);

    bool priceInputEnabled() const { return m_priceInputEnabled; }
    void setPriceInputEnabled(bool enabled);

Q_SIGNALS:
    void priceInputEnabledChanged();

private:
    QSettings m_settings;   // IniFormat, UserScope, "SmartScale"/"AppSettings"
    bool m_priceInputEnabled;
};
