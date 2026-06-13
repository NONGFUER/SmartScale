#include "VisionAIService.h"
#include <QCoreApplication>
#include <QFile>
#include <QDir>
#include <QDebug>
#include <algorithm>
#include <cmath>
#include <vector>

namespace {
    //先做Softmax归一化，再找最大概率的索引
    int getPredictionIndex(const std::vector<float>& logits, float threshold)
    {
        // 1. 打印输入参数
        qInfo() << "[Debug] Input threshold:" << threshold;
        qInfo() << "[Debug] Logits size:" << logits.size();
        
        if (logits.empty()) {
            qWarning() << "[Debug] Logits is empty, returning -1";
            return -1;
        }

        // 数值稳定性处理：找最大值用于数值稳定
        float maxLogit = *std::max_element(logits.begin(), logits.end());
        qInfo() << "[Debug] Max Logit (for stability):" << maxLogit;

        // 计算 softmax 分母
        float sum = 0.0f;
        for (size_t i = 0; i < logits.size(); ++i) {
            float v = logits[i];
            float expVal = std::exp(v - maxLogit);
            sum += expVal;
            // 可选：如果 logits 数量不多，可以打印每个指数的值，否则日志会非常多
             qInfo() << "[Debug] Logits[" << i << "]:" << v << " -> exp:" << expVal;
        }
        qInfo() << "[Debug] Softmax Sum (Denominator):" << sum;

        // 计算每个类别的概率
        std::vector<float> probs;
        probs.reserve(logits.size());
        for (float v : logits) {
            float prob = std::exp(v - maxLogit) / sum;
            probs.push_back(prob);
        }

        // 找最大概率及索引
        auto it = std::max_element(probs.begin(), probs.end());
        float maxProb = *it;
        int index = static_cast<int>(std::distance(probs.begin(), it));     //等价于max_it - output_data

        qInfo() << "[Debug] Max Probability:" << maxProb << " at Index:" << index;

        // 阈值判断
        if (maxProb < threshold) {
            qInfo() << "[Debug] Max Prob (" << maxProb << ") < Threshold (" << threshold << "), returning -1";
            return -1;
        } else {
            qInfo() << "[Debug] Prediction successful. Index:" << index;
            return index;
        }
    }
}// namespace

VisionAIService::VisionAIService(QObject *parent)
    : QObject(parent), m_env(ORT_LOGGING_LEVEL_WARNING, "VisionAIService")
{
    initModel();
}

VisionAIService::~VisionAIService()
{
}

void VisionAIService::initModel()
{
    QString basePath = QCoreApplication::applicationDirPath() + "/AI/";
    QString modelPath = basePath + "mobilenetv3_food.onnx";
    QString labelPath = basePath + "labels.txt";

    if (!QFile::exists(modelPath) || !QFile::exists(labelPath)) {
        qCritical() << "[Vision AI 致命错误] 找不到模型或标签文件！";
        qCritical() << "请检查路径是否正确:" << basePath;
        return;
    }
    qInfo() << "[Vision AI] 正在从以下路径加载模型:" << modelPath;

    // 1. 加载标签
    QFile file(labelPath);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&file);
        while (!in.atEnd()) {
            QString line = in.readLine().trimmed();
            if (!line.isEmpty()) m_labels.append(line);
        }
        file.close();
    } else {
        qWarning() << "[Vision AI] 获取分类标签失败，请检查路径:" << labelPath;
    }

    // 2. 初始化 ONNX Session
    try {
        Ort::SessionOptions session_options;
        session_options.SetIntraOpNumThreads(2); // 限制线程数防设备发热
        session_options.SetGraphOptimizationLevel(GraphOptimizationLevel::ORT_ENABLE_ALL);

        m_session = std::make_unique<Ort::Session>(m_env, modelPath.toStdString().c_str(), session_options);

        // 3. 【优化核心】在实例化时一次性获取节点名称并缓存，杜绝内存碎片
        Ort::AllocatorWithDefaultOptions allocator;
        m_inputName = m_session->GetInputNameAllocated(0, allocator).get();
        m_outputName = m_session->GetOutputNameAllocated(0, allocator).get();

        qInfo() << "[Vision AI] MobileNet 模型已加载完毕, 就绪等候。";
    } catch (const Ort::Exception& e) {
        qCritical() << "[Vision AI] 模型加载异常:" << e.what();
    }
}

std::vector<float> VisionAIService::preprocessImage(const QImage &img)
{
    // NCHW 预处理逻辑 (与之前相同)
    QImage scaled = img.scaled(224, 224, Qt::IgnoreAspectRatio).convertToFormat(QImage::Format_RGB888);
    std::vector<float> data(1 * 3 * 224 * 224);
    
    const float mean[3] = {0.485f, 0.456f, 0.406f};
    const float std_dev[3]  = {0.229f, 0.224f, 0.225f};

    for (int y = 0; y < 224; ++y) {
        const uchar* row = scaled.scanLine(y);
        for (int x = 0; x < 224; ++x) {
            for (int c = 0; c < 3; ++c) {
                float val = row[x * 3 + c] / 255.0f;
                data[c * 224 * 224 + y * 224 + x] = (val - mean[c]) / std_dev[c];
            }
        }
    }
    return data;
}

/*
功能：将模型输出的原始分数(Logits)转换为概率，并找出概率最高的类别，同时增加一个"置信度阈值"判断
*/
QString VisionAIService::predict(const QImage &img)
{
    if (!m_session || m_labels.isEmpty()) return "AI未就绪";

    auto input_tensor_values = preprocessImage(img);
    std::vector<int64_t> input_shape = {1, 3, 224, 224};

    Ort::MemoryInfo memory_info = Ort::MemoryInfo::CreateCpu(OrtArenaAllocator, OrtMemTypeDefault);
    Ort::Value input_tensor = Ort::Value::CreateTensor<float>(
        memory_info, input_tensor_values.data(), input_tensor_values.size(),
        input_shape.data(), input_shape.size()
    );

    // 直接使用缓存的指针，极致极速
    const char* input_names[] = { m_inputName.c_str() };
    const char* output_names[] = { m_outputName.c_str() };

    //ONNX推理:
    auto output_tensors = m_session->Run(
        Ort::RunOptions{nullptr},
        input_names, &input_tensor, 1,
        output_names, 1
    );
    //原始数据指针与长度
    float* output_data = output_tensors.front().GetTensorMutableData<float>();
    size_t output_size = output_tensors.front().GetTensorTypeAndShapeInfo().GetElementCount();
    // 将原始输出复制到 vector
    std::vector<float> logits(output_data, output_data + output_size);

    // 明确指针减法得到的是 ptrdiff_t，再转为 int
    //auto max_it = std::max_element(output_data, output_data + output_size);
    //int max_index = static_cast<int>(max_it - output_data);
    int max_index = getPredictionIndex(logits, 0.5f); // 阈值：0.5→0.35→0.2，进一步放宽
    //
    if (max_index != -1 && max_index < m_labels.size()) {
        return m_labels[max_index];
    }

    //直接找原始分数最大值的索引
    // int max_index = std::max_element(output_data, output_data + output_size) - output_data;

    // if (max_index < m_labels.size()) {
    //     return m_labels[max_index];
    // }
    return "未知物品";
}

QStringList VisionAIService::getLabels() const {
    return m_labels;
}

void VisionAIService::submitCorrection(const QString& originalImagePath, const QString& wrongPrediction, const QString& correctLabel)
{
    qDebug() << "[AI 数据反馈] 用户纠错触发! 误判:" << wrongPrediction << " 正确:" << correctLabel;
#if 0
    QDir errorDir(QCoreApplication::applicationDirPath() + "/ErrorDataset/" + correctLabel);
    if (!errorDir.exists()) errorDir.mkpath(".");

    QFile file(originalImagePath);
    QString newFileName = errorDir.absolutePath() + "/" + QFileInfo(originalImagePath).fileName();
    
    if (file.copy(newFileName)) {
        qInfo() << "[AI 数据反馈] 已回收至分类纠错库:" << newFileName;
    }
#endif
}
