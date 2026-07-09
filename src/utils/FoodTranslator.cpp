#include "FoodTranslator.h"
#include "core/PState.h"
#include <QFile>
#include <QDir>
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
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
    return englishName;   // 未命中则回退到原始值，避免显示字面 "unknown"
}

// ============================================================
//  从 API 数据更新内存字典 (ingrCd/emsCd → ingrNm)
//  缓存文件由 UserIngredientService 负责写入，翻译器只读不写
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
        QString emsCd = map.value("emsCd").toString().trimmed().toLower();
        QString cn = map.value("cn").toString().trimmed();

        if (!en.isEmpty() && !cn.isEmpty()) {
            m_dict.insert(en, cn);
        }
        if (!emsCd.isEmpty() && !cn.isEmpty() && emsCd != en) {
            m_dict.insert(emsCd, cn);
        }
    }

    qInfo() << "[Translator] 从 API 加载了" << m_dict.size() << "条翻译记录";

    if (!m_ready) {
        m_ready = true;
        Q_EMIT readyChanged();
    }
}

// ============================================================
//  本地 JSON 缓存读取 (新结构: categories[].items[])
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

    QJsonObject root = doc.object();

    // 旧结构 (扁平字典) 不再处理，UserIngredientService 会删除并重建
    if (!root.contains("categories")) {
        qInfo() << "[Translator] 缓存为旧格式，等待 UserIngredientService 重建";
        return;
    }

    m_dict.clear();
    QJsonArray cats = root.value("categories").toArray();
    for (const QJsonValue &cv : cats) {
        QJsonArray items = cv.toObject().value("items").toArray();
        for (const QJsonValue &iv : items) {
            QJsonObject obj = iv.toObject();
            QString en = obj.value("ingrCd").toString().trimmed().toLower();
            QString emsCd = obj.value("emsCd").toString().trimmed().toLower();
            QString cn = obj.value("ingrNm").toString().trimmed();

            if (!en.isEmpty() && !cn.isEmpty())
                m_dict.insert(en, cn);
            if (!emsCd.isEmpty() && !cn.isEmpty() && emsCd != en)
                m_dict.insert(emsCd, cn);
        }
    }

    if (!m_dict.isEmpty()) {
        m_ready = true;
        Q_EMIT readyChanged();
    }

    qInfo() << "[Translator] 从缓存加载了" << m_dict.size() << "条翻译记录:" << path;
}
