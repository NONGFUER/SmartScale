#ifndef CAMERACONTROLLER_H
#define CAMERACONTROLLER_H

#include <QObject>
#include <QtGlobal>
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
    
    // 跨线程/UI触发抓拍，传入当前重量
    Q_INVOKABLE void captureVegetable(double currentWeight);
    //通过CameraController获取AI服务指针
    VisionAIService* aiService() const { return m_aiService; }
    void setVoiceSpeaker(VoiceSpeaker *speaker) { m_voiceSpeaker = speaker; }
    void setAuthService(AuthService *authSvc) { m_authService = authSvc; }
Q_SIGNALS:
    void photoSaved(int cameraIndex, const QString &filePath);
    void aiRecognitionCompleted(const QString &predictedLabel, const QString &imagePath, qint64 inferenceTimeMs);
    // 副摄像头抓拍完成，用于串联主摄像头抓拍
    void subCaptureReady();   //
private Q_SLOTS:
    // 副摄像头管道数据泵 (rpicam-vid, 主摄像头已切换到QCamera不再需要)
    void readSubCameraData();
    // 主摄像头截图槽（从QVideoSink取当前帧）
    void handleMainCameraCapture();
    // 副摄像头抓拍完成后触发主摄像头（串联）
    void onSubCaptureReady();

private:
    QPointer<QVideoSink> m_mainSink;
    QPointer<QVideoSink> m_subSink;
    
    std::atomic<double> m_lastWeight;
    std::atomic<bool> m_captureRequestedMain; 
    std::atomic<bool> m_captureRequestedSub;

    // === 摄像头硬件流 ===
    // 主摄像头: Qt Multimedia QCamera (原生集成，零子进程)
    QCamera *m_mainCamera = nullptr;
    QMediaCaptureSession m_mainCaptureSession;
    // 副摄像头: rpicam-vid 子进程 (保持不变)
    QProcess *m_subProcess;

    QByteArray m_subBuffer;       // 副摄像头帧缓冲（主摄像头不再需要）
    
    // 摄像头配置 - 模块化设计，支持快速切换
    
    // 主摄像头配置 (USB摄像头)
    int m_mainWidth;      // USB摄像头分辨率
    int m_mainHeight;
    int m_mainFrameSize;  // YUV420P帧大小
    
    // 副摄像头配置 (IMX708)
    int m_subWidth;       // IMX708分辨率
    int m_subHeight;
    int m_subFrameSize;   // YUV420P帧大小

    VisionAIService* m_aiService;
    VoiceSpeaker *m_voiceSpeaker = nullptr;
    AuthService *m_authService = nullptr;  // 登录用户信息

    QThreadPool *m_captureThreadPool;  // 异步拍照线程池

    // 副摄像头最新抓拍图像（用于主摄像头水印中的"员工照片"区域）
    QImage m_lastSubCaptureImage;
    mutable QMutex m_subImageMutex;   // 线程安全保护

    // 辅助函数
    int frameSizeFor(int width, int height) const {
        return width * height * 3 / 2; // YUV420P大小计算
    }

    // 渲染与图像处理管线
    void pushFrameToQML(int cameraIndex, const uint8_t *data, int width, int height, int stride);
    void processAndSaveImage(int cameraIndex, QByteArray frameData, int width, int height, int stride);
    void processAndSaveImage(int cameraIndex, QImage image);  // QCamera 截图用 (已解码RGB)

    // 共享处理：裁剪 → 分发 → 时间戳 → AI推理 → 水印 → 保存（统一主/副摄逻辑）
    void _processCommon(int cameraIndex, QImage &watermarkedImg);

    // 图像锐化 (Unsharp Mask)，补偿低分辨率/插值导致的模糊
    static QImage sharpenImage(const QImage &src, float strength = 0.5f, int radius = 1);

    // 水印绘制（小管事风格：顶部栏 + 右侧员工区(副摄像照片) + 左下公章 + 右下信息）
    void drawWatermarkOverlay(QPainter &painter, int imgWidth, int imgHeight,
                              const QString &predictedLabel,
                              const QImage &employeePhoto = QImage());

private:
    // 异步拍照任务（QRunnable，提交到 m_captureThreadPool 执行）
    class CaptureTask : public QRunnable {
    public:
        // 副摄像头: YUV420P 原始数据 (rpicam-vid 管道)
        CaptureTask(CameraController *mgr, int camIdx, QByteArray data, int w, int h, int s, double weight)
            : manager(mgr), cameraIndex(camIdx), frameData(std::move(data)),
              width(w), height(h), stride(s), captureWeight(weight), useImage(false) {}
        // 主摄像头: 已解码的 QImage (QCamera 截图)
        CaptureTask(CameraController *mgr, int camIdx, QImage img, double weight)
            : manager(mgr), cameraIndex(camIdx), image(std::move(img)),
              captureWeight(weight), useImage(true) {}
        void run() override {
            manager->m_lastWeight.store(captureWeight);
            if (useImage) {
                manager->processAndSaveImage(cameraIndex, std::move(image));
            } else {
                manager->processAndSaveImage(cameraIndex, std::move(frameData), width, height, stride);
            }
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
