# Fedora / Hyprland 内建键盘突发失效问题报告

## 1. 问题概述

- 设备：Lenovo Legion Y9000P IRX8（拯救者 Y9000P 2023）
- 系统：Fedora Linux 43，桌面环境为 Hyprland
- 故障现象：笔记本自带键盘突然停止工作，键盘灯熄灭，按键输入无反应；触控板正常；外接键盘正常
- 触发背景：用户表示故障发生前键盘原本正常，期间疑似误触某个组合键，随后键盘立刻失效
- 最终恢复方式：开机时按住 `Fn + Space + 电源键` 关机后再开机，内建键盘恢复正常

## 2. 环境信息

- 主机名：`chesszyh`
- 操作系统：Fedora Linux 43 (Workstation Edition)
- 内核版本：`6.19.10-200.fc43.x86_64`
- 硬件型号：`Legion Y9000P IRX8`
- 固件版本：`KWCN36WW`
- 会话类型：Wayland
- 桌面环境：Hyprland

## 3. 初始现象

用户报告的核心现象如下：

- 内建键盘无输入
- 键盘背光熄灭
- 触控板仍可使用
- 外接键盘仍可正常使用

这组现象说明故障范围集中在“笔记本内建键盘链路”，而不是整套输入子系统全部瘫痪。

## 4. 调查过程与证据

### 4.1 输入设备枚举状态

系统中仍然可以看到内建键盘设备：

- `libinput list-devices` 中存在 `AT Translated Set 2 keyboard`
- `/proc/bus/input/devices` 中存在对应条目
- 对应事件节点存在：`/dev/input/event3`
- 对应路径：`/dev/input/by-path/platform-i8042-serio-0-event-kbd`

这说明：

- 键盘设备并未从系统中彻底消失
- `atkbd` / `i8042` 这一层并非完全没有识别到设备

### 4.2 驱动绑定状态

内核日志显示：

- `i8042: PNP: PS/2 Controller [PNP0303:PS2K]`
- `serio: i8042 KBD port at 0x60,0x64 irq 1`
- `input: AT Translated Set 2 keyboard`

同时在 sysfs 中观察到：

- `atkbd` 驱动已绑定到 `serio0`
- `err_count=0`
- `inhibited=0`

这说明：

- 不是“驱动未加载”
- 不是“设备被 Hyprland 或用户态 inhibit”
- 不是简单的权限或输入法问题

### 4.3 Hyprland 侧状态

`hyprctl devices` 中仍然可以看到：

- `at-translated-set-2-keyboard`

这说明：

- Hyprland 仍然认为这块内建键盘存在
- 不是 Wayland 合成器层面的设备丢失

### 4.4 实时事件监听结果

使用 `libinput debug-events --device /dev/input/event3` 对内建键盘进行实时监听时：

- 仅看到设备被添加（`DEVICE_ADDED`）
- 在用户按下内建键盘按键时，没有看到任何按键事件上报

这说明：

- 问题已经落在更底层
- 并非按键被桌面环境、输入法或应用拦截
- 内核虽然枚举到了设备，但没有收到有效按键扫描事件

### 4.5 驱动重新初始化测试

执行了以下无持久化影响的驱动重绑定操作：

```sh
echo serio0 > /sys/bus/serio/drivers/atkbd/unbind
sleep 1
echo serio0 > /sys/bus/serio/drivers/atkbd/bind
```

结果：

- `AT Translated Set 2 keyboard` 被重新初始化
- 键盘设备重新出现
- 但在调查时并未观察到其恢复产生按键事件

这说明：

- 简单的软件层驱动重载不足以解释或修复问题

### 4.6 额外异常日志

调查期间，内核日志中持续出现如下错误模式：

- `usb 1-6: device descriptor read/64, error -71`
- `usb 1-6: device not accepting address`
- `usb usb1-port6: unable to enumerate USB device`

该错误与内建 PS/2 键盘不是同一条输入链路，但它提示：

- 机器内部至少还有一个设备在异常枚举
- 整机内部总线、电气状态或 EC 状态可能存在异常

这进一步提高了“不是普通桌面配置问题”的概率。

## 5. 关键事实归纳

本次调查可以确认以下事实：

1. 内建键盘设备仍被内核和 Hyprland 识别。
2. 内建键盘在故障期间不产生真实按键事件。
3. 外接键盘可正常使用，说明用户态输入链路整体正常。
4. 触控板可正常使用，说明不是所有内建输入设备同时失效。
5. 键盘背光熄灭，与“键盘控制状态异常”这一判断相互印证。
6. 驱动重绑未能直接恢复，说明并非普通用户态或单纯驱动挂起。
7. 最终通过带电源键的组合操作恢复，说明恢复动作更像是触发了 EC/键盘控制器状态重置。

## 6. 根因判断

### 6.1 最可能的原因

最可能的根因是：

- 用户误触某个热键组合后，联想机器的键盘控制状态、EC（Embedded Controller，嵌入式控制器）状态或背光/扫描控制状态进入异常
- 导致系统仍能枚举到内建键盘，但无法收到有效按键扫描事件

### 6.2 不太可能的原因

以下方向证据不足或基本可以排除：

- Hyprland 快捷键禁用键盘
- fcitx 或输入法问题
- XKB 键位配置错误
- 普通应用层抢占输入
- 键盘设备在内核中完全消失

### 6.3 关于恢复操作的解释

用户通过以下方式恢复：

- 开机时按住 `Fn + Space + 电源键`

结合机器类型和故障现象，可作如下解释：

- `Fn + Space` 在联想游戏本上通常与键盘背光控制相关
- 与电源键配合的整套操作，极有可能间接触发了一次 EC、键盘控制器或键盘背光/扫描逻辑的复位
- 恢复并不意味着 Linux 配置被修改，而更像是固件层控制状态被清除

因此，本次恢复更接近“硬件控制状态重置”，而不是“软件设置改回来”。

## 7. 结论

本次故障更符合以下模型：

- 故障不是由 Hyprland、输入法或普通 Linux 配置引起
- 故障也不像键盘硬件立即物理损坏
- 更可能是误触某个组合键后，使联想笔记本键盘控制状态或 EC 状态卡住
- 系统仍识别键盘，但键盘不再上报扫描事件
- 通过 `Fn + Space + 电源键` 触发的近似硬复位后恢复正常

## 8. 后续建议

### 8.1 如果再次发生

建议按以下顺序处理：

1. 先测试是否为系统层问题：
   - 进入 BIOS 或启动菜单测试内建键盘是否正常
2. 若 BIOS 中也异常：
   - 做一次完整断电复位
   - 关机、拔电源、长按电源键 30 至 60 秒后再开机
3. 若症状与本次相同：
   - 优先尝试本次有效的恢复方式：`Fn + Space + 电源键`
4. 若问题频繁复发：
   - 关注 BIOS/EC 固件更新
   - 必要时考虑送修排查键盘模组、排线或主板 EC 状态

### 8.2 建议继续观察的点

- 是否只在误触某些 `Fn` 组合键后出现
- 是否与睡眠/唤醒有关
- 是否伴随背光异常、风扇策略异常、性能模式异常等 EC 相关现象
- 是否仍然反复出现内部 USB 枚举失败日志

## 9. 附：本次调查中的关键命令

```sh
hostnamectl
uname -a
loginctl session-status
libinput list-devices
grep -H . /proc/bus/input/devices
journalctl -b --no-pager | rg -i 'i8042|serio|atkbd|keyboard|ps2|acpi|ideapad|elan'
hyprctl devices
udevadm info -q all -n /dev/input/event3
libinput debug-events --device /dev/input/event3
```

## 10. 报告结论摘要

本次“拯救者 Y9000P 2023 在 Fedora + Hyprland 下内建键盘突然失效”的事件，最符合“误触组合键后导致 EC/键盘控制状态异常”的模型。故障期间设备仍被系统识别，但无按键事件上报；最终通过 `Fn + Space + 电源键` 组合操作恢复，说明该操作很可能等效于一次键盘控制逻辑或 EC 状态复位。
