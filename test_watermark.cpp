// 独立测试：生成小管事风格水印预览图
// 编译: g++ -std=c++17 -fPIC -o test_watermark test_watermark.cpp -lQt6Gui -lQt6Core
// 运行: ./test_watermark

#include <QImage>
#include <QPainter>
#include <QFont>
#include <QPen>
#include <QBrush>
#include <QColor>
#include <QDateTime>
#include <QStringList>
#include <QRect>
#include <QPoint>
#include <QPolygonF>
#include <QtMath>
#include <QGuiApplication>

void drawWatermarkOverlay(QPainter &painter, int imgW, int imgH,
                          const QString &predictedLabel, double weightKg)
{
    painter.setRenderHint(QPainter::Antialiasing);
    painter.setRenderHint(QPainter::TextAntialiasing);

    QString chineseName = predictedLabel;
    QDateTime now = QDateTime::currentDateTime();

    double scaleX = imgW / 1280.0;
    double scaleY = imgH / 720.0;

    auto sx = [&](int v) { return int(v * scaleX); };
    auto sy = [&](int v) { return int(v * scaleY); };
    auto sFontSize = [&](int size) { return int(size * qMin(scaleX, scaleY)); };

    QFont fontTitle("Microsoft YaHei", sFontSize(16), QFont::Bold);
    QFont fontInfo("Microsoft YaHei", sFontSize(15));
    QFont fontInfoLabel("Microsoft YaHei", sFontSize(14));

    // ---- 1) 顶部白色标题栏 ----
    QRect topBar(0, 0, imgW, sy(36));
    painter.fillRect(topBar, QColor(245, 245, 245, 240));
    painter.setPen(QColor(30, 30, 30));
    painter.setFont(fontTitle);
    painter.drawText(sx(15), 0, sx(450), sy(36),
                     Qt::AlignVCenter, QStringLiteral("小管事AI智能网络秤水印生成图片"));
    QFont fontFileName("Consolas", sFontSize(12));
    painter.setFont(fontFileName);
    QString fileName = QString("WLC200A_V-XXXXXX_%1_%2.jpg")
                           .arg(now.toString("yyyyMMdd"))
                           .arg(now.toString("HHmmss"));
    painter.drawText(sx(500), 0, imgW - sx(15), sy(36),
                     Qt::AlignRight | Qt::AlignVCenter, fileName);

    // ---- 2) 右上角员工照片区域 ----
    {
        int photoW = sx(250);
        int photoH = sy(400);
        int photoX = imgW - photoW - sx(50);
        int photoY = sy(70);

        QRect photoBg(photoX - sx(4), photoY - sy(4), photoW + sx(8), photoH + sy(24) + sy(8));
        painter.setBrush(QColor(255, 255, 255, 230));
        painter.setPen(Qt::NoPen);
        painter.drawRoundedRect(photoBg, sx(8), sy(8));

        QRect photoRect(photoX, photoY, photoW, photoH);
        // 模拟一张占位图
        painter.fillRect(photoRect, QColor(180, 200, 220));
        painter.setPen(QColor(80, 100, 120));
        painter.setFont(QFont("Microsoft YaHei", sFontSize(11)));
        painter.drawText(photoRect, Qt::AlignCenter, QStringLiteral("副摄像头\n(待抓拍)"));

        painter.setPen(QPen(QColor(180, 180, 180), 1));
        painter.setBrush(Qt::NoBrush);
        painter.drawRect(photoRect);

        QRect accountLabel(photoX, photoY + photoH + sy(4), photoW, sy(20));
        painter.setPen(QColor(40, 40, 40));
        painter.setFont(fontInfoLabel);
        painter.drawText(accountLabel, Qt::AlignCenter,
                         QStringLiteral("员工账户：操作员"));
    }

    // ---- 3) 左下角红色椭圆公章 ----
    {
        int sealCx = sx(110);
        int sealCy = imgH - sy(120);
        int sealRx = sx(112);   // 长半轴 ~225/2
        int sealRy = sy(75);    // 短半轴 ~150/2

        QPen sealPen(QColor(200, 30, 30), sx(3));
        painter.setPen(sealPen);
        painter.setBrush(Qt::NoBrush);
        painter.drawEllipse(QPoint(sealCx, sealCy), sealRx, sealRy);

        QPen innerPen(QColor(200, 30, 30), 1);
        painter.setPen(innerPen);
        painter.drawEllipse(QPoint(sealCx, sealCy), int(sealRx * 0.85), int(sealRy * 0.85));

        painter.setPen(Qt::NoPen);
        painter.setBrush(QColor(200, 30, 30));
        int starR = int(sealRy * 0.38);
        QPolygonF star;
        for (int i = 0; i < 5; ++i) {
            double outerAngle = (i * 72 - 90) * M_PI / 180.0;
            double innerAngle = ((i * 72) + 36 - 90) * M_PI / 180.0;
            star << QPointF(sealCx + starR * cos(outerAngle),
                            sealCy + starR * sin(outerAngle));
            star << QPointF(sealCx + starR * 0.38 * cos(innerAngle),
                            sealCy + starR * 0.38 * sin(innerAngle));
        }
        painter.drawPolygon(star);

        QFont fontStampBig("SimHei", sFontSize(13), QFont::Bold);
        painter.setPen(QColor(200, 30, 30));
        painter.setFont(fontStampBig);
        QString topText = QStringLiteral("小管事网络称现场图片水印认证");
        int textAngleSpan = 160;
        double startAngle = -(90 + textAngleSpan / 2);
        for (int i = 0; i < topText.size(); ++i) {
            double angleStep = (double)textAngleSpan / (topText.size() - 1);
            double angleDeg = startAngle + i * angleStep;
            double angleRad = angleDeg * M_PI / 180.0;
            int textRx = int(sealRx * 0.68);
            int textRy = int(sealRy * 0.68);
            int tx = sealCx + int(textRx * cos(angleRad));
            int ty = sealCy + int(textRy * sin(angleRad));
            painter.save();
            painter.translate(tx, ty);
            painter.rotate(angleDeg + 90);
            painter.drawText(0, 0, QString(topText[i]));
            painter.restore();
        }

        QFont fontSiteBig("Microsoft YaHei", sFontSize(24), QFont::Bold);
        painter.setPen(QColor(200, 30, 30));
        painter.setFont(fontSiteBig);
        painter.drawText(sx(8), imgH - sy(18), sx(230), sy(36),
                         Qt::AlignLeft | Qt::AlignVCenter,
                         QStringLiteral("现 场 照 片"));
    }

    // ---- 4) 右下角结构化信息列表 ----
    {
        int infoX = imgW - sx(260);
        int infoStartY = imgH - sy(170);
        int lineHeight = sy(26);

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
            QStringLiteral("操作员"),
        };

        painter.setFont(fontInfoLabel);
        int maxLabelWidth = 0;
        for (const auto &lbl : labels) {
            int w = painter.fontMetrics().horizontalAdvance(lbl);
            if (w > maxLabelWidth) maxLabelWidth = w;
        }

        for (int i = 0; i < labels.size(); ++i) {
            int y = infoStartY + i * lineHeight;
            painter.setPen(QColor(100, 100, 100));
            painter.drawText(infoX, y, maxLabelWidth, lineHeight,
                             Qt::AlignVCenter | Qt::AlignRight, labels[i]);
            painter.setPen(Qt::white);
            painter.setFont(fontInfo);
            painter.drawText(infoX + maxLabelWidth + sx(6), y,
                             sx(190), lineHeight,
                             Qt::AlignVCenter | Qt::AlignLeft, values[i]);
            painter.setFont(fontInfoLabel);
        }
    }
}

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // 创建 1280x720 测试背景（模拟摄像头画面）
    QImage image(1280, 720, QImage::Format_RGB888);
    // 填充渐变灰背景模拟场景
    QPainter bgPainter(&image);
    for (int y = 0; y < 720; ++y) {
        int gray = 140 + (y * 30) / 720;
        bgPainter.setPen(QColor(gray, gray + 5, gray - 5));
        bgPainter.drawLine(0, y, 1280, y);
    }
    bgPainter.end();

    // 绘制水印
    QPainter painter(&image);
    drawWatermarkOverlay(painter, 1280, 720, QStringLiteral("西红柿"), 2.56);
    painter.end();

    // 保存
    QString path = "/home/sjwu/Pictures/watermark_preview.jpg";
    bool ok = image.save(path, "JPG", 95);
    if (ok) {
        qDebug("OK! 已保存到: %s", qPrintable(path));
    } else {
        qCritical("FAIL! 保存失败!");
        return 1;
    }
    return 0;
}
