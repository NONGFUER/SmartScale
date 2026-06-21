#ifndef FOODTRANSLATOR_H
#define FOODTRANSLATOR_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QVariantList>

class FoodTranslator : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool ready READ isReady NOTIFY readyChanged)
public:
    explicit FoodTranslator(QObject *parent = nullptr);

    // 单例模式，方便全局调用
    static FoodTranslator* instance();

    // 在 C++ 或 QML 中调用翻译函数
    Q_INVOKABLE QString translate(const QString &englishName) const;

    // 翻译器是否已加载有效数据（登录后从 API 获取）
    bool isReady() const { return m_ready; }

    /** @brief 从 UserIngredientService 的 API 数据更新内存字典（ingrCd/emsCd → ingrNm），不再写缓存 */
    void updateFromApi(const QVariantList &items);

Q_SIGNALS:
    void readyChanged();

private:
    void loadFromCache();                     // 启动时从本地 JSON (新结构) 加载

    QHash<QString, QString> m_dict;
    bool m_ready = false;
};

#endif // FOODTRANSLATOR_H
