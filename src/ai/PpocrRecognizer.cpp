#include "PpocrRecognizer.h"

#include <QCoreApplication>
#include <QDebug>
#include <QElapsedTimer>
#include <QFile>
#include <QPainter>
#include <QPen>
#include <QPolygonF>
#include <QStringConverter>
#include <QTextStream>

#include <algorithm>
#include <cmath>
#include <numeric>

namespace {

// 识别输入高度（模型固定输入 H=48）
constexpr int kInputHeight = 48;
// 输入宽度上下限（时间步 = 宽度 / 8）
constexpr int kMinInputWidth = 48;
constexpr int kMaxInputWidth = 640;
// 最低置信度（**仅用于过滤纯噪声**）
// 注意：手写体的置信度远低于印刷体（实测正确字也常只有 0.2~0.4），阈值刻意压到很低 ——
// 宁可把结果上屏(预编辑)+候选栏让用户纠正，也不能把正确的识别结果丢掉。
constexpr float kMinConfidence = 0.02f;
// 低于该值仅打日志提示（结果仍然上屏，避免"对的被丢掉"）
constexpr float kLowConfidenceHint = 0.45f;
// 墨迹外接框小于该尺寸（像素）视为误触
constexpr qreal kMinInkSize = 6.0;

bool isUsableChar(const QChar &c)
{
    const QChar::Category cat = c.category();
    return cat != QChar::Other_Control && cat != QChar::Other_Format
            && cat != QChar::Other_Surrogate && cat != QChar::Other_NotAssigned;
}

} // namespace

PpocrRecognizer::PpocrRecognizer(QObject *parent)
    : QObject(parent)
{
}

PpocrRecognizer::~PpocrRecognizer() = default;

PpocrRecognizer *PpocrRecognizer::instance()
{
    static PpocrRecognizer s_instance;
    return &s_instance;
}

void PpocrRecognizer::warmup()
{
    ensureLoaded();
}

bool PpocrRecognizer::isReady() const
{
    return m_ready;
}

// ============================================================
//  模型 / 字典加载
// ============================================================
bool PpocrRecognizer::ensureLoaded()
{
    QMutexLocker locker(&m_mutex);

    if (m_ready)
        return true;
    if (m_loadAttempted)
        return false;   // 已尝试过且失败，不重复刷日志
    m_loadAttempted = true;

    const QString basePath = QCoreApplication::applicationDirPath() + "/AI/";
    const QString modelPath = basePath + "rec.onnx";
    const QString dictPath = basePath + "ppocrv5_dict.txt";

    if (!QFile::exists(modelPath) || !QFile::exists(dictPath)) {
        qCritical() << "[PPOCR] 模型或字典缺失:" << modelPath << dictPath;
        return false;
    }

    // ---- 1. 字典 ----
    QFile dictFile(dictPath);
    if (!dictFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        qCritical() << "[PPOCR] 字典打开失败:" << dictPath;
        return false;
    }
    QTextStream in(&dictFile);
    in.setEncoding(QStringConverter::Utf8);
    while (!in.atEnd()) {
        const QString line = in.readLine();
        if (!line.isEmpty())
            m_chars.append(line);
    }
    dictFile.close();

    if (m_chars.isEmpty()) {
        qCritical() << "[PPOCR] 字典为空:" << dictPath;
        return false;
    }

    // ---- 2. ONNX 会话 ----
    try {
        m_env = std::make_unique<Ort::Env>(ORT_LOGGING_LEVEL_ERROR, "PpocrRecognizer");

        Ort::SessionOptions options;
        options.SetIntraOpNumThreads(2);    // 限线程，避免与相机/MQTT 抢核
        options.SetInterOpNumThreads(1);
        options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        QElapsedTimer timer;
        timer.start();
        m_session = std::make_unique<Ort::Session>(*m_env, modelPath.toStdString().c_str(), options);

        Ort::AllocatorWithDefaultOptions allocator;
        m_inputName = m_session->GetInputNameAllocated(0, allocator).get();
        m_outputName = m_session->GetOutputNameAllocated(0, allocator).get();

        // 输出最后一维 = 类别数（含 CTC blank）
        const auto outShape = m_session->GetOutputTypeInfo(0).GetTensorTypeAndShapeInfo().GetShape();
        if (!outShape.empty() && outShape.back() > 0)
            m_numClasses = static_cast<int>(outShape.back());

        qInfo() << "[PPOCR] 模型加载完成:" << m_inputName.c_str() << "->" << m_outputName.c_str()
                << "类别数:" << m_numClasses
                << "字典:" << m_chars.size() << "项"
                << "耗时:" << timer.elapsed() << "ms";
    } catch (const Ort::Exception &e) {
        qCritical() << "[PPOCR] 模型加载异常:" << e.what();
        m_session.reset();
        return false;
    }

    // ---- 3. 对齐类别数：字典项 + 1(blank) 之外的类别按 PaddleOCR use_space_char 补空格 ----
    if (m_numClasses > 0) {
        const int expectedChars = m_numClasses - 1;   // 去掉 CTC blank
        while (m_chars.size() < expectedChars)
            m_chars.append(QStringLiteral(" "));
        if (m_chars.size() != expectedChars) {
            qWarning() << "[PPOCR] 字典项数" << m_chars.size()
                       << "与模型类别数" << m_numClasses << "不匹配";
        }
    } else {
        m_numClasses = m_chars.size() + 1;
        qWarning() << "[PPOCR] 未能从模型读取类别数，按字典推断:" << m_numClasses;
    }

    m_ready = true;
    return true;
}

// ============================================================
//  笔画 -> 位图
// ============================================================
QImage PpocrRecognizer::strokesToImage(const QVector<QVector<QPointF>> &strokes)
{
    return strokesToImage(strokes, PreprocessOptions());
}

QImage PpocrRecognizer::strokesToImage(const QVector<QVector<QPointF>> &strokes,
                                       const PreprocessOptions &options)
{
    // 1. 统计墨迹外接框与点数
    int pointCount = 0;
    qreal minX = 0, maxX = 0, minY = 0, maxY = 0;
    bool first = true;
    for (const QVector<QPointF> &stroke : strokes) {
        for (const QPointF &pt : stroke) {
            if (first) {
                minX = maxX = pt.x();
                minY = maxY = pt.y();
                first = false;
            } else {
                minX = qMin(minX, pt.x());
                maxX = qMax(maxX, pt.x());
                minY = qMin(minY, pt.y());
                maxY = qMax(maxY, pt.y());
            }
            ++pointCount;
        }
    }
    if (first || pointCount < 2)
        return QImage();

    const qreal inkW = qMax<qreal>(1.0, maxX - minX);
    const qreal inkH = qMax<qreal>(1.0, maxY - minY);
    const qreal aspect = inkW / inkH;
    const qreal inkSide = qMax(inkW, inkH);

    // 误触过滤：墨迹过小（点一下）不进入识别
    if (inkW < kMinInkSize && inkH < kMinInkSize)
        return QImage();

    // 2. 留白：单字按外接框方形留白（字形居中、接近训练裁剪的"占满高度"）；
    //    长条（多字横排）按墨迹高度留白，保证缩放到 48px 后字形高度一致
    const bool isSingleChar = aspect >= 1.0 / options.singleCharAspectMax
            && aspect <= options.singleCharAspectMax;
    const qreal margin = isSingleChar ? inkSide * options.margin
                                      : inkH * options.lineMargin;
    const int imgW = qMax(8, static_cast<int>(std::ceil(inkW + 2 * margin)));
    const int imgH = qMax(8, static_cast<int>(std::ceil(inkH + 2 * margin)));

    QImage canvas(imgW, imgH, QImage::Format_RGB32);
    canvas.fill(Qt::white);

    QPainter painter(&canvas);
    painter.setRenderHint(QPainter::Antialiasing, true);
    const qreal penWidth = qMax<qreal>(2.0, inkSide * options.penWidthRatio);
    painter.setPen(QPen(Qt::black, penWidth, Qt::SolidLine, Qt::RoundCap, Qt::RoundJoin));

    for (const QVector<QPointF> &stroke : strokes) {
        QPolygonF polygon;
        polygon.reserve(stroke.size());
        for (const QPointF &pt : stroke)
            polygon << QPointF(pt.x() - minX + margin, pt.y() - minY + margin);

        if (polygon.size() == 1)
            painter.drawPoint(polygon.first());
        else
            painter.drawPolyline(polygon);
    }
    painter.end();

    return canvas;
}

// ============================================================
//  预处理：位图 -> NCHW float32
// ============================================================
std::vector<float> PpocrRecognizer::preprocess(const QImage &ink, int *outWidth) const
{
    const QImage gray = ink.convertToFormat(QImage::Format_Grayscale8);
    const int srcH = qMax(1, gray.height());
    int width = static_cast<int>(std::lround(static_cast<double>(gray.width()) * kInputHeight / srcH));
    width = qBound(kMinInputWidth, width, kMaxInputWidth);

    const QImage small = gray.scaled(width, kInputHeight, Qt::IgnoreAspectRatio,
                                     Qt::SmoothTransformation);

    if (outWidth)
        *outWidth = width;

    const size_t plane = static_cast<size_t>(kInputHeight) * width;
    std::vector<float> data(3 * plane, 0.0f);
    for (int y = 0; y < kInputHeight; ++y) {
        const uchar *row = small.constScanLine(y);
        for (int x = 0; x < width; ++x) {
            const float value = (row[x] / 255.0f - 0.5f) / 0.5f;   // 归一化到 [-1, 1]
            for (int c = 0; c < 3; ++c)
                data[c * plane + static_cast<size_t>(y) * width + x] = value;
        }
    }
    return data;
}

// ============================================================
//  CTC 解码 + 候选
// ============================================================
QString PpocrRecognizer::charForClass(int classIndex) const
{
    if (classIndex <= 0)
        return QString();                       // 0 = CTC blank
    const int index = classIndex - 1;           // 1 基 -> 0 基
    if (index < 0 || index >= m_chars.size())
        return QString();
    const QString &ch = m_chars.at(index);
    if (ch.isEmpty() || !isUsableChar(ch.at(0)))
        return QString();
    return ch;
}

QList<PpocrRecognizer::Candidate> PpocrRecognizer::decode(const float *logits, int timeSteps,
                                                          int numClasses, int maxCandidates) const
{
    QList<Candidate> result;
    if (!logits || timeSteps <= 0 || numClasses <= 0)
        return result;

    QString text;
    double scoreSum = 0.0;
    int scoreCount = 0;
    int previous = -1;

    for (int t = 0; t < timeSteps; ++t) {
        const float *row = logits + static_cast<size_t>(t) * numClasses;
        int best = 0;
        float bestProb = row[0];
        for (int c = 1; c < numClasses; ++c) {
            if (row[c] > bestProb) {
                bestProb = row[c];
                best = c;
            }
        }
        if (best != previous && best != 0) {
            const QString ch = charForClass(best);
            if (!ch.isEmpty()) {
                text += ch;
                scoreSum += bestProb;
                ++scoreCount;
            }
        }
        previous = best;
    }

    if (text.isEmpty() || scoreCount == 0)
        return result;

    const float score = static_cast<float>(scoreSum / scoreCount);
    if (score < kMinConfidence) {
        qDebug() << "[PPOCR] 置信度低于噪声下限，丢弃识别结果:" << text << score;
        return result;
    }
    if (score < kLowConfidenceHint) {
        // 手写体常见情况：结果可用但把握不大 —— 仍然上屏，由候选栏纠正
        qDebug() << "[PPOCR] 低置信度识别(已上屏，可点候选纠正):" << text << score;
    }

    // 候选生成：**跨时间步聚合每个类别出现过的最大概率**后排序。
    // 比"取单个概率峰值时间步的 top-N"丰富得多：手写时模型常在某些时间步纠结偏旁
    // （实测写"鸡"时峰值步的 top 全是 火/一/，导致正确字完全不进候选），
    // 聚合后正确字也能被捞回来。
    if (maxCandidates > 1) {
        std::vector<float> classBest(static_cast<size_t>(numClasses), 0.0f);
        for (int t = 0; t < timeSteps; ++t) {
            const float *row = logits + static_cast<size_t>(t) * numClasses;
            for (int c = 1; c < numClasses; ++c) {
                if (row[c] > classBest[c])
                    classBest[c] = row[c];
            }
        }

        std::vector<int> order(static_cast<size_t>(numClasses));
        std::iota(order.begin(), order.end(), 0);
        const int wanted = qMin(numClasses, maxCandidates * 6);
        std::partial_sort(order.begin(), order.begin() + wanted, order.end(),
                          [&classBest](int a, int b) { return classBest[a] > classBest[b]; });

        QList<QString> seen;
        for (int i = 0; i < wanted && result.size() < maxCandidates; ++i) {
            const int cls = order[static_cast<size_t>(i)];
            if (cls == 0)
                continue;
            const QString ch = charForClass(cls);
            if (ch.isEmpty() || ch.size() != 1 || seen.contains(ch))
                continue;
            seen.append(ch);
            result.append(Candidate{ch, classBest[cls]});
        }
    }

    // CTC 最优路径结果始终作为首选候选（多字时即唯一候选）；已出现过的重复项先剔除
    for (int i = result.size() - 1; i >= 0; --i) {
        if (result.at(i).text == text)
            result.removeAt(i);
    }
    result.prepend(Candidate{text, score});

    return result.mid(0, qMax(1, maxCandidates));
}

// ============================================================
//  对外识别接口
// ============================================================
QList<PpocrRecognizer::Candidate> PpocrRecognizer::recognizeImage(const QImage &ink, int maxCandidates)
{
    if (ink.isNull() || !ensureLoaded())
        return {};

    QMutexLocker locker(&m_mutex);
    if (!m_session)
        return {};

    int width = 0;
    std::vector<float> input = preprocess(ink, &width);
    const std::vector<int64_t> shape = {1, 3, kInputHeight, width};

    try {
        Ort::MemoryInfo memoryInfo = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
        Ort::Value inputTensor = Ort::Value::CreateTensor<float>(
            memoryInfo, input.data(), input.size(), shape.data(), shape.size());

        const char *inputNames[] = {m_inputName.c_str()};
        const char *outputNames[] = {m_outputName.c_str()};

        QElapsedTimer timer;
        timer.start();
        auto outputs = m_session->Run(Ort::RunOptions{nullptr}, inputNames, &inputTensor, 1,
                                      outputNames, 1);
        const qint64 elapsed = timer.elapsed();

        if (outputs.empty())
            return {};

        const auto info = outputs.front().GetTensorTypeAndShapeInfo();
        const std::vector<int64_t> outShape = info.GetShape();
        if (outShape.size() != 3)
            return {};

        const float *logits = outputs.front().GetTensorMutableData<float>();
        QList<Candidate> candidates = decode(logits, static_cast<int>(outShape[1]),
                                           static_cast<int>(outShape[2]), maxCandidates);

        if (!candidates.isEmpty()) {
            qDebug() << "[PPOCR] 识别:" << candidates.first().text
                     << "置信度:" << candidates.first().score
                     << "候选数:" << candidates.size()
                     << "耗时:" << elapsed << "ms";
        }
        return candidates;
    } catch (const Ort::Exception &e) {
        qWarning() << "[PPOCR] 推理异常:" << e.what();
        return {};
    }
}

QList<PpocrRecognizer::Candidate> PpocrRecognizer::recognizeStrokes(
        const QVector<QVector<QPointF>> &strokes, int maxCandidates)
{
    return recognizeStrokes(strokes, maxCandidates, PreprocessOptions());
}

QList<PpocrRecognizer::Candidate> PpocrRecognizer::recognizeStrokes(
        const QVector<QVector<QPointF>> &strokes, int maxCandidates,
        const PreprocessOptions &options)
{
    const QImage ink = strokesToImage(strokes, options);
    if (ink.isNull())
        return {};
    return recognizeImage(ink, maxCandidates);
}

QList<PpocrRecognizer::Candidate> PpocrRecognizer::recognizeStrokesEnsemble(
        const QVector<QVector<QPointF>> &strokes, int maxCandidates)
{
    // 手写笔迹粗细/大小因人而异，而我们只能用墨迹尺寸推笔宽，固定一组参数必然有偏。
    // 这里跑三组典型参数（细笔+小留白 / 中笔默认 / 粗笔+大留白），取最有把握的一路作首选，
    // 候选取并集 —— 笔宽这一维无法先验确定，融合是这里性价比最高的提升手段。
    static const PreprocessOptions variants[] = {
        {0.05, 0.07, 0.07, 1.5},   // 细笔 + 小留白
        {0.08, 0.12, 0.12, 1.5},   // 中笔（默认，留白取实测最优附近）
        {0.12, 0.16, 0.16, 1.5},   // 粗笔 + 大留白（原行为）
    };

    QString primaryText;
    float primaryScore = -1.0f;
    QList<Candidate> merged;

    for (const PreprocessOptions &options : variants) {
        const QList<Candidate> result = recognizeStrokes(strokes, maxCandidates, options);
        if (result.isEmpty())
            continue;

        if (result.first().score > primaryScore) {
            primaryScore = result.first().score;
            primaryText = result.first().text;
        }

        for (const Candidate &candidate : result) {
            bool found = false;
            for (Candidate &existing : merged) {
                if (existing.text == candidate.text) {
                    if (candidate.score > existing.score)
                        existing.score = candidate.score;
                    found = true;
                    break;
                }
            }
            if (!found)
                merged.append(candidate);
        }
    }

    if (merged.isEmpty())
        return {};

    std::stable_sort(merged.begin(), merged.end(),
                     [](const Candidate &a, const Candidate &b) { return a.score > b.score; });

    for (int i = merged.size() - 1; i >= 0; --i) {
        if (merged.at(i).text == primaryText)
            merged.removeAt(i);
    }
    merged.prepend(Candidate{primaryText, primaryScore});

    qDebug() << "[PPOCR] 融合首选:" << primaryText << "置信度:" << primaryScore
             << "融合候选数:" << merged.size();

    return merged.mid(0, qMax(1, maxCandidates));
}

/// QML 的 strokes = [[x, y], ...] 转 C++ 点集
static QVector<QVector<QPointF>> parseQmlStrokes(const QVariantList &strokes)
{
    QVector<QVector<QPointF>> parsed;
    for (const QVariant &strokeVar : strokes) {
        QVector<QPointF> stroke;
        const QVariantList points = strokeVar.toList();
        stroke.reserve(points.size());
        for (const QVariant &pointVar : points) {
            if (pointVar.canConvert<QPointF>()) {
                stroke.append(pointVar.toPointF());
            } else {
                const QVariantMap map = pointVar.toMap();
                stroke.append(QPointF(map.value(QStringLiteral("x")).toReal(),
                                      map.value(QStringLiteral("y")).toReal()));
            }
        }
        if (!stroke.isEmpty())
            parsed.append(stroke);
    }
    return parsed;
}

static QVariantList toQmlCandidates(const QList<PpocrRecognizer::Candidate> &candidates)
{
    QVariantList result;
    for (const PpocrRecognizer::Candidate &candidate : candidates) {
        QVariantMap item;
        item.insert(QStringLiteral("text"), candidate.text);
        item.insert(QStringLiteral("score"), candidate.score);
        result.append(item);
    }
    return result;
}

QVariantList PpocrRecognizer::recognizeStrokesQml(const QVariantList &strokes, int maxCandidates)
{
    const QVector<QVector<QPointF>> parsed = parseQmlStrokes(strokes);
    return toQmlCandidates(recognizeStrokesEnsemble(parsed, maxCandidates));
}

QVariantList PpocrRecognizer::recognizeStrokesQmlWithParams(const QVariantList &strokes,
                                                            int maxCandidates,
                                                            double penWidthRatio, double margin)
{
    PreprocessOptions options;
    options.penWidthRatio = penWidthRatio;
    options.margin = margin;
    options.lineMargin = margin;
    const QVector<QVector<QPointF>> parsed = parseQmlStrokes(strokes);
    return toQmlCandidates(recognizeStrokes(parsed, maxCandidates, options));
}
