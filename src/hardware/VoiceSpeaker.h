#ifndef VOICESPEAKER_H
#define VOICESPEAKER_H

#include <QObject>
#include <QProcess>
#include <QString>
#include <QThread>
#include <atomic>

// sherpa-onnx C API 前向声明（通过 dlopen RTLD_LOCAL 动态加载，避免 ORT 1.27 与项目 1.24.4 符号冲突）
struct SherpaOnnxOfflineTts;
struct SherpaOnnxOfflineTtsConfig;
struct SherpaOnnxGenerationConfig;
struct SherpaOnnxGeneratedAudio;

/// 合成工作线程：持有 sherpa-onnx 引擎（本线程创建/销毁），执行 TTS 合成
class TtsSynthWorker : public QObject {
    Q_OBJECT
public:
    explicit TtsSynthWorker(QObject *parent = nullptr);
    ~TtsSynthWorker();

    /// 初始化引擎（必须在本线程调用）。成功返回 true
    bool initializeEngine();

public Q_SLOTS:
    /// 执行合成任务（由主线程通过 signal-slot 投递到本线程）
    void synthesize(const QString &text, uint32_t generation);

Q_SIGNALS:
    void audioReady(QByteArray pcm16Data, int sampleRate, uint32_t generation);
    void synthError(QString message, uint32_t generation);

private:
    // dlopen 句柄（RTLD_LOCAL 隔离符号）
    void *m_sherpaHandle;

    // dlsym 函数指针类型
    using FnCreateOfflineTts = const SherpaOnnxOfflineTts *(*)(const SherpaOnnxOfflineTtsConfig *);
    using FnDestroyOfflineTts = void (*)(const SherpaOnnxOfflineTts *);
    using FnGenerateWithConfig = const SherpaOnnxGeneratedAudio *(*)(
        const SherpaOnnxOfflineTts *, const char *,
        const SherpaOnnxGenerationConfig *,
        int32_t (*)(const float *, int32_t, float, void *), void *);
    using FnDestroyGeneratedAudio = void (*)(const SherpaOnnxGeneratedAudio *);

    FnCreateOfflineTts     fnCreate;
    FnDestroyOfflineTts    fnDestroy;
    FnGenerateWithConfig   fnGenerate;
    FnDestroyGeneratedAudio fnDestroyAudio;

    // 引擎句柄（仅在本线程有效）
    const SherpaOnnxOfflineTts *m_engine;

    bool resolveSymbols();
};

class VoiceSpeaker : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isSpeaking READ isSpeaking NOTIFY speakingChanged)
    Q_PROPERTY(bool isReady READ isReady NOTIFY readyChanged)

public:
    explicit VoiceSpeaker(QObject *parent = nullptr);
    ~VoiceSpeaker();

    Q_INVOKABLE void speak(const QString &text);
    Q_INVOKABLE void stop();
    Q_INVOKABLE void warmup();
    Q_INVOKABLE bool checkSystemReady();

    bool isSpeaking() const { return m_isSpeaking; }
    bool isReady() const { return m_isReady; }

Q_SIGNALS:
    void speakingChanged();
    void readyChanged();
    void speakStarted();
    void speakFinished();
    void errorOccurred(const QString &errorMessage);

    // 内部信号（投递合成任务到工作线程）
    void requestSynthesize(const QString &text, uint32_t generation);

private Q_SLOTS:
    void onAudioReady(QByteArray pcm16Data, int sampleRate, uint32_t generation);
    void onSynthError(QString message, uint32_t generation);

private:
    void startAplay(const QByteArray &pcm16Data);
    void stopAplay();
    void startSynthThread();  // 构造函数中调用：后台预初始化引擎，消除首次播报延迟

    // 合成线程
    QThread m_synthThread;
    TtsSynthWorker *m_worker;   // owned by m_synthThread

    // 播放进程
    QProcess *m_aplayProcess;

    // 取消代际：每次 speak/stop 递增，callback 中比对判断是否已取消
    std::atomic<uint32_t> m_generation;

    bool m_isSpeaking;
    bool m_isReady;
    bool m_threadStarted;  // 惰性线程启动标记：首次 speak() 时才创建 QThread
    QString m_pendingText;  // 引擎未就绪时缓存的 speak 文本，就绪后自动重播
};

#endif // VOICESPEAKER_H
