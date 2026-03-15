# Fedora Hyprland / SDDM 启动问题速查版

适用场景:

- 开机卡很久
- 黑屏不出 SDDM
- 进了 tty 但不确定是 `akmods`、`SDDM`、外接屏，还是用户会话服务的问题

使用原则:

- 先区分“启动慢”与“黑屏”
- 再区分“`SDDM` 没起来”与“`SDDM` 已起来但画面跑错输出”
- 最后再看用户会话里的额外报错

## 0. 最快判断

### 0.1 当前内核

```bash
uname -r
```

如果刚切到新内核，优先怀疑 `akmods`。

### 0.2 现在系统是否已经进图形目标

```bash
systemctl is-active graphical.target
systemctl status sddm.service --no-pager
```

判断:

- `graphical.target` 已激活，但屏幕黑: 优先查 `SDDM` 输出路径
- `sddm.service` 还没起来: 优先查启动链阻塞

## 1. 开机卡很久

### 1.1 看是谁拖慢了启动

```bash
systemd-analyze blame | head -20
systemd-analyze critical-chain graphical.target
systemd-analyze critical-chain sddm.service
```

重点判断:

- `akmods.service` 接近 1 分钟以上: 新内核首启现场编译 kmod
- `NetworkManager-wait-online.service` 明显偏长: 有网络依赖链
- 其他慢项再单独分析

### 1.2 看 `akmods` 是否在编 NVIDIA

```bash
journalctl -b -u akmods --no-pager -n 200
```

重点看:

- `Building and installing nvidia-kmod`
- `Building and installing v4l2loopback-kmod`

如果看到了，说明“慢”主要是正常的首次编译行为。

### 1.3 确认当前内核的 NVIDIA 模块是否已经加载

```bash
lsmod | rg '^nvidia|^v4l2loopback'
modinfo -F vermagic nvidia 2>/dev/null
```

## 2. 黑屏但怀疑 SDDM

### 2.1 看 `SDDM` 是否已经起来

```bash
journalctl -b -u sddm --no-pager -n 200
```

重点看:

- `Started sddm.service`
- `Loading qrc:/theme/Main.qml...`
- `Starting Wayland user session`

判断:

- 出现 `Loading qrc:/theme/Main.qml...`: greeter 已经在跑
- 没出现: 再看 `sddm` 为什么没拉起 greeter

### 2.2 直接看 greeter 的 Wayland 输出枚举

```bash
journalctl -b --no-pager | rg "HDMI-A-1|eDP-1|Loading qrc:/theme/Main.qml|Starting Wayland user session|Command line: /usr/bin/weston"
```

重点判断:

- `HDMI-A-1 ... connected` 且 `eDP-1 ... connected`: 小心 greeter 跑到外屏
- `HDMI-A-1 ... disconnected`: 外接显示器不是当前问题重点
- `weston --shell=kiosk --config=/etc/sddm/weston.ini`: 说明已启用 SDDM 专用输出限制

### 2.3 直接验证外接屏是否还被系统识别

进入桌面后:

```bash
hyprctl monitors all
```

如果怀疑悬空 HDMI:

1. 物理拔掉 HDMI / DP 线
2. 再重启验证

## 3. tty 里临时救援

### 3.1 切到 tty

```text
Ctrl + Alt + F2
```

### 3.2 看 SDDM 当前状态

```bash
systemctl status sddm.service --no-pager
```

### 3.3 临时重启 SDDM

```bash
sudo systemctl restart sddm.service
```

如果仍黑屏，再看输出日志:

```bash
journalctl -b -u sddm --no-pager -n 200
```

### 3.4 临时手动起 Hyprland

```bash
Hyprland
```

如果这样能进桌面，通常说明:

- 问题更偏向 greeter 阶段
- 不一定是 Hyprland 会话本身坏了

## 4. 双屏 / 外接屏问题专项

### 4.1 查看 SDDM 的 greeter 当前是否已被限制只走内屏

```bash
sudo cat /etc/sddm.conf.d/20-wayland-greeter.conf
sudo cat /etc/sddm/weston.ini
```

当前推荐配置应类似:

```ini
[Wayland]
CompositorCommand=weston --shell=kiosk --config=/etc/sddm/weston.ini
```

```ini
[output]
name=HDMI-A-1
mode=off

[output]
name=eDP-1
mode=current
```

### 4.2 重启 SDDM 后确认配置实际生效

```bash
sudo systemctl restart sddm.service
journalctl -b --since "5 min ago" --no-pager | rg "Command line: /usr/bin/weston|head 'HDMI-A-1'|head 'eDP-1'|Output 'eDP-1'|Output 'HDMI-A-1'"
```

判断:

- 命令行出现 `--config=/etc/sddm/weston.ini`: 配置已生效
- 只启用 `eDP-1`: greeter 输出限制正常

## 5. SDDM 主题问题

### 5.1 查主题报错

```bash
journalctl -b -u sddm --no-pager | rg "theme|Current=|doesn't exist"
```

### 5.2 看当前显式主题设置

```bash
sudo cat /etc/sddm.conf.d/10-theme.conf
```

推荐:

```ini
[Theme]
Current=
```

作用:

- 直接使用 embedded theme
- 避免指向不存在主题

## 6. 新内核后减少 akmods 启动卡顿

### 6.1 检查是否启用了关机阶段预编译

```bash
sudo systemctl is-enabled akmods-shutdown.service
```

期望输出:

```text
enabled
```

### 6.2 如果未启用，启用它

```bash
sudo systemctl enable akmods-shutdown.service
```

说明:

- 不能保证完全消除卡顿
- 但可以尽量把“下次启动的编译”搬到“本次关机”阶段

## 7. 启动日志里的噪音项

这些项目不一定是启动黑屏根因，但值得顺手检查。

### 7.1 `rc-local.service` 每次失败

查看:

```bash
ls -l /etc/rc.d/rc.local
journalctl -b --no-pager | rg "rc-local|rc.local"
```

如果是空文件但带执行位，可去掉执行位:

```bash
sudo chmod 0644 /etc/rc.d/rc.local
```

### 7.2 `openclaw-gateway.service` 持续失败重启

查看:

```bash
systemctl --user status openclaw-gateway.service --no-pager
systemctl --user cat openclaw-gateway.service
```

如果暂时不用:

```bash
systemctl --user disable --now openclaw-gateway.service
```

### 7.3 `swaync.service` 失败

查看:

```bash
systemctl --user status swaync.service --no-pager
journalctl --user -b --no-pager | rg "swaync"
```

### 7.4 `xdg-desktop-portal-hyprland` / 其他用户会话崩溃

查看:

```bash
journalctl -b --no-pager -p warning..alert
coredumpctl list --no-pager | tail -20
```

## 8. 如果下次再次遇到黑屏，建议按这个顺序执行

### 路线 A: 还没进桌面，只能 tty

```bash
uname -r
systemctl status sddm.service --no-pager
systemd-analyze critical-chain sddm.service
journalctl -b -u akmods --no-pager -n 200
journalctl -b -u sddm --no-pager -n 200
journalctl -b --no-pager | rg "HDMI-A-1|eDP-1|Loading qrc:/theme/Main.qml|Starting Wayland user session|weston"
```

### 路线 B: 已经进桌面，做复盘

```bash
systemd-analyze blame | head -20
systemd-analyze critical-chain graphical.target
hyprctl monitors all
systemctl --user status openclaw-gateway.service --no-pager
systemctl --user status swaync.service --no-pager
journalctl -b --no-pager -p warning..alert -n 200
```

## 9. 本机当前已知有效状态

建议保留以下配置:

- [10-theme.conf](/etc/sddm.conf.d/10-theme.conf)
- [20-wayland-greeter.conf](/etc/sddm.conf.d/20-wayland-greeter.conf)
- [weston.ini](/etc/sddm/weston.ini)

建议保留以下优化:

- `akmods-shutdown.service` 已启用
- `/etc/rc.d/rc.local` 不再带执行位
- 若不用 `openclaw-gateway`，保持其禁用

