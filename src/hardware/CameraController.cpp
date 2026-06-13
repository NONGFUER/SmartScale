#include "CameraController.h"
#include "utils/FoodTranslator.h"
#include <QVideoFrameFormat>
#include <QPainter>
#include <QDateTime>
#include <QDir>
#include <QDebug>
#include <QDeadlineTimer>
#include <QMetaObject>
#include <QCoreApplication>
#include <algorithm>


// ==========================================
// 📷 摄像头配置模块
// ==========================================
// 副摄像头选择：
// 1. 使用 IMX708 (CSI摄像头0) - 推荐方案
// 2. 使用 OV5647 (CSI摄像头1) - 旧方案
// 修改下面的宏定义来切换摄像头方案
#define SUB_CAMERA_IMX708   1
#define SUB_CAMERA_OV5647   2
#define CURRENT_SUB_CAMERA  SUB_CAMERA_IMX708  // 当前使用的副摄像头
#define USB_CAMERA_DEVICE_BY_ID  "/dev/v4l/by-id/usb-UGREEN_Camera_2K_UGREEN_Camera_2K_CM8260001-video-index0"
#define USB_CAMERA_DEVICE_BY_ID2  "/dev/v4l/by-id/usb-Sonix_Technology_Co.__Ltd._UGREEN_Camera_1080P_SN0001-video-index0"
#define USB_CAMERA_DEVICE_BY_ID3  "/dev/v4l/by-id/usb-USB_2.0_Camera_USB_2.0_Camera-video-index0"


// USB摄像头设备路径（可根据实际情况修改）
#define USB_CAMERA_DEVICE   USB_CAMERA_DEVICE_BY_ID3


// 副摄像头显示名称（根据 CURRENT_SUB_CAMERA 自动确定）
#if CURRENT_SUB_CAMERA == SUB_CAMERA_IMX708
#define SUB_CAMERA_NAME "IMX708"
#elif CURRENT_SUB_CAMERA == SUB_CAMERA_OV5647
#define SUB_CAMERA_NAME "OV5647"
#else
#define SUB_CAMERA_NAME "Unknown"
#endif

// ==========================================

CameraController::CameraController(QObject *parent)
    : QObject(parent), 
      m_mainSink(nullptr), m_subSink(nullptr),
      m_lastWeight(0.0), 
      m_captureRequestedMain(false), m_captureRequestedSub(false),
      // 主摄像头分辨率: 2592×1944 (约500万像素)
      // 比原1080p高80%，支持MJPG格式30fps
      // 注意：此分辨率仅支持MJPG格式，YUV不可用
      m_mainWidth(1920), m_mainHeight(1080),
      //m_mainWidth(1920), m_mainHeight(1080),
      // 副摄像头分辨率: 1280×720 (720p) — 性能优化
      // 原 IMX708 全分辨率 2304×1296 导致每帧 4.3MB 数据量，造成严重卡顿
      // 降为 720p 后数据量减少 68%（~1.4MB/帧），大幅减轻主线程负担
      m_subWidth(1280), m_subHeight(720)
{
    // ==========================================
    // 树莓派ISP调优文件路径差异
    // Pi 4B / Compute Module 4 使用 vc4 目录："/usr/share/libcamera/ipa/rpi/vc4/"
    // Pi 5 使用 pisp 目录："/usr/share/libcamera/ipa/rpi/pisp/"
    // ==========================================
    QString tuningBaseDir = "/usr/share/libcamera/ipa/rpi/pisp/";

    // 计算副摄像头帧大小（主摄像头使用 QCamera 不需要手动计算）
    // m_mainFrameSize = frameSizeFor(m_mainWidth, m_mainHeight);  // 不再需要
    m_subFrameSize = frameSizeFor(m_subWidth, m_subHeight);

    // 预分配副摄像头内存
    // m_mainBuffer.reserve(m_mainFrameSize * 2);  // 主摄像头已切换到 QCamera
    m_subBuffer.reserve(m_subFrameSize * 2);

    // 初始化异步拍照线程池（单线程，避免并发拍照）
    m_captureThreadPool = new QThreadPool(this);
    m_captureThreadPool->setMaxThreadCount(1);

    // 初始化外挂的 AI 服务模块
    m_aiService = new VisionAIService(this);

    // ==========================================
    // 🐕 摄像头看门狗初始化（防卡死自动恢复）
    // ==========================================
    m_watchdogTimer = new QTimer(this);
    m_watchdogTimer->setInterval(m_watchdogIntervalMs);
    connect(m_watchdogTimer, &QTimer::timeout, this, &CameraController::onWatchdogTimeout);

    // ==========================================
    // 🎥 主摄像头 (USB摄像头 - Qt Multimedia QCamera)
    // ==========================================
    // 遍历所有视频输入设备，找到 USB 摄像头
    const QList<QCameraDevice> cameras = QMediaDevices::videoInputs();
    QCameraDevice usbCamera;
    bool found = false;
    for (const auto &cam : cameras) {
        QString camId = QString::fromUtf8(cam.id());
        qDebug() << "[CameraController] 发现摄像头:" << camId << cam.description();
        if (camId.contains("USB", Qt::CaseInsensitive) ||
            cam.description().contains("UGREEN", Qt::CaseInsensitive) ||
            cam.description().contains("2K", Qt::CaseInsensitive) ||
            cam.description().contains("1080P", Qt::CaseInsensitive)) {
            usbCamera = cam;
            found = true;
            qInfo() << "[CameraController] 选择USB主摄像头:" << cam.description() << "ID:" << cam.id();
            break;
        }
    }
    if (!found && !cameras.isEmpty()) {
        usbCamera = cameras.first();
        found = true;
        qInfo() << "[CameraController] 未匹配到特定USB摄像头，使用默认设备:" << usbCamera.description();
    }

    if (found) {
        m_mainCamera = new QCamera(usbCamera, this);

        // === 摄像头健康监控信号连接 ===
        connect(m_mainCamera, &QCamera::errorOccurred,
                this, &CameraController::onCameraErrorOccurred);
        connect(m_mainCamera, &QCamera::statusChanged,
                this, &CameraController::onCameraStatusChanged);

        // 设置摄像头分辨率和帧率（目标 15fps）
        const int TARGET_FPS = 30;
        auto supportedFormats = usbCamera.videoFormats();

        qInfo() << "[CameraController] 主摄像头支持的所有格式:";
        for (const auto &fmt : supportedFormats) {
            qInfo() << "  " << fmt.resolution().width() << "x" << fmt.resolution().height()
                    << " @" << fmt.minFrameRate() << "-" << fmt.maxFrameRate() << "fps";
        }

        QCameraFormat targetFormat;
        bool formatFound = false;

        // 第一轮：精确匹配分辨率 + 帧率 ≤ 16fps（+1 容差）
        for (const auto &fmt : supportedFormats) {
            if (fmt.resolution().width() == m_mainWidth && fmt.resolution().height() == m_mainHeight) {
                if (fmt.maxFrameRate() <= TARGET_FPS + 1) {
                    targetFormat = fmt;
                    formatFound = true;
                    break;
                }
            }
        }

        // 第二轮：同分辨率取最低帧率的
        if (!formatFound) {
            QCameraFormat lowestFpsFormat;
            for (const auto &fmt : supportedFormats) {
                if (fmt.resolution().width() == m_mainWidth && fmt.resolution().height() == m_mainHeight) {
                    if (lowestFpsFormat.resolution().isEmpty() || fmt.maxFrameRate() < lowestFpsFormat.maxFrameRate()) {
                        lowestFpsFormat = fmt;
                    }
                }
            }
            if (!lowestFpsFormat.resolution().isEmpty()) {
                targetFormat = lowestFpsFormat;
                formatFound = true;
            }
        }
        if (formatFound) {
            m_mainCamera->setCameraFormat(targetFormat);
            qInfo() << "[CameraController] 主摄像头已设置为:"
                    << targetFormat.resolution().width() << "x" << targetFormat.resolution().height()
                    << " @" << targetFormat.maxFrameRate() << "fps";
        } else {
            // 未精确匹配时，选择最接近的较小分辨率
            QCameraFormat bestMatch;
            int bestDiff = INT_MAX;
            for (const auto &fmt : supportedFormats) {
                int diff = std::abs(fmt.resolution().width() * fmt.resolution().height()
                                   - m_mainWidth * m_mainHeight);
                if (diff < bestDiff && fmt.resolution().width() <= m_mainWidth) {
                    bestDiff = diff;
                    bestMatch = fmt;
                }
            }
            if (!bestMatch.resolution().isEmpty()) {
                m_mainCamera->setCameraFormat(bestMatch);
                qInfo() << "[CameraController] 主摄像头使用最接近分辨率:"
                        << bestMatch.resolution().width() << "x" << bestMatch.resolution().height();
            }
        }

        m_mainCaptureSession.setCamera(m_mainCamera);
        // setVideoOutput 会在 setMainVideoSink 中调用
        m_mainCamera->start();
        qInfo() << "[CameraController] QCamera 主摄像头已启动";

        // 启动看门狗（在 start 之后，确保摄像头进入 Active 状态后开始监控）
        m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
        m_watchdogTimer->start();
    } else {
        qWarning() << "[CameraController] 未找到任何视频输入设备！";
    }

    // ==========================================
    // 🎥 副摄像头进程配置（模块化设计）
    // 通过修改 CURRENT_SUB_CAMERA 宏来切换摄像头方案
    // ==========================================
    m_subProcess = new QProcess(this);
    connect(m_subProcess, &QProcess::readyReadStandardOutput, this, &CameraController::readSubCameraData);
    // 串联信号：副摄像头完成 → 触发主摄像头
    connect(this, &CameraController::subCaptureReady, this, &CameraController::onSubCaptureReady);
    
    QStringList subArgs;
    
    #if CURRENT_SUB_CAMERA == SUB_CAMERA_IMX708
    // IMX708 配置 (CSI摄像头0)
    subArgs = {
        "--camera", "0",  // 使用CSI摄像头0 (IMX708)
        "--tuning-file", tuningBaseDir + "imx708.json",
        "--width", QString::number(m_subWidth),
        "--height", QString::number(m_subHeight),
        "--framerate", "15",
        "--codec", "yuv420",
        "--nopreview",
        "--timeout", "0",
        "-o", "-"
    };
    qInfo() << "[CameraController] 副摄像头(IMX708)进程已启动，分辨率:" << m_subWidth << "x" << m_subHeight;
    
    #elif CURRENT_SUB_CAMERA == SUB_CAMERA_OV5647
    // OV5647 配置 (CSI摄像头1)
    subArgs = {
        "--camera", "1", 
        "--tuning-file", tuningBaseDir + "ov5647.json",
        "--width", QString::number(m_subWidth), 
        "--height", QString::number(m_subHeight), 
        "--framerate", "15", 
        "--codec", "yuv420", 
        "--nopreview", 
        "--timeout", "0", 
        "-o", "-"
    };
    qInfo() << "[CameraController] 副摄(OV5647)进程已启动...";
    
    #else
    #error "请为 CURRENT_SUB_CAMERA 宏选择有效的摄像头配置"
    #endif
    
    m_subProcess->start("rpicam-vid", subArgs);
}

CameraController::~CameraController() {
    // 停止主摄像头 (QCamera)
    if (m_mainCamera) {
        m_mainCamera->stop();
    }
    // 优雅且强制地回收副摄像头子进程
    if (m_subProcess && m_subProcess->state() == QProcess::Running) {
        m_subProcess->terminate();
        m_subProcess->waitForFinished(1000);
    }
}

void CameraController::setMainVideoSink(QVideoSink *sink) {
    m_mainSink = sink;
    // 将 QCamera 直接绑定到 QVideoSink，零拷贝原生渲染
    m_mainCaptureSession.setVideoOutput(sink);

    // === 连接帧心跳信号（监控预览是否存活） ===
    if (sink) {
        connect(sink, &QVideoSink::videoFrameChanged,
                this, &CameraController::onMainVideoFrameChanged, Qt::DirectConnection);
        qInfo() << "[CameraController] 主摄像头帧心跳已连接";
    }
}
void CameraController::setSubVideoSink(QVideoSink *sink) { m_subSink = sink; }

void CameraController::captureVegetable(double currentWeight) {
    m_lastWeight.store(currentWeight);
    // === 串行方案: 先触发副摄像头，完成后自动触发主摄像头 ===
    m_captureRequestedSub.store(true);
    qDebug() << "[CameraController] 串行抓拍: 第1步-请求副摄像头...";
}

// -----------------------------------------------------
// 槽函数：主摄像头截图 (从 QVideoSink 取当前帧)
// -----------------------------------------------------
void CameraController::handleMainCameraCapture()
{
    if (!m_captureRequestedMain.exchange(false)) return;
    if (!m_mainSink || !m_mainSink->videoFrame().isValid()) {
        qWarning() << "[CameraController] 主摄像头截图失败: sink为空或当前帧无效";
        return;
    }

    QVideoFrame frame = m_mainSink->videoFrame();
    // QVideoFrame → QImage
    QImage img = frame.toImage();
    if (img.isNull()) {
        qWarning() << "[CameraController] 主摄像头截图失败: frame.toImage() 返回空";
        return;
    }

    double weightAtCapture = m_lastWeight.load();
    auto *task = new CaptureTask(this, 0, img, weightAtCapture);
    m_captureThreadPool->start(task);
}

// -----------------------------------------------------
// 槽函数：副摄像头抓拍完成 → 触发主摄像头（串联）
// -----------------------------------------------------
void CameraController::onSubCaptureReady()
{
    qDebug() << "[CameraController] 串行抓拍: 第2步-副摄像头已完成，触发主摄像头...";
    m_captureRequestedMain.store(true);
    QMetaObject::invokeMethod(this, "handleMainCameraCapture", Qt::QueuedConnection);
}

// -----------------------------------------------------
// 槽函数：副摄像头管道数据泵 (IMX708)
// -----------------------------------------------------
void CameraController::readSubCameraData() {
    m_subBuffer.append(m_subProcess->readAllStandardOutput());
    
    while (m_subBuffer.size() >= m_subFrameSize) {
        const uint8_t *frameData = reinterpret_cast<const uint8_t*>(m_subBuffer.constData());
        pushFrameToQML(1, frameData, m_subWidth, m_subHeight, m_subWidth);
        
        m_subBuffer.remove(0, m_subFrameSize);
    }
}

// -----------------------------------------------------
// 核心逻辑：触发拦截抓拍，以及将裸 YUV 数据送入 GPU
// -----------------------------------------------------
void CameraController::pushFrameToQML(int cameraIndex, const uint8_t *data, int width, int height, int stride)
{
    std::atomic<bool>& captureFlag = (cameraIndex == 0) ? m_captureRequestedMain : m_captureRequestedSub;

    // AI 拦截抓图侦测点：拷贝帧数据，异步处理，不阻塞帧推送
    if (captureFlag.exchange(false)) {
        QByteArray frameCopy(reinterpret_cast<const char*>(data), frameSizeFor(width, height));
        double weightAtCapture = m_lastWeight.load();
        auto *task = new CaptureTask(this, cameraIndex, std::move(frameCopy), width, height, stride, weightAtCapture);
        m_captureThreadPool->start(task);
    }

    QVideoSink* targetSink = (cameraIndex == 0) ? m_mainSink.data() : m_subSink.data();
    // QPointer 在指向的 QObject 被销毁时自动置空，此处双重检查防止野指针
    if (!targetSink || targetSink != ((cameraIndex == 0) ? m_mainSink.data() : m_subSink.data())) return;

    QVideoFrameFormat format(QSize(width, height), QVideoFrameFormat::Format_YUV420P);
    QVideoFrame frame(format);

    if (frame.map(QVideoFrame::WriteOnly)) {
        int ySize = stride * height; 
        int uvStride = stride / 2;
        int uvHeight = height / 2;
        int uvSize   = uvStride * uvHeight; 

        // std::memcpy 在此处是针对裸流最高效的操作
        memcpy(frame.bits(0), data, ySize);                      // Y 分量
        memcpy(frame.bits(1), data + ySize, uvSize);             // U 分量
        memcpy(frame.bits(2), data + ySize + uvSize, uvSize);    // V 分量

        frame.unmap();
        frame.setStartTime(QDeadlineTimer::current().deadline() * 1000);
        targetSink->setVideoFrame(frame);
    }
}

// -----------------------------------------------------
// CPU 加速 YUV 转 RGB，然后委托共享处理
// -----------------------------------------------------
void CameraController::processAndSaveImage(int cameraIndex, QByteArray frameData, int width, int height, int stride)
{
    const uint8_t *data = reinterpret_cast<const uint8_t*>(frameData.constData());

    QImage watermarkedImg(width, height, QImage::Format_RGB32);

    int ySize = stride * height;
    const uint8_t *yData = data;
    const uint8_t *uData = data + ySize;
    const uint8_t *vData = uData + (ySize / 4);

    // 位运算优化的极速 YUV to RGB，避免浮点数开销
    for (int j = 0; j < height; ++j) {
        QRgb *scanline = (QRgb*)watermarkedImg.scanLine(j);
        const uint8_t *yRow = yData + j * stride;
        const uint8_t *uRow = uData + (j / 2) * (stride / 2);
        const uint8_t *vRow = vData + (j / 2) * (stride / 2);

        for (int i = 0; i < width; ++i) {
            int c = yRow[i] - 16;
            int d = uRow[i / 2] - 128;
            int e = vRow[i / 2] - 128;

            int r = std::clamp((298 * c           + 409 * e + 128) >> 8, 0, 255);
            int g = std::clamp((298 * c - 100 * d - 208 * e + 128) >> 8, 0, 255);
            int b = std::clamp((298 * c + 516 * d           + 128) >> 8, 0, 255);

            scanline[i] = qRgb(r, g, b);
        }
    }

    _processCommon(cameraIndex, watermarkedImg);
}

// -----------------------------------------------------
// QCamera 截图处理：空检查后委托共享处理
// -----------------------------------------------------
void CameraController::processAndSaveImage(int cameraIndex, QImage image)
{
    if (image.isNull()) {
        qWarning() << "[CameraController] QCamera截图: 收到空图像";
        return;
    }

    _processCommon(cameraIndex, image);
}

// -----------------------------------------------------
// 共享处理管线：裁剪 → 分发 → 时间戳 → AI推理 → 水印 → 保存
// -----------------------------------------------------
void CameraController::_processCommon(int cameraIndex, QImage &watermarkedImg)
{
    // ② 裁剪（按比例切到称台区域，分辨率变化时自动适配）
    // 称台位置: 水平偏左(45%), 垂直偏下(53%); 大小约占画面35%
    double cropRatio = 0.35;                    // 裁剪区占画面边长的比例
    int side = (int)(qMin(watermarkedImg.width(), watermarkedImg.height()) * cropRatio);
    int cropX = (int)(watermarkedImg.width() * 0.45) - (side / 2);
    int cropY = (int)(watermarkedImg.height() * 0.53) - (side / 2);

    // ③ 分发：主摄存 yt0.jpg，副摄存 yt1.jpg + 缓存员工照片 + 串联通知
    QString debugPrefix = (cameraIndex == 0) ? "yt0" : "yt1";
    watermarkedImg.save(QString("/home/sjwu/Pictures/%1.jpg").arg(debugPrefix), "JPG", 90);

    QImage pureImageForAI = watermarkedImg.copy(cropX, cropY, side, side);
    pureImageForAI.save("/home/sjwu/Pictures/cp0.jpg", "JPG", 90);

    if (cameraIndex != 0) {
        // 副摄像头图像 → 缓存为员工照片（线程安全）
        {
            QMutexLocker locker(&m_subImageMutex);
            m_lastSubCaptureImage = pureImageForAI;
            qDebug() << "[CameraController] 副摄像头图像已缓存，尺寸:" << pureImageForAI.size();
        }
        // === 串联：通知主摄像头可以开始 ===
        QMetaObject::invokeMethod(this, "onSubCaptureReady", Qt::QueuedConnection);
    }

    // ④ 时间戳 / 路径准备（仅主摄生成最终保存路径）
    QString timeStamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
    QString predictedLabel = "--";
    QString savePath = "";
    if (cameraIndex == 0) {
        QDir dir(QDir::homePath() + "/Pictures");
        if (!dir.exists()) dir.mkpath(".");
        savePath = dir.absolutePath() + QString("/WLC200A_V-XXXXXX_%1.jpg").arg(timeStamp);
    }

    // ⑤ 主摄 AI 推理 + 语音播报
    if (cameraIndex == 0 && m_aiService) {
        // 调用 AI 类的预测接口
        qint64 startTime = QDateTime::currentMSecsSinceEpoch();
        predictedLabel = m_aiService->predict(pureImageForAI);
        qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startTime;
        qInfo() << "[CameraController] 委托 AI 处理完毕，结果:" << predictedLabel << "耗时:" << elapsed << "ms";

        // ===== AI 推理完成，立即触发语音播报（不等图片保存）=====
        if (m_voiceSpeaker && predictedLabel != "--") {
            QString speakText;
            if (predictedLabel == "未知物品") {
                speakText = QStringLiteral("未识别物品");
            } else {
                QString chineseName = FoodTranslator::instance()->translate(predictedLabel);
                speakText = QString("识别到%1").arg(chineseName);
            }
            QMetaObject::invokeMethod(m_voiceSpeaker, "speak", Qt::QueuedConnection,
                Q_ARG(QString, speakText));
            qDebug() << "[CameraController] 已提交语音播报:" << speakText;
        }
        // ============================================================

        Q_EMIT aiRecognitionCompleted(predictedLabel, savePath, elapsed);
    }

    // ⑥ 水印绘制（主摄时取副摄缓存作为员工照片）
    QPainter painter(&watermarkedImg);
    QImage empPhoto;
    if (cameraIndex == 0) {
        QMutexLocker locker(&m_subImageMutex);
        empPhoto = m_lastSubCaptureImage;
    }
    drawWatermarkOverlay(painter, watermarkedImg.width(), watermarkedImg.height(), predictedLabel, empPhoto);

    // ⑦ 保存图片（仅主摄保存最终图片 + ai_target.jpg）
    if (cameraIndex == 0 && !savePath.isEmpty()) {
        pureImageForAI.save("/home/sjwu/Pictures/ai_target.jpg", "JPG", 90);
        if (watermarkedImg.save(savePath, "JPG", 90)) {
            qDebug() << "[CameraController] 主摄画面保存完毕:" << savePath;
            Q_EMIT photoSaved(cameraIndex, savePath);
        } else {
            qWarning() << "[CameraController] 图片保存失败!";
        }
    }
}

// ============================================================
//  小管事风格水印绘制
//  布局：顶部标题栏 | 右侧员工区(副摄像照片) | 左下公章 | 右下信息
// ============================================================
void CameraController::drawWatermarkOverlay(QPainter &painter, int imgW, int imgH,
                                            const QString &predictedLabel,
                                            const QImage &employeePhoto)
{
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::TextAntialiasing);

    // 获取当前登录用户名，未登录则用占位符
    QString operatorName = (m_authService && !m_authService->currentUser().isEmpty())
                           ? m_authService->currentUser()
                           : QStringLiteral("操作员");

    double weightKg = m_lastWeight.load();
    QString chineseName = (predictedLabel == "未知物品" || predictedLabel == "--")
                          ? predictedLabel
                          : FoodTranslator::instance()->translate(predictedLabel);
    QDateTime now = QDateTime::currentDateTime();

    // ---- 布局常量（按 1280x720 基准等比缩放）----
    double scaleX = imgW / 1280.0;
    double scaleY = imgH / 720.0;

    auto sx = [&](int v) { return int(v * scaleX); };
    auto sy = [&](int v) { return int(v * scaleY); };
    auto sFontSize = [&](int size) { return int(size * qMin(scaleX, scaleY)); };

    QFont fontTitle("Microsoft YaHei", sFontSize(14), QFont::Bold);
    QFont fontInfo("Microsoft YaHei", sFontSize(15), QFont::Bold);
    QFont fontInfoLabel("Microsoft YaHei", sFontSize(14), QFont::Bold);
    QFont fontStamp("SimHei", sFontSize(9), QFont::Bold);   // 公章文字
    QFont fontSite("Microsoft YaHei", sFontSize(18), QFont::Bold);  // 现场照片

    // =============================================
    // 1) 顶部白色标题栏（全宽）
    // ============================================= {
        QRect topBar(0, 0, imgW, sy(36));
        painter.fillRect(topBar, QColor(245, 245, 245, 240));

        // 左侧：标题文字
        painter.setPen(QColor(30, 30, 30));
        painter.setFont(fontTitle);
        painter.drawText(sx(15), 0, sx(450), sy(36),
                         Qt::AlignVCenter, QStringLiteral("小管事AI智能网络秤水印生成图片"));

        // 右侧：文件名 WLC200A_序列号_日期时间.jpg（强制深色粗体确保可见）
        QFont fontFileName("Microsoft YaHei", sFontSize(14), QFont::Bold);
        painter.setPen(QColor(30, 30, 30));
        painter.setFont(fontFileName);
        QString fileName = QString("WLC200A_1026040405050001_%1_%2.jpg")
                               .arg(now.toString("yyyyMMdd"))
                               .arg(now.toString("HHmmss"));
        int fnRight = imgW - sx(10);
        int fnWidth = painter.fontMetrics().horizontalAdvance(fileName) + sx(10);
        painter.drawText(fnRight - fnWidth, 0, fnWidth, sy(36),
                         Qt::AlignCenter, fileName);

    // =============================================
    // 2) 右上角：员工照片区域（副摄像头图像）+ 账户名
    // =============================================
    {
        int photoW = sx(250);
        int photoH = sy(400);
        int photoX = imgW - photoW - sx(50);
        int photoY = sy(70);

        // 白色背景框 + 阴影（加高以完整包裹账户名标签）
        QRect photoBg(photoX - sx(4), photoY - sy(4), photoW + sx(8), photoH + sy(48));
        painter.setBrush(QColor(255, 255, 255, 230));
        painter.setPen(Qt::NoPen);
        painter.drawRoundedRect(photoBg, sx(8), sy(8));

        QRect photoRect(photoX, photoY, photoW, photoH);

        if (!employeePhoto.isNull()) {
            // 有副摄像头图像 → 缩放绘制到照片区域（保持比例居中裁切）
            QImage scaled = employeePhoto.scaled(photoW, photoH,
                                                  Qt::KeepAspectRatioByExpanding,
                                                  Qt::SmoothTransformation);
            int offsetX = (scaled.width() - photoW) / 2;
            int offsetY = (scaled.height() - photoH) / 2;
            painter.drawImage(photoRect, scaled,
                              QRect(offsetX, offsetY, photoW, photoH));
        } else {
            // 无图像时显示占位提示
            painter.fillRect(photoRect, QColor(220, 220, 220));
            painter.setPen(QColor(150, 150, 150));
            painter.setFont(QFont("Microsoft YaHei", sFontSize(11)));
            painter.drawText(photoRect, Qt::AlignCenter, QStringLiteral("副摄像头\n(待抓拍)"));
        }

        // 边框
        painter.setPen(QPen(QColor(180, 180, 180), 1));
        painter.setBrush(Qt::NoBrush);
        painter.drawRect(photoRect);

        // 账户名标签（加宽上下边距 + 更宽的标签区域）
        QRect accountLabel(photoX - sx(10), photoY + photoH + sy(8), photoW + sx(20), sy(36));
        painter.setPen(QColor(40, 40, 40));
        painter.setFont(fontInfoLabel);
        painter.drawText(accountLabel, Qt::AlignCenter,
                         QStringLiteral("员工账户：%1").arg(operatorName));
    }

    // =============================================
    // 3) 左下角：用 history_icon.png 替代公章 + "现场照片"文字
    // =============================================
    {
        QString iconPath = QCoreApplication::applicationDirPath() + "/resources/img/shuiyin.png";
        QImage sealIcon(iconPath);

        if (!sealIcon.isNull()) {
            int iconW = sx(320);
            int iconH = sy(210);
            int iconX = sx(0);
            int iconY = imgH - iconH - sy(25);
            QImage scaled = sealIcon.scaled(iconW, iconH,
                                           Qt::KeepAspectRatio,
                                           Qt::SmoothTransformation);
            int ix = iconX + (iconW - scaled.width()) / 2;
            int iy = iconY + (iconH - scaled.height()) / 2;
            painter.drawImage(ix, iy, scaled);
        }
    }

    // =============================================
    // 4) 右下角：结构化信息列表
    // =============================================
    {
        int infoX = imgW - sx(260);
        int infoStartY = imgH - sy(190);
        int lineHeight = sy(36);

        QStringList labels = {
            QStringLiteral("日期："),
            QStringLiteral("时间："),
            QStringLiteral("食材："),
            QStringLiteral("重量："),
            QStringLiteral("操作员："),
        };
        QStringList values = {
            now.toString("yyyyMMdd"),
            now.toString("HH:mm:ss"),
            chineseName,
            QString("%1KG").arg(int(weightKg)),
            operatorName,
        };

        painter.setFont(fontInfoLabel);
        int maxLabelWidth = 0;
        for (const auto &lbl : labels) {
            int w = painter.fontMetrics().horizontalAdvance(lbl);
            if (w > maxLabelWidth) maxLabelWidth = w;
        }

        for (int i = 0; i < labels.size(); ++i) {
            int y = infoStartY + i * lineHeight;

            // 标签（右对齐）
            painter.setPen(Qt::white);
            painter.setFont(fontInfoLabel);
            QRect lblRect(infoX, y, maxLabelWidth, lineHeight);
            painter.drawText(lblRect, Qt::AlignVCenter | Qt::AlignRight, labels[i]);

            // 值（左对齐，基线对齐）
            painter.setPen(Qt::white);
            painter.setFont(fontInfo);
            int valX = infoX + maxLabelWidth + sx(8);
            int valTextH = painter.fontMetrics().height();
            int valTextY = y + (lineHeight - valTextH) / 2 + painter.fontMetrics().ascent();
            painter.drawText(valX, valTextY, values[i]);
            painter.setFont(fontInfoLabel); // 恢复
        }
    }
}

// ============================================================
// 🐕 摄像头健康监控系统 — 防卡死自动恢复
// ============================================================

void CameraController::onCameraStatusChanged(QCamera::Status status)
{
    QString statusStr;
    switch (status) {
    case QCamera::UnloadedStatus:   statusStr = QStringLiteral("Unloaded(未加载)"); break;
    case QCamera::UnloadingStatus:  statusStr = QStringLiteral("Unloading(卸载中)"); break;
    case QCamera::LoadingStatus:    statusStr = QStringLiteral("Loading(加载中)"); break;
    case QCamera::LoadedStatus:     statusStr = QStringLiteral("Loaded(已就绪)"); break;
    case QCamera::StandbyStatus:    statusStr = QStringLiteral("Standby(待机)"); break;
    case QCamera::ActiveStatus:     statusStr = QStringLiteral("Active(活跃)"); break;
    default:                       statusStr = QStringLiteral("Unknown(%1)").arg((int)status); break;
    }

    qInfo() << "[CameraController] 主摄像头状态变更:" << statusStr;

    // 进入 Active 状态时重置心跳
    if (status == QCamera::ActiveStatus) {
        m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
        if (!m_watchdogTimer->isActive()) {
            m_watchdogTimer->start();
        }
    }

    Q_EMIT cameraStatusChanged(statusStr);
}

void CameraController::onCameraErrorOccurred(QCamera::Error error, const QString &errorString)
{
    qWarning() << "[CameraController] ⚠️ 主摄像头错误!"
               << "错误代码:" << error << "详情:" << errorString;

    Q_EMIT cameraStatusChanged(QStringLiteral("Error: %1").arg(errorString));

    // 尝试自动恢复
    if (!m_isRestarting && m_restartCount < MAX_AUTO_RESTART) {
        qWarning() << "[CameraController] 触发错误恢复重启...";
        restartMainCamera();
    } else if (m_restartCount >= MAX_AUTO_RESTART) {
        qCritical() << "[CameraController] 🔴 已达最大重启次数(" << MAX_AUTO_RESTART
                    << ")，停止自动恢复，需人工检查硬件";
    }
}

void CameraController::onMainVideoFrameChanged()
{
    // 每收到一帧就更新时间戳（DirectConnection 保证实时）
    m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
}

void CameraController::onWatchdogTimeout()
{
    // 如果正在重启中或摄像头未创建，跳过检测
    if (m_isRestarting || !m_mainCamera) return;

    qint64 now = QDateTime::currentMSecsSinceEpoch();
    qint64 elapsed = now - m_lastFrameTimeMs;

    // 判定卡死：超过 watchdogInterval 秒没收到帧
    // 给 1 个 interval 的容差（即 2 倍时间才判定真正卡死）
    if (elapsed > m_watchdogIntervalMs * 2) {
        qWarning() << "[CameraController] 🐕 看门狗触发! 已" << elapsed / 1000.0
                   << "秒未收到视频帧，预览可能卡死";

        // 检查当前摄像头状态辅助判断
        auto currentStatus = m_mainCamera ? m_mainCamera->status() : QCamera::UnloadedStatus;
        qWarning() << "[CameraController] 当前QCamera状态:" << (int)currentStatus;

        if (m_restartCount < MAX_AUTO_RESTART) {
            restartMainCamera();
        } else {
            qCritical() << "[CameraController] 🔴 已达最大重启次数(" << MAX_AUTO_RESTART
                        << ")，停止自动恢复";
            m_watchdogTimer->stop();  // 停止看门狗避免刷日志
        }
    }
    // 正常情况：只打 trace 日志（每 30 秒一次，避免刷屏）
    else if ((int)(elapsed / 1000) % 30 == 0 && elapsed > 1000) {
        qDebug() << "[CameraController] 🐕 心跳正常，距上次帧:" << elapsed / 1000.0 << "秒前";
    }
}

// ============================================================
// 🔁 摄像头自动重启核心逻辑
// ============================================================

void CameraController::restartMainCamera()
{
    if (m_isRestarting) {
        qDebug() << "[CameraController] 重已在进行中，跳过重复调用";
        return;
    }
    m_isRestarting = true;
    m_restartCount++;

    qWarning() << "[CameraController] 🔁 开始第" << m_restartCount << "次自动重启摄像头...";

    // 1. 停止看门狗（防止重启过程中误触）
    m_watchdogTimer->stop();

    // 2. 停止旧摄像头
    if (m_mainCamera) {
        m_mainCamera->stop();
        // 断开旧信号连接（避免旧对象残留信号干扰）
        m_mainCamera->disconnect(this);
    }

    // 3. 延迟后重新启动（给 USB 总线释放资源的时间）
    QTimer::singleShot(800, this, [this]() {
        if (m_mainCamera) {
            // 重新连接监控信号
            connect(m_mainCamera, &QCamera::errorOccurred,
                    this, &CameraController::onCameraErrorOccurred);
            connect(m_mainCamera, &QCamera::statusChanged,
                    this, &CameraController::onCameraStatusChanged);

            m_mainCamera->start();

            // 重置心跳时间戳
            m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
            // 重启看门狗
            m_watchdogTimer->start();

            qInfo() << "[CameraController] ✅ 摄像头重启完成，看门狗已恢复";
        }

        Q_EMIT cameraStatusChanged(QStringLiteral("Restarted(第%1次重启)").arg(m_restartCount));
        m_isRestarting = false;
    });
}

