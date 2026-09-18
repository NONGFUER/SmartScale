#ifndef HANDWRITINGINPUTMETHOD_H
#define HANDWRITINGINPUTMETHOD_H

#include <QFutureWatcher>
#include <QList>
#include <QPointF>
#include <QString>
#include <QStringList>
#include <QVector>

#include "ai/PpocrRecognizer.h"

#include <QtVirtualKeyboard/qvirtualkeyboardabstractinputmethod.h>
#include <QtVirtualKeyboard/qvirtualkeyboardinputengine.h>
#include <QtVirtualKeyboard/qvirtualkeyboardselectionlistmodel.h>

QT_BEGIN_NAMESPACE
class QVirtualKeyboardInputContext;
class QVirtualKeyboardTrace;
QT_END_NAMESPACE

/**
 * @brief 手写输入法 — 接管 Qt 虚拟键盘手写模式的笔迹，用 PP-OCRv5 识别并落字
 *
 * 工作方式（复用 Qt 自带手写框架，无需改动任何业务输入框）：
 *   1. 键盘进入手写模式后加载 handwriting 布局，其中的 TraceInputKey 采集笔迹；
 *   2. 引擎把 traceBegin/traceEnd 回调给本输入法，本类收集 QVirtualKeyboardTrace 点集；
 *   3. 所有笔画结束后空闲 ~380ms 触发识别（工作线程跑 ONNX，避免阻塞 UI 与墨迹绘制）；
 *   4. 识别结果作为预编辑文本（下划线）显示，候选栏列出 top-5，点选即纠正；
 *   5. 用户继续写下一笔时自动提交上一字 —— 连续手写。
 *
 * 注意：继承 QVirtualKeyboardAbstractInputMethod 需要 Qt6::VirtualKeyboard（已安装）。
 */
class HandwritingInputMethod : public QVirtualKeyboardAbstractInputMethod
{
    Q_OBJECT

public:
    explicit HandwritingInputMethod(QObject *parent = nullptr);
    ~HandwritingInputMethod() override;

    // ---- QVirtualKeyboardAbstractInputMethod 接口 ----
    QList<QVirtualKeyboardInputEngine::InputMode> inputModes(const QString &locale) override;
    bool setInputMode(const QString &locale, QVirtualKeyboardInputEngine::InputMode inputMode) override;
    bool setTextCase(QVirtualKeyboardInputEngine::TextCase textCase) override;
    bool keyEvent(Qt::Key key, const QString &text, Qt::KeyboardModifiers modifiers) override;

    QList<QVirtualKeyboardSelectionListModel::Type> selectionLists() override;
    int selectionListItemCount(QVirtualKeyboardSelectionListModel::Type type) override;
    QVariant selectionListData(QVirtualKeyboardSelectionListModel::Type type, int index,
                               QVirtualKeyboardSelectionListModel::Role role) override;
    void selectionListItemSelected(QVirtualKeyboardSelectionListModel::Type type, int index) override;

    QList<QVirtualKeyboardInputEngine::PatternRecognitionMode> patternRecognitionModes() const override;
    QVirtualKeyboardTrace *traceBegin(
            int traceId, QVirtualKeyboardInputEngine::PatternRecognitionMode patternRecognitionMode,
            const QVariantMap &traceCaptureDeviceInfo, const QVariantMap &traceScreenInfo) override;
    bool traceEnd(QVirtualKeyboardTrace *trace) override;

    void reset() override;
    void update() override;

    /// 结束当前手写会话：提交未确认的预编辑文本并丢弃笔迹。
    /// 由 QML 在「切回普通键盘 / 收起全屏手写」前调用 —— 引擎切换输入法时不会通知旧输入法，
    /// 不显式提交会把最后那个还没确认的字丢掉。
    Q_INVOKABLE void finishInput();

protected:
    void timerEvent(QTimerEvent *event) override;

private:
    void scheduleRecognition();                     // 起表：等待笔画结束后识别
    void startRecognition();                        // 快照笔画 -> 投递工作线程
    void onRecognitionFinished();                   // 工作线程回调（主线程）
    void commitPending();                           // 提交当前预编辑 + 清候选
    void commitText(const QString &text);           // 直接落字
    void clearCandidates(bool notify);
    void clearTraces();
    void stopResultTimer();
    int countActiveTraces() const;
    QVector<QVector<QPointF>> collectStrokes() const;
    /// 按当前输入模式对备选候选**排序**（数字模式数字优先、拉丁模式 ASCII 优先）。
    /// 只调整顺序，**绝不丢弃候选**：手写时用户可能在任何语言/模式下书写，
    /// 硬过滤会出现"写对中文却什么也输不出来"或"被改写成游离数字"的离谱行为。
    void rankCandidatesByInputMode(QList<PpocrRecognizer::Candidate> *candidates) const;
    void notifyCandidates();
    bool publishCandidates(const QList<PpocrRecognizer::Candidate> &candidates,
                          bool allowCandidates);

    QList<QVirtualKeyboardTrace *> m_traces;    // 本字尚未识别的笔迹
    QStringList m_candidates;                   // 候选栏内容
    QString m_preeditText;                      // 当前预编辑（下划线）文本

    int m_resultTimer = 0;                      // 识别去抖定时器
    int m_activeCandidateIndex = -1;

    QFutureWatcher<QList<PpocrRecognizer::Candidate>> *m_watcher = nullptr;
    quint64 m_generation = 0;                   // 新笔画/重置时自增，用于丢弃过期结果
    quint64 m_inFlightGeneration = 0;
    bool m_recognitionPending = false;

    QVirtualKeyboardInputEngine::InputMode m_inputMode =
            QVirtualKeyboardInputEngine::InputMode::ChineseHandwriting;
};

#endif // HANDWRITINGINPUTMETHOD_H
