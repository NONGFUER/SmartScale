#pragma once

#include <QObject>
#include <QString>

class QNetworkAccessManager;

/**
 * @brief 更新信息服务 — 查询 update.shxgs.cn 上的最新版本信息
 *
 * 接口: POST https://update.shxgs.cn:5196/UpdateInfo/latest
 * 请求体: 写死 JSON 字符串 "User_Dzc"（无需登录态 / Bearer Token）
 * 响应: { "data": { id/appType/verCode/version/pubTime/fileName/url/
 *         force/size/differential/verCodeMax/verCodeMin/hash }, "success": bool, ... }
 *       注意 data 内数字字段均为字符串形式（"325"、"11175996"）
 */
class UpdateService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool    checking     READ checking     NOTIFY checkingChanged)
    Q_PROPERTY(bool    hasInfo      READ hasInfo      NOTIFY infoChanged)      // 是否已成功获取到更新信息
    Q_PROPERTY(QString updateId     READ updateId     NOTIFY infoChanged)
    Q_PROPERTY(QString version      READ version      NOTIFY infoChanged)      // 如 "V2.13.3.24"
    Q_PROPERTY(int     verCode      READ verCode      NOTIFY infoChanged)      // 如 325
    Q_PROPERTY(QString pubTime      READ pubTime      NOTIFY infoChanged)      // 已格式化 "yyyy-MM-dd HH:mm:ss"
    Q_PROPERTY(QString fileName     READ fileName     NOTIFY infoChanged)
    Q_PROPERTY(QString downloadUrl  READ downloadUrl  NOTIFY infoChanged)      // 已拼接 UPDATE_BASE_URL 的完整地址
    Q_PROPERTY(bool    force        READ force        NOTIFY infoChanged)      // 是否强制更新
    Q_PROPERTY(qint64  size         READ size         NOTIFY infoChanged)      // 字节
    Q_PROPERTY(bool    differential READ differential NOTIFY infoChanged)      // 是否差分包
    Q_PROPERTY(int     verCodeMax   READ verCodeMax   NOTIFY infoChanged)
    Q_PROPERTY(int     verCodeMin   READ verCodeMin   NOTIFY infoChanged)
    Q_PROPERTY(QString hash         READ hash         NOTIFY infoChanged)      // SHA256

public:
    explicit UpdateService(QObject *parent = nullptr);

    bool    checking()     const { return m_checking; }
    bool    hasInfo()      const { return m_hasInfo; }
    QString updateId()     const { return m_updateId; }
    QString version()      const { return m_version; }
    int     verCode()      const { return m_verCode; }
    QString pubTime()      const { return m_pubTime; }
    QString fileName()     const { return m_fileName; }
    QString downloadUrl()  const { return m_downloadUrl; }
    bool    force()        const { return m_force; }
    qint64  size()         const { return m_size; }
    bool    differential() const { return m_differential; }
    int     verCodeMax()   const { return m_verCodeMax; }
    int     verCodeMin()   const { return m_verCodeMin; }
    QString hash()         const { return m_hash; }

    /** @brief 发起最新版本信息查询（重复调用防抖：进行中直接忽略） */
    Q_INVOKABLE void checkUpdate();

Q_SIGNALS:
    void checkingChanged();
    void infoChanged();
    /** @brief 查询结束。success=true 时 message 为最新版本号，否则为错误描述 */
    void checkFinished(bool success, const QString &message);

private:
    QNetworkAccessManager *m_networkMgr;
    bool    m_checking = false;

    // === 最近一次查询结果 ===
    bool    m_hasInfo      = false;
    QString m_updateId;     // 更新包 ID（字符串保留，下载 URL 拼接用）
    QString m_version;
    int     m_verCode      = 0;
    QString m_pubTime;
    QString m_fileName;
    QString m_downloadUrl;
    bool    m_force        = false;
    qint64  m_size         = 0;
    bool    m_differential = false;
    int     m_verCodeMax   = 0;
    int     m_verCodeMin   = 0;
    QString m_hash;
};
