#include "CameraController.h"
#include "hardware/WeightSensor.h"
#include "utils/FoodTranslator.h"
#include "core/PState.h"
#include <QVideoFrameFormat>
#include <QPainter>
#include <QDateTime>
#include <QDir>
#include <QDebug>
#include <QDeadlineTimer>
#include <QMetaObject>
#include <QCoreApplication>
#include <algorithm>
#include <QHttpMultiPart>
#include <QBuffer>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QJsonObject>
#include <QCryptographicHash>
#include <QPainterPath>
#include "core/NetworkUtils.h"

// 副摄像头配置 (IMX519 CSI)
#define SUB_TUNING_FILE "/usr/share/libcamera/ipa/rpi/pisp/imx519.json"
// ============================================================
//  公共工具方法
// ============================================================

QCameraDevice CameraController::findUsbCamera()
{
    const QList<QCameraDevice> cameras = QMediaDevices::videoInputs();
    if (!cameras.isEmpty()) {
        qDebug() << "[Camera] 主摄像头:" << cameras.first().description();
        return cameras.first();
    }
    return {};
}

void CameraController::setupCameraFormat(QCameraDevice &device)
{
    static constexpr int TARGET_FPS = 30;
    auto formats = device.videoFormats();

    // 策略1: 精确匹配分辨率 + 低帧率
    QCameraFormat best;
    for (const auto &f : formats) {
        if (f.resolution().width() == m_mainWidth && f.resolution().height() == m_mainHeight) {
            if (f.maxFrameRate() <= TARGET_FPS + 1) { best = f; break; }
            if (best.isNull() || f.maxFrameRate() < best.maxFrameRate()) best = f;
        }
    }

    // 策略2: 取最接近的小分辨率
    if (best.isNull()) {
        int bestDiff = INT_MAX;
        for (const auto &f : formats) {
            int diff = std::abs(f.resolution().width() * f.resolution().height()
                                - m_mainWidth * m_mainHeight);
            if (diff < bestDiff && f.resolution().width() <= m_mainWidth) {
                bestDiff = diff;
                best = f;
            }
        }
    }

    if (!best.isNull()) {
        m_mainCamera->setCameraFormat(best);
        qDebug() << "[Camera] 分辨率:" << best.resolution().width() << "x" << best.resolution().height()
                 << " @" << best.maxFrameRate() << "fps";
    }
}

// ============================================================
//  构造/析构
// ============================================================

CameraController::CameraController(QObject *parent)
    : QObject(parent),
      m_lastWeight(0.0), m_captureRequestedMain(false), m_captureRequestedSub(false)
{
    m_subFrameSize = frameSizeFor(m_subWidth, m_subHeight);
    m_subBuffer.reserve(m_subFrameSize * 2);

    m_captureThreadPool = new QThreadPool(this);
    m_captureThreadPool->setMaxThreadCount(1);
    //暂不启用本地AI模型
    //m_aiService = new VisionAIService(this);  
    m_networkMgr = new QNetworkAccessManager(this);
    connect(m_networkMgr, &QNetworkAccessManager::finished,
        this, &CameraController::onNetworkReply);

    // === 看门狗 ===
    m_watchdogTimer = new QTimer(this);
    m_watchdogTimer->setInterval(m_watchdogIntervalMs);
    connect(m_watchdogTimer, &QTimer::timeout, this, &CameraController::onWatchdogTimeout);

    // === 主摄像头 (USB QCamera) ===
    auto usbCam = findUsbCamera();
    if (!usbCam.isNull()) {
        m_mainCamera = new QCamera(usbCam, this);
        connect(m_mainCamera, SIGNAL(errorOccurred(int, const QString &)),
                this, SLOT(onCameraErrorOccurred(int, const QString &)));
        connect(m_mainCamera, SIGNAL(statusChanged(QCamera::Status)),
                this, SLOT(onCameraStatusChanged(int)));
        setupCameraFormat(usbCam);
        m_mainCaptureSession.setCamera(m_mainCamera);
        m_mainCamera->start();
        m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
        m_watchdogTimer->start();
    } else {
        qWarning() << "[Camera] 未找到任何摄像头设备!";
    }

    // === 副摄像头 (rpicam-vid IMX708) ===
    m_subProcess = new QProcess(this);
    connect(m_subProcess, &QProcess::readyReadStandardOutput, this, &CameraController::readSubCameraData);
    connect(this, &CameraController::subCaptureReady, this, &CameraController::onSubCaptureReady);

    QStringList subArgs = {"--camera", "0", "--tuning-file", SUB_TUNING_FILE,
                           "--width", QString::number(m_subWidth),
                           "--height", QString::number(m_subHeight),
                           "--mode", "2328:1748",
                          // "--roi", m_subRoi,
                           "--framerate", "15", "--codec", "yuv420",
                           "--autofocus-mode", "auto",
                           "--nopreview", "--timeout", "0", "-o", "-"};
    m_subProcess->start("rpicam-vid", subArgs);
}

void CameraController::setAuthService(AuthService *authSvc) {
    m_authService = authSvc;
    // 接入统一 Token 刷新协调器
    if (m_authService) {
        QObject::connect(m_authService, &AuthService::tokenRefreshCompleted,
                         this, &CameraController::onTokenRefreshCompleted,
                         Qt::UniqueConnection);
    }
}

CameraController::~CameraController() {
    m_watchdogTimer->stop();
    if (m_mainCamera) m_mainCamera->stop();
    if (m_subProcess && m_subProcess->state() == QProcess::Running) {
        m_subProcess->terminate();
        m_subProcess->waitForFinished(1000);
    }
    if (m_captureThreadPool) {
        m_captureThreadPool->clear();
        m_captureThreadPool->waitForDone(3000);
    }
}

void CameraController::setMainVideoSink(QVideoSink *sink) {
    m_mainSink = sink;
    m_mainCaptureSession.setVideoOutput(sink);
    if (sink) {
        connect(sink, &QVideoSink::videoFrameChanged,
                this, &CameraController::onMainVideoFrameChanged, Qt::DirectConnection);
    }
}

void CameraController::setSubVideoSink(QVideoSink *sink) { m_subSink = sink; }

void CameraController::captureVegetable(double currentWeight, const QString &watermarkLabel) {
    if (m_isRestarting) {
        qWarning() << "[Camera] 摄像头重启中，跳过本次拍照";
        return;
    }
    m_lastWeight.store(currentWeight);
    {
        QMutexLocker locker(&m_captureMetaMutex);
        m_watermarkLabel = watermarkLabel;
    }
    m_captureRequestedSub.store(true);
    qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ②captureVegetable 设副摄抓拍标志";
}

// -----------------------------------------------------
// 槽函数：主摄像头截图 (从 QVideoSink 取当前帧)
// -----------------------------------------------------
void CameraController::handleMainCameraCapture()
{
    if (!m_captureRequestedMain.exchange(false)) return;
    if (m_isRestarting) {
        qWarning() << "[Camera] 摄像头重启中，跳过主摄截图";
        return;
    }
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
    qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ④onSubCaptureReady 触发主摄截图";
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
    qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ③副摄任务开始(YUV→RGB+保存)";
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
    qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ④b主摄任务开始(水印+保存)";
    if (image.isNull()) {
        qWarning() << "[CameraController] QCamera截图: 收到空图像";
        return;
    }

    _processCommon(cameraIndex, image);
}

// -----------------------------------------------------
// 共享处理管线：裁剪 → 分发 → 时间戳 → 水印 → 保存
// -----------------------------------------------------
void CameraController::_processCommon(int cameraIndex, QImage &watermarkedImg)
{
    // 2 裁剪：主摄切称台区域 / 副摄居中切人脸区域
    QRect cropRect;
    if (cameraIndex != 0) {
        // 副摄像头（人脸）：居中大方形，占短边80%
        int side = (int)(qMin(watermarkedImg.width(), watermarkedImg.height()) * 0.80);
        cropRect = QRect((watermarkedImg.width() - side) / 2,
                          (watermarkedImg.height() - side) / 2,
                          side, side);
    } else {
        // 主摄像头（称台）：水平居中50%、垂直偏下53%，约占50%
        double cropRatio = 0.50;
        int side = (int)(qMin(watermarkedImg.width(), watermarkedImg.height()) * cropRatio);
        int cropX = (int)(watermarkedImg.width() * 0.5) - (side / 2);
        int cropY = (int)(watermarkedImg.height() * 0.53) - (side / 2);
        cropRect = QRect(cropX, cropY, side, side);
    }

    // 3 裁剪供 AI 识别（yt0/yt1 调试图已移除以节省 JPG 编码耗时）
    QImage pureImageForAI = watermarkedImg.copy(cropRect);
    pureImageForAI.save("/home/sjwu/Pictures/cp0.jpg", "JPG", 90);

    if (cameraIndex != 0) {
        // 副摄像头图像 → 缓存为员工照片（线程安全）
        {
            QMutexLocker locker(&m_subImageMutex);
            m_lastSubCaptureImage = pureImageForAI;
            qDebug() << "[CameraController] 副摄像头图像已缓存，尺寸:" << pureImageForAI.size();
        }
        // === 串联：通知主摄像头可以开始 ===
        qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ③b副摄处理完成→触发主摄";
        QMetaObject::invokeMethod(this, "onSubCaptureReady", Qt::QueuedConnection);
    }

    // 4时间戳 / 路径准备（仅主摄生成最终保存路径）
    QString timeStamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");
    QString savePath = "";
    if (cameraIndex == 0) {
        QDir dir(QDir::homePath() + "/Pictures");
        if (!dir.exists()) dir.mkpath(".");
        QString deviceSn = m_weightSensor ? m_weightSensor->sn() : QStringLiteral("V-XXXXXX");
        if (deviceSn.isEmpty()) deviceSn = QStringLiteral("V-XXXXXX");
        savePath = dir.absolutePath() + QString("/WLC200A_%1_%2.jpg").arg(deviceSn).arg(timeStamp);
    }

    // 5 主摄：绘制水印并落盘（aiOnlyMode 时跳过——仅拍照给AI用）
    if (cameraIndex == 0 && !savePath.isEmpty()) {
        // AI-only 模式：不画水印、不落盘，仅裁剪图供识别（避免产生无用图片）
        bool isAiOnly = false;
        {
            QMutexLocker locker(&m_captureMetaMutex);
            isAiOnly = m_aiOnlyMode;
        }
        if (isAiOnly) {
            qDebug() << "[CameraController] AI-only 模式，跳过水印保存";
            // 仍然通知 QML 照片已"就绪"（路径用 cp0.jpg），但不落水印盘
            QMetaObject::invokeMethod(this, [this]() {
                Q_EMIT photoSaved(0, QStringLiteral("/home/sjwu/Pictures/cp0.jpg"));
            }, Qt::QueuedConnection);
            return;  // 跳过后续所有水印逻辑
        }
        // 读取线程安全的水印标签，空标签默认为 "--"
        QString label;
        {
            QMutexLocker locker(&m_captureMetaMutex);
            label = m_watermarkLabel.isEmpty() ? QStringLiteral("--") : m_watermarkLabel;
            m_lastSavePath = savePath;
        }

        // 获取员工照片副本
        QImage empPhotoCopy;
        {
            QMutexLocker locker(&m_subImageMutex);
            empPhotoCopy = m_lastSubCaptureImage;
        }

        // 立即绘制水印 + 保存（工作线程直接操作，无跨线程问题）
        QPainter painter(&watermarkedImg);
        drawWatermarkOverlay(painter, watermarkedImg.width(),
                             watermarkedImg.height(), label, empPhotoCopy);
        painter.end();

        if (watermarkedImg.save(savePath, "JPG", 90)) {
            qInfo().noquote() << "[SAVE-TIMER]" << QDateTime::currentDateTime().toString("HH:mm:ss.zzz") << "| ⑤主摄处理完成→emit photoSaved" << savePath;
            // 跨线程发射信号
            QMetaObject::invokeMethod(this, [this, savePath]() {
                Q_EMIT photoSaved(0, savePath);
            }, Qt::QueuedConnection);
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

    // === 计算原图(未加水印)的 SHA256 存证哈希 ===
    // 必须在绘制任何水印之前算，否则哈希会自我引用无法验证
    QString hashDisplay;
    {
        QImage *imgPtr = dynamic_cast<QImage*>(painter.device());
        if (imgPtr) {
            QByteArray jpgBytes;
            QBuffer buf(&jpgBytes);
            buf.open(QIODevice::WriteOnly);
            imgPtr->save(&buf, "JPG", 90);
            buf.close();
            QString hashFull = QCryptographicHash::hash(jpgBytes, QCryptographicHash::Sha256)
                                   .toHex().toLower();
            qDebug() << "[Watermark] 存证哈希(SHA256):" << hashFull;
            // 完整 64 位哈希，卡片分三行显示
            hashDisplay = hashFull;
        }
    }

    // 获取当前登录用户名，未登录则用占位符
    QString operatorName = (m_authService && !m_authService->currentUser().isEmpty())
                           ? m_authService->currentUser()
                           : QStringLiteral("操作员");

    double weightKg = m_lastWeight.load();
    QString chineseName = (predictedLabel == PState::UNKNOWN || predictedLabel == PState::NONE)
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
        QString deviceSn = m_weightSensor ? m_weightSensor->sn() : QStringLiteral("UNKNOWN");
        QString fileName = QString("WLC200A_%1_%2_%3.jpg")
                               .arg(deviceSn)
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
    // 3) 左下角：盾牌锁 + 密钥存证卡片（浅蓝渐变底板）
    // 色号：主文字#1D3FA8 哈希#263FB0 标签#2448B4 边框#4D86E8(3px)
    //       内边框#AFCBFF(1px) 虚线#8CB2F6(2px) 渐变背景#D8E3F3→#F4F8FF
    //       盾牌描边#4E8BF0 锁头#243BA7
    // =============================================
    {
        // 卡片整体尺寸（按 1280x720 基准等比缩放）
        int cardW = sx(240);
        int cardH = sy(162);  // 收紧高度，减少底部空白
        int cardX = sx(15);
        int cardY = imgH - cardH - sy(20);

        QRect cardRect(cardX, cardY, cardW, cardH);
        int r = sx(14); // 圆角半径

        // 浅蓝渐变底板（上浅→下深）
        QLinearGradient grad(cardX, cardY, cardX, cardY + cardH);
        grad.setColorAt(0.0, QColor("#F4F8FF"));
        grad.setColorAt(1.0, QColor("#D8E3F3"));
        painter.setBrush(grad);
        painter.setPen(Qt::NoPen);
        painter.drawRoundedRect(cardRect, r, r);

        // 蓝色内边框（缩进 3px，2px 蓝色描边）
        QRect innerRect(cardRect.x() + sx(3), cardRect.y() + sy(3),
                        cardRect.width() - sx(6), cardRect.height() - sy(6));
        painter.setBrush(Qt::NoBrush);
        painter.setPen(QPen(QColor("#4D86E8"), sx(2)));
        painter.drawRoundedRect(innerRect, qMax(r - sx(3), 0), qMax(r - sy(3), 0));

        // 白色外边框（3px 白色描边画在最外层）
        painter.setBrush(Qt::NoBrush);
        painter.setPen(QPen(QColor("#FFFFFF"), sx(3)));
        painter.drawRoundedRect(cardRect, r, r);

        // ---- 左侧：盾牌锁图标 + 紧贴右侧的标题文字（同侧布局）----
        QString lockIconPath = QCoreApplication::applicationDirPath() + "/resources/img/lock.png";
        QImage lockIcon(lockIconPath);
        int iconActualW = 0;
        int contentLeft = cardX + sx(14);  // 图标和文字统一左边界
        if (!lockIcon.isNull()) {
            int iconW = sy(46);
            int iconH = sy(50);
            QImage scaled = lockIcon.scaled(iconW, iconH,
                                           Qt::KeepAspectRatio,
                                           Qt::SmoothTransformation);
            iconActualW = scaled.width();
            painter.drawImage(contentLeft, cardY + sy(10), scaled);
        }

        // 标题紧跟在图标右边
        int titleX = contentLeft + (iconActualW > 0 ? iconActualW + sx(6) : 0);
        int txtW = cardW - (titleX - cardX) - sx(14);

        painter.setPen(QColor("#1D3FA8"));
        QFont fontTitle("SimHei", sFontSize(17), QFont::Bold);
        painter.setFont(fontTitle);
        int titleLineH = sy(24);
        painter.drawText(titleX, cardY + sy(10), txtW, titleLineH,
                         Qt::AlignLeft | Qt::AlignVCenter,
                         QStringLiteral("本图像已通过"));
        painter.drawText(titleX, cardY + sy(34), txtW, titleLineH,
                         Qt::AlignLeft | Qt::AlignVCenter,
                         QStringLiteral("密钥存证"));

        // 虚线分隔线
        int dashY = cardY + sy(62);
        QPen dashPen(QColor("#8CB2F6"), sx(2), Qt::DashLine);
        dashPen.setDashOffset(0);
        painter.setPen(dashPen);
        painter.drawLine(contentLeft, dashY, contentLeft + txtW + sx(44), dashY);

        // "存证哈希:" 标签
        QFont fontLabel("SimHei", sFontSize(15));
        painter.setPen(QColor("#2448B4"));
        painter.setFont(fontLabel);
        int labelY = dashY + sy(5);
        painter.drawText(contentLeft, labelY, txtW, sy(20),
                         Qt::AlignLeft | Qt::AlignTop,
                         QStringLiteral("存证哈希:"));

        // 完整哈希值（标签下方留足间距避免重叠）
        QFont fontHash("SimHei", sFontSize(12), QFont::Bold);
        painter.setFont(fontHash);
        painter.setPen(QColor("#263FB0"));
        int hashLineH = sy(20);
        int hashStartY = labelY + sy(25);
        // 用矩形区域 + TextWrapAnywhere 自动换行，避免硬编码 mid() 切片
        QRectF hashRect(contentLeft, hashStartY, txtW+sy(42), hashLineH * 3);
        painter.drawText(hashRect,
                         Qt::AlignLeft | Qt::AlignTop | Qt::TextWrapAnywhere,
                         hashDisplay);
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
            QString("%1 KG").arg(weightKg, 0, 'f', 2),
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
//  摄像头健康监控系统 — 防卡死自动恢复
//
// 注意：此处避免直接引用 QCamera::Status 嵌套枚举，
// 因为 Qt6 Multimedia 模块化头文件可能导致编译器看不到完整定义。
// 使用与 Qt6 QCamera::Status 枚举值对应的 int 常量代替。
// ============================================================

namespace CamStatus {
    // 与 Qt6 QCamera::Status 枚举值一一对应 (qcamera.h)
    constexpr int UnloadedStatus  = 0;
    constexpr int UnloadingStatus = 1;
    constexpr int LoadingStatus   = 2;
    constexpr int LoadedStatus    = 3;
    constexpr int StandbyStatus   = 4;
    constexpr int ActiveStatus    = 5;
}

void CameraController::onCameraStatusChanged(int status)
{
    QString statusStr;
    switch (status) {
    case CamStatus::UnloadedStatus:  statusStr = QStringLiteral("Unloaded(未加载)"); break;
    case CamStatus::UnloadingStatus: statusStr = QStringLiteral("Unloading(卸载中)"); break;
    case CamStatus::LoadingStatus:   statusStr = QStringLiteral("Loading(加载中)"); break;
    case CamStatus::LoadedStatus:    statusStr = QStringLiteral("Loaded(已就绪)"); break;
    case CamStatus::StandbyStatus:   statusStr = QStringLiteral("Standby(待机)"); break;
    case CamStatus::ActiveStatus:    statusStr = QStringLiteral("Active(活跃)"); break;
    default:                        statusStr = QStringLiteral("Unknown(%1)").arg(status); break;
    }

    qInfo() << "[CameraController] 主摄像头状态变更:" << statusStr;

    // 进入 Active 状态时重置心跳
    if (status == CamStatus::ActiveStatus) {
        m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
        if (!m_watchdogTimer->isActive()) {
            m_watchdogTimer->start();
        }
    }

    Q_EMIT cameraStatusChanged(statusStr);
}

void CameraController::onCameraErrorOccurred(int error, const QString &errorString)
{
    qWarning() << "[CameraController]  主摄像头错误!"
               << "错误代码:" << error << "详情:" << errorString;

    Q_EMIT cameraStatusChanged(QStringLiteral("Error: %1").arg(errorString));

    // 尝试自动恢复（restartMainCamera 内部会循环重试，永不放弃）
    if (!m_isRestarting) {
        qWarning() << "[CameraController] 触发错误恢复重启...";
        restartMainCamera();
    }
}

void CameraController::onMainVideoFrameChanged()
{
    m_lastFrameTimeMs = QDateTime::currentMSecsSinceEpoch();
}

void CameraController::onWatchdogTimeout()
{
    if (m_isRestarting || !m_mainCamera) return;

    qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - m_lastFrameTimeMs;
    if (elapsed > m_watchdogIntervalMs * 2) {
        qWarning() << "[Camera] 看门狗触发:" << elapsed / 1000.0 << "s无帧, 重启#" << (m_restartCount + 1);
        restartMainCamera();
    }
}

// ============================================================
//  摄像头自动重启核心逻辑
// ============================================================

void CameraController::restartMainCamera()
{
    if (m_isRestarting) return;
    m_isRestarting = true;

    // 超过最大次数后重置计数器，允许持续尝试（不放弃）
    if (m_restartCount >= MAX_AUTO_RESTART) {
        qWarning() << "[Camera] 重启计数归零，继续监控恢复";
        m_restartCount = 0;
    }
    m_restartCount++;
    m_watchdogTimer->stop();

    // 销毁旧摄像头
    if (m_mainCamera) {
        m_mainCamera->stop();
        m_mainCaptureSession.setCamera(nullptr);
        m_mainCamera->deleteLater();
        m_mainCamera = nullptr;
    }

    // 固定 2s 延迟等待 USB 释放，不做指数退避
    QTimer::singleShot(2000, this, [this]() {
        auto usbCam = findUsbCamera();
        if (usbCam.isNull()) {
            qCritical() << "[Camera] 重启失败: 无可用设备，5秒后重试";
            m_isRestarting = false;
            m_restartCount--; // 不算作有效重启，回退计数
            QTimer::singleShot(5000, this, &CameraController::restartMainCamera);
            return;
        }

        m_mainCamera = new QCamera(usbCam, this);
        connect(m_mainCamera, SIGNAL(errorOccurred(int, const QString &)),
                this, SLOT(onCameraErrorOccurred(int, const QString &)));
        connect(m_mainCamera, SIGNAL(statusChanged(QCamera::Status)),
                this, SLOT(onCameraStatusChanged(int)));
        setupCameraFormat(usbCam);
        m_mainCaptureSession.setCamera(m_mainCamera);

        if (m_mainSink) {
            m_mainCaptureSession.setVideoOutput(m_mainSink);
            m_mainSink->disconnect(this);
            connect(m_mainSink, &QVideoSink::videoFrameChanged,
                    this, &CameraController::onMainVideoFrameChanged, Qt::DirectConnection);
        }

        m_mainCamera->start();
        // 心跳由 onCameraStatusChanged(Active) 统一重置，此处不提前打戳
        m_watchdogTimer->start();
        Q_EMIT cameraStatusChanged(QString("Restarted(#%1)").arg(m_restartCount));
        m_isRestarting = false;
        qDebug() << "[Camera] 重启完成";
    });
}

// ============================================================
//  独立 AI 识别入口（不阻塞拍照/保存管线）
// ============================================================
void CameraController::recognizeLastCapture()
{
    // 读取最后一次裁剪图（cp0.jpg 由 _processCommon 保存）
    QImage cropImage("/home/sjwu/Pictures/cp0.jpg");
    if (cropImage.isNull()) {
        qWarning() << "[CameraController] recognizeLastCapture: 裁剪图不可用";
        return;
    }

    QString savePath;
    {
        QMutexLocker locker(&m_captureMetaMutex);
        savePath = m_lastSavePath;
    }

    postAiRecognize(cropImage, savePath);
}

// ============================================================
//  在线 AI 识别 — 公共请求/回复基础设施
// ============================================================

void CameraController::postAiRecognize(const QImage &image, const QString &savePath)
{
    if (!m_networkMgr || !m_authService) return;

    // === Token 预检 ===
    QString token = m_authService->token();
    if (token.isEmpty()) {
        qWarning() << "[CameraController] 未登录，无法进行在线 AI 识别";
        setAiError("未登录，无法进行AI识别");
        emitAiResult(PState::UNKNOWN, savePath, 0);
        return;
    }
    if (m_authService->isTokenExpiringSoon()) {
        qDebug() << "[CameraController] Token 即将过期，排队等待刷新后识别";
        PendingAiRequest req{image, savePath};
        m_pendingAiRequests.append(req);
        if (!m_refreshingToken && !m_authService->isRefreshingToken()) {
            m_refreshingToken = true;
            m_authService->requestTokenRefresh();
        }
        return;
    }

    // ① 用工具类创建请求（零样板）
    QNetworkRequest request = NetworkUtils::createMultipartApiRequest(
        NetworkUtils::Api::AI_RECOGNIZE_FILE,
        token,
        "image/jpeg"
    );

    // ② 构建 multipart body
    QHttpMultiPart *multiPart = new QHttpMultiPart(QHttpMultiPart::FormDataType);

    QHttpPart imagePart;
    imagePart.setHeader(QNetworkRequest::ContentDispositionHeader,
                        QVariant("form-data; name=\"File\"; filename=\"capture.jpg\""));
    imagePart.setHeader(QNetworkRequest::ContentTypeHeader, QVariant("image/jpeg"));

    QByteArray imageData;
    QBuffer buffer(&imageData);
    buffer.open(QIODevice::WriteOnly);
    image.save(&buffer, "JPG", 90);
    buffer.close();
    imagePart.setBody(imageData);
    multiPart->append(imagePart);

    // ③ 发送 + 附加上下文（用于回调时区分请求类型）
    QNetworkReply *reply = m_networkMgr->post(request, multiPart);
    multiPart->setParent(reply);  // reply 删除时自动清理 multiPart

    reply->setProperty("_reqType", "ai_recognize");
    reply->setProperty("_aiSavePath", savePath);
    reply->setProperty("_aiStartTime", QDateTime::currentMSecsSinceEpoch());
    reply->setProperty("_aiOriginalImage", QVariant::fromValue(image));

    qInfo() << "[CameraController] AI识别已发送," << imageData.size() << "bytes";
}

void CameraController::onNetworkReply(QNetworkReply *reply)
{
    QString reqType = reply->property("_reqType").toString();

    if (reqType == "ai_recognize") {
        handleAiRecognizeResponse(reply);
    } else {
        // 未来其他 API 类型在这里扩展:
        // } else if (reqType == "xxx") { handleXxx(reply); }
        reply->deleteLater();
    }
}

void CameraController::handleAiRecognizeResponse(QNetworkReply *reply)
{
    QString savePath = reply->property("_aiSavePath").toString();
    qint64 startTime = reply->property("_aiStartTime").toLongLong();
    qint64 elapsed = QDateTime::currentMSecsSinceEpoch() - startTime;
    QImage originalImage = reply->property("_aiOriginalImage").value<QImage>();

    reply->deleteLater();

    // ---- 网络错误 ----
    if (reply->error() != QNetworkReply::NoError) {
        // === 401/403 自动刷新重试 ===
        if (AuthService::isUnauthorizedError(reply)) {
            qDebug() << "[在线AI] 收到 401/403 未授权，触发 Token 刷新并重试"
                     << "savePath=" << savePath;
            PendingAiRequest req{originalImage.isNull() ? QImage(savePath) : originalImage, savePath};
            m_pendingAiRequests.append(req);
            if (!m_refreshingToken && m_authService && !m_authService->isRefreshingToken()) {
                m_refreshingToken = true;
                m_authService->requestTokenRefresh();
            }
            return;
        }

        QString netErr = QString("网络请求失败：%1").arg(reply->errorString());
        int httpCode = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (httpCode > 0) netErr += QString("（HTTP %1）").arg(httpCode);
        qWarning() << "[在线AI]" << netErr;
        setAiError(netErr);
        emitAiResult(PState::UNKNOWN, savePath, elapsed);
        return;
    }

    // ---- 解析 JSON 响应 ----
    QByteArray data = reply->readAll();
    qInfo() << "[在线AI] 响应数据:" << data;

    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (doc.isNull() || !doc.isObject()) {
        qWarning() << "[在线AI] JSON 解析失败";
        setAiError("服务器响应格式异常，无法解析");
        emitAiResult(PState::UNKNOWN, savePath, elapsed);
        return;
    }

    QJsonObject obj = doc.object();
    bool success = obj["success"].toBool(false);
    QString message = obj["message"].toString();

    // ★ 兼容三种 data 格式：
    //   新格式: { "data": [{ "code": "tudou", "name": "土豆" }, ...] }  → 数组，取首个 code
    //   中间格式: { "data": { "code": "tudou", "name": "土豆" } }      → 单对象
    //   旧格式: { "data": "POTATO" }                                   → 纯字符串
    QString label;
    QJsonValue dataVal = obj.value("data");
    m_aiCandidateList.clear();          // 每次先清空

    if (dataVal.isArray()) {
        // ★ 新格式：[{code,name}, ...] 数组
        QJsonArray arr = dataVal.toArray();
        for (const auto &v : arr) {
            if (v.isObject()) {
                QJsonObject o = v.toObject();
                QVariantMap m;
                m["code"] = o.value("code").toString();
                m["name"] = o.value("name").toString();
                if (!m["code"].toString().isEmpty())
                    m_aiCandidateList.append(m);
            }
        }
        label = !m_aiCandidateList.isEmpty()
            ? m_aiCandidateList.first().toMap()["code"].toString()
            : PState::NONE;
        qInfo() << "[在线AI] 新格式数组响应, candidates=" << m_aiCandidateList.size()
                << " label=" << label;
        Q_EMIT aiCandidateListChanged();

    } else if (dataVal.isObject()) {
        // 兼容中间格式单对象
        QJsonObject dataObj = dataVal.toObject();
        label = dataObj.value("code").toString();
        QString name = dataObj.value("name").toString();
        qInfo() << "[在线AI] 单对象响应, code=" << label << "name=" << name;
        Q_EMIT aiCandidateListChanged();

    } else {
        // 兼容更早格式纯字符串
        label = dataVal.toString(PState::NONE);
        if (!label.isEmpty() && label != PState::NONE)
            qInfo() << "[在线AI] 旧格式响应, label=" << label;
        Q_EMIT aiCandidateListChanged();
    }

    // 业务结果判定：success 为假、label 为空/NONE 均视为识别失败
    if (!success || label == PState::NONE || label.isEmpty()) {
        qWarning() << "[在线AI] 识别失败, success=" << success
                   << "message=" << message
                   << "label=" << label;
        // 使用服务端返回的 message 作为错误提示，没有则用默认文案
        QString errDetail = message.isEmpty() ? QStringLiteral("未能识别出食材") : message;
        setAiError(errDetail);
        label = PState::UNKNOWN;
    } else {
        // 成功时清空错误
        setAiError("");
    }

    qInfo() << "[在线AI] 识别结果:" << label << "耗时:" << elapsed << "ms";

    // ---- 语音播报 ----
    speakPredictedLabel(label);

    // ---- 发射结果通知 QML 更新界面（图片已提前保存完毕）----
    emitAiResult(label, savePath, elapsed);
}

void CameraController::emitAiResult(const QString &label, const QString &path, qint64 ms)
{
    Q_EMIT aiRecognitionCompleted(label, path, ms);
}

void CameraController::setAiError(const QString &error)
{
    if (m_lastAiError != error) {
        m_lastAiError = error;
        QMetaObject::invokeMethod(this, [this]() { Q_EMIT lastAiErrorChanged(); }, Qt::QueuedConnection);
    }
}

void CameraController::speakPredictedLabel(const QString &label)
{
    if (!m_voiceSpeaker || label == PState::NONE || label == PState::UNKNOWN) return;

    QString chineseName = FoodTranslator::instance()->translate(label);
    QString speakText = QString("识别到%1").arg(chineseName);
    QMetaObject::invokeMethod(m_voiceSpeaker, "speak", Qt::QueuedConnection,
                              Q_ARG(QString, speakText));
}

// ==========================================================================
//  Token 刷新完成回调 — 重发排队请求
// ==========================================================================

void CameraController::onTokenRefreshCompleted(bool success, const QString &errMsg)
{
    m_refreshingToken = false;

    if (!success) {
        qWarning() << "[CameraController] Token 刷新失败，丢弃" << m_pendingAiRequests.size()
                   << "条排队 AI 识别请求";
        for (const auto &req : m_pendingAiRequests) {
            emitAiResult(PState::UNKNOWN, req.savePath, 0);
        }
        m_pendingAiRequests.clear();
        return;
    }

    qDebug() << "[CameraController] Token 刷新成功，重发"
             << m_pendingAiRequests.size() << "条排队 AI 识别请求";

    // 逐个重发（AI 识别通常不需要去重）
    QList<PendingAiRequest> pending = m_pendingAiRequests;
    m_pendingAiRequests.clear();
    for (const auto &req : pending) {
        postAiRecognize(req.image, req.savePath);
    }
}
