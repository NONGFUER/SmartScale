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

// 副摄像头配置 (IMX708 CSI)
#define SUB_TUNING_FILE "/usr/share/libcamera/ipa/rpi/pisp/imx519.json"
// ============================================================
//  公共工具方法
// ============================================================

QCameraDevice CameraController::findUsbCamera()
{
    const QList<QCameraDevice> cameras = QMediaDevices::videoInputs();
    for (const auto &cam : cameras) {
        QString id = QString::fromUtf8(cam.id());
        QString desc = cam.description();
        if (id.contains("USB", Qt::CaseInsensitive) || desc.contains("UGREEN", Qt::CaseInsensitive)
            || desc.contains("2K", Qt::CaseInsensitive) || desc.contains("1080P", Qt::CaseInsensitive)) {
            qDebug() << "[Camera] 找到USB摄像头:" << desc;
            return cam;
        }
    }
    if (!cameras.isEmpty()) {
        qDebug() << "[Camera] 使用默认摄像头:" << cameras.first().description();
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
    m_aiService = new VisionAIService(this);

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
        qWarning() << "[Camera] 未找到USB摄像头!";
    }

    // === 副摄像头 (rpicam-vid IMX708) ===
    m_subProcess = new QProcess(this);
    connect(m_subProcess, &QProcess::readyReadStandardOutput, this, &CameraController::readSubCameraData);
    connect(this, &CameraController::subCaptureReady, this, &CameraController::onSubCaptureReady);

    QStringList subArgs = {"--camera", "0", "--tuning-file", SUB_TUNING_FILE,
                           "--width", QString::number(m_subWidth),
                           "--height", QString::number(m_subHeight),
                           "--framerate", "15", "--codec", "yuv420",
                           "--autofocus-mode", "continuous",
                           "--nopreview", "--timeout", "0", "-o", "-"};
    m_subProcess->start("rpicam-vid", subArgs);
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

void CameraController::captureVegetable(double currentWeight) {
    if (m_isRestarting) {
        qWarning() << "[Camera] 摄像头重启中，跳过本次拍照";
        return;
    }
    m_lastWeight.store(currentWeight);
    m_captureRequestedSub.store(true);
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

