#ifndef FOODTRANSLATOR_H
#define FOODTRANSLATOR_H

#include <QObject>
#include <QString>
#include <QHash>
#include <QVariantMap>

class FoodTranslator : public QObject
{
    Q_OBJECT
public:
    explicit FoodTranslator(QObject *parent = nullptr);

    // 单例模式，方便全局调用
    static FoodTranslator* instance();

    // 在 C++ 或 QML 中调用翻译函数
    Q_INVOKABLE QString translate(const QString &englishName) const;

    // 如果以后想从外部 JSON 加载字典，可以调这个方法
    bool loadDictionary(const QString &filePath);

private:
    void initDefaultDictionary();
    QHash<QString, QString> m_dict;
};

#endif // FOODTRANSLATOR_H
