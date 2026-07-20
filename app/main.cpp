#include <QGuiApplication>
#include <QCursor>
#include <QQmlApplicationEngine>
#include <Qt>
#include <QQmlContext>

// 日志落盘
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QMutex>
#include <QDir>
#include <QFileInfo>
#include <QTimer>
#include <QProcess>
#include <QFont>
#include <QFontDatabase>
#include <cstdio>

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
#include "services/CategoryService.h"
#include "services/UserIngredientService.h"   // USER 域食材服务
#include "services/SystemInfoService.h"       // [测试] 系统调试信息服务
#include "services/AppSettingsService.h"      // 应用设置（价格输入开关等）
#include "services/NetworkManagerService.h"   // 网络管理服务 (WiFi + 4G)
#include "services/MqttClientService.h"           // MQTT 客户端服务
#include "services/CellularModemService.h"        // 蜂窝模组 CCID(ICCID) 获取 (AT 指令)

// 数据层
#include "data/DatabaseManager.h"
#include "data/repositories/WeightRecordRepo.h"
#include "data/repositories/UserRepo.h"
#include "core/PState.h"

// ============================================================================
// 日志：同时输出到控制台(stderr) 与 data/smartscale.log（带时间+级别）
// ============================================================================
static QFile  g_logFile;
static QMutex g_logMutex;

static void smartScaleMessageHandler(QtMsgType type,
                                     const QMessageLogContext &ctx,
                                     const QString &msg)
{
    // 过滤 qt6ct 平台主题插件的调试噪音（palette() 被反复请求刷屏）
    if (msg.contains("Qt6CTPlatformTheme"))
        return;

    QString level;
    switch (type) {
    case QtDebugMsg:    level = "DEBUG"; break;
    case QtInfoMsg:     level = "INFO";  break;
    case QtWarningMsg:  level = "WARN";  break;
    case QtCriticalMsg: level = "CRIT";  break;
    case QtFatalMsg:    level = "FATAL"; break;
    default:            level = "???";   break;
    }
    const QString text = QString("[%1] %2: %3")
        .arg(QDateTime::currentDateTime().toString("yyyy-MM-dd HH:mm:ss.zzz"))
        .arg(level)
        .arg(msg);

    // 1) 控制台（保持原有行为）
    fprintf(stderr, "%s\n", qPrintable(text));
    fflush(stderr);

    // 2) 文件（线程安全）
    QMutexLocker locker(&g_logMutex);
    if (g_logFile.isOpen()) {
        QTextStream ts(&g_logFile);
        ts << text << Qt::endl;
    }
}

int main(int argc, char *argv[])
{
    // 接管 Qt 日志输出
    qInstallMessageHandler(smartScaleMessageHandler);

    // 虚拟键盘配置
    // 注意：Debian 13 的 Qt6 VirtualKeyboard 不打包 Pinyin 插件，
    // 触摸屏键盘只能输入英文/数字/符号，无法输入中文（除非自编译 Pinyin 插件）。
    qputenv("QT_IM_MODULE", QByteArray("qtvirtualkeyboard"));
    qputenv("QT_VIRTUALKEYBOARD_STYLE", "light");  // light 纯白明亮风格（自定义样式 src/ui/vkbdstyle/light/style.qml，经 app.qrc alias 嵌入）
    qputenv("QT_MEDIA_BACKEND", "ffmpeg");

    QGuiApplication app(argc, argv);

    // 注册内嵌 PingFang SC 字体（Linux 主板无此字体，必须打包 + 运行时注册）
    {
        QFile fontFile(":/resources/fonts/PingFangSC-Regular.ttf");
        if (fontFile.open(QIODevice::ReadOnly)) {
            const int fontId = QFontDatabase::addApplicationFontFromData(fontFile.readAll());
            if (fontId == -1)
                qWarning() << "[Main] PingFang SC 字体加载失败，将 fallback 到系统默认字体";
            else
                qInfo() << "[Main] 已注册字体族:" << QFontDatabase::applicationFontFamilies(fontId);
        } else {
            qWarning() << "[Main] 无法打开字体资源文件，将 fallback 到系统默认字体";
        }
    }

    // 注册内嵌 DIN Bold 字体（用于称重数值显示）
    {
        QFile dinFile(":/resources/fonts/din-bold-2.ttf");
        if (dinFile.open(QIODevice::ReadOnly)) {
            const int dinId = QFontDatabase::addApplicationFontFromData(dinFile.readAll());
            if (dinId == -1)
                qWarning() << "[Main] DIN 字体加载失败，称重数值将 fallback 到系统默认字体";
            else
                qInfo() << "[Main] 已注册字体族:" << QFontDatabase::applicationFontFamilies(dinId);
        } else {
            qWarning() << "[Main] 无法打开 DIN 字体资源文件";
        }
    }

    // 注册内嵌 Alimama ShuHeiTi 字体（用于状态栏大标题）
    {
        QFile titleFile(":/resources/fonts/AlimamaShuHeiTi-Bold.ttf");
        if (titleFile.open(QIODevice::ReadOnly)) {
            const int titleId = QFontDatabase::addApplicationFontFromData(titleFile.readAll());
            if (titleId == -1)
                qWarning() << "[Main] Alimama ShuHeiTi 字体加载失败，大标题将 fallback 到系统默认字体";
            else
                qInfo() << "[Main] 已注册字体族:" << QFontDatabase::applicationFontFamilies(titleId);
        } else {
            qWarning() << "[Main] 无法打开 Alimama ShuHeiTi 字体资源文件";
        }
    }

    // 全局默认字体：所有未显式指定 font.family 的 QML 文本都会继承此字体族
    QFont defaultFont("PingFang SC");
    defaultFont.setPixelSize(30);   // 默认字号兜底，可按需调整
    app.setFont(defaultFont);

    // 打开日志文件：写到可执行文件目录的 data/smartscale.log（超过 2MB 自动截断）
    {
        const QString logPath = QCoreApplication::applicationDirPath()
                                + "/data/smartscale.log";
        QDir().mkpath(QFileInfo(logPath).absolutePath());
        g_logFile.setFileName(logPath);
        QIODevice::OpenMode mode = QIODevice::WriteOnly | QIODevice::Text;
        mode |= (QFile::exists(logPath) && QFile(logPath).size() > 2 * 1024 * 1024)
                ? QIODevice::Truncate
                : QIODevice::Append;
        if (!g_logFile.open(mode))
            qWarning() << "[Main] 无法打开日志文件:" << logPath;
        else
            qInfo() << "[Main] 日志文件:" << logPath;
    }

    // 触摸屏环境：全局隐藏鼠标光标
    QGuiApplication::setOverrideCursor(QCursor(Qt::BlankCursor));

    QQmlApplicationEngine engine;

    // ============================================================
    // 1. 初始化数据库 (必须在所有 Service 之前)
    // ============================================================
    auto &dbMgr = DatabaseManager::instance();
    QString dbPath = QCoreApplication::applicationDirPath() + "/data/smartscale.db";
    if (!dbMgr.initialize(dbPath)) {
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
    CategoryService *categoryService = new CategoryService(&app);
    UserIngredientService *userIngredientService = new UserIngredientService(&app);
    VoiceSpeaker *voiceSpeaker = new VoiceSpeaker(&app);

    // [测试] 系统调试信息服务 — 记录重启次数、开机/关机时间
    SystemInfoService *systemInfoService = new SystemInfoService(&app);

    // 应用设置服务 — 用户可配置开关（价格输入等），QSettings 持久化
    AppSettingsService *appSettings = new AppSettingsService(&app);

    // 网络管理服务 — Wi-Fi 扫描/连接/断开 + 4G 开启/关闭
    NetworkManagerService *networkManagerService = new NetworkManagerService(&app);

    // 4G 开关重启记忆：上次关机前用户关闭了 4G，则本次启动后自动禁用以恢复状态。
    // 延迟 3 秒执行：等 NetworkManagerService 构造里的首轮 refresh 完成、
    // 4G 硬件被发现（hasCellularHardware=true）后再下发禁用，避免对不存在的接口空操作。
    if (!appSettings->cellularEnabled()) {
        QTimer::singleShot(3000, networkManagerService, [networkManagerService]() {
            if (networkManagerService->hasCellularHardware()) {
                qInfo() << "[Main] 恢复 4G 记忆状态: 上次为关闭，自动禁用 4G";
                networkManagerService->disableCellular();
            } else {
                qInfo() << "[Main] 恢复 4G 记忆状态: 未检测到 4G 硬件，跳过自动禁用";
            }
        });
    }

    // MQTT 客户端服务 — 设备信息上报 (mqtts://user.shxgs.cn:8888)
    MqttClientService *mqttClientService = new MqttClientService(&app);

    // 蜂窝模组服务 — 遍历 /dev/ttyUSB* 发送 AT 指令动态确认端口并读取 CCID(ICCID)
    CellularModemService *cellularModemService = new CellularModemService(&app);

    // 语音播报注入 CameraController，AI推理完成后直接播报（省掉QML往返）
    cameraController->setVoiceSpeaker(voiceSpeaker);
    // 登录用户信息注入 CameraController（水印中显示操作员）
    cameraController->setAuthService(authService);

    // === 设备序列号注入 ===
    authService->setDeviceSn(weightSensor->sn());          // 初始值（可能为空，异步读取后会更新）
    cameraController->setWeightSensor(weightSensor);        // CameraController 直接访问 WeightSensor

    // === 食材服务注入 AuthService（登录成功后统一调度拉取）===
    authService->setIngredientService(userIngredientService);

    // SN 异步读取完成后同步更新 AuthService
    QObject::connect(weightSensor, &WeightSensor::snChanged,
                     authService, [authService, weightSensor]() {
                         authService->setDeviceSn(weightSensor->sn());
                     });

    // === 设备信息上报：SN 与 custId 到达顺序不确定，任一就绪后都尝试补发 ===
    // 登录(后端返回 custId) 可能早于 SN 串口读取完成，或反之。
    // 抽成 lambda 供两个信号共用：两者都齐了才上报，并打印日志定位缺了哪个。
    auto tryPublishDeviceInfo = [mqttClientService, authService,
                                 weightSensor, systemInfoService,
                                 cellularModemService]() {
        QString sn = weightSensor->sn();
        qint64 custId = authService->custId();
        if (sn.isEmpty() || custId <= 0) {
            qInfo() << "[Main] 设备信息暂不上报 (等待双方就绪):"
                    << "sn=" << (sn.isEmpty() ? "<empty>" : sn)
                    << "custId=" << custId;
            return;
        }
        QString sim = cellularModemService->ccid();   // sim ← CCID(ICCID) 蜂窝模组 (未取到则空串)

        // 去重守卫：内容与上次相同时跳过，避免 SN/custId/ccid 信号多次触发导致重复上报
        static QString s_lastSim;
        static bool    s_published = false;
        if (s_published && s_lastSim == sim) {
            qDebug() << "[Main] 设备信息内容未变化，跳过重复上报";
            return;
        }
        s_published = true;
        s_lastSim = sim;

        // 启动/刷新设备心跳上报（SN 与 custId 均就绪后平台靠它判断在线）
        mqttClientService->startHeartbeat(sn, custId);

        // 启动/刷新设备状态上报（温度 + 联网 IP，默认 30s 周期）
        mqttClientService->startDeviceStatusReport(sn, custId);

        // 启动/刷新下行命令监听（cust/.../down/cmd: close/restart/exituser）
        mqttClientService->startCommandListener(sn, custId);

        qInfo() << "[Main] MQTT 上报设备信息: sn=" << sn
                << "custId=" << custId;
        qInfo() << "[Main] 硬件信息字段: hardModel=" << systemInfoService->hardModel()
                << "hardRevision=" << systemInfoService->hardRevision()
                << "hardSerial=" << systemInfoService->hardSerial()
                << "sim(CCID)=" << (sim.isEmpty() ? "<empty>" : sim);
        mqttClientService->publishDeviceInfo(
            sn, custId,
            systemInfoService->hardModel(),     // hardver ← /proc/cpuinfo Model
            systemInfoService->appVersion(),    // softver ← v2.13.2.9_日期
            sim,                                // sim ← CCID(ICCID) 蜂窝模组 AT 指令获取
            systemInfoService->hardRevision(),  // revision ← /proc/cpuinfo Revision
            systemInfoService->hardSerial());   // serial ← /proc/cpuinfo Serial
    };

    // SN 就绪后自动初始化 MQTT 连接 (shxgs Broker)
    // 首次连接: 生成随机密码并持久化; 后续复用密码
    QObject::connect(weightSensor, &WeightSensor::snChanged,
                     mqttClientService, [mqttClientService, authService,
                                          weightSensor,
                                          tryPublishDeviceInfo]() {
                         QString sn = weightSensor->sn();
                         if (sn.isEmpty()) return;
                         qInfo() << "[Main] MQTT 初始化: sn=" << sn;
                         mqttClientService->initAndConnect(
                             sn, authService->custId());
                         // SN 到了，若已登录(custId>0)则补发设备信息
                         tryPublishDeviceInfo();
                     });

    // custId 变更后更新 MQTT（登录成功后触发）；若 SN 也已就绪则上报
    QObject::connect(authService, &AuthService::userInfoChanged,
                     mqttClientService, tryPublishDeviceInfo);

    // CCID 获取成功后自动补发设备信息（带 sim 字段），去重守卫避免重复上报
    QObject::connect(cellularModemService, &CellularModemService::ccidChanged,
                     mqttClientService, tryPublishDeviceInfo);

    // ============================================================
    // 下行命令处理: cust/{custId}/device/{sn}/down/cmd
    //   cmd=close   预留，暂不处理
    //   cmd=restart 重启设备
    //   cmd=exituser 退出登录
    // time 字段指定延迟多少毫秒后执行(<=0 立即执行)
    // ============================================================
    QObject::connect(mqttClientService, &MqttClientService::deviceCommandReceived,
                     &app, [authService, &app](const QString &cmd, qint64 timeMs) {
        const qint64 delay = (timeMs > 0) ? timeMs : 0;
        if (cmd == QStringLiteral("exituser")) {
            qInfo() << "[Main] MQTT 命令: 退出登录, 延时" << delay << "ms";
            QTimer::singleShot(delay, authService, [authService]() {
                qInfo() << "[Main] 执行退出登录";
                authService->logout();
            });
        } else if (cmd == QStringLiteral("restart")) {
            qInfo() << "[Main] MQTT 命令: 重启设备, 延时" << delay << "ms";
            QTimer::singleShot(delay, &app, []() {
                qInfo() << "[Main] 执行设备重启";
                // 嵌入式 Linux: reboot（systemd 环境回退 systemctl reboot）
                if (QProcess::execute(QStringLiteral("reboot")) != 0)
                    QProcess::execute(QStringLiteral("systemctl"),
                                      QStringList() << QStringLiteral("reboot"));
            });
        } else if (cmd == QStringLiteral("close")) {
            // 预留命令，暂不处理
            qInfo() << "[Main] MQTT 命令 close (预留): 暂不处理";
        } else {
            qWarning() << "[Main] 未知 MQTT 命令:" << cmd;
        }
    });

    // 启动 CCID 获取：开机即尝试（服务内置重试）；4G 硬件就绪/启用后再补触发一次
    cellularModemService->start();
    QObject::connect(networkManagerService, &NetworkManagerService::cellularHardwareChanged,
                     cellularModemService, [cellularModemService](bool has) {
                         if (has) cellularModemService->start();
                     });
    QObject::connect(networkManagerService, &NetworkManagerService::cellularEnabled,
                     cellularModemService, [cellularModemService]() {
                         cellularModemService->start();
                     });

    // 注入 AuthService 给 HistoryService（云同步需要 token/userId）
    historyService->setAuthService(authService);

    // 注入 AuthService 给 CategoryService（云端拉取品类需要 token）
    categoryService->setAuthService(authService);

    // 注入 AuthService 给 UserIngredientService（USER 域食材拉取需要 token/custId）
    userIngredientService->setAuthService(authService);

    // 注入 UserIngredientService 给 WeightHistoryService（创建用户记录需要 ingrId 映射）
    historyService->setUserIngredientService(userIngredientService);

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
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "CategoryService", categoryService);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "UserIngredientService", userIngredientService);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "VoiceSpeaker", voiceSpeaker);
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "SystemInfo", systemInfoService);  // [测试] 系统信息
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "AppSettings", appSettings);      // 应用设置（价格输入开关等）
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "NetworkManager", networkManagerService);  // 网络管理 (WiFi + 4G)
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "MqttClient", mqttClientService);          // MQTT 设备上报 (shxgs)
    qmlRegisterSingletonInstance("App.Backend", 1, 0, "CellularModem", cellularModemService);     // 蜂窝模组 CCID(ICCID)
    qmlRegisterSingletonInstance<FoodTranslator>("SmartScale.Tools", 1, 0, "Translator", FoodTranslator::instance());
    qmlRegisterSingletonInstance<PState>("SmartScale.Tools", 1, 0, "PState", &PState::inst());

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
