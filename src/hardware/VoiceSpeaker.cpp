#include "VoiceSpeaker.h"
#include <QDebug>
#include <QCoreApplication>
#include <QDir>
#include <QStandardPaths>
#include <QFileInfo>
#include <QRegularExpression>

VoiceSpeaker::VoiceSpeaker(QObject *parent)
    : QObject(parent)
    , m_process(nullptr)
    , m_isSpeaking(false)
    , m_isReady(false)
    , m_healthCheckTimer(nullptr)
{
    initializePiperPath();
    m_isReady = validatePiperInstallation();
    
    if (m_isReady) {
        qDebug() << "[VoiceSpeaker] Piper TTS system initialized successfully";
        qDebug() << "[VoiceSpeaker] Model:" << m_modelPath;
    } else {
        qWarning() << "[VoiceSpeaker] Piper TTS system not ready";
    }
    
    m_healthCheckTimer = new QTimer(this);
    connect(m_healthCheckTimer, &QTimer::timeout, this, [this]() {
        if (!m_isReady) {
            m_isReady = validatePiperInstallation();
            if (m_isReady) {
                Q_EMIT readyChanged();
            }
        }
    });
    // 每30秒检查一次系统就绪状态
    m_healthCheckTimer->start(30000);
}

VoiceSpeaker::~VoiceSpeaker()
{
    stop();
    cleanupProcess();
}

void VoiceSpeaker::initializePiperPath()
{
    // 默认 piper 安装路径
    m_piperPath = "/home/sjwu/piper/piper";
    
    // 模型文件路径
    m_modelPath = "/home/sjwu/piper/zh_CN-huayan-medium.onnx";
    m_configPath = "/home/sjwu/piper/zh_CN-huayan-medium.onnx.json";
    
    // 检查文件是否存在
    QFileInfo piperFile(m_piperPath);
    QFileInfo modelFile(m_modelPath);
    QFileInfo configFile(m_configPath);
    
    if (!piperFile.exists()) {
        qWarning() << "[VoiceSpeaker] Piper executable not found at:" << m_piperPath;
    }
    if (!modelFile.exists()) {
        qWarning() << "[VoiceSpeaker] Model file not found at:" << m_modelPath;
    }
    if (!configFile.exists()) {
        qWarning() << "[VoiceSpeaker] Config file not found at:" << m_configPath;
    }
}

bool VoiceSpeaker::validatePiperInstallation()
{
    QFileInfo piperFile(m_piperPath);
    QFileInfo modelFile(m_modelPath);
    QFileInfo configFile(m_configPath);
    
    if (!piperFile.exists() || !modelFile.exists() || !configFile.exists()) {
        return false;
    }
    
    // 检查 piper 是否可执行
    if (!piperFile.isExecutable()) {
        qWarning() << "[VoiceSpeaker] Piper is not executable:" << m_piperPath;
        return false;
    }
    
    // 检查音频播放器是否可用
    QProcess checkProcess;
    checkProcess.start("/bin/bash", QStringList() << "-c" << "command -v aplay");
    if (!checkProcess.waitForFinished(1000)) {
        qWarning() << "[VoiceSpeaker] Failed to check for aplay";
        return false;
    }
    if (checkProcess.exitCode() != 0) {
        qWarning() << "[VoiceSpeaker] aplay not found. Audio playback may not work.";
        // 不返回失败，因为仍然可以合成语音（只是无法播放）
    }
    
    return true;
}

QString VoiceSpeaker::sanitizeText(const QString &text) const
{
    // 移除可能影响命令行的特殊字符
    QString sanitized = text;
    sanitized.replace("\"", "'");
    sanitized.replace("`", "");
    sanitized.replace("$", "");
    sanitized.replace("\\", " ");
    sanitized.replace("\n", ". ");
    sanitized.replace("\r", "");
    
    // 限制长度，避免命令行过长
    const int maxLength = 1000;
    if (sanitized.length() > maxLength) {
        sanitized = sanitized.left(maxLength) + "...";
    }
    
    return sanitized.trimmed();
}

void VoiceSpeaker::speak(const QString &text)
{
    if (m_isSpeaking) {
        qDebug() << "[VoiceSpeaker] Already speaking, stopping current speech";
        stop();
        // 给一点时间清理
        QCoreApplication::processEvents();
    }
    
    if (!m_isReady) {
        qWarning() << "[VoiceSpeaker] TTS system not ready";
        Q_EMIT errorOccurred("语音合成系统未就绪，请检查 Piper TTS 安装");
        return;
    }
    
    QString sanitizedText = sanitizeText(text);
    if (sanitizedText.isEmpty()) {
        qWarning() << "[VoiceSpeaker] Text is empty after sanitization";
        return;
    }
    
    qDebug() << "[VoiceSpeaker] Speaking text:" << sanitizedText;
    
    cleanupProcess();
    m_process = new QProcess(this);
    
    connect(m_process, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &VoiceSpeaker::onProcessFinished);
    connect(m_process, &QProcess::errorOccurred,
            this, &VoiceSpeaker::onProcessErrorOccurred);
    connect(m_process, &QProcess::readyReadStandardError,
            this, &VoiceSpeaker::onProcessReadyReadStandardError);
    
    // 使用 bash 管道：将文本传递给 piper，然后将原始音频传递给 aplay
    // 注意：需要对文本进行适当的转义，以安全地嵌入到 bash 命令中
    QString escapedText = sanitizedText;
    escapedText.replace("'", "'\"'\"'");  // 转义单引号：' -> '"'"'
    
    // 构建完整的 shell 命令
    QString shellCommand = QString(
        "echo '%1' | '%2' --model '%3' --config '%4' --output_raw 2>/dev/null | "
        "aplay -r 22050 -f S16_LE -c 1 2>/dev/null"
    ).arg(escapedText, m_piperPath, m_modelPath, m_configPath);
    
    qDebug() << "[VoiceSpeaker] Executing command:" << shellCommand;
    
    // 设置环境变量，确保 piper 能找到依赖库
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("LD_LIBRARY_PATH", "/home/sjwu/piper:" + env.value("LD_LIBRARY_PATH"));
    m_process->setProcessEnvironment(env);
    
    // 启动 bash 进程执行管道命令
    m_process->start("/bin/bash", QStringList() << "-c" << shellCommand);
    
    if (!m_process->waitForStarted(3000)) {
        qWarning() << "[VoiceSpeaker] Failed to start speech process";
        Q_EMIT errorOccurred("无法启动语音播放进程");
        cleanupProcess();
        return;
    }
    
    m_isSpeaking = true;
    Q_EMIT speakingChanged();
    Q_EMIT speakStarted();
    
    qDebug() << "[VoiceSpeaker] Speech started successfully";
}

void VoiceSpeaker::stop()
{
    if (m_process && m_process->state() != QProcess::NotRunning) {
        qDebug() << "[VoiceSpeaker] Stopping speech";
        m_process->terminate();
        if (!m_process->waitForFinished(1000)) {
            m_process->kill();
        }
    }
    
    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
}

bool VoiceSpeaker::checkSystemReady()
{
    bool wasReady = m_isReady;
    m_isReady = validatePiperInstallation();
    
    if (m_isReady != wasReady) {
        Q_EMIT readyChanged();
    }
    
    return m_isReady;
}

void VoiceSpeaker::onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)
    
    qDebug() << "[VoiceSpeaker] Piper process finished with exit code:" << exitCode;
    
    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
    
    cleanupProcess();
}

void VoiceSpeaker::onProcessErrorOccurred(QProcess::ProcessError error)
{
    QString errorMsg;
    switch (error) {
    case QProcess::FailedToStart:
        errorMsg = "语音合成进程启动失败，请检查 Piper TTS 安装";
        break;
    case QProcess::Crashed:
        errorMsg = "语音合成进程意外崩溃";
        break;
    case QProcess::Timedout:
        errorMsg = "语音合成进程超时";
        break;
    case QProcess::WriteError:
        errorMsg = "写入语音数据失败";
        break;
    case QProcess::ReadError:
        errorMsg = "读取语音数据失败";
        break;
    default:
        errorMsg = "未知的语音合成错误";
        break;
    }
    
    qWarning() << "[VoiceSpeaker] Process error:" << errorMsg;
    Q_EMIT errorOccurred(errorMsg);
    
    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
    
    cleanupProcess();
}

void VoiceSpeaker::onProcessReadyReadStandardError()
{
    if (m_process) {
        QByteArray errorData = m_process->readAllStandardError();
        QString errorStr = QString::fromUtf8(errorData).trimmed();
        if (!errorStr.isEmpty()) {
            qWarning() << "[VoiceSpeaker] Piper stderr:" << errorStr;
            // 如果错误包含关键信息，发送信号
            if (errorStr.contains("error", Qt::CaseInsensitive) ||
                errorStr.contains("failed", Qt::CaseInsensitive) ||
                errorStr.contains("not found", Qt::CaseInsensitive)) {
                Q_EMIT errorOccurred("语音合成错误: " + errorStr);
            }
        }
    }
}

void VoiceSpeaker::cleanupProcess()
{
    if (m_process) {
        if (m_process->state() != QProcess::NotRunning) {
            m_process->terminate();
            m_process->waitForFinished(100);
        }
        m_process->deleteLater();
        m_process = nullptr;
    }
}
