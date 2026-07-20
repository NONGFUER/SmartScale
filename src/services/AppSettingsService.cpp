#include "AppSettingsService.h"

#include <QDebug>

static const char *kKeyPriceInputEnabled = "priceInputEnabled";
static const char *kKeyCellularEnabled   = "cellularEnabled";

// ============================================================================
// 构造 — 从 QSettings 读取持久化配置
// ============================================================================

AppSettingsService::AppSettingsService(QObject *parent)
    : QObject(parent)
    , m_settings(QSettings::IniFormat, QSettings::UserScope,
                 QStringLiteral("SmartScale"), QStringLiteral("AppSettings"))
{
    m_priceInputEnabled = m_settings.value(kKeyPriceInputEnabled, false).toBool();
    m_cellularEnabled   = m_settings.value(kKeyCellularEnabled, true).toBool();  // 默认 true 保持开机自连

    qDebug() << "[AppSettings] 加载配置:"
             << "priceInputEnabled =" << m_priceInputEnabled
             << "cellularEnabled =" << m_cellularEnabled
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
