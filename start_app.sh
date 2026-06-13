#!/bin/bash

# 等待桌面环境完全启动
sleep 5

# 设置环境变量：强制使用X11（兼容性更好）、全屏、禁用窗口装饰
export QT_QPA_PLATFORM=xcb
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_AUTO_SCREEN_SCALE_FACTOR=0

# 进入程序所在目录
cd /home/sjwu/SmartScale/build

# 运行程序，并将输出重定向到日志文件便于调试
./appSmartScale 2>&1 | tee -a /tmp/smartscale.log
