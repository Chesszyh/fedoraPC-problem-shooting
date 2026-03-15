# Fedora Hyprland 启动黑屏与 akmods 启动延迟排查报告

日期: 2026-03-15
主机: `chesszyh`
系统: Fedora + Hyprland + SDDM + NVIDIA

## 1. 问题概述

本次排查涉及两个容易混在一起的问题:

1. 新内核首次启动时，`akmods` 现场编译 NVIDIA / `v4l2loopback` 模块，导致图形目标显著延迟。
2. `SDDM` 的 Wayland greeter 使用 `weston` 时，在 HDMI 线仍插着但外接显示链路状态异常的情况下，把外接输出当成有效显示器，导致登录界面黑屏或出现在不可见输出上。

最终结论:

- “启动很慢”的主因是 `akmods.service`。
- “黑屏但手动进 tty 再起 Hyprland 能进桌面”的主因高度相关于 `SDDM + Weston + NVIDIA + HDMI 悬挂外屏`。
- `Hyprland` 本身不是根因。

## 2. 原始现象

用户描述:

- Fedora + Hyprland
- 最近一次启动时卡了很久
- 最终黑屏，没有自动进入 SDDM 登录页
- 手动 `Ctrl` + `Alt` + `F2` 进入 tty 后，`systemctl restart sddm.service` 仍然黑屏
- 直接在 tty 里执行 `Hyprland` 后可进入桌面

补充信息:

- 曾使用双屏
- 一次异常启动前，副屏电源已拔，但 HDMI 线仍然插着
- 之后拔掉 HDMI 线，系统不再识别副屏

## 3. 关键时间线

### 3.1 上一次异常启动

关键特征:

- `sddm` 已经启动并加载 greeter
- 但 `weston` 识别到 `HDMI-A-1` 与 `eDP-1` 同时连接
- 输入设备先关联到 `HDMI-A-1`
- greeter 虽存活，但用户看到黑屏

核心日志特征:

- `Loading qrc:/theme/Main.qml...`
- `DRM: head 'HDMI-A-1' found ... connected`
- `DRM: head 'eDP-1' found ... connected`
- `associating input device ... with output HDMI-A-1`

这说明:

- `SDDM` 并不是没启动
- greeter 也不是直接崩溃
- 问题更像是 greeter 的输出目标或显示焦点落在了异常的 HDMI 输出

### 3.2 2026-03-15 当前成功启动到 6.19.7

当前内核:

- `6.19.7-200.fc43.x86_64`

关键时间:

- `10:21:01` 开始执行 `akmods.service`
- `10:22:16` 构建并安装 `nvidia-kmod`
- `10:22:36` 构建并安装 `v4l2loopback-kmod`
- `10:22:40` `akmods.service` 完成
- `10:22:40` `sddm.service` 启动
- `10:22:41` `weston` 识别 `HDMI-A-1` 为 `disconnected`
- `10:22:41` 仅启用 `eDP-1`
- `10:22:44` 启动 Hyprland 用户会话

这次能正常进入图形界面，和上次最关键的差异就是:

- HDMI 输出在 greeter 阶段不再被当成可用显示器

## 4. 根因分析

### 4.1 启动慢的根因

`systemd-analyze` 结果显示:

- `akmods.service`: `1min 39.204s`
- `sddm.service @1min 42.698s`

结论:

- 图形目标延迟的直接原因不是 SDDM
- 是新内核第一次启动时，`akmods` 需要为当前内核编译缺失模块

这属于 Fedora + akmods + NVIDIA 的典型行为:

- 每次切换到一个新内核
- 若当前内核缺少相应 kmod
- 首次启动就会在 boot 期间补编译

### 4.2 黑屏的根因

本次证据链支持如下判断:

1. `SDDM` 的 Wayland greeter 使用的是 `weston --shell=kiosk`
2. HDMI 线仍插着时，即便外屏断电或不可见，DRM 仍可能通过 hotplug / EDID 把它识别为 `connected`
3. 在无显式输出策略时，`weston` 可能先初始化 HDMI 输出
4. greeter 可能被绘制到用户不可见或状态异常的外接输出
5. 同一台机器在 HDMI 真正 `disconnected` 时即可正常启动并显示登录界面

因此，“黑屏”的本质不是:

- `Hyprland` 崩溃
- `sddm` 服务根本没起
- NVIDIA 模块没加载

而是:

- `SDDM` 的 greeter 输出路径在 HDMI 悬挂场景下不稳定

## 5. 本次实际修改

### 5.1 清理 SDDM 不存在主题

问题:

- `SDDM` 曾反复报:
  - `The configured theme "01-breeze-fedora" doesn't exist, using the embedded theme instead`

处理:

- 新增文件 [10-theme.conf](/etc/sddm.conf.d/10-theme.conf)

内容:

```ini
[Theme]
Current=
```

作用:

- 明确强制 `SDDM` 使用内置主题
- 不再尝试不存在的 `01-breeze-fedora`

结果:

- 新日志中该主题报错已消失

### 5.2 让 SDDM greeter 忽略 HDMI 外屏

新增文件:

- [20-wayland-greeter.conf](/etc/sddm.conf.d/20-wayland-greeter.conf)
- [weston.ini](/etc/sddm/weston.ini)

`20-wayland-greeter.conf` 内容:

```ini
[Wayland]
CompositorCommand=weston --shell=kiosk --config=/etc/sddm/weston.ini
```

`weston.ini` 内容:

```ini
[output]
name=HDMI-A-1
mode=off

[output]
name=eDP-1
mode=current
```

作用:

- 仅对 `SDDM` 的 greeter 生效
- 强制关闭 `HDMI-A-1`
- 强制使用内屏 `eDP-1`
- 不影响登录进入 Hyprland 后的正常外接屏使用

验证:

- `10:25:58` 重启 `sddm` 后，日志中命令行已变为:
  - `weston --shell=kiosk --config=/etc/sddm/weston.ini`
- 同时日志确认:
  - `HDMI-A-1 ... disconnected`
  - 仅启用 `eDP-1`

### 5.3 优化 akmods 的触发时机

处理:

- 启用 `akmods-shutdown.service`

作用:

- 在关机 / 重启阶段尽量提前构建缺失 kmod
- 目标是减少“下次新内核首次启动时”的 boot 卡顿

说明:

- 该项不会让当前已经发生的 boot 变快
- 它改善的是“以后安装新内核后的下一次启动体验”

### 5.4 去掉无效的 rc.local 启动失败

发现:

- `/etc/rc.d/rc.local` 是空文件
- 但带可执行位，导致 systemd 自动生成 `rc-local.service`
- 每次启动都报 `Exec format error`

处理:

- 去掉 `/etc/rc.d/rc.local` 的可执行位

结果:

- 下次启动不会再生成这个无效失败项

## 6. 未直接修改，但值得记录的问题

### 6.1 `openclaw-gateway.service` 持续失败重启

现象:

- 用户 systemd 中该服务启用
- `Restart=always`
- 大约每 5 秒自动重试
- 单次失败会消耗数秒 CPU 和约 `260MB+` 内存峰值

处理状态:

- 用户已执行:

```bash
systemctl --user disable --now openclaw-gateway.service
```

意义:

- 这不是图形登录前卡顿的主因
- 但它是用户会话里非常明显的持续资源浪费和日志噪音来源

### 6.2 `swaync.service` 配置异常

现象:

- 启动后多次失败
- 之后触发 `Start request repeated too quickly`

影响:

- 对图形登录前关键路径影响较小
- 但用户会话日志会持续报错

建议:

- 后续单独检查 swaync 配置文件

### 6.3 `NetworkManager-wait-online.service` 约 5.4 秒

现象:

- 启动时间约 `5.4s`

但不建议直接关闭，原因:

- 反向依赖 `network-online.target` 的服务很多:
  - `cloudflared.service`
  - `docker.service`
  - `nginx.service`
  - 以及其他网络相关服务

结论:

- 这不是“无副作用可直接优化”的项

## 7. 为什么手动执行 Hyprland 能成功

原因在于:

- 手动从 tty 启动 `Hyprland`，绕过了 `SDDM` 的 greeter 输出路径
- `Hyprland` 自己的输出管理与热插拔处理正常
- 所以即便 `SDDM + weston` 阶段黑屏，手动起 Hyprland 仍可能成功进入桌面

这进一步证明:

- 问题出在 greeter 阶段
- 不在 Hyprland 会话本身

## 8. 可复用的排查流程

以后遇到类似问题，建议按下面顺序排查。

### 8.1 先区分“启动慢”还是“登录界面黑屏”

看:

```bash
systemd-analyze blame | head -20
systemd-analyze critical-chain graphical.target
systemd-analyze critical-chain sddm.service
```

目的:

- 判断是 `akmods` / 网络等待 / 图形目标依赖慢
- 还是 `sddm` 本身起不来

### 8.2 看当前 boot 的 `sddm` 与输出枚举

```bash
journalctl -b -u sddm --no-pager -n 200
journalctl -b --no-pager | rg "HDMI-A-1|eDP-1|Loading qrc:/theme/Main.qml|Starting Wayland user session"
```

目的:

- 判断 `sddm-greeter` 是否已启动
- 判断外接屏是否被识别为 `connected`
- 判断 greeter 是否真的在跑

### 8.3 看是否是新内核首次启动导致 `akmods` 卡住

```bash
uname -r
journalctl -b -u akmods --no-pager -n 200
```

重点看:

- 是否在构建 `nvidia-kmod`
- 是否在构建 `v4l2loopback-kmod`

### 8.4 双屏问题优先验证

如果怀疑外接显示链路:

1. 拔掉 HDMI / DP 物理线
2. 重启验证
3. 观察 greeter 是否恢复

如果恢复:

- 高度怀疑 greeter 输出焦点落到了外接输出

### 8.5 用户会话异常与 boot 关键路径分开看

看:

```bash
systemctl --user status <unit>
journalctl -b --no-pager -p warning..alert
```

不要把以下问题和“登录前黑屏”混为一谈:

- `openclaw-gateway.service` 持续失败
- `swaync.service` 配置错误
- 某些桌面组件的 coredump

它们可能浪费资源，但不一定是开机黑屏的根因。

## 9. 经验总结

本次案例的核心经验:

1. `SDDM` 看到黑屏，不等于 `SDDM` 没启动。
2. `Loading qrc:/theme/Main.qml...` 出现时，greeter 已经在跑。
3. Fedora + NVIDIA + akmods 下，切换到新内核后的首次 boot 慢是正常现象，要和黑屏分开分析。
4. HDMI 线插着但副屏状态异常，足以让 greeter 落到错误输出。
5. 手动起 `Hyprland` 成功，往往说明问题在登录管理器阶段，而不是桌面会话本身。

## 10. 当前状态

当前已完成:

- SDDM 不存在主题已清理
- SDDM greeter 已限制为只使用内屏
- `akmods-shutdown.service` 已启用
- 空的 `rc.local` 误启动已清理
- `openclaw-gateway.service` 已由用户手动禁用

预计效果:

- 下次即使 HDMI 线仍插着，SDDM greeter 也不应再跑去外屏
- 下次安装新内核后，首次启动的 `akmods` 卡顿概率和时长应有所改善
- 启动日志噪音会减少

