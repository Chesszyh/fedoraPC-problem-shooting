# Fedora Logitech M720 连接成功但无输入问题报告

生成时间: 2026-05-26T21:36:49+08:00

## Problem Description

深度拆机清灰换硅脂后，用户发现 Logitech M720 Triathlon 鼠标在本机异常：

- 蓝牙看起来能连接或尝试连接，但鼠标移动无反应；
- 使用 USB 接收器时系统也能识别设备，但鼠标移动无反应；
- 蓝牙耳机在本机正常；
- 另一只 USB 鼠标在本机正常；
- 这只 M720 在其他电脑上正常。

最终通过移除本机旧蓝牙配对记录并重新配对恢复。

## Environment and Scope

- 主机: `/home/chesszyh`
- 系统: Fedora 43 / Hyprland
- 蓝牙控制器: Intel AX211 Bluetooth，控制器地址 `E0:2E:0B:08:D6:70`
- 鼠标: Logitech M720 Triathlon
- 旧蓝牙地址: `DE:A2:F9:DF:F1:21`
- 重新配对后地址: `DE:A2:F9:DF:F1:25`

本报告覆盖本次鼠标输入异常，不代表所有 Logitech 设备问题。

## Symptoms and Reproduction

异常状态下：

```bash
bluetoothctl info DE:A2:F9:DF:F1:21
```

显示 M720 已配对、已绑定，但未连接：

```text
Name: M720 Triathlon
Paired: yes
Bonded: yes
Trusted: no
Connected: no
UUID: Human Interface Device
Modalias: usb:v046DpB015d0013
```

用户重新连接蓝牙时报错：

```text
连接失败：le-connection-abort-by-local
```

USB 接收器路径下，系统曾识别出真正的 M720：

```text
Name="Logitech M720 Triathlon"
Handlers=sysrq kbd leds mouse0 event6
```

但对 `/dev/input/event6` 监听时只有设备添加，没有移动或点击事件：

```bash
timeout 5s sudo libinput debug-events --device /dev/input/event6
```

输出只出现：

```text
DEVICE_ADDED Logitech M720 Triathlon
```

## Investigation Timeline

1. 先排除整机蓝牙硬件大故障：蓝牙耳机可正常使用。
2. 排除桌面输入栈整体故障：另一只 USB 鼠标正常。
3. 排除鼠标本体彻底损坏：M720 在其他电脑上正常。
4. 查看 `bluetoothctl`，发现旧地址 `DE:A2:F9:DF:F1:21` 是已配对但未连接。
5. 查看 `journalctl -u bluetooth -b`，发现 HOG/HID 初始化失败：

```text
profiles/input/hog-lib.c:uhid_create() Failed to connection details: getpeername: Transport endpoint is not connected (107)
HID Information read failed: Request attribute has encountered an unlikely error
Read Report Reference descriptor failed: Request attribute has encountered an unlikely error
```

6. 查看 `dmesg`，发现 Logitech BLE HID++ 解析失败：

```text
logitech-hidpp-device 0005:046D:B015... hidpp_probe:parse failed
probe with driver logitech-hidpp-device failed with error -22
```

7. USB 接收器模式下，Hyprland 和 libinput 都能看到 M720，但监听 event 节点没有输入事件，说明设备节点存在不等于鼠标实际向该通道发送输入。
8. 执行移除旧配对并重新配对后，M720 恢复；重新配对后系统看到新地址 `DE:A2:F9:DF:F1:25` 和新的输入节点 `/dev/input/event7`。

## Root Cause

最可能根因是：**M720 在本机的旧 BLE 配对缓存或 HID over GATT 状态损坏，导致 BlueZ 能保留设备记录，但无法正确建立 HID 输入通道。**

证据：

- 只有 M720 在本机异常，蓝牙耳机和另一只 USB 鼠标都正常。
- M720 在其他电脑正常，说明鼠标硬件本体不是主要问题。
- 旧配对记录显示 `Paired=yes`、`Bonded=yes`，但 `Connected=no`。
- BlueZ 日志中有 HOG/HID 读 descriptor 失败。
- 内核日志中有 `hidpp_probe:parse failed` 和 `error -22`。
- 移除旧配对后重新配对立即恢复。

与拆机清灰的关系：清灰可能通过断电、重启、蓝牙控制器重新初始化间接触发旧配对状态失效；但没有证据表明无线网卡、天线或输入系统被拆坏。

## Changes Made

执行了对旧 M720 配对记录的移除：

```bash
bluetoothctl remove DE:A2:F9:DF:F1:21
```

随后用户将 M720 对应 Easy-Switch 通道重新进入配对模式并重新连接。

## Verification

修复后：

```bash
bluetoothctl devices Connected
```

显示：

```text
Device DE:A2:F9:DF:F1:25 M720 Triathlon
```

`/proc/bus/input/devices` 显示新的蓝牙 HID 输入节点：

```text
Name="Logitech M720 Triathlon Multi-Device Mouse"
Phys=e0:2e:0b:08:d6:70
Uniq=de:a2:f9:df:f1:25
Handlers=sysrq kbd mouse3 event7
```

用户确认移除后重新连接，鼠标已经恢复正常。

## Problems Encountered During Debugging

- 一开始对 `/dev/input/event22` 的 `libinput debug-events` 监听产生了大量移动事件，但用户后来确认当时移动的是另一只鼠标，因此这组事件不能作为 M720 的输入证据。
- M720 同时支持蓝牙和 Logitech 接收器，并且有 Easy-Switch 多设备通道；设备节点存在时，仍可能因为鼠标当前通道不匹配或旧配对状态损坏而没有输入事件。
- 旧蓝牙地址 `DE:A2:F9:DF:F1:21` 移除后，重新配对显示为 `DE:A2:F9:DF:F1:25`，这是 BLE 随机地址/身份变化场景下可以出现的现象。

## Reuse Notes and Lessons

- “已配对”或“系统识别到设备节点”不等于 HID 输入通道正常。
- Logitech 多设备鼠标排障时，要同时检查蓝牙配对、Easy-Switch 通道、USB 接收器和 `libinput debug-events`。
- 如果只是一只 BLE HID 鼠标异常，耳机和其他鼠标正常，优先清理该设备的 BlueZ 配对缓存，而不是判断为拆机造成天线损坏。

## Appendix: Reusable Commands

查看 M720 蓝牙状态：

```bash
bluetoothctl devices
bluetoothctl devices Connected
bluetoothctl info DE:A2:F9:DF:F1:21
```

移除旧配对：

```bash
bluetoothctl remove DE:A2:F9:DF:F1:21
```

查看输入设备：

```bash
grep -n -A12 -B2 -Ei 'M720|Triathlon|046d|Logitech' /proc/bus/input/devices
hyprctl devices
libinput list-devices
```

监听指定输入节点：

```bash
sudo libinput debug-events --device /dev/input/event7
```

查看蓝牙日志：

```bash
journalctl -u bluetooth -b --no-pager | tail -120
sudo dmesg -T | grep -Ei 'logitech|hidpp|046d|b015|bluetooth|hog|uhid' | tail -120
```
