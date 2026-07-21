#include "VoiceSpeaker.h"
#include <QDebug>
#include <QCoreApplication>
#include <QFile>
#include <cmath>
#include <dlfcn.h>

// 使用官方头文件确保结构体布局与 sherpa-onnx 1.13.x 二进制完全一致
// 仅用于编译期类型信息；运行时仍通过 dlopen(RTLD_LOCAL) 隔离加载，不产生链接依赖
#include "c-api.h"

// ============================================================
// 模型路径常量（集中管理）
// ============================================================
static const QString MODEL_DIR("/home/sjwu/matcha-icefall-zh-baker");
static const QString SHERPA_SO_PATH(
    "/home/sjwu/.local/lib/python3.13/site-packages/sherpa_onnx/lib/libsherpa-onnx-c-api.so");

// ============================================================
// TtsSynthWorker 实现 — 运行在独立合成线程
// ============================================================
TtsSynthWorker::TtsSynthWorker(QObject *parent)
    : QObject(parent)
    , m_sherpaHandle(nullptr)
    , fnCreate(nullptr)
    , fnDestroy(nullptr)
    , fnGenerate(nullptr)
    , fnDestroyAudio(nullptr)
    , m_engine(nullptr)
{
}

TtsSynthWorker::~TtsSynthWorker()
{
    if (m_engine && fnDestroy) {
        fnDestroy(m_engine);
        m_engine = nullptr;
    }
    if (m_sherpaHandle) {
        dlclose(m_sherpaHandle);
        m_sherpaHandle = nullptr;
    }
}

bool TtsSynthWorker::resolveSymbols()
{
    fnCreate        = (FnCreateOfflineTts)dlsym(m_sherpaHandle, "SherpaOnnxCreateOfflineTts");
    fnDestroy       = (FnDestroyOfflineTts)dlsym(m_sherpaHandle, "SherpaOnnxDestroyOfflineTts");
    fnGenerate      = (FnGenerateWithConfig)dlsym(m_sherpaHandle, "SherpaOnnxOfflineTtsGenerateWithConfig");
    fnDestroyAudio  = (FnDestroyGeneratedAudio)dlsym(m_sherpaHandle, "SherpaOnnxDestroyOfflineTtsGeneratedAudio");

    if (!fnCreate || !fnDestroy || !fnGenerate || !fnDestroyAudio) {
        qWarning() << "[TtsWorker] dlsym failed:" << dlerror();
        return false;
    }
    return true;
}

bool TtsSynthWorker::initializeEngine()
{
    Q_ASSERT(QThread::currentThread() == thread());

    static const QByteArray soPath = SHERPA_SO_PATH.toUtf8();
    static const QByteArray sherpaLibDir = "/home/sjwu/.local/lib/python3.13/site-packages/sherpa_onnx/lib";

    qDebug() << "[TtsWorker] === TTS Engine Init Start ===";
    qDebug() << "[TtsWorker] soPath:" << soPath;

    // 注入 sherpa 库目录到 LD_LIBRARY_PATH，确保 dlopen 能解析 sherpa 自带的 libonnxruntime.so
    //（sherpa 自带 ORT 1.27，与项目 ORT 1.24.4 不同；RTLD_LOCAL 隔离全局符号）
    QByteArray oldLdPath = qgetenv("LD_LIBRARY_PATH");
    QByteArray newLdPath = sherpaLibDir;
    if (!oldLdPath.isEmpty()) {
        newLdPath += ":" + oldLdPath;
    }
    qputenv("LD_LIBRARY_PATH", newLdPath);
    qDebug() << "[TtsWorker] LD_LIBRARY_PATH updated with" << sherpaLibDir;

    // dlopen RTLD_LOCAL: 隔离 sherpa 自带的 ORT 1.27 符号，
    // 避免与项目链接的 ORT 1.24.4 全局符号冲突
    m_sherpaHandle = dlopen(soPath.constData(), RTLD_NOW | RTLD_LOCAL);

    // 恢复原 LD_LIBRARY_PATH（避免影响其他组件）
    if (oldLdPath.isEmpty()) {
        qunsetenv("LD_LIBRARY_PATH");
    } else {
        qputenv("LD_LIBRARY_PATH", oldLdPath);
    }

    if (!m_sherpaHandle) {
        qWarning() << "[TtsWorker] dlopen FAILED:" << dlerror();
        return false;
    }
    qDebug() << "[TtsWorker] dlopen OK";

    if (!resolveSymbols()) {
        qWarning() << "[TtsWorker] resolveSymbols FAILED";
        dlclose(m_sherpaHandle);
        m_sherpaHandle = nullptr;
        return false;
    }
    qDebug() << "[TtsWorker] all symbols resolved";

    // 路径字符串必须用静态存储（config 持有 const char* 指针，不能指向临时）
    // qPrintable() 返回的 char* 在语句结束时释放，导致悬垂指针
    static const QByteArray pathAcoustic = (MODEL_DIR + "/model-steps-3.onnx").toUtf8();
    static const QByteArray pathVocoder   = (MODEL_DIR + "/vocos-22khz-univ.onnx").toUtf8();
    static const QByteArray pathLexicon   = (MODEL_DIR + "/lexicon.txt").toUtf8();
    static const QByteArray pathTokens    = (MODEL_DIR + "/tokens.txt").toUtf8();
    static const QByteArray pathDataDir   = MODEL_DIR.toUtf8();

    // 构建 Matcha-TTS 配置
    SherpaOnnxOfflineTtsConfig config;
    memset(&config, 0, sizeof(config));

    config.model.num_threads = 1;          // 最小线程数，避让 UI/相机线程
    config.model.debug = 0;                // 关闭 debug（避免 stderr 大量输出）
    config.model.provider = "cpu";
    config.model.matcha.acoustic_model = pathAcoustic.constData();
    config.model.matcha.vocoder       = pathVocoder.constData();
    config.model.matcha.lexicon        = pathLexicon.constData();
    config.model.matcha.tokens         = pathTokens.constData();
    config.model.matcha.data_dir       = nullptr;                  // 中文模型不填（espeak 路径）
    config.model.matcha.noise_scale    = 0.667f;
    config.model.matcha.length_scale   = 0.92f;
    config.model.matcha.dict_dir       = pathDataDir.constData();  // 中文分词字典目录
    config.max_num_sentences = 1;
    config.silence_scale      = 0.3f;

    qDebug() << "[TtsWorker] Creating Matcha-TTS engine (Baker)...";

    // 诊断：检查模型文件是否存在
    for (const auto &p : {pathAcoustic, pathVocoder, pathLexicon, pathTokens}) {
        if (!QFile::exists(QString::fromUtf8(p))) {
            qWarning() << "[TtsWorker] MISSING FILE:" << p;
        }
    }

    m_engine = fnCreate(&config);
    if (!m_engine) {
        qWarning() << "[TtsWorker] SherpaOnnxCreateOfflineTts returned NULL";
        dlclose(m_sherpaHandle);
        m_sherpaHandle = nullptr;
        return false;
    }

    qDebug() << "[TtsWorker] Matcha-TTS engine created successfully";
    return true;
}

// 合成进度回调已移除：取消机制改为 VoiceSpeaker::onAudioReady 的代际检查，
// 过期合成结果在主线程被丢弃即可，无需中断 sherpa 内部推理

void TtsSynthWorker::synthesize(const QString &text, uint32_t generation)
{
    Q_ASSERT(QThread::currentThread() == thread());

    if (!m_engine || !fnGenerate) {
        Q_EMIT synthError("TTS 引擎未初始化", generation);
        return;
    }

    QByteArray utf8Text = text.toUtf8();
    if (utf8Text.trimmed().isEmpty()) {
        return;
    }

    qDebug() << "[TtsWorker] Synthesizing:" << text;

    SherpaOnnxGenerationConfig genCfg;
    memset(&genCfg, 0, sizeof(genCfg));
    genCfg.sid           = 0;
    genCfg.speed         = 1.0f;
    genCfg.silence_scale = 0.3f;

    const SherpaOnnxGeneratedAudio *audio = fnGenerate(
        m_engine, utf8Text.constData(), &genCfg,
        nullptr, nullptr);  // 不用 callback，取消靠 onAudioReady 代际检查丢弃结果

    if (!audio || !audio->samples || audio->n <= 0) {
        qWarning() << "[TtsWorker] Generate returned NULL or empty audio";
        Q_EMIT synthError("语音合成失败", generation);
        return;
    }

    // 峰值归一化 + float → int16 PCM（复用 tts_worker.py 已验证逻辑）
    // 注意：必须在 fnDestroyAudio 之前保存 sampleRate
    int32_t n = audio->n;
    int32_t sampleRate = audio->sample_rate;
    const float *samples = audio->samples;
    float peak = 0.0f;
    for (int32_t i = 0; i < n; ++i) {
        float absVal = std::abs(samples[i]);
        if (absVal > peak) peak = absVal;
    }

    QByteArray pcm16;
    pcm16.resize(n * sizeof(int16_t));
    auto *dst = reinterpret_cast<int16_t *>(pcm16.data());
    if (peak > 0.0f) {
        float invPeak = 32767.0f / peak;
        for (int32_t i = 0; i < n; ++i) {
            dst[i] = static_cast<int16_t>(std::clamp(samples[i] * invPeak, -32768.0f, 32767.0f));
        }
    } else {
        memset(dst, 0, n * sizeof(int16_t));
    }

    fnDestroyAudio(audio);

    qDebug() << "[TtsWorker] Synthesis done:" << n << "samples @" << sampleRate << "Hz, peak=" << peak;

    Q_EMIT audioReady(pcm16, sampleRate, generation);
}

// ============================================================
// VoiceSpeaker 实现 — 主线程（对外接口不变）
// ============================================================
VoiceSpeaker::VoiceSpeaker(QObject *parent)
    : QObject(parent)
    , m_worker(nullptr)
    , m_aplayProcess(nullptr)
    , m_generation(0)
    , m_isSpeaking(false)
    , m_isReady(false)
    , m_threadStarted(false)
{
    // 惰性启动：线程只在首次 speak() 时创建，不影响 app 启动速度
}

VoiceSpeaker::~VoiceSpeaker()
{
    stop();
    stopAplay();
    if (m_threadStarted) {
        m_synthThread.quit();
        m_synthThread.wait(5000);
        delete m_worker;
    }
}

void VoiceSpeaker::speak(const QString &text)
{
    if (text.trimmed().isEmpty()) {
        return;
    }

    // 惰性启动：首次 speak() 时才创建线程和引擎
    if (!m_threadStarted) {
        m_threadStarted = true;
        qDebug() << "[VoiceSpeaker] Lazy-starting synth thread...";

        m_worker = new TtsSynthWorker();
        m_worker->moveToThread(&m_synthThread);

        connect(this, &VoiceSpeaker::requestSynthesize,
                m_worker, &TtsSynthWorker::synthesize);
        connect(m_worker, &TtsSynthWorker::audioReady,
                this, &VoiceSpeaker::onAudioReady, Qt::QueuedConnection);
        connect(m_worker, &TtsSynthWorker::synthError,
                this, &VoiceSpeaker::onSynthError, Qt::QueuedConnection);

        m_synthThread.start();

        // 异步初始化引擎
        QMetaObject::invokeMethod(m_worker, [this]() {
            bool ok = m_worker->initializeEngine();
            QMetaObject::invokeMethod(this, [this, ok]() {
                m_isReady = ok;
                if (ok) {
                    qDebug() << "[VoiceSpeaker] Sherpa-onnx Matcha TTS ready";
                    if (!m_pendingText.isEmpty()) {
                        QString text = m_pendingText;
                        m_pendingText.clear();
                        qDebug() << "[VoiceSpeaker] Replaying pending speak:" << text;
                        speak(text);
                    }
                } else {
                    qWarning() << "[VoiceSpeaker] Sherpa-onnx Matcha TTS init FAILED";
                    m_pendingText.clear();
                }
                Q_EMIT readyChanged();
            }, Qt::QueuedConnection);
        });
    }

    // 引擎未就绪：缓存本次文本，等引擎初始化完成后自动重播
    if (!m_isReady) {
        qDebug() << "[VoiceSpeaker] Engine not ready, pending speak:" << text;
        m_pendingText = text;
        return;
    }

    // 取消正在进行的旧合成+播放
    if (m_isSpeaking) {
        stop();
    }

    uint32_t gen = m_generation.fetch_add(1) + 1;

    qDebug() << "[VoiceSpeaker] speak:" << text << "gen=" << gen;

    m_isSpeaking = true;
    Q_EMIT speakingChanged();
    Q_EMIT speakStarted();

    // 投递到合成线程
    Q_EMIT requestSynthesize(text, gen);
}

void VoiceSpeaker::stop()
{
    qDebug() << "[VoiceSpeaker] stop requested";
    m_generation.fetch_add(1);
    stopAplay();

    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
}

void VoiceSpeaker::warmup()
{
    qDebug() << "[VoiceSpeaker] warmup: engine is resident, no-op";
}

bool VoiceSpeaker::checkSystemReady()
{
    return m_isReady;
}

// ── 播放控制（主线程，aplay 常驻进程，不再每次新建） ──

void VoiceSpeaker::startAplay(const QByteArray &pcm16Data)
{
    stopAplay();  // 如果上一个 aplay 还在播，先停掉

    m_aplayProcess = new QProcess(this);
    // 不 connect finished/errorOccurred 到具体槽函数，
    // 改用 lambda 内联处理，避免信号累积
    connect(m_aplayProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, [this](int exitCode, QProcess::ExitStatus) {
        if (m_isSpeaking) {
            qDebug() << "[VoiceSpeaker] aplay finished, exitCode=" << exitCode;
            m_isSpeaking = false;
            Q_EMIT speakingChanged();
            Q_EMIT speakFinished();
        }
    });
    connect(m_aplayProcess, &QProcess::errorOccurred,
            this, [this](QProcess::ProcessError error) {
        qWarning() << "[VoiceSpeaker] aplay error:" << error;
        if (m_isSpeaking) {
            m_isSpeaking = false;
            Q_EMIT speakingChanged();
            Q_EMIT speakFinished();
        }
    });

    m_aplayProcess->start("aplay", QStringList({
        "-r", "22050", "-f", "S16_LE", "-c", "1"
    }));

    if (!m_aplayProcess->waitForStarted(2000)) {
        qWarning() << "[VoiceSpeaker] aplay failed to start";
        Q_EMIT errorOccurred("音频播放器启动失败");
        m_aplayProcess->deleteLater();
        m_aplayProcess = nullptr;
        return;
    }

    m_aplayProcess->write(pcm16Data);
    m_aplayProcess->closeWriteChannel();
}

void VoiceSpeaker::stopAplay()
{
    if (!m_aplayProcess) return;

    QProcess *p = m_aplayProcess;
    m_aplayProcess = nullptr;

    if (p->state() != QProcess::NotRunning) {
        p->disconnect(this);          // 断开所有信号，避免 lambda 引用已释放的 this
        p->terminate();
        p->waitForFinished(200);      // 最多等 200ms，不阻塞主线程
        if (p->state() != QProcess::NotRunning) {
            p->kill();
            p->waitForFinished(100);
        }
    }
    p->deleteLater();
}

// ── 合成回调（主线程，QueuedConnection） ──

void VoiceSpeaker::onAudioReady(QByteArray pcm16Data, int sampleRate, uint32_t generation)
{
    Q_UNUSED(sampleRate)

    // 代际检查：如果已有更新的 speak/stop，丢弃过期结果
    if (generation != m_generation.load(std::memory_order_relaxed)) {
        qDebug() << "[VoiceSpeaker] Dropping stale audio: gen" << generation
                 << "!= current" << m_generation.load();
        return;
    }

    if (!m_isSpeaking) {
        return;  // 已经被 stop 了
    }

    qDebug() << "[VoiceSpeaker] Playing audio, size=" << pcm16Data.size() << "bytes";
    startAplay(pcm16Data);
}

void VoiceSpeaker::onSynthError(QString message, uint32_t generation)
{
    // 同样做代际检查
    if (generation != m_generation.load(std::memory_order_relaxed)) {
        return;  // 过期错误，忽略
    }

    qWarning() << "[VoiceSpeaker] Synth error:" << message;
    Q_EMIT errorOccurred(message);

    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
}
