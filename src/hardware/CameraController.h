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

class CameraController : public QObject
{
    Q_OBJECT

public:
    explicit CameraController(QObject *parent = nullptr);
    ~CameraController();

    Q_INVOKABLE void setMainVideoSink(QVideoSink *sink);
    Q_INVOKABLE void setSubVideoSink(QVideoSink *sink);
    Q_INVOKABLE void captureVegetable(double currentWeight);

    VisionAIService* aiService() const { return m_aiService; }
    void setVoiceSpeaker(VoiceSpeaker *speaker) { m_voiceSpeaker = speaker; }
    void setAuthService(AuthService *authSvc) { m_authService = authSvc; }

Q_SIGNALS:
    void photoSaved(int cameraIndex, const QString &filePath);
    void aiRecognitionCompleted(const QString &predictedLabel, const QString &imagePath, qint64 inferenceTimeMs);
    void subCaptureReady();
    void cameraStatusChanged(const QString &statusText);

private Q_SLOTS:
    void readSubCameraData();
    void handleMainCameraCapture();
    void onSubCaptureReady();
    void onCameraStatusChanged(int status);
    void onCameraErrorOccurred(int error, const QString &errorString);
    void onMainVideoFrameChanged();
    void onWatchdogTimeout();
    void restartMainCamera();

private:
    // === 公共工具方法（消除构造函数/重启函数重复代码）===
    QCameraDevice findUsbCamera();                          // 扫描USB摄像头设备
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

    VisionAIService* m_aiService = nullptr;
    VoiceSpeaker *m_voiceSpeaker = nullptr;
    AuthService *m_authService = nullptr;

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
