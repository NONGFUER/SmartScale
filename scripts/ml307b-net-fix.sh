#!/bin/bash
# ML307B 驱动完美共存脚本: 网卡 + AT 串口

VID="2ecc"
PID="3012"

# 1. 加载 option 串口驱动
modprobe option

# 2. 告诉 option 驱动接管 2ecc 3012 的设备
echo "$VID $PID" > /sys/bus/usb-serial/drivers/option1/new_id 2>/dev/null

# 3. 稍微等待 1 秒，让内核完成绑定
sleep 1

# 4. 巡查被 option 占用的通道，把“网卡”释放出来交还给系统
for path in /sys/bus/usb/drivers/option/*:*; do
    if [ -e "$path/bInterfaceClass" ]; then
        cls=$(cat "$path/bInterfaceClass")
        # e0 (Wireless) 和 0a (CDC Data) 是网卡的特征
        if [ "$cls" = "e0" ] || [ "$cls" = "0a" ]; then
            dev=$(basename "$path")
            # 从串口驱动中解除绑定
            echo "$dev" > /sys/bus/usb/drivers/option/unbind 2>/dev/null
            # 重新触发网卡驱动接管
            echo "$dev" > /sys/bus/usb/drivers_probe 2>/dev/null
        fi
    fi
done

exit 0