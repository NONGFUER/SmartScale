#include "FoodTranslator.h"
#include "core/PState.h"
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QDebug>

FoodTranslator::FoodTranslator(QObject *parent) : QObject(parent) {
    initDefaultDictionary();
}

FoodTranslator* FoodTranslator::instance() {
    static FoodTranslator _instance;
    return &_instance;
}

void FoodTranslator::initDefaultDictionary() {
    // 这里预填你 AI 模型可能输出的常见食品名
    // 嵌入式开发建议直接硬编码常用词，防止文件读取失败
    m_dict.insert("bailuobo", "白萝卜");
    m_dict.insert("baoxincai", "包心菜");
    m_dict.insert("biandoujia", "扁豆荚");
    m_dict.insert("bocai", "菠菜");
    m_dict.insert("changhuanggua", "长黄瓜");
    m_dict.insert("dabaicai", "大白菜");
    m_dict.insert("duankugua", "短苦瓜");
    m_dict.insert("gailan", "芥兰");
    m_dict.insert("gangdou", "缸豆");
    m_dict.insert("helandou", "荷兰豆");
    m_dict.insert("hongqiezi", "红茄子");
    m_dict.insert("hongshu", "红薯");
    m_dict.insert("huacai", "花菜");
    m_dict.insert("hulugua", "葫芦瓜");
    m_dict.insert("huluobo", "胡萝卜");
     m_dict.insert("jiaobai", "茭白");
    m_dict.insert("jituigu", "鸡腿菇");
    m_dict.insert("jiucai", "韭菜");
    m_dict.insert("jiuhuang", "韭黄");
    m_dict.insert("kongxincai", "空心菜");
    m_dict.insert("lianou", "莲藕");
    m_dict.insert("luosijiao", "螺丝椒‌");
    m_dict.insert("lvdouya", "绿豆芽");
    m_dict.insert("nangua", "南瓜");
    m_dict.insert("niuxinbao", "牛心包");
    
    m_dict.insert("pinggu", "平菇");
    m_dict.insert("qincai", "芹菜");
    m_dict.insert("qingcai", "青菜");
    m_dict.insert("qingcong", "青葱");
    m_dict.insert("qingmugua", "青木瓜");
    m_dict.insert("qingqiezi", "青茄子");
    m_dict.insert("qingwandoujia", "青豌豆荚");
    m_dict.insert("qiukui", "秋葵");
    m_dict.insert("shanyao", "山药");
    m_dict.insert("shengcai", "生菜");
    m_dict.insert("shengjiang", "生姜");
    m_dict.insert("sigua", "丝瓜");
    m_dict.insert("sijidou", "四季豆");
    m_dict.insert("suantou", "蒜头");
    m_dict.insert("tianjiao", "甜椒");
    m_dict.insert("tudou", "土豆");
    m_dict.insert("xiangcai", "香菜");
    m_dict.insert("xianjiao", "鲜椒");
    m_dict.insert("xianxianggu", "鲜香菇");
    m_dict.insert("xiaohuaguang", "小黄瓜");
    m_dict.insert("xihongshi", "西红柿");
    m_dict.insert("xilanhua", "西兰花");
    m_dict.insert("xiqin", "西芹");
    
    m_dict.insert("yangcong", "洋葱");
    m_dict.insert("youmaicai", "油麦菜");
    m_dict.insert("yunai", "芋艿");
    m_dict.insert("yutou", "芋头");
    m_dict.insert("ziganlan", "紫甘蓝");
}

QString FoodTranslator::translate(const QString &englishName) const {
    // 转换为小写匹配，防止大小写不一致导致匹配失败
    QString key = englishName.trimmed().toLower();
    
    // 如果翻译字典里有，返回中文；没有则返回原义（或首字母大写）
    if (m_dict.contains(key)) {
        return m_dict.value(key);
    }
  
    qWarning() << "Missing translation for:" << englishName;
    return PState::UNKNOWN;
}

// 进阶功能：支持从本地 JSON 文件更新翻译，无需重新编译程序
bool FoodTranslator::loadDictionary(const QString &filePath) {
    QFile file(filePath);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QByteArray data = file.readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isNull()) return false;

    QJsonObject obj = doc.object();
    for (auto it = obj.begin(); it != obj.end(); ++it) {
        m_dict.insert(it.key().toLower(), it.value().toString());
    }
    return true;
}
