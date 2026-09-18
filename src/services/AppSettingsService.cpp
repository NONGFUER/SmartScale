#include "AppSettingsService.h"
#include "utils/AppPaths.h"

#include <QDebug>

static const char *kKeyPriceInputEnabled = "priceInputEnabled";
static const char *kKeyCellularEnabled   = "cellularEnabled";
static const char *kKeyWifiEnabled       = "wifiEnabled";
static const char *kKeyNetworkAutoSwitch = "networkAutoSwitch";
static const char *kKeyNetworkMode       = "networkMode";
static const char *kKeyWeightUnit        = "weightUnit";

// ============================================================================
// 构造 — 从 QSettings 读取持久化配置
// ============================================================================

// 设置文件路径：显式指定，不再用 QSettings::UserScope
// （UserScope 依赖进程 HOME，会被 OTA 以 root 拉起时的 /root 带偏，
//   导致同一台设备出现两套设置，例如"按斤显示"在 OTA 后失效）
static QString appSettingsPath()
{
    AppPaths::ensureDir(AppPaths::configDir());
    return AppPaths::configDir() + QStringLiteral("/AppSettings.ini");
}

AppSettingsService::AppSettingsService(QObject *parent)
    : QObject(parent)
    , m_settings(appSettingsPath(), QSettings::IniFormat)
{
    m_priceInputEnabled = m_settings.value(kKeyPriceInputEnabled, false).toBool();
    m_cellularEnabled   = m_settings.value(kKeyCellularEnabled, true).toBool();  // 默认 true 保持开机自连
    m_wifiEnabled       = m_settings.value(kKeyWifiEnabled, true).toBool();       // 默认 true
    m_networkAutoSwitch = m_settings.value(kKeyNetworkAutoSwitch, true).toBool(); // 默认 true
    m_networkMode       = m_settings.value(kKeyNetworkMode, -1).toInt();          // -1 表示尚未选择
    m_weightUnit        = m_settings.value(kKeyWeightUnit, UnitKg).toInt();       // 默认 kg

    qDebug() << "[AppSettings] 加载配置:"
             << "priceInputEnabled =" << m_priceInputEnabled
             << "cellularEnabled =" << m_cellularEnabled
             << "wifiEnabled =" << m_wifiEnabled
             << "networkAutoSwitch =" << m_networkAutoSwitch
             << "networkMode =" << m_networkMode
             << "weightUnit =" << m_weightUnit
             << "文件:" << m_settings.fileName();
}

// ============================================================================
// priceInputEnabled setter — 写回 QSettings 并发射信号
// ============================================================================

void AppSettingsService::setPriceInputEnabled(bool enabled)
{
    if (m_priceInputEnabled == enabled)
        return;

    m_priceInputEnabled = enabled;
    m_settings.setValue(kKeyPriceInputEnabled, enabled);
    m_settings.sync();

    qDebug() << "[AppSettings] priceInputEnabled ->" << enabled;
    Q_EMIT priceInputEnabledChanged();
}

// ============================================================================
// cellularEnabled setter — 写回 QSettings 并发射信号
// ============================================================================

void AppSettingsService::setCellularEnabled(bool enabled)
{
    if (m_cellularEnabled == enabled)
        return;

    m_cellularEnabled = enabled;
    m_settings.setValue(kKeyCellularEnabled, enabled);
    m_settings.sync();

    qDebug() << "[AppSettings] cellularEnabled ->" << enabled;
    Q_EMIT cellularEnabledChanged();
}

// ============================================================================
// wifiEnabled setter — 写回 QSettings 并发射信号
// ============================================================================

void AppSettingsService::setWifiEnabled(bool enabled)
{
    if (m_wifiEnabled == enabled)
        return;

    m_wifiEnabled = enabled;
    m_settings.setValue(kKeyWifiEnabled, enabled);
    m_settings.sync();

    qDebug() << "[AppSettings] wifiEnabled ->" << enabled;
    Q_EMIT wifiEnabledChanged();
}

// ============================================================================
// networkAutoSwitch setter — 写回 QSettings 并发射信号
// ============================================================================

void AppSettingsService::setNetworkAutoSwitch(bool enabled)
{
    if (m_networkAutoSwitch == enabled)
        return;

    m_networkAutoSwitch = enabled;
    m_settings.setValue(kKeyNetworkAutoSwitch, enabled);
    m_settings.sync();

    qDebug() << "[AppSettings] networkAutoSwitch ->" << enabled;
    Q_EMIT networkAutoSwitchChanged();
}

// ============================================================================
// networkMode setter — 写回 QSettings 并发射信号
// ============================================================================

void AppSettingsService::setNetworkMode(int mode)
{
    if (m_networkMode == mode)
        return;

    m_networkMode = mode;
    m_settings.setValue(kKeyNetworkMode, mode);
    m_settings.sync();

    qDebug() << "[AppSettings] networkMode ->" << mode;
    Q_EMIT networkModeChanged();
}

// ============================================================================
// weightUnit setter — 写回 QSettings 并发射信号（0=kg, 1=斤）
// ============================================================================

void AppSettingsService::setWeightUnit(int unit)
{
    if (m_weightUnit == unit)
        return;

    m_weightUnit = unit;
    m_settings.setValue(kKeyWeightUnit, unit);
    m_settings.sync();

    qDebug() << "[AppSettings] weightUnit ->" << unit << (unit == UnitJin ? "(斤)" : "(kg)");
    Q_EMIT weightUnitChanged();
}
