#ifndef VOICESPEAKER_H
#define VOICESPEAKER_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QTimer>

class VoiceSpeaker : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isSpeaking READ isSpeaking NOTIFY speakingChanged)
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)

public:
    explicit VoiceSpeaker(QObject *parent = nullptr);
    ~VoiceSpeaker();

    // Q_INVOKABLE 方法供 QML 调用
    Q_INVOKABLE void speak(const QString &text);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void warmup();  // 预热：开机加载模型到 OS page cache，避免首次语音延迟

    // 检查 TTS 系统是否就绪（检查 piper 程序和模型文件）
    Q_INVOKABLE bool checkSystemReady();

    // 属性读取器
    bool isSpeaking() const { return m_isSpeaking; }
    bool isReady() const { return m_isReady; }

Q_SIGNALS:
    void speakingChanged();
    void readyChanged();
    void speakStarted();
    void speakFinished();
    void errorOccurred(const QString &errorMessage);

private Q_SLOTS:
    void onProcessFinished(int exitCode, QProcess::ExitStatus exitStatus);
    void onProcessErrorOccurred(QProcess::ProcessError error);
    void onProcessReadyReadStandardError();

private:
    void initializePiperPath();
    bool validatePiperInstallation();
    void cleanupProcess();
    QString sanitizeText(const QString &text) const;

private:
    QProcess *m_process;
    QString m_piperPath;
    QString m_modelPath;
    QString m_configPath;
    bool m_isSpeaking;
    bool m_isReady;
    QTimer *m_healthCheckTimer;
};

#endif // VOICESPEAKER_H
