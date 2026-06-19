#include "FoodTranslator.h"
#include "core/PState.h"
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

static QString cacheFilePath()
{
    // 缓存路径: ~/.cache/smartscale/ingredients.json
    QString dir = QDir::homePath() + "/.cache/smartscale";
    QDir().mkpath(dir);
    return dir + "/ingredients.json";
}

FoodTranslator::FoodTranslator(QObject *parent) : QObject(parent)
{
    loadFromCache();
}

FoodTranslator* FoodTranslator::instance()
{
    static FoodTranslator _instance;
    return &_instance;
}

QString FoodTranslator::translate(const QString &englishName) const
{
    QString key = englishName.trimmed().toLower();

    if (m_dict.contains(key)) {
        return m_dict.value(key);
    }

    qWarning() << "Missing translation for:" << englishName;
    return PState::UNKNOWN;
}

// ============================================================
//  从 API 数据更新字典并写入本地缓存
// ============================================================
void FoodTranslator::updateFromApi(const QVariantList &items)
{
    if (items.isEmpty()) {
        qWarning() << "[Translator] API 食材数据为空，保留现有缓存";
        return;
    }

    m_dict.clear();

    for (const QVariant &v : items) {
        QVariantMap map = v.toMap();
        QString en = map.value("en").toString().trimmed().toLower();
        QString cn = map.value("cn").toString().trimmed();

        if (!en.isEmpty() && !cn.isEmpty()) {
            m_dict.insert(en, cn);
        }
    }

    qInfo() << "[Translator] 从 API 加载了" << m_dict.size() << "条翻译记录";

    saveToCache();

    if (!m_ready) {
        m_ready = true;
        Q_EMIT readyChanged();
    }
}

// ============================================================
//  本地 JSON 缓存读写
// ============================================================
void FoodTranslator::loadFromCache()
{
    QString path = cacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) {
        qInfo() << "[Translator] 无本地缓存，等待登录后从 API 加载";
        return;
    }

    QByteArray data = file.readAll();
    file.close();

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        qWarning() << "[Translator] 缓存 JSON 格式错误，忽略";
        return;
    }

    QJsonObject obj = doc.object();
    m_dict.clear();
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        m_dict.insert(it.key().toLower(), it.value().toString());
    }

    if (!m_dict.isEmpty()) {
        m_ready = true;
        Q_EMIT readyChanged();
    }

    qInfo() << "[Translator] 从缓存加载了" << m_dict.size() << "条翻译记录:" << path;
}

void FoodTranslator::saveToCache()
{
    QJsonObject obj;
    for (auto it = m_dict.constBegin(); it != m_dict.constEnd(); ++it) {
        obj.insert(it.key(), it.value());
    }

    QString path = cacheFilePath();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        qWarning() << "[Translator] 无法写入缓存文件:" << path;
        return;
    }

    file.write(QJsonDocument(obj).toJson(QJsonDocument::Compact));
    file.close();

    qInfo() << "[Translator] 缓存已写入:" << path << "(" << m_dict.size() << "条)";
}
