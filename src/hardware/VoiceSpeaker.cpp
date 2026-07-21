#include "VoiceSpeaker.h"
#include <QDebug>
#include <QCoreApplication>
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

    config.model.num_threads = 2;          // RPi 级 CPU，避让 UI/相机线程
    config.model.debug = 1;                // 开 debug 让 sherpa 打印拒绝原因到 stderr
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
    qDebug() << "[TtsWorker] acoustic:" << pathAcoustic;
    qDebug() << "[TtsWorker] vocoder:" << pathVocoder;
    qDebug() << "[TtsWorker] lexicon:" << pathLexicon;
    qDebug() << "[TtsWorker] tokens:" << pathTokens;
    qDebug() << "[TtsWorker] dict_dir:" << pathDataDir;
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

// 合成进度回调：返回 0 终止合成，返回 1 继续
// arg 是指向 std::atomic<uint32_t> 的指针（代际取消标志）
static int32_t synthProgressCallback(const float * /*samples*/, int32_t /*n*/,
                                     float /*progress*/, void *arg)
{
    auto currentGen = static_cast<std::atomic<uint32_t> *>(arg)->load(std::memory_order_relaxed);
    static uint32_t lastReportedGen = 0;
    // 只在代际变化时打一次 log（避免刷屏）
    if (currentGen != lastReportedGen) {
        lastReportedGen = currentGen;
        qDebug() << "[TtsWorker] Synth cancelled: generation changed to" << currentGen;
    }
    return 0; // 始终让调用方检查代际
}

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
        synthProgressCallback, &generation);

    if (!audio || !audio->samples || audio->n <= 0) {
        qWarning() << "[TtsWorker] Generate returned NULL or empty audio";
        Q_EMIT synthError("语音合成失败", generation);
        return;
    }

    // 峰值归一化 + float → int16 PCM（复用 tts_worker.py 已验证逻辑）
    int32_t n = audio->n;
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

    qDebug() << "[TtsWorker] Synthesis done:" << n << "samples @"
             << audio->sample_rate << "Hz, peak=" << peak;

    Q_EMIT audioReady(pcm16, audio->sample_rate, generation);
}

// ============================================================
// VoiceSpeaker 实现 — 主线程（对外接口不变）
// ============================================================
VoiceSpeaker::VoiceSpeaker(QObject *parent)
    : QObject(parent)
    , m_aplayProcess(nullptr)
    , m_generation(0)
    , m_isSpeaking(false)
    , m_isReady(false)
{
    // 创建并启动合成工作线程
    m_worker = new TtsSynthWorker();
    m_worker->moveToThread(&m_synthThread);

    // 主线程 → 工作线程：投递合成任务
    connect(this, &VoiceSpeaker::requestSynthesize,
            m_worker, &TtsSynthWorker::synthesize);

    // 工作线程 → 主线程：返回合成结果
    connect(m_worker, &TtsSynthWorker::audioReady,
            this, &VoiceSpeaker::onAudioReady, Qt::QueuedConnection);
    connect(m_worker, &TtsSynthWorker::synthError,
            this, &VoiceSpeaker::onSynthError, Qt::QueuedConnection);

    m_synthThread.start();

    // 异步初始化引擎（在工作线程中执行，不阻塞主线程）
    QMetaObject::invokeMethod(m_worker, [this]() {
        bool ok = m_worker->initializeEngine();
        QMetaObject::invokeMethod(this, [this, ok]() {
            m_isReady = ok;
            if (ok) {
                qDebug() << "[VoiceSpeaker] Sherpa-onnx Matcha TTS ready";
            } else {
                qWarning() << "[VoiceSpeaker] Sherpa-onnx Matcha TTS init FAILED";
            }
            Q_EMIT readyChanged();
        }, Qt::QueuedConnection);
    });
}

VoiceSpeaker::~VoiceSpeaker()
{
    stop();
    stopAplay();
    m_synthThread.quit();
    m_synthThread.wait(5000);
    delete m_worker;
}

void VoiceSpeaker::speak(const QString &text)
{
    if (text.trimmed().isEmpty()) {
        return;
    }

    // 取消正在进行的旧合成+播放
    if (m_isSpeaking) {
        stop();
        QCoreApplication::processEvents();
    }

    if (!m_isReady) {
        qWarning() << "[VoiceSpeaker] TTS system not ready";
        Q_EMIT errorOccurred("语音合成系统未就绪");
        return;
    }

    // 递增代际（使旧的 callback 检测到取消）
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

    // 递增代际 → 合成线程的 progress callback 会检测到变化并终止
    m_generation.fetch_add(1);

    // 立即终止播放进程
    stopAplay();

    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
}

void VoiceSpeaker::warmup()
{
    // 引擎常驻后无需预热 page cache；保留接口兼容 QML 调用
    qDebug() << "[VoiceSpeaker] warmup: engine is resident, no-op";
}

bool VoiceSpeaker::checkSystemReady()
{
    return m_isReady;  // isReady 由引擎异步初始化结果决定
}

// ── 播放控制（主线程） ──

void VoiceSpeaker::startAplay(const QByteArray &pcm16Data)
{
    stopAplay();

    m_aplayProcess = new QProcess(this);
    connect(m_aplayProcess, QOverload<int, QProcess::ExitStatus>::of(&QProcess::finished),
            this, &VoiceSpeaker::onAplayFinished);
    connect(m_aplayProcess, &QProcess::errorOccurred,
            this, &VoiceSpeaker::onAplayErrorOccurred);

    // aplay 仅播放裸 PCM stdin，命令固定不含文本（安全）
    m_aplayProcess->start("aplay", QStringList({
        "-r", "22050",
        "-f", "S16_LE",
        "-c", "1"
    }));

    if (!m_aplayProcess->waitForStarted(2000)) {
        qWarning() << "[VoiceSpeaker] aplay failed to start";
        Q_EMIT errorOccurred("音频播放器启动失败");
        delete m_aplayProcess;
        m_aplayProcess = nullptr;
        return;
    }

    m_aplayProcess->write(pcm16Data);
    m_aplayProcess->closeWriteChannel();
}

void VoiceSpeaker::stopAplay()
{
    if (m_aplayProcess && m_aplayProcess->state() != QProcess::NotRunning) {
        m_aplayProcess->terminate();
        if (!m_aplayProcess->waitForFinished(500)) {
            m_aplayProcess->kill();
        }
    }
}

void VoiceSpeaker::onAplayFinished(int exitCode, QProcess::ExitStatus exitStatus)
{
    Q_UNUSED(exitStatus)

    if (m_isSpeaking) {
        qDebug() << "[VoiceSpeaker] aplay finished, exitCode=" << exitCode;
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
}

void VoiceSpeaker::onAplayErrorOccurred(QProcess::ProcessError error)
{
    qWarning() << "[VoiceSpeaker] aplay error:" << error;

    if (m_isSpeaking) {
        m_isSpeaking = false;
        Q_EMIT speakingChanged();
        Q_EMIT speakFinished();
    }
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
