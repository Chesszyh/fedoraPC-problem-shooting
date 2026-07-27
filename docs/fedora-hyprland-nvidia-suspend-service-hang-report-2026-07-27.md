# Fedora 43 Hyprland 锁屏后 NVIDIA 挂起准备卡死报告

生成时间: 2026-07-27T14:26:59+08:00

## 1. 问题描述

本机多次出现以下故障：

1. 凌晨锁屏并离开电脑；
2. 一段时间后内屏彻底熄灭；
3. 键盘、鼠标和电源键短按均无法恢复画面；
4. 最终只能长按电源键强制关机。

表面现象很像“电脑已经挂起，但恢复失败”。本次检查最终证明：系统没有真正进入 suspend，而是卡在 NVIDIA 驱动的挂起准备阶段。

本报告记录 2026-07-27 凌晨事件的本机证据、排除过程、直接根因、临时规避措施及后续可测试方案。

## 2. 环境和范围

### 硬件与软件

| 项目 | 当前值 |
| --- | --- |
| 设备 | Lenovo Legion Y9000P IRX8 |
| 操作系统 | Fedora Linux 43 Workstation |
| 桌面环境 | Hyprland / Wayland |
| 内核 | `7.1.4-104.fc43.x86_64` |
| 独立显卡 | NVIDIA GeForce RTX 4060 Laptop GPU，8 GiB |
| NVIDIA 驱动 | `580.173.02`，Open Kernel Module |
| NVIDIA 电源包 | `xorg-x11-drv-nvidia-power-580.173.02-1.fc43` |
| 固件 | Lenovo `KWCN36WW`，2023-04-28 |
| suspend 模式 | `/sys/power/mem_sleep` 显示 `s2idle [deep]`，当前选择 `deep` |

本机启用了 RPM Fusion 提供的 NVIDIA 电源管理配置：

```text
/usr/lib/modprobe.d/nvidia-power-management.conf:
options nvidia NVreg_PreserveVideoMemoryAllocations=1
options nvidia NVreg_TemporaryFilePath=/var/tmp
```

运行时参数由 `/proc/driver/nvidia/params` 确认：

```text
PreserveVideoMemoryAllocations: 1
TemporaryFilePath: "/var/tmp"
```

### 调查边界

- 调查对象是 `2026-07-27 00:55` 开始、`08:12` 后被强制关机的上一次启动。
- 根因调查阶段保持只读，没有主动执行 suspend 复现，以免再次造成不可恢复黑屏。
- 最终只修改了用户级 `hypridle` 自动挂起规则。
- 没有修改 NVIDIA 驱动、内核参数、systemd 系统服务或固件。

## 3. 症状与复现

自动触发路径来自：

```text
/home/chesszyh/.config/hypr/hypridle.conf
```

原配置包含：

```ini
listener {
  timeout = 1200
  on-timeout = systemctl suspend
  on-resume = notify-send -i $iDIR " Oh! you're back" "Hello !!!"
}
```

故障并非每次 suspend 都出现。2026-07-25 相同内核和相同 NVIDIA 驱动曾正常完成一次挂起和恢复：

```text
12:48:05 Starting nvidia-suspend.service
12:48:11 Finished nvidia-suspend.service
12:48:11 PM: suspend entry (deep)
13:30:12 System returned from sleep operation 'suspend'
13:30:12 PM: suspend exit
13:30:13 Finished nvidia-resume.service
```

因此复现条件不是简单的“该驱动必然无法挂起”，而是与触发时的 NVIDIA/GPU 客户端或驱动内部状态有关的偶发故障。

## 4. 调查时间线

### 4.1 锁屏、熄屏与挂起请求

关键事件如下：

| 时间 | 事件 |
| --- | --- |
| 01:50:50 | Hyprland 会话锁定，`hyprlock` 已存在 |
| 02:58:44 | DBus idle inhibitor 释放，空闲计时开始生效 |
| 03:07:44 | 触发 9 分钟空闲提醒 |
| 03:08:44 | 执行 `loginctl lock-session` |
| 03:09:14 | 执行 `hyprctl dispatch dpms off`，内屏关闭 |
| 03:18:44 | 执行 `systemctl suspend` |
| 03:18:44 | `systemd-logind`: `The system will suspend now!` |
| 03:18:44 | `nvidia-suspend.service` 开始，之后一直没有完成 |
| 08:12 左右 | 上一次启动的日志结束，随后机器被强制断电 |
| 14:00:13 | 再次开机，journald 和文件系统确认上次未正常关闭 |

`hypridle` 的关键日志：

```text
03:09:14 Running hyprctl dispatch dpms off
03:18:44 Running systemctl suspend
03:18:44 Got PrepareForSleep from dbus with sleep true
```

systemd 的关键日志：

```text
03:18:44 Reached target sleep.target - Sleep.
03:18:44 Starting nvidia-suspend.service - NVIDIA system suspend actions...
03:18:44 suspend: nvidia-suspend.service
```

缺失的关键日志：

```text
Finished nvidia-suspend.service
PM: suspend entry (deep)
System returned from sleep operation 'suspend'
PM: suspend exit
Starting nvidia-resume.service
```

### 4.2 NVIDIA 服务的实际执行路径

`/usr/lib/systemd/system/nvidia-suspend.service` 执行：

```ini
ExecStart=/usr/bin/nvidia-sleep.sh "suspend"
```

`/usr/bin/nvidia-sleep.sh` 的挂起路径为：

```bash
fgconsole > /var/run/nvidia-sleep/Xorg.vt_number
chvt 63
echo "suspend" > /proc/driver/nvidia/suspend
```

服务已经打印启动标记，却没有退出或失败日志。结合脚本结构，阻塞点位于 `chvt 63` 之后、服务完成之前，最符合本次全部证据的位置是：

```bash
echo "suspend" > /proc/driver/nvidia/suspend
```

该写操作会进入 NVIDIA 内核驱动，保存 GPU 状态和已分配显存。

### 4.3 机器并未真正睡眠

03:18 以后仍有后台守护进程持续输出日志，直到早晨。这意味着：

- CPU 仍在运行；
- 内核没有进入 `deep` suspend；
- 不是“已经睡着但恢复失败”；
- 用户后来按键时不存在可执行的 resume 阶段。

与此同时，挂起准备已经产生了部分外部效果：

- NetworkManager 进入睡眠状态并断开网络；
- Hyprland DPMS 已关闭显示器；
- NVIDIA 脚本切换到 VT 63；
- systemd 电源事务仍在等待无启动超时的 `nvidia-suspend.service`。

因此用户看到的是一台仍在运行、但图形显示和网络已被关闭、且 suspend 事务永久阻塞的机器。

### 4.4 排除内存压力和磁盘问题

本机以前出现过由 zram、换页和 NVMe 延迟导致的桌面冻结，因此本次也检查了同类证据。

03:10 和 03:20 的 `sar` 采样：

```text
CPU idle:       96.43% / 96.83%
内存使用率:     22.05% / 22.43%
swap 使用率:    14.37% / 14.29%
pswpout/s:      0.00
```

这与之前约 94% swap、重度换页的冻结特征完全不同。本次没有：

- 系统级内存耗尽；
- OOM killer 或 systemd-oomd 动作；
- NVIDIA Xid；
- GPU hang 报告；
- Hyprland coredump；
- 热故障或磁盘错误。

`NVreg_TemporaryFilePath=/var/tmp` 也不是因为容量不足失败：

```text
文件系统: /dev/nvme0n1p3
类型:     Btrfs
可用空间: 约 140 GiB
GPU 显存: 8 GiB
```

### 4.5 强制关机证据

下一次启动记录：

```text
File .../system.journal corrupted or uncleanly shut down, renaming and replacing.
Dirty bit is set. Fs was not properly unmounted and some data may be corrupt.
```

这与用户长按电源键强制断电一致。

## 5. 根因

### 已证实的直接根因

`nvidia-suspend.service` 在调用 NVIDIA 的实验性 procfs 电源管理接口时永久阻塞，导致 systemd 无法继续访问 `/sys/power/state`，机器没有真正进入 suspend。

完整故障链为：

```text
hypridle 空闲 20 分钟
  → systemctl suspend
  → NetworkManager 等组件执行睡眠准备
  → nvidia-sleep.sh 切换到 VT 63
  → 写 suspend 到 /proc/driver/nvidia/suspend
  → NVIDIA 驱动内部操作永久阻塞
  → PM: suspend entry 从未发生
  → 屏幕和网络已关闭，但系统仍在运行
  → 无法触发 resume，只能强制关机
```

### 尚未证实的底层触发条件

日志只能把故障边界定位到 NVIDIA 驱动的 procfs suspend 操作，不能恢复当时每个 GPU 客户端和显存分配的精确快照。因此不能断言是 Chrome、Screenpipe、CUDA、Hyprland 或某个单独应用导致。

现有证据支持“与当时 GPU、UVM 或显存状态相关的偶发驱动死锁”，但具体 NVIDIA 内部函数和触发客户端仍未知。

### 为什么不是其他常见解释

- **不是 resume 黑屏**：没有 `PM: suspend entry`，自然也没有 resume。
- **不是 Hyprland 独有故障**：阻塞发生在 systemd 的 NVIDIA 驱动准备服务中。
- **不是 s2idle 已知恢复时序问题**：本机选择的是 `deep`，而且还没进入内核 suspend。
- **不是固定内核回归**：相同 `7.1.4-104.fc43` 曾成功挂起。
- **不是本次系统内存耗尽**：RAM、swap 和换页数据均正常。
- **不是 `/var/tmp` 空间不足**：可用空间远大于显存容量。

### 与网上报告的对应关系

NVIDIA 官方文档说明：

- `/proc/driver/nvidia/suspend` 是仍被标为实验性的电源管理接口；
- `NVreg_PreserveVideoMemoryAllocations=1` 通过该接口保存全部显存分配；
- `nvidia-suspend.service` 必须在真正写 `/sys/power/state` 前完成。

参考：

- [NVIDIA 580.173.02：Configuring Power Management Support](https://download.nvidia.com/XFree86/Linux-x86_64/580.173.02/README/powermanagement.html)
- [Fedora：NVIDIA GPU - Failure to suspend](https://discussion.fedoraproject.org/t/nvidia-gpu-failure-to-suspend/154535)
- [Fedora 43 / NVIDIA 580：Nvidia power management causes suspend issues](https://forums.developer.nvidia.com/t/bug-nvidia-power-management-causes-suspend-issues-nvidia-suspend-service/358259)
- [Fedora Legion：Suspend sometimes fails because of nvidia-suspend.service](https://www.reddit.com/r/Fedora/comments/1mnwzy0/suspend_sometimes_fails_because_of/)

这些报告支持“随机卡在 NVIDIA suspend 服务或 procfs 写入”这一故障类别，但截至本次调查，没有找到明确声明“580.173.02 的该问题已在某个版本修复”的上游结论。

## 6. 已做改动

为避免无人值守时再次自动触发该故障，修改：

```text
/home/chesszyh/.config/hypr/hypridle.conf
```

将自动 suspend listener 整体注释：

```ini
# Suspend disabled: NVIDIA may hang in nvidia-suspend.service before sleep.
# listener {
#   timeout = 1200
#   on-timeout = systemctl suspend
#   on-resume = notify-send -i $iDIR " Oh! you're back" "Hello !!!"
# }
```

随后执行：

```bash
systemctl --user restart hypridle.service
```

该改动只停用空闲 20 分钟后的自动挂起：

- 9 分钟提醒仍保留；
- 10 分钟自动锁屏仍保留；
- 10.5 分钟 DPMS 熄屏仍保留；
- 手动睡眠键和电源菜单仍可能执行 `systemctl suspend`。

未改动：

- `/usr/lib/modprobe.d/nvidia-power-management.conf`
- `nvidia-suspend.service`
- `nvidia-resume.service`
- NVIDIA 驱动版本
- 内核命令行
- BIOS/UEFI

## 7. 验证

### 7.1 hypridle 生效验证

重启后：

```text
hypridle.service: active (running)
found 3 rules
```

有效规则只剩：

```text
540s  → 空闲提醒
600s  → loginctl lock-session
630s  → hyprctl dispatch dpms off
```

日志中不再出现：

```text
Registered timeout rule for 1200s
on-timeout: systemctl suspend
```

### 7.2 配置差异验证

```bash
git -C /home/chesszyh/.config/hypr diff -- hypridle.conf
git -C /home/chesszyh/.config/hypr diff --check -- hypridle.conf
```

`diff --check` 通过，没有新增空白错误。该 Git 工作树原本还存在与本任务无关的用户修改，本次没有改动或覆盖它们。

### 7.3 当前验证边界

目前已验证“自动 suspend 不再注册”，没有再次主动测试真正 suspend。要判断 NVIDIA 问题是否根治，后续需要在可现场恢复、重要文件已保存的条件下进行受控 A/B 挂起测试。

## 8. 调试过程中遇到的问题

### 8.1 最初可能误判为 resume 黑屏

用户现象是“彻底黑屏、无法唤醒”，最自然的假设是系统已经睡眠并在恢复时失败。通过检查是否存在 `PM: suspend entry` 和 `PM: suspend exit`，才确认实际卡在 suspend 前。

以后应先区分：

```text
没有 PM: suspend entry → 挂起准备失败
有 entry、无 exit      → 内核/固件恢复失败
有 entry 和 exit       → 图形栈或显示恢复失败
```

### 8.2 宽泛搜索产生大量 Tailscale 噪声

最初使用包含 `sleep`、`resume` 等宽泛关键词的 journal 搜索，命中了大量网络守护进程文本。后续改为针对：

```text
systemd-suspend.service
nvidia-suspend.service
nvidia-resume.service
PM: suspend entry
PM: suspend exit
systemd-logind
hypridle
```

### 8.3 NVIDIA 参数位置判断错误

曾尝试从：

```text
/sys/module/nvidia/parameters/
```

读取模块参数，但本机 Open Kernel Module 没有暴露该路径。有效运行时证据来自：

```text
/proc/driver/nvidia/params
```

### 8.4 旧故障经验不能直接套用

这台机器以前发生过内存换页风暴导致的桌面冻结。若只根据“黑屏 + 强制重启”沿用旧结论，会误判本次事件。`sar` 证明本次内存和 swap 压力都很低。

### 8.5 社区 workaround 不能写成确定修复

网上存在多种互相冲突的方案，且不同硬件、驱动分支、混合显卡模式结果不同。本报告将其列为后续受控实验，不把个别用户成功经验当成已确认根治。

## 9. 可复用说明与经验

### 9.1 推荐的后续测试顺序

#### 方案 A：等待或切换 NVIDIA 驱动

优先使用 Fedora/RPM Fusion 正式打包的后续驱动做受控测试，或者回退到经过多轮 suspend 验证的版本。

优点：

- 可能真正修复驱动死锁；
- 不需要改变显存保存语义。

限制：

- 本次没有找到明确的修复版本；
- 单次成功不足以证明修复，本机同版本也曾成功过。

建议至少测试：

```text
空闲桌面 × 3
浏览器/视频播放后 × 3
GPU 应用退出后 × 3
```

#### 方案 B：绕开 procfs 全显存保存机制

测试：

```text
NVreg_PreserveVideoMemoryAllocations=0
禁用 nvidia-suspend/nvidia-resume/nvidia-hibernate 服务
```

这样改用 NVIDIA 默认的内核回调机制，直接绕开本次卡住的 `/proc/driver/nvidia/suspend` 路径。

优点：

- 与本次直接阻塞点高度对应；
- 网上有用户通过此路径恢复 suspend。

风险：

- 只能可靠保存较少显存；
- Wayland、浏览器、游戏或 CUDA 应用恢复后可能花屏、崩溃或丢失 GPU 状态；
- NVIDIA 官方指出高级 CUDA/UVM 功能需要 procfs 机制。

参考：

- [PreserveVideoMemoryAllocations + systemd services causes resume from hibernate to fail](https://forums.developer.nvidia.com/t/preservevideomemoryallocations-systemd-services-causes-resume-from-hibernate-to-fail/233643)

#### 方案 C：禁用 Runtime D3

测试模块参数：

```text
NVreg_DynamicPowerManagement=0x00
```

Fedora 混合显卡用户报告该设置解决随机 suspend 失败。

优点：

- 若根因是独显运行时断电状态与系统 suspend 冲突，可能直接避开该状态机。

风险和适用性：

- 独显空闲时可能不再完全断电，增加耗电和发热；
- 本机当前只看到 NVIDIA 显示控制器，可能处于独显直连模式，因此该方案匹配度低于典型 Optimus 混合显卡笔记本。

#### 方案 D：挂起前退出 GPU/UVM 客户端

受控测试前退出：

- CUDA/LLM 任务；
- 游戏；
- 浏览器 GPU 进程；
- 录屏、OCR、视频编码和其他长期 GPU 客户端。

如果故障只在某类客户端使用后出现，可以进一步缩小 NVIDIA 内部触发条件。该方法是定位和规避手段，不是驱动根治。

### 9.2 不推荐把服务超时当作根治

本机 `nvidia-suspend.service` 当前：

```text
TimeoutStartUSec=infinity
```

添加启动超时可以避免 systemd 永久等待，但 NVIDIA 驱动可能已经完成部分挂起，强杀脚本后 GPU 状态未必能恢复。除非同时设计失败后的 `resume`/恢复路径，否则不能视为安全修复。

### 9.3 再次现场发生时的取证

如果黑屏后还能通过另一台机器 SSH 进入，优先保存：

```bash
systemctl status nvidia-suspend.service
ps -eo pid,ppid,stat,wchan:40,comm,args | rg 'nvidia-sleep|systemctl suspend'
cat /proc/<nvidia-sleep-pid>/stack
journalctl -b -k --no-pager
nvidia-bug-report.sh
```

若 `nvidia-sleep.sh` 为 `D` 状态且内核栈停在 NVIDIA procfs 写入，可以把底层死锁证据进一步提交给 NVIDIA。

## 10. 附录：可复用命令

### A. 确认启动与异常关机

```bash
journalctl --list-boots --no-pager
last -x | head -n 20
journalctl -b 0 --no-pager | rg -i 'unclean|corrupt|dirty|replay'
```

### B. 区分挂起准备、真正挂起和恢复

```bash
journalctl -b -1 --no-pager -o short-iso |
  rg 'The system will suspend now|nvidia-suspend|nvidia-resume|PM: suspend entry|PM: suspend exit|System returned from sleep'

journalctl -b -1 \
  -u nvidia-suspend.service \
  -u systemd-suspend.service \
  -u nvidia-resume.service \
  --no-pager -o short-iso
```

### C. 检查 hypridle 时间线

```bash
journalctl -b -1 _COMM=hypridle --no-pager -o short-iso |
  rg 'Idled:|Resumed:|dpms|systemctl suspend|PrepareForSleep|session got locked'
```

### D. 检查 NVIDIA 电源配置

```bash
systemctl cat nvidia-suspend.service nvidia-resume.service
systemctl show nvidia-suspend.service \
  -p ExecStart -p TimeoutStartUSec -p TimeoutStopUSec

rg 'PreserveVideoMemory|TemporaryFile|DynamicPower' \
  /etc/modprobe.d /usr/lib/modprobe.d

rg 'PreserveVideoMemoryAllocations|TemporaryFilePath|EnableGpuFirmware' \
  /proc/driver/nvidia/params

cat /sys/power/mem_sleep
```

### E. 排除内存、swap 和存储压力

```bash
sar -f /var/log/sa/saDD -s HH:MM:SS -e HH:MM:SS -r -S -B -W -u -d
df -hT /var/tmp
findmnt -T /var/tmp
journalctl -k -b -1 --no-pager |
  rg -i 'oom|out of memory|Xid|hung task|blocked for more than|I/O error'
```

### F. 验证自动 suspend 已停用

```bash
systemctl --user restart hypridle.service
systemctl --user status hypridle.service --no-pager -n 100
journalctl --user -u hypridle.service -b --no-pager |
  rg 'Registered timeout rule|found [0-9]+ rules|systemctl suspend'
```
