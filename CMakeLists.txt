cmake_minimum_required(VERSION 3.16)

project(SmartScale VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(QT_QML_GENERATE_QMLLS_INI ON)

# Qt 组件
find_package(Qt6 REQUIRED COMPONENTS Quick VirtualKeyboard Multimedia Sql Network SerialPort)

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(appSmartScale
    app/main.cpp
)

add_definitions(-DQT_NO_KEYWORDS)

qt_add_qml_module(appSmartScale
    URI SmartScale
    QML_FILES
        src/ui/Main.qml
        src/ui/pages/LoginPage.qml             # 登录页面
        src/ui/pages/WorkstationPage.qml       # 主操作台页面
        src/ui/pages/SettingsPage.qml          # 设置页面
        src/ui/pages/FoodSelectPage.qml        # 食品选择页面
        src/ui/components/StatusBar.qml
        src/ui/components/FoodItemCard.qml
        src/ui/components/LoginDialog.qml      # 登录弹窗
        src/ui/pages/CategoryCorrectionDialog.qml  # 品类纠错弹窗

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

set(ONNXRUNTIME_DIR "${CMAKE_CURRENT_SOURCE_DIR}/3rdparty/onnxruntime-linux-aarch64-1.24.4")

target_include_directories(appSmartScale
    PRIVATE
    "${ONNXRUNTIME_DIR}/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/src"
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
