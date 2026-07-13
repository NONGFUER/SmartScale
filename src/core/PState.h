#pragma once
#include <QString>
#include <QObject>

class PState : public QObject {
    Q_OBJECT
public:
    explicit PState(QObject *parent = nullptr) : QObject(parent) {}
    static PState& inst() { static PState s; return s; }

    // ---- QML 属性 ----
    Q_PROPERTY(QString IDLE      READ idle      CONSTANT)
    Q_PROPERTY(QString NOT_READY READ notReady CONSTANT)
    Q_PROPERTY(QString BUSY      READ busy      CONSTANT)
    Q_PROPERTY(QString UNKNOWN   READ unknown   CONSTANT)
    Q_PROPERTY(QString NONE      READ none      CONSTANT)

    QString idle()      const { return QStringLiteral("idle"); }
    QString notReady()  const { return QStringLiteral("not_ready"); }
    QString busy()      const { return QStringLiteral("busy"); }
    QString unknown()   const { return QStringLiteral("unknown"); }
    QString none()      const { return QStringLiteral("--"); }

    // ---- C++ 便捷静态常量 (PState::UNKNOWN) ----
    static inline const QString IDLE      = QStringLiteral("idle");
    static inline const QString NOT_READY = QStringLiteral("not_ready");
    static inline const QString BUSY      = QStringLiteral("busy");
    static inline const QString UNKNOWN   = QStringLiteral("unknown");
    static inline const QString NONE      = QStringLiteral("--");

    // ---- 方法 ----
    Q_INVOKABLE QString label(const QString &s) const {
        if (s == IDLE)                  return QStringLiteral("");
        if (s == NOT_READY)             return QStringLiteral("设备未就绪");
        if (s == UNKNOWN)               return QStringLiteral("--");
        if (s == NONE)                  return QStringLiteral("无识别结果");
        if (s == BUSY)                  return QStringLiteral("识别中...");
        return s;
    }
    Q_INVOKABLE bool isValid(const QString &s) const {
        return s != IDLE && s != NOT_READY && s != BUSY
            && s != UNKNOWN && s != NONE;
    }
};
