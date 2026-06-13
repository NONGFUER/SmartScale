#ifndef VISIONAISERVICE_H
#define VISIONAISERVICE_H

#include <QObject>
#include <QImage>
#include <QStringList>
#include <vector>
#include <memory>
#include <string>
#include <onnxruntime_cxx_api.h>

class VisionAIService : public QObject
{
    Q_OBJECT

public:
    explicit VisionAIService(QObject *parent = nullptr);
    ~VisionAIService() override;

    // 核心功能
    QString predict(const QImage &img);

    // QML 交互支持 (暴露给前端纠错使用)
    Q_INVOKABLE QStringList getLabels() const;
    Q_INVOKABLE void submitCorrection(const QString& originalImagePath, 
                                      const QString& wrongPrediction, 
                                      const QString& correctLabel);

private:
    void initModel();
    std::vector<float> preprocessImage(const QImage &img);

private:
    Ort::Env m_env;
    std::unique_ptr<Ort::Session> m_session;
    QStringList m_labels;

    // 【性能优化】：将输入输出节点名称缓存下来，避免在推理循环中动态分配内存
    std::string m_inputName;
    std::string m_outputName;
};

#endif // VISIONAISERVICE_H
