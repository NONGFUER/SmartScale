#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <Qt>
#include <QQmlContext>

// 硬件层
#include "hardware/WeightSensor.h"
#include "hardware/CameraController.h"

// AI 层
#include "ai/VisionAIService.h"

// 工具层
#include "utils/FoodTranslator.h"
#include "hardware/VoiceSpeaker.h"

// 业务层 (已接入 Repository)
#include "services/AuthService.h"
#include "services/WeightHistoryService.h"

// 数据层
#include "data/DatabaseManager.h"
#include "data/repositories/WeightRecordRepo.h"
#include "data/repositories/UserRepo.h"

int main(int argc, char *argv[])
{
    // 虚拟键盘配置 - 严格限制只显示中英文
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));
    qputenv("QT_VIRTUALKEYBOARD_LAYOUTS", "zh_CN;en_GB");
    qputenv("QT_VIRTUALKEYBOARD_DEFAULT_LOCALE", "zh_CN");
    qputenv("QT_VIRTUALKEYBOARD_AVAILABLE_LOCALES", "zh_CN;en_GB");
    qputenv("QT_VIRTUALKEYBOARD_STYLE", "default");
    qputenv("QT_VIRTUALKEYBOARD_LANGUAGE_FILTER", "zh-CN,en-GB");
    qputenv("QT_VIRTUALKEYBOARD_DISABLE", "0");
    qputenv("QT_MEDIA_BACKEND", "ffmpeg");

    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;

    // ============================================================
    // 1. 初始化数据库 (必须在所有 Service 之前)
    // ============================================================
    auto &dbMgr = DatabaseManager::instance();
    if (!dbMgr.initialize("data/smartscale.db")) {
        qCritical() << "数据库初始化失败，程序无法启动";
        return -1;
    }

    // ============================================================
    // 2. 创建 Repository 层 (生命周期由 main 管理)
    // ============================================================
    WeightRecordRepo *weightRecordRepo = new WeightRecordRepo(dbMgr, &app);
    UserRepo *userRepo = new UserRepo(dbMgr, &app);

    // ============================================================
    // 3. 创建业务层 Service / Hardware Controller，注入 Repository
    // ============================================================
    AuthService *authService = new AuthService(&app);
    authService->setUserRepo(userRepo);  // 注入离线登录支持
    WeightSensor *weightSensor = new WeightSensor(&app);
    CameraController *cameraController = new CameraController(&app);
    WeightHistoryService *historyService = new WeightHistoryService(weightRecordRepo, &app);
    VoiceSpeaker *voiceSpeaker = new VoiceSpeaker(&app);

    // 语音播报注入 CameraController，AI推理完成后直接播报（省掉QML往返）
    cameraController->setVoiceSpeaker(voiceSpeaker);
    // 登录用户信息注入 CameraController（水印中显示操作员）
    cameraController->setAuthService(authService);

    // 注入 AuthService 给 HistoryService（云同步需要 token/userId）
    historyService->setAuthService(authService);

    // 从 CameraController 中借出 AI 服务指针，准备注册给前端
    VisionAIService *aiService = cameraController->aiService();

    // ============================================================
    // 4. 注入到 QML 全局环境
    // ============================================================
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "WeightManager", weightSensor);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "CameraController", cameraController);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "BackendAuth", authService);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "VisionAI", aiService);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "WeightHistoryService", historyService);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "VoiceSpeaker", voiceSpeaker);
    qmlRegisterSingletonInstance<FoodTranslator>("SmartScale.Tools", 1, 0, "Translator", FoodTranslator::instance());

    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
        
    // 确保程序退出时安全关闭数据库
    QObject::connect(&app, &QCoreApplication::aboutToQuit, [&dbMgr]() {
        dbMgr.close();
    });
    engine.loadFromModule("SmartScale", "Main");

    return QCoreApplication::exec();
}
