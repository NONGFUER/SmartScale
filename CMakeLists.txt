cmake_minimum_required(VERSION 3.16)

project(SmartScale VERSION 2.13.3 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(QT_QML_GENERATE_QMLLS_INI ON)

# ============================================================
# 版本号配置 (手动模式)
#   编译时: cmake .. -DBUILD_NUMBER=10
# ============================================================
set(BUILD_NUMBER "9" CACHE STRING "Build number (手动递增)")
string(TIMESTAMP APP_BUILD_DATE "%Y%m%d")
set(APP_VERSION_FULL "${PROJECT_VERSION}.${BUILD_NUMBER}")

configure_file(
    "${CMAKE_CURRENT_SOURCE_DIR}/src/version.h.in"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/version.h"
)
message(STATUS "应用版本: ${APP_VERSION_FULL}_${APP_BUILD_DATE}")

# ============================================================
# Modbus 协议变体 (编译期宏开关)
#   cmake .. -DSMARTSCALE_MODBUS_PROTOCOL=feigong|v2
#   默认: feigong (飞功标准协议)
#   宏定义: SMARTSCALE_MODBUS_PROTOCOL_FEIGONG / SMARTSCALE_MODBUS_PROTOCOL_V2
# ============================================================
set(SMARTSCALE_MODBUS_PROTOCOL "feigong" CACHE STRING "Modbus protocol variant: feigong|v2")
if(SMARTSCALE_MODBUS_PROTOCOL STREQUAL "v2")
    add_compile_definitions(SMARTSCALE_MODBUS_PROTOCOL_V2)
    message(STATUS "Modbus 协议: V2 (旧版, 0x0010 起 9 寄存器)")
else()
    add_compile_definitions(SMARTSCALE_MODBUS_PROTOCOL_FEIGONG)
    message(STATUS "Modbus 协议: Feigong (飞功标准, 0x0000 起 5 寄存器)")
endif()

# Qt 组件 (QtMqtt 从源码编译安装到 /usr/local)
set(Qt6Mqtt_DIR "/usr/local/lib/aarch64-linux-gnu/cmake/Qt6Mqtt" CACHE PATH "" FORCE)
find_package(Qt6 REQUIRED COMPONENTS Quick VirtualKeyboard Multimedia Sql Network SerialPort Concurrent Mqtt)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(appSmartScale
    app/main.cpp
)

add_definitions(-DQT_NO_KEYWORDS)

# 声明 Theme.qml 为 QML singleton（pragma Singleton 需配合此源文件属性）
# 必须在 qt_add_qml_module 之前设置
set_source_files_properties(src/ui/Theme.qml PROPERTIES
    QT_QML_SINGLETON_TYPE TRUE
)

qt_add_qml_module(appSmartScale
    URI SmartScale
    QML_FILES
        src/ui/Theme.qml                       # 全局主题 singleton（字体/颜色常量）
        src/ui/Main.qml
        src/ui/pages/LoginPage.qml             # 登录页面
        src/ui/pages/WorkstationPage.qml       # 主操作台页面
        src/ui/pages/SettingsPage.qml          # 设置页面（已废弃，保留兼容）
        src/ui/components/SettingsDialog.qml    # 设置弹窗组件（替代 SettingsPage）
        src/ui/components/StatusBar.qml
        src/ui/components/BottomStatusBar.qml
        src/ui/components/FoodItemCard.qml
        src/ui/components/ActionButton.qml     # 仿品类网格质感的操作按钮组件
        src/ui/components/RecordDetailDialog.qml   # 称重记录详情弹窗
        src/ui/components/LogoutConfirmDialog.qml  # 退出登录确认弹窗
        src/ui/components/LoginDialog.qml      # 登录弹窗
        src/ui/pages/CategoryCorrectionDialog.qml  # 品类纠错弹窗
        src/ui/components/SystemInfoDialog.qml     # [测试] 系统调试信息弹窗
        src/ui/components/Toast.qml                # 全局 Toast 提示组件
        src/ui/components/AlertDialog.qml          # 通用错误/确认弹窗（全局）
        src/ui/components/WifiListDialog.qml       # Wi-Fi 网络列表弹窗
        src/ui/components/WifiPasswordDialog.qml   # Wi-Fi 密码输入弹窗
        src/ui/components/CellularDialog.qml        # 4G 移动数据控制弹窗
        src/ui/components/AddIngredientDialog.qml   # 添加食材弹窗
        src/ui/components/WeightRecordSearchDialog.qml  # 称重记录查询弹窗
        src/ui/components/SaveConfirmDialog.qml         # 保存确认弹窗（含价格输入）

    # --- 核心基础设施 ---
        SOURCES src/core/NetworkUtils.h src/core/NetworkUtils.cpp
        SOURCES src/core/PState.h src/core/PState.cpp

        # --- 硬件层 (Hardware) ---
        SOURCES src/hardware/WeightSensorWorker.h src/hardware/WeightSensorWorker.cpp
        SOURCES src/hardware/WeightSensor.h src/hardware/WeightSensor.cpp
        SOURCES src/hardware/CameraController.h src/hardware/CameraController.cpp
        SOURCES src/hardware/VoiceSpeaker.h src/hardware/VoiceSpeaker.cpp

        # --- AI 推理层 ---
        SOURCES src/ai/VisionAIService.h src/ai/VisionAIService.cpp

        # --- 工具层 (Utils) ---
        SOURCES src/utils/FoodTranslator.h src/utils/FoodTranslator.cpp

        # --- 业务服务层 (Services) ---
        SOURCES src/services/AuthService.h src/services/AuthService.cpp
        SOURCES src/services/WeightHistoryService.h src/services/WeightHistoryService.cpp
        SOURCES src/services/CategoryService.h src/services/CategoryService.cpp
        SOURCES src/services/UserIngredientService.h src/services/UserIngredientService.cpp
        SOURCES src/services/SystemInfoService.h src/services/SystemInfoService.cpp       # [测试] 系统信息服务
        SOURCES src/services/NetworkManagerService.h src/services/NetworkManagerService.cpp  # 网络管理服务 (WiFi + 4G)
        SOURCES src/services/MqttClientService.h src/services/MqttClientService.cpp           # MQTT 客户端服务
        SOURCES src/services/CellularModemService.h src/services/CellularModemService.cpp     # 蜂窝模组 CCID(ICCID) 获取 (AT 指令)

        # --- 数据层: Models ---
        SOURCES src/data/models/WeightRecord.h src/data/models/WeightRecord.cpp
        SOURCES src/data/models/User.h src/data/models/User.cpp
        SOURCES src/data/models/HardwareConfig.h src/data/models/HardwareConfig.cpp

        # --- 数据层: Database ---
        SOURCES src/data/DatabaseManager.h src/data/DatabaseManager.cpp

        # --- 数据层: Repositories ---
        SOURCES src/data/repositories/WeightRecordRepo.h src/data/repositories/WeightRecordRepo.cpp
        SOURCES src/data/repositories/UserRepo.h src/data/repositories/UserRepo.cpp
        SOURCES src/data/repositories/HardwareConfigRepo.h src/data/repositories/HardwareConfigRepo.cpp

)

qt_add_resources(appSmartScale "app_assets"
    PREFIX "/"
    FILES
        resources/img/workstation_bg.png
        resources/img/pageUp.png
        resources/img/pageDown.png
        resources/img/ai.png
        resources/img/ingr.png
        resources/img/logo.png
        resources/icon/eye-fill.png
        resources/icon/eye-close-fill.png
        resources/fonts/PingFangSC-Regular.ttf
        resources/fonts/din-bold-2.ttf
        resources/fonts/AlimamaShuHeiTi-Bold.ttf
        resources/img/Signal0.png
        resources/img/Signal1.png
        resources/img/Signal2.png
        resources/img/Signal3.png
        resources/img/Signal4.png
        resources/img/Wifi0.png
        resources/img/Wifi1.png
        resources/img/Wifi2.png
        resources/img/Wifi3.png
        resources/img/Wifi4.png
        resources/img/Setting.png
        resources/img/close.png
)

set(ONNXRUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/onnxruntime-linux-aarch64-1.24.4")

target_include_directories(appSmartScale
    PRIVATE
    "${ONNXRUNTIME_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
    "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

set_target_properties(appSmartScale PROPERTIES
    INSTALL_RPATH "${ONNXRUNTIME_DIR}/lib"
)

target_link_directories(appSmartScale PRIVATE "${ONNXRUNTIME_DIR}/lib")

target_link_libraries(appSmartScale
    PRIVATE
        Qt6::Quick
        Qt6::VirtualKeyboard
        Qt6::Multimedia
        Qt6::Sql
        Qt6::Network
        Qt6::SerialPort
        Qt6::Concurrent
        Qt6::Mqtt
        pthread
        onnxruntime
)

install(TARGETS appSmartScale
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# 部署 AI 模型文件和 ONNX Runtime 动态库到编译输出目录
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/AI"
     DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")

# 部署资源文件（图标、水印等）到编译输出目录
file(COPY "${CMAKE_CURRENT_SOURCE_DIR}/resources"
     DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")

file(COPY "${ONNXRUNTIME_DIR}/lib/"
     DESTINATION "${CMAKE_CURRENT_BINARY_DIR}"
     FILES_MATCHING PATTERN "*.so*")

message(STATUS "已配置 AI 模型文件拷贝队列")
