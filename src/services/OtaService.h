#pragma once

#include <QObject>
#include <QString>
#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QTimer>

class QNetworkAccessManager;
class QNetworkReply;
class QFile;
class UpdateService;

/**
 * @brief OTA 远程升级服务 — 编排 检查→下载→校验→刷写 全流程状态机
 *
 * 职责：
 *   - 版本检查：转发 UpdateService 查询，QVersionNumber 比较远端 version 与本地 APP_VERSION_FULL
 *   - 固件下载：QNetworkReply 流式落盘 data/ota/update.part，同步增量 SHA256
 *   - 完整性校验：下载完成即比对 hash（与 UpdateService.hash 不区分大小写）
 *   - 刷写：QProcess::startDetached 调 data/ota/apply_update.sh（脚本内 备份/替换/拉起/30s存活验证/回滚）
 *   - 首启自检：重启后读取 data/ota/result.success|result.rolledback|pending.json 补报升级结果
 *
 * 状态机：
 *   Idle → Checking → HasUpdate → Downloading → Verifying → ReadyToInstall → Installing
 *   终态：Success / Failed / RolledBack（resetState() 回 Idle）
 *
 * 目录约定（applicationDirPath()/data/ota/）：
 *   update.part      下载中临时文件
 *   <fileName>       校验通过后的完整包
 *   pending.json     install() 写入（version/package/time），首启自检依据
 *   result.success / result.rolledback   刷写脚本写入（内容首行为版本号）
 *   apply_update.sh  install() 时从 qrc:/scripts/apply_update.sh 导出
 */
class OtaService : public QObject
{
    Q_OBJECT
    Q_PROPERTY(int     state           READ state           NOTIFY stateChanged)
    Q_PROPERTY(bool    updateAvailable READ updateAvailable NOTIFY stateChanged)
    Q_PROPERTY(QString latestVersion   READ latestVersion   NOTIFY stateChanged)
    Q_PROPERTY(int     percent         READ percent         NOTIFY progressChanged)
    Q_PROPERTY(qint64  bytesReceived   READ bytesReceived   NOTIFY progressChanged)
    Q_PROPERTY(qint64  bytesTotal      READ bytesTotal      NOTIFY progressChanged)
    Q_PROPERTY(double  speedKBs        READ speedKBs        NOTIFY progressChanged)
    Q_PROPERTY(QString errorString     READ errorString     NOTIFY stateChanged)

public:
    enum State {
        Idle = 0,          // 初始/无更新
        Checking,          // 查询版本中
        HasUpdate,         // 发现新版本，等待用户操作
        Downloading,       // 下载中
        Verifying,         // 校验中
        ReadyToInstall,    // 包就绪，等待确认安装
        Installing,        // 刷写脚本已启动（应用即将被停止）
        Success,           // 升级成功（首启自检补报）
        Failed,            // 失败（errorString 可读，可重试）
        RolledBack         // 已回滚到旧版本（首启自检补报）
    };
    Q_ENUM(State)

    explicit OtaService(UpdateService *updateService, QObject *parent = nullptr);

    int     state()           const { return m_state; }
    bool    updateAvailable() const { return m_updateAvailable; }
    QString latestVersion()   const { return m_latestVersion; }
    int     percent()         const { return m_percent; }
    qint64  bytesReceived()   const { return m_bytesReceived; }
    qint64  bytesTotal()      const { return m_bytesTotal; }
    double  speedKBs()        const { return m_speedKBs; }
    QString errorString()     const { return m_errorString; }

    /** @brief 检查更新（Checking/Downloading/Verifying/Installing 中忽略） */
    Q_INVOKABLE void checkUpdate();
    /** @brief 开始下载（仅 HasUpdate 态有效） */
    Q_INVOKABLE void startDownload();
    /** @brief 取消下载（仅 Downloading 态有效），清理临时文件回 HasUpdate（更新信息保留，可再次下载） */
    Q_INVOKABLE void cancelDownload();
    /** @brief 确认安装（仅 ReadyToInstall 态有效），导出脚本并 startDetached 执行 */
    Q_INVOKABLE void install();
    /** @brief 终态（Failed/Success/RolledBack）或 HasUpdate 复位回 Idle */
    Q_INVOKABLE void resetState();

Q_SIGNALS:
    void stateChanged();
    void progressChanged();
    /** @brief 查询结束（success=查询是否成功，hasUpdate=是否有新版本，version=远端版本号） */
    void checkFinished(bool success, bool hasUpdate, const QString &version);
    /** @brief 首启自检补报升级结果（应用被杀无法在线展示 Installing 结果） */
    void upgradeResult(bool success, const QString &version, bool rolledBack);

private:
    void setState(State s);
    /** @brief 置 Failed 态并记录脱敏错误（禁含路径/技术细节） */
    void setError(const QString &msg);
    void onCheckFinished(bool success, const QString &message);
    void onDownloadReadyRead();
    void onDownloadFinished();
    /** @brief 关闭并删除 .part 临时文件，释放句柄 */
    void cleanupDownload();
    /** @brief 首启自检：读 result 标记/pending.json 判定 Success/RolledBack 并补报 */
    void checkPendingResult();
    /** @brief data/ota 目录路径（applicationDirPath 下） */
    QString otaDir() const;

    UpdateService         *m_updateService;   // 不持有所有权
    QNetworkAccessManager *m_nam;
    QNetworkReply         *m_reply = nullptr;
    QFile                 *m_file  = nullptr;
    QCryptographicHash     m_hash{QCryptographicHash::Sha256};

    State   m_state           = Idle;
    bool    m_updateAvailable = false;
    QString m_latestVersion;
    int     m_percent         = 0;
    qint64  m_bytesReceived   = 0;
    qint64  m_bytesTotal      = 0;
    double  m_speedKBs        = 0.0;
    QString m_errorString;
    QString m_packagePath;    // 校验通过后的完整包路径

    // 进度节流与速度滑窗
    QElapsedTimer m_speedTimer;
    QElapsedTimer m_emitTimer;
    qint64        m_windowBytes = 0;

    // 查询看门狗：Checking 态若长时间无回调（底层请求挂死），强制回 Idle 自愈
    QTimer m_checkWatchdog;
};
