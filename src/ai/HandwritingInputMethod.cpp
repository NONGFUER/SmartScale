#include "HandwritingInputMethod.h"

#include <QDebug>
#include <QTimerEvent>
#include <QtConcurrent/QtConcurrentRun>

#include <algorithm>    // std::stable_sort

#include <QtVirtualKeyboard/qvirtualkeyboardinputcontext.h>
#include <QtVirtualKeyboard/qvirtualkeyboardtrace.h>

namespace {

// 笔画结束后的识别去抖时长（ms）：短于手指停顿间隔，长于多笔画字的书写间隔
constexpr int kStrokeIdleTimeoutMs = 380;
// 候选栏候选数量（手写体的正确字常常不在第 1 位，候选给足便于纠正）
constexpr int kMaxCandidates = 8;

} // namespace

HandwritingInputMethod::HandwritingInputMethod(QObject *parent)
    : QVirtualKeyboardAbstractInputMethod(parent)
{
    m_watcher = new QFutureWatcher<QList<PpocrRecognizer::Candidate>>(this);
    connect(m_watcher, &QFutureWatcherBase::finished,
            this, &HandwritingInputMethod::onRecognitionFinished);

    // 预热识别引擎：放到工作线程加载模型，避免阻塞 UI 启动
    (void)QtConcurrent::run([]() {
        PpocrRecognizer::instance()->warmup();
    });
    qInfo() << "[HWR] 手写输入法就绪 (PP-OCRv5)";
}

HandwritingInputMethod::~HandwritingInputMethod()
{
    clearTraces();
}

// ============================================================
//  输入模式
// ============================================================
QList<QVirtualKeyboardInputEngine::InputMode> HandwritingInputMethod::inputModes(const QString &locale)
{
    QList<QVirtualKeyboardInputEngine::InputMode> modes;
    if (locale.startsWith(QLatin1String("zh"), Qt::CaseInsensitive)) {
        modes << QVirtualKeyboardInputEngine::InputMode::ChineseHandwriting;
    }
    modes << QVirtualKeyboardInputEngine::InputMode::Latin
          << QVirtualKeyboardInputEngine::InputMode::Numeric
          << QVirtualKeyboardInputEngine::InputMode::Dialable;
    // 非中文 locale 也提供中文手写兜底：否则在英文键盘下用户无法切换到中文手写模式
    // （识别本身与 locale 无关，PP-OCRv5 中英数字通吃）
    if (!locale.startsWith(QLatin1String("zh"), Qt::CaseInsensitive))
        modes << QVirtualKeyboardInputEngine::InputMode::ChineseHandwriting;
    return modes;
}

bool HandwritingInputMethod::setInputMode(const QString &locale,
                                          QVirtualKeyboardInputEngine::InputMode inputMode)
{
    Q_UNUSED(locale)
    commitPending();
    m_inputMode = inputMode;
    qDebug() << "[HWR] 输入模式切换:" << static_cast<int>(inputMode);
    return true;
}

bool HandwritingInputMethod::setTextCase(QVirtualKeyboardInputEngine::TextCase textCase)
{
    Q_UNUSED(textCase)
    return true;
}

// ============================================================
//  按键
// ============================================================
bool HandwritingInputMethod::keyEvent(Qt::Key key, const QString &text, Qt::KeyboardModifiers modifiers)
{
    Q_UNUSED(modifiers)

    switch (key) {
    case Qt::Key_Backspace:
        if (!m_preeditText.isEmpty()) {
            m_preeditText.chop(1);
            if (m_preeditText.isEmpty()) {
                clearCandidates(true);
            } else if (QVirtualKeyboardInputContext *ic = inputContext()) {
                ic->setPreeditText(m_preeditText);
            }
            return true;                       // 已消费：删除未确认的识别结果
        }
        return false;                          // 无预编辑 -> 交给引擎删除正文
    case Qt::Key_Enter:
    case Qt::Key_Return:
    case Qt::Key_Tab:
    case Qt::Key_Space:
        commitPending();
        return false;                          // 回车/空格交由应用处理
    default:
        commitPending();
        return false;                          // 标点等可打印字符交由引擎插入
    }
}

// ============================================================
//  候选栏
// ============================================================
QList<QVirtualKeyboardSelectionListModel::Type> HandwritingInputMethod::selectionLists()
{
    return QList<QVirtualKeyboardSelectionListModel::Type>()
            << QVirtualKeyboardSelectionListModel::Type::WordCandidateList;
}

int HandwritingInputMethod::selectionListItemCount(QVirtualKeyboardSelectionListModel::Type type)
{
    Q_UNUSED(type)
    return m_candidates.size();
}

QVariant HandwritingInputMethod::selectionListData(QVirtualKeyboardSelectionListModel::Type type,
                                                   int index,
                                                   QVirtualKeyboardSelectionListModel::Role role)
{
    if (index < 0 || index >= m_candidates.size())
        return QVariant();

    switch (role) {
    case QVirtualKeyboardSelectionListModel::Role::Display:
        return QVariant(m_candidates.at(index));
    case QVirtualKeyboardSelectionListModel::Role::WordCompletionLength:
        return QVariant(0);
    case QVirtualKeyboardSelectionListModel::Role::Dictionary:
        return QVariant(static_cast<int>(QVirtualKeyboardSelectionListModel::DictionaryType::Default));
    case QVirtualKeyboardSelectionListModel::Role::CanRemoveSuggestion:
        return QVariant(false);
    default:
        return QVirtualKeyboardAbstractInputMethod::selectionListData(type, index, role);
    }
}

void HandwritingInputMethod::selectionListItemSelected(QVirtualKeyboardSelectionListModel::Type type,
                                                       int index)
{
    Q_UNUSED(type)
    if (index < 0 || index >= m_candidates.size())
        return;

    const QString selected = m_candidates.at(index);
    qDebug() << "[HWR] 用户选择候选:" << selected;
    commitText(selected);
    m_preeditText.clear();
    clearCandidates(true);
}

void HandwritingInputMethod::notifyCandidates()
{
    m_activeCandidateIndex = m_candidates.isEmpty() ? -1 : 0;
    Q_EMIT selectionListChanged(QVirtualKeyboardSelectionListModel::Type::WordCandidateList);
    Q_EMIT selectionListActiveItemChanged(QVirtualKeyboardSelectionListModel::Type::WordCandidateList,
                                         m_activeCandidateIndex);
}

void HandwritingInputMethod::clearCandidates(bool notify)
{
    const bool had = !m_candidates.isEmpty();
    m_candidates.clear();
    m_activeCandidateIndex = -1;
    if (had && notify)
        notifyCandidates();
}

// ============================================================
//  笔迹采集
// ============================================================
QList<QVirtualKeyboardInputEngine::PatternRecognitionMode> HandwritingInputMethod::patternRecognitionModes() const
{
    return QList<QVirtualKeyboardInputEngine::PatternRecognitionMode>()
            << QVirtualKeyboardInputEngine::PatternRecognitionMode::Handwriting;
}

QVirtualKeyboardTrace *HandwritingInputMethod::traceBegin(
        int traceId, QVirtualKeyboardInputEngine::PatternRecognitionMode patternRecognitionMode,
        const QVariantMap &traceCaptureDeviceInfo, const QVariantMap &traceScreenInfo)
{
    Q_UNUSED(traceId)
    Q_UNUSED(patternRecognitionMode)
    Q_UNUSED(traceCaptureDeviceInfo)
    Q_UNUSED(traceScreenInfo)

    // 上一字尚未确认（预编辑/候选在屏）时，新笔画立即落字 —— 连续手写
    if (!m_preeditText.isEmpty() || !m_candidates.isEmpty())
        commitPending();

    // 新一轮笔迹：丢弃在途识别结果并停表
    ++m_generation;
    stopResultTimer();

    auto *trace = new QVirtualKeyboardTrace(this);
    trace->setChannels(QStringList() << QStringLiteral("t"));   // 记录每点时间（可选，TraceInputArea 会填）
    m_traces.append(trace);

    return trace;
}

bool HandwritingInputMethod::traceEnd(QVirtualKeyboardTrace *trace)
{
    if (!trace)
        return false;

    if (trace->isCanceled()) {
        m_traces.removeOne(trace);
        trace->deleteLater();
        return true;
    }

    // 所有笔画都结束 -> 起表等待识别
    if (countActiveTraces() == 0)
        scheduleRecognition();

    return true;
}

int HandwritingInputMethod::countActiveTraces() const
{
    int count = 0;
    for (QVirtualKeyboardTrace *trace : m_traces) {
        if (!trace->isFinal())
            ++count;
    }
    return count;
}

QVector<QVector<QPointF>> HandwritingInputMethod::collectStrokes() const
{
    QVector<QVector<QPointF>> strokes;
    strokes.reserve(m_traces.size());
    for (QVirtualKeyboardTrace *trace : m_traces) {
        QVector<QPointF> stroke;
        const QVariantList points = trace->points(0, -1);
        stroke.reserve(points.size());
        for (const QVariant &point : points) {
            if (point.canConvert<QPointF>())
                stroke.append(point.toPointF());
        }
        if (!stroke.isEmpty())
            strokes.append(stroke);
    }
    return strokes;
}

void HandwritingInputMethod::clearTraces()
{
    for (QVirtualKeyboardTrace *trace : m_traces)
        trace->deleteLater();       // 删除 trace 即清除对应墨迹
    m_traces.clear();
}

void HandwritingInputMethod::stopResultTimer()
{
    if (m_resultTimer) {
        killTimer(m_resultTimer);
        m_resultTimer = 0;
    }
}

void HandwritingInputMethod::scheduleRecognition()
{
    stopResultTimer();
    m_resultTimer = startTimer(kStrokeIdleTimeoutMs);
}

// ============================================================
//  识别流程
// ============================================================
void HandwritingInputMethod::timerEvent(QTimerEvent *event)
{
    if (event->timerId() != m_resultTimer) {
        QVirtualKeyboardAbstractInputMethod::timerEvent(event);
        return;
    }
    stopResultTimer();
    startRecognition();
}

void HandwritingInputMethod::startRecognition()
{
    const QVector<QVector<QPointF>> strokes = collectStrokes();
    if (strokes.isEmpty())
        return;

    if (m_recognitionPending) {
        qDebug() << "[HWR] 上一次识别尚未返回，跳过本次";
        return;
    }

    // 墨迹在识别开始时就清除：避免用户抢写下一笔时新旧笔画混在一起
    clearTraces();

    m_recognitionPending = true;
    m_inFlightGeneration = m_generation;
    qDebug() << "[HWR] 提交识别, 笔画数:" << strokes.size();

    m_watcher->setFuture(QtConcurrent::run([strokes]() {
        // 多参数融合识别（细/中/粗笔宽各一次），提高手写体的鲁棒性
        return PpocrRecognizer::instance()->recognizeStrokesEnsemble(strokes, kMaxCandidates);
    }));
}

void HandwritingInputMethod::onRecognitionFinished()
{
    m_recognitionPending = false;

    QList<PpocrRecognizer::Candidate> candidates = m_watcher->result();

    // 用户已开始写下一笔：本结果直接落字，不做预编辑/候选
    if (m_inFlightGeneration != m_generation) {
        if (!candidates.isEmpty())
            commitText(candidates.first().text);
        return;
    }

    if (candidates.isEmpty()) {
        qDebug() << "[HWR] 未识别出结果";
        return;
    }

    // 模式只影响备选排序，首选结果与候选集合都不会被丢弃
    rankCandidatesByInputMode(&candidates);
    publishCandidates(candidates, candidates.first().text.size() == 1);
}

bool HandwritingInputMethod::publishCandidates(const QList<PpocrRecognizer::Candidate> &candidates,
                                               bool allowCandidates)
{
    if (candidates.isEmpty())
        return false;

    clearCandidates(false);
    if (allowCandidates) {
        for (const PpocrRecognizer::Candidate &candidate : candidates)
            m_candidates << candidate.text;
    } else {
        m_candidates << candidates.first().text;
    }

    m_preeditText = m_candidates.first();
    if (QVirtualKeyboardInputContext *ic = inputContext())
        ic->setPreeditText(m_preeditText);
    notifyCandidates();

    // 日志带上模式/hints/locale：手写"输出不了"多数是模式与 locale 组合引起
    Qt::InputMethodHints hints = Qt::ImhNone;
    QString locale;
    if (QVirtualKeyboardInputContext *ic = inputContext()) {
        hints = ic->inputMethodHints();
        locale = ic->locale();
    }
    qDebug() << "[HWR] 预编辑:" << m_preeditText << "候选:" << m_candidates
             << "模式:" << static_cast<int>(m_inputMode)
             << "hints:" << static_cast<int>(hints)
             << "locale:" << locale;
    return true;
}

void HandwritingInputMethod::rankCandidatesByInputMode(QList<PpocrRecognizer::Candidate> *candidates) const
{
    if (!candidates || candidates->size() < 2)
        return;

    const auto mode = m_inputMode;
    const bool numericMode = (mode == QVirtualKeyboardInputEngine::InputMode::Numeric
                              || mode == QVirtualKeyboardInputEngine::InputMode::Dialable);
    const bool latinMode = (mode == QVirtualKeyboardInputEngine::InputMode::Latin);
    if (!numericMode && !latinMode)
        return;     // 中文手写模式：保持识别顺序

    auto rank = [latinMode](const QString &text) -> int {
        if (text.isEmpty())
            return 0;
        if (latinMode) {
            for (const QChar &ch : text) {
                if (ch.unicode() > 127)
                    return 0;       // 含非 ASCII -> 排后面（但不丢弃）
            }
            return 2;
        }
        bool hasDigit = false;
        for (const QChar &ch : text) {
            if (ch.isDigit()) {
                hasDigit = true;
                continue;
            }
            if (ch != QLatin1Char('.') && ch != QLatin1Char('-'))
                return hasDigit ? 1 : 0;
        }
        return hasDigit ? 2 : 0;
    };

    // 首选（CTC 最优路径结果 = 真正的识别结果）保持不动，只调整其后备选顺序
    std::stable_sort(candidates->begin() + 1, candidates->end(),
                     [&rank](const PpocrRecognizer::Candidate &a, const PpocrRecognizer::Candidate &b) {
                         return rank(a.text) > rank(b.text);
                     });
}

// ============================================================
//  生命周期
// ============================================================
void HandwritingInputMethod::commitPending()
{
    if (!m_preeditText.isEmpty()) {
        if (QVirtualKeyboardInputContext *ic = inputContext())
            ic->commit();               // 提交当前预编辑文本
    }
    m_preeditText.clear();
    clearCandidates(true);
}

void HandwritingInputMethod::commitText(const QString &text)
{
    if (text.isEmpty())
        return;
    if (QVirtualKeyboardInputContext *ic = inputContext())
        ic->commit(text);
}

void HandwritingInputMethod::reset()
{
    ++m_generation;                     // 丢弃在途识别结果
    m_recognitionPending = false;
    stopResultTimer();
    commitPending();
    clearTraces();
}

void HandwritingInputMethod::update()
{
    commitPending();
}

void HandwritingInputMethod::finishInput()
{
    commitPending();
    clearTraces();
}
