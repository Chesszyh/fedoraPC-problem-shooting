# Fedora Hyprland VS Code inotify 耗尽导致图形会话崩溃报告

生成时间: 2026-06-14T17:41:16+08:00

## 1. Problem Description

2026-06-14 17:25 左右，用户在 Fedora Hyprland 桌面中使用 VS Code 时，VS Code 曾提示“无法监听文件更改”。随后图形界面黑屏，表现为 Hyprland 桌面会话被整体带下线。用户重新拉起 Hyprland 后再次打开 VS Code，问题暂时恢复。

本次排查目标是确认：

- 这是 VS Code 自身崩溃、GPU/驱动问题，还是 Hyprland/Portal/DBus 链路问题。
- VS Code 提示“无法监听文件更改”和黑屏是否相关。
- 含 `node_modules` 的仓库是否是触发因素。

最终结论：这次不是整机重启，也不是 NVIDIA 驱动 Xid/NVRM 级别崩溃；更符合 `inotify` watcher 资源耗尽后，用户会话中的 systemd/DBus/Portal 链条失稳，`xdg-desktop-portal-hyprland` 在 `libwayland-client.so.0.24.0` 中 SIGSEGV，UWSM/systemd 随后结束旧 Hyprland 图形会话。VS Code 打开含 `node_modules` 的仓库是高概率诱因。

## 2. Environment and Scope

- 主机：`chesszyh`
- 系统：Fedora Linux 43 Workstation
- 桌面：Hyprland under UWSM
- 内核：`7.0.12-101.fc43.x86_64`
- GPU：NVIDIA GeForce RTX 4060 Mobile
- NVIDIA 驱动：`580.159.04`
- Hyprland 包：`hyprland-0.51.1-3.fc43.x86_64`
- Portal 包：`xdg-desktop-portal-hyprland-1.3.11-1.fc43.x86_64`
- Wayland 库：`wayland-1.24.0-1.fc43.x86_64`
- VS Code 包：`code-1.124.2-1781225578.el8.x86_64`
- systemd：`systemd-258.8-1.fc43.x86_64`
- DBus broker：`dbus-broker-37-2.fc43.x86_64`

本报告只覆盖 2026-06-14 当前 boot 中 17:24-17:28 附近的图形会话事故。报告没有修改系统配置，也没有安装、卸载或重装软件。

## 3. Symptoms and Reproduction

用户可见现象：

- VS Code 先提示“无法监听文件更改”。
- 崩溃前打开过一个含有 `node_modules` 的仓库。
- 随后 Hyprland 图形界面黑屏。
- 重新拉起 Hyprland 后，再打开 VS Code 又恢复正常。

系统侧关键现象：

```text
Jun 14 17:25:23 systemd[2295]: app-flatpak-com.qq.QQ-9364390.scope:
Failed to add control inotify watch descriptor ... 设备上没有空间

Jun 14 17:25:32 dbus-broker-launch[2553]:
ERROR dirwatch_add ... No space left on device

Jun 14 17:25:32 kernel:
xdg-desktop-por[5421]: segfault ... in libwayland-client.so.0.24.0

Jun 14 17:25:33 systemd-coredump:
Process 5421 (xdg-desktop-por) of user 1000 dumped core.

Jun 14 17:25:37 systemd-coredump:
Process 7885 (code) of user 1000 dumped core.
```

这里的 `设备上没有空间` / `No space left on device` 不是磁盘空间耗尽。现场检查显示根分区和 home 仍有可用空间：

```text
/dev/nvme0n1p3  953G  710G  233G  76% /
/dev/nvme0n1p3  953G  710G  233G  76% /home
```

该错误在这类上下文中指向 inotify watcher 或相关内核监听资源耗尽。

## 4. Investigation Timeline

### 17:24-17:25：VS Code 活跃并触发监听资源压力

17:24 左右系统记录到新的 VS Code scope：

```text
Jun 14 17:24:00 systemd[2295]: Started app-Hyprland-code-5a58447c.scope - code.
Jun 14 17:24:01 systemd[2295]: Started app-code-718461.scope.
```

用户补充：崩溃前 VS Code 提示“无法监听文件更改”，并且打开过含 `node_modules` 的仓库。这个提示与后续 inotify 报错吻合。

### 17:25:23-17:25:31：用户 systemd 开始无法添加 inotify watch

多个用户应用 scope 创建时失败：

```text
Failed to add control inotify watch descriptor ... 设备上没有空间
Failed to add memory inotify watch descriptor ... 设备上没有空间
```

受影响对象包括：

- `app-flatpak-com.qq.QQ-9364390.scope`
- `flatpak-portal.service`
- `app-flatpak-com.qq.QQ-27037450.scope`
- `app-flatpak-com.tencent.WeChat-1103204328.scope`
- Telegram 相关 DBus service

这说明问题已经不局限于 VS Code，而是用户会话管理层的资源也开始申请失败。

### 17:25:32：DBus 和 Portal 链条断裂

DBus broker 在重载配置时无法添加目录监听：

```text
dbus-broker-launch[2553]: ERROR dirwatch_add @ ../src/util/dirwatch.c +122: No space left on device
```

随后多项依赖 DBus 的用户会话服务异常退出或被停止：

- `xdg-permission-store.service`
- `xdg-desktop-portal.service`
- `xdg-document-portal.service`
- `flatpak-session-helper.service`
- `gvfsd`
- `fcitx5`
- `swaync`
- `wireplumber` 的 DBus 连接

### 17:25:32-17:25:33：`xdg-desktop-portal-hyprland` 崩溃

内核和 coredump 记录显示：

```text
xdg-desktop-por[5421]: segfault at 6c ip ... error 6 in libwayland-client.so.0.24.0
```

coredump 栈顶：

```text
#0 wl_map_insert_at (libwayland-client.so.0 + 0x3731)
#1 proxy_destroy (libwayland-client.so.0 + 0x38a1)
#2 wl_proxy_marshal_array_flags (libwayland-client.so.0 + 0x3df7)
#3 wl_proxy_marshal_flags (libwayland-client.so.0 + 0x4ad2)
#4 Hyprutils::Memory::CSharedPointer<CCWlOutput>::_delete
#5 CPortalManager::~CPortalManager
```

崩溃进程：

```text
Executable: /usr/libexec/xdg-desktop-portal-hyprland
Package: xdg-desktop-portal-hyprland/1.3.11-1.fc43
Signal: 11 (SEGV)
```

### 17:25:32-17:25:39：旧 Hyprland 会话被结束

系统停止用户图形会话相关服务：

```text
Stopped target graphical-session.target
Stopped target wayland-session@hyprland.desktop.target
Stopping wayland-wm@hyprland.desktop.service
```

旧 Hyprland 主服务统计：

```text
wayland-wm@hyprland.desktop.service:
Consumed 5h 44min 25.225s CPU time, 8.8G memory peak, 3.3G memory swap peak.
```

旧 VS Code scope 统计：

```text
app-code-7885.scope:
Consumed 1h 58min 59.006s CPU time, 5.5G memory peak, 2.6G memory swap peak.
```

### 17:25:37：VS Code 本体也发生 SIGTRAP core dump

```text
Process 7885 (code) of user 1000 dumped core.
Signal: 5 (TRAP)
Command Line: /usr/share/code/code
```

这说明 VS Code 确实崩溃，但从时间链看，它不是唯一崩溃点。更关键的是在它之前，用户会话已经出现 inotify 资源耗尽、DBus 重载失败和 Portal 崩溃。

### 17:26 后：重新拉起 Hyprland 后恢复

当前 boot 没有重启，Hyprland 在新会话中重新启动：

```text
wayland-wm@hyprland.desktop.service
Active: active (running) since Sun 2026-06-14 17:26:13 CST
```

`xdg-desktop-portal-hyprland.service` 也在新会话中正常运行：

```text
Active: active (running) since Sun 2026-06-14 17:26:14 CST
```

重新拉起后资源被释放，VS Code 再打开时暂时恢复正常，这符合 inotify watcher 被旧会话进程释放后的表现。

## 5. Root Cause

根因不是“磁盘满”，也不是“单纯 VS Code 崩溃”，而是：

1. VS Code 打开含 `node_modules` 的仓库后，文件监听需求显著增加。
2. 当前系统 `fs.inotify.max_user_watches = 124821`、`fs.inotify.max_user_instances = 128`，在大仓库、Electron 应用、Flatpak 应用和桌面服务共同运行时被打到上限。
3. VS Code 先给出“无法监听文件更改”的用户可见提示。
4. 随后用户 systemd 和 DBus broker 也无法添加 inotify watch，出现 `设备上没有空间` / `No space left on device`。
5. DBus/Portal 相关服务连锁异常，`xdg-desktop-portal-hyprland` 在 Wayland proxy 清理路径中 SIGSEGV。
6. UWSM/systemd 将旧 Hyprland 图形会话整体结束，表现为黑屏。

证据支持点：

- 事故前后没有看到 `NVRM`、`Xid`、OOM kill、NVMe I/O error 等 GPU/内核硬件级崩溃证据。
- `nvidia-smi` 显示 NVIDIA 驱动版本和当前 GPU 状态正常。
- 磁盘空间和 inode 不是问题。
- 现场日志中 inotify watch 创建失败早于 Portal core dump。
- 重启 Hyprland 会话后旧 watcher 被释放，问题立即缓解。
- 当前新会话中 VS Code 仍是主要 watcher 使用者之一，单个 VS Code 进程观察到约 `9934` 个 watches。

## 6. Changes Made

本次没有修改系统配置。

已执行的操作仅包括：

- 查看 boot 和用户会话时间线。
- 查看 coredump 列表和 `coredumpctl info`。
- 查看内核日志中是否存在 GPU、OOM、NVMe 错误。
- 查看用户 journal 中 VS Code、Hyprland、Portal、DBus、systemd 相关日志。
- 检查磁盘空间、内存、swap、NVIDIA 当前状态。
- 检查当前 inotify 上限和新会话中的 watcher 使用情况。

未执行：

- 未修改 `/etc/sysctl.d/`。
- 未修改 VS Code `settings.json`。
- 未重装 VS Code、Hyprland、Portal 或 NVIDIA 驱动。
- 未禁用任何桌面服务。

## 7. Verification

已确认当前状态：

```text
wayland-wm@hyprland.desktop.service
Active: active (running) since Sun 2026-06-14 17:26:13 CST

xdg-desktop-portal-hyprland.service
Active: active (running) since Sun 2026-06-14 17:26:14 CST
```

已确认当前 NVIDIA 驱动正常响应：

```text
NVIDIA-SMI 580.159.04
Driver Version: 580.159.04
GPU: NVIDIA GeForce RTX 4060 Mobile
```

已确认磁盘不是触发原因：

```text
/dev/nvme0n1p3  953G  710G  233G  76% /
/dev/nvme0n1p3  953G  710G  233G  76% /home
tmpfs           1.6G  5.9M  1.6G   1% /run/user/1000
```

已确认当前 inotify 上限：

```text
fs.inotify.max_user_watches = 124821
fs.inotify.max_user_instances = 128
fs.inotify.max_queued_events = 16384
```

已确认新会话中 VS Code 仍是 watcher 使用大户：

```text
9934 watches   2 fds pid=732925 code
1733 watches   3 fds pid=733103 code
```

## 8. Problems Encountered During Debugging

### 误区 1：把黑屏直接归因于 NVIDIA 驱动

这台机器之前发生过 NVIDIA 用户态/内核模块版本不匹配导致 llvmpipe 或图形性能异常的问题。因此第一反应容易怀疑 GPU。但本次事故窗口内没有 `NVRM`、`Xid`、GPU reset、OOM kill 等证据，`nvidia-smi` 也正常。

### 误区 2：把 `设备上没有空间` 当成磁盘满

日志中的 `设备上没有空间` 出现在 `Failed to add ... inotify watch descriptor` 和 `dirwatch_add` 上下文中，语义是监听资源耗尽，而不是文件系统空间不足。`df -h` 和 `df -ih` 已排除磁盘空间和 inode。

### 误区 3：只看 VS Code core dump

VS Code 的确在 17:25:37 SIGTRAP core dump，但在它之前已经出现：

- 用户 systemd 添加 inotify watch 失败。
- DBus broker `dirwatch_add` 失败。
- `xdg-desktop-portal-hyprland` SIGSEGV。
- 图形会话目标开始停止。

因此 VS Code 是诱因或参与者，不是唯一崩溃点。

### 误区 4：重启后问题消失容易误判为偶发

重新拉起 Hyprland 会释放旧会话进程持有的 watcher，因此问题短期消失是预期现象，不代表根因已经修复。

## 9. Reuse Notes and Lessons

下次遇到类似现象时，应优先判断是否是 inotify 资源耗尽：

- VS Code 提示“无法监听文件更改”。
- systemd 用户日志出现 `Failed to add ... inotify watch descriptor`。
- DBus 日志出现 `dirwatch_add ... No space left on device`。
- 桌面服务、Portal、Flatpak、通知、输入法或 GVFS 同时异常。
- 重启图形会话后暂时恢复。

长期修复建议：

1. 提高 inotify 上限，例如：

```bash
printf '%s\n' \
  'fs.inotify.max_user_watches = 1048576' \
  'fs.inotify.max_user_instances = 1024' \
  'fs.inotify.max_queued_events = 32768' |
  sudo tee /etc/sysctl.d/99-inotify.conf
sudo sysctl --system
```

2. 在 VS Code 中排除大目录监听，尤其是：

```json
{
  "files.watcherExclude": {
    "**/node_modules/**": true,
    "**/.git/objects/**": true,
    "**/.git/subtree-cache/**": true,
    "**/dist/**": true,
    "**/build/**": true,
    "**/.next/**": true,
    "**/.cache/**": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/dist": true,
    "**/build": true,
    "**/.next": true,
    "**/.cache": true
  }
}
```

3. 对特别大的 JavaScript/TypeScript 仓库，优先从仓库根部的 `.vscode/settings.json` 做项目级排除，避免全局设置误伤其他项目。

4. 排查时不要直接重启机器。先保留现场，抓取 journal、coredump、inotify 统计，再重启会话。

## 10. Appendix: Reusable Commands

### 查看 boot 和事故时间线

```bash
journalctl --list-boots --no-pager | tail -8
journalctl --user -b --since "2026-06-14 17:24:30" --until "2026-06-14 17:27:30" --no-pager
journalctl -b --since "2026-06-14 17:24:30" --until "2026-06-14 17:27:30" --no-pager
```

### 查找 inotify 资源耗尽证据

```bash
journalctl --user -b --since "1 hour ago" --no-pager | grep -E 'inotify|No space|设备上没有空间|dirwatch'
sysctl fs.inotify.max_user_watches fs.inotify.max_user_instances fs.inotify.max_queued_events
```

### 统计当前进程 inotify watch 使用量

```bash
for p in /proc/[0-9]*; do
  pid=${p##*/}
  comm=$(cat "$p/comm" 2>/dev/null) || continue
  total=0
  fds=0
  for f in "$p"/fdinfo/*; do
    [ -r "$f" ] || continue
    c=$(grep -c '^inotify' "$f" 2>/dev/null || true)
    if [ "${c:-0}" -gt 0 ]; then
      total=$((total + c))
      fds=$((fds + 1))
    fi
  done
  if [ "$total" -gt 0 ]; then
    printf "%7s watches %3s fds pid=%-7s %s\n" "$total" "$fds" "$pid" "$comm"
  fi
done | sort -nr | head -40
```

### 查看 coredump

```bash
coredumpctl list --no-pager --since "2 hours ago"
coredumpctl info --no-pager 5421
coredumpctl info --no-pager 7885
```

### 排除 GPU/OOM/NVMe 类错误

```bash
journalctl -k -b --since "2 hours ago" --no-pager |
  grep -E 'NVRM|Xid|gpu|nvidia|drm|oom|out of memory|Killed process|nvme|I/O error|watchdog|blocked'

nvidia-smi
free -h
swapon --show
df -h / /home /run/user/1000
df -ih / /home /run/user/1000
```

### 查看当前 Hyprland 和 Portal 状态

```bash
pgrep -a Hyprland
systemctl --user --no-pager --full status \
  wayland-wm@hyprland.desktop.service \
  xdg-desktop-portal-hyprland.service
```
