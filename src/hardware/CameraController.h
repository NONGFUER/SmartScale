#ifndef CAMERACONTROLLER_H
#define CAMERACONTROLLER_H

#include <QObject>
#include <QPointer>
#include <QVideoSink>
#include <QVideoFrame>
#include <QImage>
#include <QProcess>
#include <QByteArray>
#include <QThreadPool>
#include <QRunnable>
#include <QMutex>
#include <atomic>
#include <QCamera>
#include <QMediaCaptureSession>
#include <QMediaDevices>
#include <QTimer>
#include "ai/VisionAIService.h"
#include "hardware/VoiceSpeaker.h"
#include "services/AuthService.h"
#include <QNetworkAccessManager>
#include <QNetworkReply>

class CameraController : public QObject
{
    Q_OBJECT

public:
    explicit CameraController(QObject *parent = nullptr);
    ~CameraController();

    Q_INVOKABLE void setMainVideoSink(QVideoSink *sink);
    Q_INVOKABLE void setSubVideoSink(QVideoSink *sink);
    Q_INVOKABLE void captureVegetable(double currentWeight, const QString &watermarkLabel = QString());
    Q_INVOKABLE void recognizeLastCapture();                  // 独立 AI 入口，不阻塞拍照/保存

    // AI-only 模式：仅拍照裁剪用于识别，不画水印不落盘（避免产生无用图片）
    Q_PROPERTY(bool aiOnlyMode READ aiOnlyMode WRITE setAiOnlyMode NOTIFY aiOnlyModeChanged)
    bool aiOnlyMode() const { return m_aiOnlyMode; }
    void setAiOnlyMode(bool on) { if (m_aiOnlyMode != on) { m_aiOnlyMode = on; Q_EMIT aiOnlyModeChanged(); } }

    // AI 候选列表（新接口返回多个候选时，供 QML 在选择食材弹窗中展示）
    Q_PROPERTY(QVariantList aiCandidateList READ aiCandidateList NOTIFY aiCandidateListChanged)
    QVariantList aiCandidateList() const { return m_aiCandidateList; }

    // 最后一次 AI 识别错误信息（QML 读取后弹 alert）
    Q_PROPERTY(QString lastAiError READ lastAiError NOTIFY lastAiErrorChanged)
    QString lastAiError() const { return m_lastAiError; }
    void setAiError(const QString &error);

    VisionAIService* aiService() const { return m_aiService; }
    void setVoiceSpeaker(VoiceSpeaker *speaker) { m_voiceSpeaker = speaker; }
    void setAuthService(AuthService *authSvc);
    void setWeightSensor(class WeightSensor *ws) { m_weightSensor = ws; }

Q_SIGNALS:
    void photoSaved(int cameraIndex, const QString &filePath);
    void aiRecognitionCompleted(const QString &predictedLabel, const QString &imagePath, qint64 inferenceTimeMs);
    void subCaptureReady();
    void cameraStatusChanged(const QString &statusText);
    void aiOnlyModeChanged();
    void lastAiErrorChanged();
    void aiCandidateListChanged();

private Q_SLOTS:
    void readSubCameraData();
    void handleMainCameraCapture();
    void onSubCaptureReady();
    void onCameraStatusChanged(int status);
    void onCameraErrorOccurred(int error, const QString &errorString);
    void onMainVideoFrameChanged();
    void onWatchdogTimeout();
    void restartMainCamera();
    void onNetworkReply(QNetworkReply *reply);          // 统一网络回复分发入口

private:
    QNetworkAccessManager *m_networkMgr = nullptr;

    // === 在线 AI 识别（公共请求/回复基础设施）===
    Q_INVOKABLE void postAiRecognize(const QImage &image, const QString &savePath);
    void handleAiRecognizeResponse(QNetworkReply *reply);   // 纯业务逻辑
    void emitAiResult(const QString &label, const QString &path, qint64 ms);  // 发射结果信号
    void speakPredictedLabel(const QString &label);         // 语音播报
    // === 公共工具方法（消除构造函数/重启函数重复代码）===
    QCameraDevice findUsbCamera();                          // 获取默认摄像头设备
    void setupCameraFormat(QCameraDevice &device);          // 设置最佳分辨率格式

    QPointer<QVideoSink> m_mainSink;
    QPointer<QVideoSink> m_subSink;

    std::atomic<double> m_lastWeight;
    std::atomic<bool> m_captureRequestedMain;
    std::atomic<bool> m_captureRequestedSub;

    QCamera *m_mainCamera = nullptr;
    QMediaCaptureSession m_mainCaptureSession;
    QProcess *m_subProcess;

    QByteArray m_subBuffer;
    int m_mainWidth = 1920;
    int m_mainHeight = 1080;
    int m_subWidth = 1280;
    int m_subHeight = 720;
    int m_subFrameSize = 0;
    // rpicam-vid --roi 归一化坐标 (x,y,w,h)，0~1；居中裁掉四周 10%
    // 修改后需重启进程生效（见 setSubRoi / restartSubCamera）
    QString m_subRoi = QStringLiteral("0.1,0.1,0.8,0.8");

    VisionAIService* m_aiService = nullptr;
    VoiceSpeaker *m_voiceSpeaker = nullptr;
    AuthService *m_authService = nullptr;
    class WeightSensor *m_weightSensor = nullptr;  // 用于获取设备 SN（水印文件名）

    QThreadPool *m_captureThreadPool = nullptr;
    QImage m_lastSubCaptureImage;
    mutable QMutex m_subImageMutex;

    // 看门狗（防卡死）
    QTimer *m_watchdogTimer = nullptr;
    qint64  m_lastFrameTimeMs = 0;
    int     m_watchdogIntervalMs = 5000;
    int     m_restartCount = 0;
    static constexpr int MAX_AUTO_RESTART = 10;
    bool    m_isRestarting = false;

    // 辅助函数
    int frameSizeFor(int w, int h) const { return w * h * 3 / 2; }

    // 图像处理管线
    void pushFrameToQML(int cameraIndex, const uint8_t *data, int width, int height, int stride);
    void processAndSaveImage(int cameraIndex, QByteArray frameData, int w, int h, int stride);
    void processAndSaveImage(int cameraIndex, QImage image);
    void _processCommon(int cameraIndex, QImage &img);
    void drawWatermarkOverlay(QPainter &painter, int imgW, int imgH,
                              const QString &label, const QImage &empPhoto = QImage());

    // 线程安全：工作线程读取水印标签和保存路径
    mutable QMutex m_captureMetaMutex;
    QString m_watermarkLabel;      // captureVegetable 传入的标签（英文，用于水印）
    QString m_lastSavePath;        // 最后一次主摄保存路径（供独立 AI 识别上下文）
    bool m_aiOnlyMode = false;     // true=仅拍照用于AI识别，不画水印不落盘
    QString m_lastAiError;         // 最后一次 AI 识别错误信息
    QVariantList m_aiCandidateList; // AI 候选列表 [{code,name}, ...]

    // === Token 刷新协调 ===
    bool m_refreshingToken = false;
    struct PendingAiRequest {
        QImage image;
        QString savePath;
    };
    QList<PendingAiRequest> m_pendingAiRequests;

private:
    void onTokenRefreshCompleted(bool success, const QString &errMsg);

    // 异步拍照任务
    class CaptureTask : public QRunnable {
    public:
        CaptureTask(CameraController *mgr, int camIdx, QByteArray data, int w, int h, int s, double weight)
            : manager(mgr), cameraIndex(camIdx), frameData(std::move(data)),
              width(w), height(h), stride(s), captureWeight(weight), useImage(false) {}
        CaptureTask(CameraController *mgr, int camIdx, QImage img, double weight)
            : manager(mgr), cameraIndex(camIdx), image(std::move(img)),
              captureWeight(weight), useImage(true) {}
        void run() override {
            manager->m_lastWeight.store(captureWeight);
            if (useImage) manager->processAndSaveImage(cameraIndex, std::move(image));
            else manager->processAndSaveImage(cameraIndex, std::move(frameData), width, height, stride);
        }
    private:
        CameraController *manager;
        int cameraIndex;
        QByteArray frameData;
        QImage image;
        int width = 0, height = 0, stride = 0;
        double captureWeight;
        bool useImage;
    };
};

#endif // CAMERACONTROLLER_H
