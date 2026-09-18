#ifndef PPOCRRECOGNIZER_H
#define PPOCRRECOGNIZER_H

#include <QImage>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QPointF>
#include <QString>
#include <QVariantList>
#include <QVector>

#include <memory>
#include <string>
#include <vector>

#include <onnxruntime_cxx_api.h>

/**
 * @brief PP-OCRv5 文字识别引擎（手写输入法用）
 *
 * 模型 AI/rec.onnx
 *   输入  x        : [1, 3, 48, W]  float32（W 动态，8 倍下采样）
 *   输出  fetch_name_0 : [1, T, 18385] float32，**已内置 softmax**（每行概率和为 1）
 *
 * 字典 AI/ppocrv5_dict.txt（18383 行）
 *   类别映射：输出索引 i>0 -> 字典第 i 行（1 基）；i==0 为 CTC blank。
 *   类别总数 = 18383 + 1(末尾空格类，PaddleOCR use_space_char) + 1(blank) = 18385，
 *   与模型输出维度一致，加载时会按模型维度自动补齐末尾空格类。
 *
 * 预处理：白底黑墨位图 -> 按墨迹外接框方形留白/保持长宽比 -> 高 48 等比缩放
 *         -> 灰度归一化 (v/255-0.5)/0.5 -> NCHW。
 *
 * 线程安全：recognize*() 可跨线程调用（内部互斥串行，模型懒加载）。
 */
class PpocrRecognizer : public QObject
{
    Q_OBJECT

public:
    struct Candidate {
        QString text;
        float score = 0.0f;
    };

    /// 墨迹预处理参数（识别率主要靠这几个量）
    /// 取值依据（2026-09-18 消融实测，变形字形样本 252 个）：
    ///   留白 0.16 -> 98.4%，0.10 -> 97.6%，0.07 -> 97.2%，0.04 -> 96.4%
    ///   ⇒ "把字形放大"的直觉是错的，留白保持较大值；笔宽无法用印刷字形验证
    ///     （字形是实心填充，笔宽不起作用），因此用 ensemble 覆盖多种笔宽。
    struct PreprocessOptions {
        qreal penWidthRatio = 0.08;        // 笔宽 / 墨迹边长（缩放后约 3.4px @48px）
        qreal margin = 0.12;               // 单字：四周留白 / 墨迹边长
        qreal lineMargin = 0.12;           // 长条（多字横排）：留白 / 墨迹高度（保证与单字同样缩放）
        qreal singleCharAspectMax = 1.5;   // 长宽比在此范围内视为"单字"
    };

    /// 全局单例（QML 侧注册为 SmartScale.Hwr/Ppocr）
    static PpocrRecognizer *instance();

    /// 预热：加载模型与字典（幂等，阻塞至加载完成）。建议启动时在工作线程调用
    Q_INVOKABLE void warmup();

    /// 引擎是否就绪（模型 + 字典均已加载）
    Q_INVOKABLE bool isReady() const;

    /// 手写笔画点集识别（默认参数）
    QList<Candidate> recognizeStrokes(const QVector<QVector<QPointF>> &strokes,
                                      int maxCandidates = 5);

    /// 手写笔画点集识别（指定预处理参数；板端参数扫描用）
    /// 注：用重载而非默认实参 —— 嵌套结构体的 NSDMI 不能直接用作同一类内成员函数的默认实参
    QList<Candidate> recognizeStrokes(const QVector<QVector<QPointF>> &strokes,
                                      int maxCandidates, const PreprocessOptions &options);

    /// 手写笔画识别 —— **多参数融合(ensemble)**：用细/中/粗三种笔宽 + 不同留白各识别一次，
    /// 取"最有把握"(首选置信度最高)的一路作首选、候选取并集。
    /// 手写笔迹粗细因人而异，而我们只能按墨迹尺寸推算笔宽，用固定值必然有一半人吃亏，
    /// 融合是这里性价比最高的准确率提升手段（约 45ms/字，仍在去抖窗口内）。
    QList<Candidate> recognizeStrokesEnsemble(const QVector<QVector<QPointF>> &strokes,
                                              int maxCandidates = 5);

    /// 位图识别（白底黑字）
    QList<Candidate> recognizeImage(const QImage &ink, int maxCandidates = 5);

    /// 笔画 -> 白底黑墨位图（保持墨迹原始尺寸，仅做留白处理）
    static QImage strokesToImage(const QVector<QVector<QPointF>> &strokes);
    static QImage strokesToImage(const QVector<QVector<QPointF>> &strokes,
                                 const PreprocessOptions &options);

    // ---- QML 调试接口（手写识别测试弹窗用）----
    /// QML 版笔画识别：strokes = [[Qt.point(x,y), ...], ...]
    /// 返回 [{ text: "土", score: 0.99 }, ...]
    Q_INVOKABLE QVariantList recognizeStrokesQml(const QVariantList &strokes,
                                                 int maxCandidates = 5);

    /// 指定预处理参数的识别（板端参数扫描：笔宽/留白网格搜索，用真实手写找最优值）
    Q_INVOKABLE QVariantList recognizeStrokesQmlWithParams(const QVariantList &strokes,
                                                           int maxCandidates,
                                                           double penWidthRatio,
                                                           double margin);

private:
    explicit PpocrRecognizer(QObject *parent = nullptr);
    ~PpocrRecognizer() override;
    Q_DISABLE_COPY(PpocrRecognizer)

    /// 懒加载模型与字典（线程安全）
    bool ensureLoaded();
    /// 位图 -> NCHW 归一化张量；outWidth 返回实际时间步对应的输入宽度
    std::vector<float> preprocess(const QImage &ink, int *outWidth) const;
    /// CTC 贪心解码 + 候选生成
    QList<Candidate> decode(const float *logits, int timeSteps, int numClasses,
                            int maxCandidates) const;
    /// 输出类别索引 -> 字符（索引 0 为 blank）
    QString charForClass(int classIndex) const;

    mutable QMutex m_mutex;
    bool m_loadAttempted = false;
    bool m_ready = false;

    std::unique_ptr<Ort::Env> m_env;
    std::unique_ptr<Ort::Session> m_session;
    std::string m_inputName;
    std::string m_outputName;
    int m_numClasses = 0;
    QVector<QString> m_chars;   // 索引 i 对应输出类别 i+1
};

#endif // PPOCRRECOGNIZER_H
