#include "OtaService.h"
#include "UpdateService.h"
#include "version.h"

#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QSslConfiguration>
#include <QSslSocket>
#include <QSslError>
#include <QFile>
#include <QDir>
#include <QFileInfo>
#include <QStorageInfo>
#include <QVersionNumber>
#include <QJsonObject>
#include <QJsonDocument>
#include <QDateTime>
#include <QProcess>
#include <QCoreApplication>
#include <QTimer>
#include <QDebug>

OtaService::OtaService(UpdateService *updateService, QObject *parent)
    : QObject(parent)
    , m_updateService(updateService)
    , m_nam(new QNetworkAccessManager(this))
{
    connect(m_updateService, &UpdateService::checkFinished,
            this, &OtaService::onCheckFinished);

    // 查询看门狗：进入 Checking 后若底层请求长时间无回调（如网络接口热插拔导致
    // QNetworkReply 泄漏），强制回 Idle 自愈，避免状态永久卡死无法再次触发查询。
    m_checkWatchdog.setSingleShot(true);
    m_checkWatchdog.setInterval(30000);
    connect(&m_checkWatchdog, &QTimer::timeout, this, [this]() {
        if (m_state == Checking) {
            qWarning() << "[OtaService] 版本查询超时(30s)，强制回 Idle 自愈";
            m_errorString = QStringLiteral("检查更新超时，请稍后重试");
            m_checkWatchdog.stop();
            setState(Idle);
        }
    });

    // 首启自检：检测上次刷写结果标记（result.success/result.rolledback/pending.json）
    checkPendingResult();
}

QString OtaService::otaDir() const
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/data/ota");
}

void OtaService::setState(State s)
{
    if (m_state == s)
        return;
    m_state = s;
    qInfo() << "[OtaService] 状态迁移 ->" << s;
    Q_EMIT stateChanged();
}

void OtaService::setError(const QString &msg)
{
    m_errorString = msg;
    qWarning() << "[OtaService] 失败:" << msg;
    setState(Failed);
}

// ============================================================================
// 版本检查
// ============================================================================

void OtaService::checkUpdate()
{
    // if (m_state == Checking || m_state == Downloading
    //     || m_state == Verifying || m_state == Installing) {
    //     qDebug() << "[OtaService] 当前状态不允许查询:" << m_state;
    //     return;
    // }
    m_errorString.clear();
    Q_EMIT stateChanged();
    setState(Checking);
    m_checkWatchdog.start();   // 启动看门狗，等待回调或超时自愈
    m_updateService->checkUpdate();
}

void OtaService::onCheckFinished(bool success, const QString &message)
{
    Q_UNUSED(message)
    m_checkWatchdog.stop();   // 收到回调即取消看门狗
    if (!success) {
        if (m_state == Checking) {
            m_errorString = QStringLiteral("检查更新失败，请稍后重试");
            setState(Idle);   // 查询失败回 Idle（errorString 仍可读）
        }
        Q_EMIT checkFinished(false, false, QString());
        return;
    }

    // 版本比较：远端 version（"V2.13.3.24"，去 V 前缀）vs 本地 APP_VERSION_FULL
    // 注意：不比较 verCode vs BUILD_NUMBER —— 服务端 verCode 与本地构建号非同序列
    const QString remote = m_updateService->version();
    QString remoteNum = remote;
    if (remoteNum.startsWith(QLatin1Char('V'), Qt::CaseInsensitive))
        remoteNum = remoteNum.mid(1);
    const QVersionNumber remoteVer = QVersionNumber::fromString(remoteNum);
    const QVersionNumber localVer  = QVersionNumber::fromString(QStringLiteral(APP_VERSION_FULL));
    const bool newer = !remoteVer.isNull() && QVersionNumber::compare(remoteVer, localVer) > 0;

    qInfo() << "[OtaService] 版本比较: 远端" << remote << "本地" << APP_VERSION_FULL
            << "=> hasUpdate=" << newer;

    m_updateAvailable = newer;
    if (newer) {
        m_latestVersion = remote;
        if (m_state == Checking || m_state == Idle)
            setState(HasUpdate);
        else
            Q_EMIT stateChanged();   // 其他态仅刷新 updateAvailable/latestVersion
    } else if (m_state == Checking) {
        setState(Idle);
    }
    Q_EMIT checkFinished(true, newer, remote);
}

// ============================================================================
// 固件下载（流式落盘 + 增量 SHA256 + 500ms 节流进度）
// ============================================================================

void OtaService::startDownload()
{
    // Failed 态允许重试下载（updateAvailable 仍为 true 时）
    if ((m_state != HasUpdate && m_state != Failed) || !m_updateService->hasInfo()) {
        qDebug() << "[OtaService] 当前状态不允许下载:" << m_state;
        return;
    }
    const QString url = m_updateService->downloadUrl();
    if (url.isEmpty()) {
        setError(QStringLiteral("下载地址无效"));
        return;
    }

    // 磁盘空间预检：可用空间需 > 包大小 x2（包 + 解压缓冲）
    const qint64 pkgSize = m_updateService->size();
    const QStorageInfo storage(QCoreApplication::applicationDirPath());
    if (pkgSize > 0 && storage.isValid() && storage.bytesAvailable() >= 0
        && storage.bytesAvailable() < pkgSize * 2) {
        qWarning() << "[OtaService] 磁盘空间不足: 可用" << storage.bytesAvailable()
                   << "需要" << pkgSize * 2;
        setError(QStringLiteral("存储空间不足"));
        return;
    }

    QDir().mkpath(otaDir());
    const QString partPath = otaDir() + QStringLiteral("/update.part");
    QFile::remove(partPath);   // 清理上次残留

    delete m_file;
    m_file = new QFile(partPath, this);
    if (!m_file->open(QIODevice::WriteOnly)) {
        qWarning() << "[OtaService] 无法创建临时文件:" << m_file->errorString();
        delete m_file;
        m_file = nullptr;
        setError(QStringLiteral("无法写入更新包"));
        return;
    }

    m_hash.reset();
    m_bytesReceived = 0;
    m_bytesTotal    = pkgSize > 0 ? pkgSize : 0;
    m_percent       = 0;
    m_speedKBs      = 0.0;
    m_windowBytes   = 0;
    m_speedTimer.start();
    m_emitTimer.start();
    Q_EMIT progressChanged();

    // 下载请求：镜像 NetworkUtils 的 SSL 配置（VerifyNone + TLS1.2+ + HTTP/1.1）
    QNetworkRequest request{QUrl(url)};
    QSslConfiguration sslConf = request.sslConfiguration();
    sslConf.setPeerVerifyMode(QSslSocket::VerifyNone);
    sslConf.setProtocol(QSsl::TlsV1_2OrLater);
    request.setSslConfiguration(sslConf);
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    request.setAttribute(QNetworkRequest::RedirectPolicyAttribute,
                         QNetworkRequest::NoLessSafeRedirectPolicy);

    qInfo() << "[OtaService] 开始下载:" << url << "size=" << pkgSize;

    m_reply = m_nam->get(request);
    connect(m_reply, &QNetworkReply::readyRead,
            this, &OtaService::onDownloadReadyRead);
    connect(m_reply, &QNetworkReply::finished,
            this, &OtaService::onDownloadFinished);
    // SSL：VerifyNone 仍可能因自签名/私有CA触发 sslErrors，需 ignore 否则握手中止
    connect(m_reply, &QNetworkReply::sslErrors, this,
            [this](const QList<QSslError> &errors) {
                for (const QSslError &e : errors)
                    qWarning() << "[OtaService] SSL 错误(已忽略):" << e.errorString();
                if (m_reply)
                    m_reply->ignoreSslErrors();
            });
    connect(m_reply, &QNetworkReply::errorOccurred, this,
            [this](QNetworkReply::NetworkError code) {
                qWarning() << "[OtaService] 网络错误(" << static_cast<int>(code)
                           << "):" << (m_reply ? m_reply->errorString() : QString());
            });

    setState(Downloading);
}

void OtaService::onDownloadReadyRead()
{
    if (!m_reply || !m_file)
        return;
    const QByteArray chunk = m_reply->readAll();
    if (chunk.isEmpty())
        return;

    m_file->write(chunk);
    m_hash.addData(chunk);
    m_bytesReceived += chunk.size();
    m_windowBytes   += chunk.size();

    // 速度：500ms 滑窗 + 指数平滑
    if (m_speedTimer.elapsed() >= 500) {
        const double secs = m_speedTimer.elapsed() / 1000.0;
        const double inst = (m_windowBytes / 1024.0) / secs;
        m_speedKBs = (m_speedKBs <= 0.0) ? inst : (m_speedKBs * 0.5 + inst * 0.5);
        m_windowBytes = 0;
        m_speedTimer.restart();
    }
    if (m_bytesTotal > 0)
        m_percent = static_cast<int>(m_bytesReceived * 100 / m_bytesTotal);

    // 进度信号 500ms 节流，防 QML 重绘风暴
    if (m_emitTimer.elapsed() >= 500) {
        m_emitTimer.restart();
        Q_EMIT progressChanged();
    }
}

void OtaService::onDownloadFinished()
{
    QNetworkReply *reply = m_reply;
    m_reply = nullptr;
    if (!reply)
        return;
    reply->deleteLater();

    // 取消：abort() 触发 OperationCanceledError
    if (reply->error() == QNetworkReply::OperationCanceledError) {
        qInfo() << "[OtaService] 下载已取消";
        cleanupDownload();
        m_percent = 0;
        m_speedKBs = 0.0;
        Q_EMIT progressChanged();
        setState(HasUpdate);   // 更新信息仍有效，回 HasUpdate 允许再次下载（不可回 Idle，否则 startDownload 守卫拒绝）
        return;
    }

    // 网络错误 / HTTP 4xx/5xx
    const int httpStatus = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (reply->error() != QNetworkReply::NoError || httpStatus >= 400) {
        qWarning() << "[OtaService] 下载失败:" << reply->errorString() << "HTTP" << httpStatus;
        cleanupDownload();
        setError(QStringLiteral("下载失败，请检查网络后重试"));
        return;
    }

    m_file->flush();
    m_file->close();

    // 大小校验（与服务端声明 size 不符视为不完整）
    if (m_bytesTotal > 0 && m_bytesReceived != m_bytesTotal) {
        qWarning() << "[OtaService] 下载不完整:" << m_bytesReceived << "/" << m_bytesTotal;
        cleanupDownload();
        setError(QStringLiteral("下载不完整，请重试"));
        return;
    }

    m_percent  = 100;
    m_speedKBs = 0.0;
    Q_EMIT progressChanged();

    setState(Verifying);

    // SHA256 校验（增量计算已完成，直接出结果比对）
    const QString actual = QString::fromLatin1(m_hash.result().toHex()).toLower();
    const QString expect = m_updateService->hash().toLower();
    qInfo() << "[OtaService] SHA256: 实际" << actual << "期望" << expect;
    if (!expect.isEmpty() && actual != expect) {
        cleanupDownload();
        setError(QStringLiteral("安装包校验失败，请重新下载"));
        return;
    }

    // 落盘为最终包名
    QString finalName = m_updateService->fileName();
    if (finalName.isEmpty())
        finalName = QStringLiteral("update.tar.gz");
    const QString finalPath = otaDir() + QLatin1Char('/') + finalName;
    QFile::remove(finalPath);
    if (!QFile::rename(otaDir() + QStringLiteral("/update.part"), finalPath)) {
        qWarning() << "[OtaService] 重命名失败:" << finalPath;
        cleanupDownload();
        setError(QStringLiteral("安装包保存失败"));
        return;
    }
    delete m_file;
    m_file = nullptr;

    m_packagePath = finalPath;
    qInfo() << "[OtaService] 包就绪:" << finalPath << m_bytesReceived << "字节";
    setState(ReadyToInstall);
}

void OtaService::cancelDownload()
{
    if (m_state != Downloading)
        return;
    if (m_reply) {
        m_reply->abort();   // 触发 finished(OperationCanceledError) → 清理 + 回 HasUpdate
    } else {
        cleanupDownload();
        setState(HasUpdate);
    }
}

void OtaService::cleanupDownload()
{
    if (m_file) {
        if (m_file->isOpen())
            m_file->close();
        QFile::remove(m_file->fileName());
        delete m_file;
        m_file = nullptr;
    }
}

// ============================================================================
// 刷写（脚本内：备份 .bak → 新版就位 → 拉起 → 30s 存活验证 → 失败自动回滚）
// ============================================================================

void OtaService::install()
{
    if (m_state != ReadyToInstall || m_packagePath.isEmpty()) {
        qDebug() << "[OtaService] 当前状态不允许安装:" << m_state;
        return;
    }

    QDir().mkpath(otaDir());

    // 写 pending.json（首启自检依据：脚本未写 result 标记时按版本比对兜底）
    QJsonObject pending;
    pending[QStringLiteral("version")] = m_latestVersion;
    pending[QStringLiteral("package")] = m_packagePath;
    pending[QStringLiteral("time")]    = QDateTime::currentDateTime().toString(Qt::ISODate);
    QFile pf(otaDir() + QStringLiteral("/pending.json"));
    if (pf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        pf.write(QJsonDocument(pending).toJson());
        pf.close();
    } else {
        qWarning() << "[OtaService] 无法写入 pending.json:" << pf.errorString();
    }

    // 从 qrc 导出刷写脚本（设备部署目录无 scripts/，必须内嵌）
    const QString scriptPath = otaDir() + QStringLiteral("/apply_update.sh");
    QFile res(QStringLiteral(":/scripts/apply_update.sh"));
    if (!res.open(QIODevice::ReadOnly)) {
        setError(QStringLiteral("升级组件缺失，请重新下载"));
        return;
    }
    const QByteArray scriptData = res.readAll();
    res.close();
    QFile sf(scriptPath);
    if (!sf.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        setError(QStringLiteral("升级组件写入失败"));
        return;
    }
    sf.write(scriptData);
    sf.close();
    QFile::setPermissions(scriptPath,
                          QFileDevice::ReadOwner | QFileDevice::WriteOwner | QFileDevice::ExeOwner |
                          QFileDevice::ReadGroup | QFileDevice::ExeGroup |
                          QFileDevice::ReadOther | QFileDevice::ExeOther);

    qInfo() << "[OtaService] 启动刷写脚本:" << scriptPath
            << "包:" << m_packagePath;
    setState(Installing);

    // 分离进程执行：脚本随后会停止本应用，必须独立于本进程存活
    qint64 pid = 0;
    const bool started = QProcess::startDetached(
        QStringLiteral("/bin/bash"),
        {scriptPath, m_packagePath, QCoreApplication::applicationDirPath()},
        QString(), &pid);
    if (!started) {
        qWarning() << "[OtaService] 刷写脚本启动失败";
        QFile::remove(otaDir() + QStringLiteral("/pending.json"));
        setError(QStringLiteral("无法启动安装程序"));
        return;
    }
    qInfo() << "[OtaService] 刷写脚本已启动, pid=" << pid << "（应用即将被脚本停止）";
}

// ============================================================================
// 复位 / 首启自检
// ============================================================================

void OtaService::resetState()
{
    if (m_state == Checking || m_state == Downloading
        || m_state == Verifying || m_state == Installing)
        return;
    m_errorString.clear();
    m_percent = 0;
    m_speedKBs = 0.0;
    Q_EMIT progressChanged();
    setState(Idle);
}

void OtaService::checkPendingResult()
{
    const QString dir = otaDir();
    const QString successPath   = dir + QStringLiteral("/result.success");
    const QString rolledbackPath = dir + QStringLiteral("/result.rolledback");
    const QString pendingPath   = dir + QStringLiteral("/pending.json");

    // 从 pending.json 读目标版本（result 文件内容第一行也是版本号，优先）
    QString pendingVersion;
    QFile pf(pendingPath);
    if (pf.open(QIODevice::ReadOnly)) {
        const QJsonDocument doc = QJsonDocument::fromJson(pf.readAll());
        pf.close();
        pendingVersion = doc.object().value(QStringLiteral("version")).toString();
    }

    auto readResultVersion = [&pendingVersion](const QString &path) {
        QFile f(path);
        if (f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            const QString v = QString::fromUtf8(f.readLine()).trimmed();
            f.close();
            if (!v.isEmpty())
                return v;
        }
        return pendingVersion;
    };

    // 清理函数：结果处理后移除标记与包文件
    auto cleanupMarkers = [&]() {
        QFile::remove(successPath);
        QFile::remove(rolledbackPath);
        QFile::remove(pendingPath);
        QDir ota(dir);
        const QStringList pkgs = ota.entryList({QStringLiteral("*.tar.gz"),
                                                QStringLiteral("*.part")},
                                               QDir::Files);
        for (const QString &p : pkgs)
            ota.remove(p);
    };

    bool hasResult = false;
    bool ok = false;
    bool rolledBack = false;
    QString version;

    if (QFile::exists(successPath)) {
        hasResult = true;
        ok = true;
        version = readResultVersion(successPath);
    } else if (QFile::exists(rolledbackPath)) {
        hasResult = true;
        ok = false;
        rolledBack = true;
        version = readResultVersion(rolledbackPath);
    } else if (QFile::exists(pendingPath)) {
        // 脚本未写 result 标记（中途断电等）：按当前版本与目标版本比对兜底
        hasResult = true;
        QString targetNum = pendingVersion;
        if (targetNum.startsWith(QLatin1Char('V'), Qt::CaseInsensitive))
            targetNum = targetNum.mid(1);
        if (!targetNum.isEmpty()
            && QVersionNumber::compare(QVersionNumber::fromString(QStringLiteral(APP_VERSION_FULL)),
                                       QVersionNumber::fromString(targetNum)) == 0) {
            ok = true;   // 当前就是目标版本：标记丢失但事实成功
        } else {
            ok = false;
            rolledBack = true;
        }
        version = pendingVersion;
    }

    if (!hasResult)
        return;

    m_latestVersion = version;
    m_updateAvailable = false;
    setState(ok ? Success : (rolledBack ? RolledBack : Failed));
    if (!ok && !rolledBack)
        m_errorString = QStringLiteral("升级未完成");

    qInfo() << "[OtaService] 首启自检: ok=" << ok << "rolledBack=" << rolledBack
            << "version=" << version;

    cleanupMarkers();

    // 延迟补报：等 QML 加载完成连接信号后再发
    QTimer::singleShot(3000, this, [this, ok, version, rolledBack]() {
        Q_EMIT upgradeResult(ok, version, rolledBack);
    });
}
