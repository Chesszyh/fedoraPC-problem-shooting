# Fedora Hyprland Snipaste AppImage FUSE 挂载耗尽与 Rofi 启动项失效报告

生成时间: 2026-06-29T12:03:39+08:00

## Problem Description

Fedora Hyprland 桌面持续弹出 AppImage 错误通知：

```text
Cannot mount AppImage, please check your FUSE setup.
You might still be able to extract the contents of this AppImage
if you run it with the --appimage-extract option.
See https://github.com/AppImage/AppImageKit/wiki/FUSE
for more information
```

用户还观察到两个后续问题：

- 开机自启动后，有时顶部 Waybar 看不到 Snipaste 托盘图标。
- 手动 `pkill -9 Snipaste` 后，想通过 `Win+D` 从 Rofi/自定义应用启动器重新启动 Snipaste，但启动器里找不到 Snipaste。

最终确认问题集中在 Snipaste 的 AppImage 启动链，而不是 Hyprland 本身，也不是系统缺少 FUSE 包。

## Environment and Scope

- 主机环境：Fedora 43 Workstation，Hyprland Wayland 会话。
- 桌面栏：Waybar user service。
- 应用启动器：`Win+D` 绑定到 `/home/chesszyh/.config/hypr/UserScripts/DarkAngelAppLauncher.py`。
- AppImage 管理：AppImageLauncher 3.0.0 alpha。
- 涉及应用：`/home/chesszyh/Applications/Snipaste-2.11.3-x86_64_9fa0ae9967819a4a166804ebf074147e.AppImage`。
- 主要变更范围：
  - `/home/chesszyh/.config/systemd/user/snipaste.service`
  - `/home/chesszyh/.local/share/applications/appimagekit_d633ea4a4d9488cf7d4c6898954c4231-Snipaste.desktop`
  - `/home/chesszyh/.config/systemd/user/rofi-invalid-launchers.service`
  - 删除 `/home/chesszyh/.local/bin/snipaste-wayland-wrapper`
  - 删除 `/home/chesszyh/.config/systemd/user/snipaste-clipboard-bridge.service`

## Symptoms and Reproduction

### AppImage 弹窗持续出现

用户截图显示 `Cannot mount AppImage`。用户日志中对应条目来自 `snipaste-wayland-wrapper`：

```text
snipaste-wayland-wrapper: fusermount: too many FUSE filesystems mounted; mount_max=N can be set in /etc/fuse.conf
snipaste-wayland-wrapper: Cannot mount AppImage, please check your FUSE setup.
```

### FUSE 包实际存在

检查发现系统已安装 FUSE 2/3 相关包，`/dev/fuse` 也存在：

```bash
rpm -q fuse fuse-libs fuse3 fuse3-libs appimagelauncher
ls -l /dev/fuse
```

关键输出：

```text
fuse-2.9.9-24.fc43.x86_64
fuse-libs-2.9.9-24.fc43.x86_64
fuse3-3.16.2-6.fc43.x86_64
fuse3-libs-3.16.2-6.fc43.x86_64
appimagelauncher-3.0.0_alpha_4_gha261~5a65ad0-1.x86_64
crw-rw-rw-. 1 root root 10, 229 ... /dev/fuse
```

### Snipaste 重启风暴

`snipaste.service` 处于失败后自动重启状态，重启次数超过 1100 次：

```text
Active: activating (auto-restart) (Result: exit-code)
ExecStart=/home/chesszyh/.local/bin/snipaste-wayland-wrapper (code=exited, status=127)
NRestarts=1148
```

### FUSE mount 数量异常

`mount` 里存在大量 Snipaste AppImage 残留挂载：

```text
Snipaste-2.11.3-...AppImage on /tmp/.mount_Snipas... type fuse.Snipaste-2.11.3-...AppImage
```

统计结果：

```text
mount_count:1001
```

其中 Snipaste 残留挂载清理前约 998 个。

### Rofi 启动器找不到 Snipaste

Snipaste 的 `.desktop` 文件仍指向已经删除或准备删除的 wrapper：

```ini
Exec=/home/chesszyh/.local/bin/snipaste-wayland-wrapper
```

自定义启动器会解析 `.desktop` 的 `Exec`，并过滤掉命令不存在的启动项。因此 wrapper 删除后，`Win+D` 启动器中 Snipaste 被视为无效应用。

## Investigation Timeline

1. 先从用户截图确认错误类型是 AppImage FUSE mount 失败，而不是普通应用崩溃。
2. 查询当前进程，发现 Snipaste AppImage 与 AppImageLauncher 的 `binfmt-bypass` 相关进程仍存在。
3. 搜索用户 journal，定位到 `snipaste-wayland-wrapper` 每隔数秒输出 `Cannot mount AppImage`。
4. 检查 FUSE 包、`/dev/fuse` 和用户组，排除“系统未安装 FUSE”这一常见解释。
5. 检查 `systemctl --user status snipaste.service`，发现 `Restart=on-failure` 导致服务失败后不断重启，`NRestarts` 已超过 1100。
6. 检查 `mount`，发现约 1000 个 Snipaste AppImage FUSE 挂载点，确认 `fusermount` 的 `too many FUSE filesystems mounted` 是直接触发条件。
7. 停止 `snipaste.service` 和 `snipaste-clipboard-bridge.service`，批量卸载 `/tmp/.mount_Snipas*` 残留挂载，Snipaste 相关 FUSE mount 从 998 降为 0。
8. 按用户要求完全移除 `~/.local/bin/snipaste-wayland-wrapper`，改为只保留一个 Snipaste systemd 自启动入口。
9. 初次将 `snipaste.service` 改为直接启动 AppImage 后，发现已有 Snipaste 实例仍运行，直接启动会退出，systemd 显示 `status=1/FAILURE`。
10. 清理旧 Snipaste 进程和残留挂载后，重新启动 `snipaste.service`，服务进入 `active (running)`。
11. 根据用户反馈继续检查 `Win+D` 找不到 Snipaste，定位到 `.desktop` 的 `Exec` 仍引用 wrapper。
12. 修改 Snipaste `.desktop`，让 Rofi 启动器直接启动 AppImage，并保留原 wrapper 中的 Qt 兼容环境变量。
13. 为降低开机时托盘图标偶发缺失概率，让 `snipaste.service` 显式 `Wants=waybar.service`、`After=waybar.service`，并加入 `ExecStartPre=/usr/bin/sleep 5`。
14. 发现 `rofi-invalid-launchers.service` 指向不存在的 `MaterialA1AppLauncher.py`，修正为真实存在且当前 `Win+D` 使用的 `DarkAngelAppLauncher.py`。
15. 运行 `systemctl --user daemon-reload`、重启服务、刷新 desktop database，并验证 Snipaste 已回到启动器索引。

## Root Cause

根因由两个配置漂移叠加造成。

第一层根因是 Snipaste 的 user service 通过 wrapper 启动 AppImage，并设置：

```ini
Restart=on-failure
RestartSec=3
```

当 Snipaste/AppImage 启动失败或 wrapper 返回非零状态时，systemd 每 3 秒重启一次。大量重启产生大量未及时释放的 Snipaste AppImage FUSE mount，最终触发：

```text
fusermount: too many FUSE filesystems mounted; mount_max=N can be set in /etc/fuse.conf
```

此后新的 AppImage 启动都会失败，并继续刷 `Cannot mount AppImage`。

第二层根因是用户要求移除 wrapper 后，Snipaste 的 `.desktop` 启动项仍保留：

```ini
Exec=/home/chesszyh/.local/bin/snipaste-wayland-wrapper
```

自定义 Rofi 启动器会检查 `Exec` 中的命令是否存在。wrapper 删除后，该启动项被判断为无效，因此 `Win+D` 中找不到 Snipaste。

托盘图标偶发缺失不是 FUSE 错误的直接原因，更可能是开机时 Snipaste 早于 Waybar/status-notifier 托盘组件启动，导致托盘注册时机不稳定。修复中通过 systemd 顺序和短延迟降低该 race 的概率。

## Changes Made

### 1. 删除 wrapper

删除文件：

```text
/home/chesszyh/.local/bin/snipaste-wayland-wrapper
```

删除原因：用户明确要求不再保留 wrapper；同时避免 `.desktop` 和 service 继续引用额外脚本层。

### 2. 删除额外 Snipaste bridge service

删除文件：

```text
/home/chesszyh/.config/systemd/user/snipaste-clipboard-bridge.service
```

并执行：

```bash
systemctl --user disable --now snipaste-clipboard-bridge.service
```

删除原因：用户要求只保留一个可开机自启动的 Snipaste systemd 入口。

### 3. 修改 Snipaste user service

修改文件：

```text
/home/chesszyh/.config/systemd/user/snipaste.service
```

最终保留一个直接启动 AppImage 的 service，并内联原 wrapper 的兼容环境变量：

```ini
[Unit]
Description=Snipaste with Hyprland-compatible rendering settings
Wants=waybar.service
After=graphical-session.target waybar.service
PartOf=graphical-session.target
ConditionEnvironment=DISPLAY

[Service]
Type=exec
Environment=QT_QPA_PLATFORM=xcb
Environment=QT_OPENGL=software
Environment=QT_XCB_GL_INTEGRATION=none
Environment=QSG_RHI_BACKEND=software
Environment=LIBGL_ALWAYS_SOFTWARE=1
ExecStartPre=/usr/bin/sleep 5
ExecStart=%h/Applications/Snipaste-2.11.3-x86_64_9fa0ae9967819a4a166804ebf074147e.AppImage
Restart=on-abnormal
RestartSec=10

[Install]
WantedBy=graphical-session.target
```

关键变化：

- `ExecStart` 从 wrapper 改为 AppImage。
- `Restart=on-failure` 改为 `Restart=on-abnormal`，避免普通退出也被快速拉起。
- `RestartSec=3` 改为 `RestartSec=10`，降低失败循环压力。
- 增加 Waybar 顺序依赖和 5 秒延迟，缓解托盘注册 race。

### 4. 修改 Snipaste desktop entry

修改文件：

```text
/home/chesszyh/.local/share/applications/appimagekit_d633ea4a4d9488cf7d4c6898954c4231-Snipaste.desktop
```

将 `Exec` 从 wrapper 改为直接启动 AppImage：

```ini
Exec=env QT_QPA_PLATFORM=xcb QT_OPENGL=software QT_XCB_GL_INTEGRATION=none QSG_RHI_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 /home/chesszyh/Applications/Snipaste-2.11.3-x86_64_9fa0ae9967819a4a166804ebf074147e.AppImage
```

这样 `Win+D` 的应用启动器可以解析到真实可执行文件，不再因为 wrapper 缺失而过滤 Snipaste。

### 5. 修复 invalid launcher 清理服务

修改文件：

```text
/home/chesszyh/.config/systemd/user/rofi-invalid-launchers.service
```

将不存在的脚本：

```ini
ExecStart=%h/.config/hypr/UserScripts/MaterialA1AppLauncher.py --clean --apply
```

改为当前实际使用的脚本：

```ini
ExecStart=%h/.config/hypr/UserScripts/DarkAngelAppLauncher.py --clean --apply
```

## Verification

### Snipaste service 运行状态

验证命令：

```bash
systemctl --user show snipaste.service -p ActiveState -p SubState -p Result -p NRestarts -p ExecMainPID --no-pager
```

关键结果：

```text
Id=snipaste.service
ActiveState=active
SubState=running
Result=success
NRestarts=0
ExecMainPID=231354
```

### Snipaste FUSE mount 数恢复正常

验证命令：

```bash
mount | rg -i "Snipaste|/tmp/\\.mount_Snipas" | wc -l
```

结果：

```text
1
```

说明当前只剩 Snipaste 正常运行所需的一个 AppImage FUSE mount，不再是异常堆积的约 1000 个。

### Snipaste 启动项回到应用启动器索引

通过导入 `DarkAngelAppLauncher.py` 并查询有效应用项，确认 Snipaste 存在：

```text
appimagekit_d633ea4a4d9488cf7d4c6898954c4231-Snipaste.desktop
Snipaste
env QT_QPA_PLATFORM=xcb QT_OPENGL=software QT_XCB_GL_INTEGRATION=none QSG_RHI_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 /home/chesszyh/Applications/Snipaste-2.11.3-x86_64_9fa0ae9967819a4a166804ebf074147e.AppImage
count 1
```

### invalid launcher 清理服务恢复正常

验证命令：

```bash
systemctl --user start rofi-invalid-launchers.service
systemctl --user status rofi-invalid-launchers.service --no-pager -l
```

关键结果：

```text
ExecStart=/home/chesszyh/.config/hypr/UserScripts/DarkAngelAppLauncher.py --clean --apply (code=exited, status=0/SUCCESS)
Finished rofi-invalid-launchers.service - Hide invalid Rofi desktop launchers.
```

### user failed units 清空

验证命令：

```bash
systemctl --user reset-failed rofi-invalid-launchers.service
systemctl --user --failed --no-pager
```

结果：

```text
0 loaded units listed.
```

### wrapper 引用清空

验证命令：

```bash
find ~/.local/bin ~/.config/systemd/user ~/.local/share/applications -maxdepth 1 -type f -print0 \
  | xargs -0 rg -n "snipaste-wayland-wrapper"
```

结果为空，说明主要启动入口中不再引用 wrapper。

## Problems Encountered During Debugging

### 1. 初始命令被 `rtk`/shell quoting 影响

早期使用 `ps`、`find`、`journalctl` 管道时，部分命令因为参数解析和 shell 重定向没有按预期传递而失败，例如：

```text
ps: error: garbage option
find: paths must precede expression: `2>/dev/null'
journalctl: Failed to open files: No such file or directory
```

后续改用：

```bash
rtk proxy zsh -lc '...'
```

显式交给 shell 解析管道、重定向和引号。

### 2. `pkill -f` 误匹配自己的命令行

清理旧 Snipaste 进程时，一条 `pkill -f` 命令匹配到了包含模式字符串的清理命令自身，导致命令以 `SIGTERM` 结束：

```text
Process exited with code 143
```

经验：对复杂 pattern 使用 `pkill -f` 时要避免匹配当前 shell 命令行；更稳妥的方式是先 `pgrep -af` 列出 PID，再逐个处理，或用更窄的进程名/父进程约束。

### 3. `findmnt` 没有显示全部 AppImage FUSE mount

一次 `findmnt -t fuse,...` 只显示了 gvfs/portal 两个挂载，但 `mount | rg Snipaste` 显示大量 Snipaste AppImage FUSE mount。后续以 `mount` 输出作为判断依据。

经验：FUSE 类型名可能是 `fuse.<AppImageName>`，筛选文件系统类型时容易漏掉；排查 AppImage mount 残留时直接按挂载目标或 source 名称匹配更可靠。

### 4. 直接启动 AppImage 一度失败

将 service 改为直接启动 AppImage 后，首次启动返回 `status=1/FAILURE`。当时系统中仍有旧 Snipaste 实例和残留 mount。清理旧进程与挂载后，重新启动进入 `active (running)`。

经验：Snipaste 这类单实例 GUI 程序可能在已有实例存在时直接退出，systemd 会把这视为启动失败。修改 service 后应先清理旧实例再验证。

### 5. `rofi-invalid-launchers.service` 本身也有配置漂移

该 service 指向不存在的 `MaterialA1AppLauncher.py`：

```text
Unable to locate executable '/home/chesszyh/.config/hypr/UserScripts/MaterialA1AppLauncher.py'
Failed at step EXEC
```

这与 Snipaste FUSE 错误不是同一个根因，但会影响启动器清理与排障可信度。因此一起修为 `DarkAngelAppLauncher.py`。

## Reuse Notes and Lessons

- 看到 AppImage 的 `Cannot mount AppImage` 时，不要直接假设是缺 FUSE 包。先看 `journalctl` 中具体调用方和 `fusermount` 的完整错误。
- `too many FUSE filesystems mounted` 通常说明存在 mount 泄漏或快速重启风暴。应先停止触发源，再清理残留 mount。
- 对 GUI 自启动程序，`Restart=on-failure` 可能造成灾难性循环。单实例托盘应用更适合谨慎使用 `Restart=on-abnormal` 或不自动重启。
- 删除 wrapper 或迁移启动路径时，必须同步检查：
  - systemd user service
  - `.desktop` 的 `Exec` / `TryExec`
  - 自定义 launcher 的有效性过滤逻辑
  - autostart 或 Hyprland `exec-once`
- Waybar 托盘图标偶发缺失时，应考虑启动顺序问题。对托盘应用可以让其 `After=waybar.service` 并加入短延迟。
- 修复 live desktop 问题时，`systemctl --user show-environment`、真实 GUI 进程环境和当前 shell 环境可能不同，需要以正在运行的 user services 和进程为准。

## Appendix: Reusable Commands

### 定位 AppImage/FUSE 错误来源

```bash
journalctl --user --since "6 hours ago" --no-pager \
  | rg -i "AppImage|appimage|FUSE|fuse|Cannot mount|appimage-extract"
```

```bash
ps -eo pid,ppid,stat,lstart,args \
  | rg -i "appimage|AppRun|fuse|Snipaste|appimagelauncher"
```

### 检查 FUSE 环境

```bash
rpm -q fuse fuse-libs fuse3 fuse3-libs appimagelauncher
ls -l /dev/fuse
id
groups
```

### 统计 Snipaste AppImage mount

```bash
mount | rg -i "Snipaste|/tmp/\\.mount_Snipas"
mount | rg -i "Snipaste|/tmp/\\.mount_Snipas" | wc -l
```

### 停止 Snipaste 并清理残留 mount

```bash
systemctl --user stop snipaste.service

mount | awk '/Snipaste-2\.11\.3.* on \/tmp\/\.mount_Snipas/ {print $3}' \
  | sort -r \
  | while IFS= read -r mp; do
      fusermount3 -uz "$mp" 2>/dev/null || fusermount -uz "$mp" 2>/dev/null || true
    done
```

### 检查 Snipaste service

```bash
systemctl --user status snipaste.service --no-pager -l
systemctl --user show snipaste.service \
  -p ActiveState -p SubState -p Result -p NRestarts -p ExecMainPID --no-pager
```

### 检查 Snipaste desktop entry

```bash
desktop-file-validate ~/.local/share/applications/appimagekit_d633ea4a4d9488cf7d4c6898954c4231-Snipaste.desktop

rg -n "Name=Snipaste|Exec=.*Snipaste|TryExec=.*Snipaste|snipaste-wayland-wrapper" \
  ~/.local/share/applications/appimagekit_d633ea4a4d9488cf7d4c6898954c4231-Snipaste.desktop \
  ~/.config/systemd/user/snipaste.service \
  ~/.config/systemd/user/rofi-invalid-launchers.service
```

### 刷新 systemd 与 desktop database

```bash
systemctl --user daemon-reload
systemctl --user reset-failed snipaste.service rofi-invalid-launchers.service
update-desktop-database ~/.local/share/applications
```

### 验证 user services 没有失败项

```bash
systemctl --user --failed --no-pager
```
