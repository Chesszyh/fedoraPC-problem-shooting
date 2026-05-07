# tmux 远程开发配置与持久化问题报告

生成时间: 2026-04-14T15:04:35+08:00

## 1. Problem Description（问题描述）

用户希望为服务器上的 tmux 建立一套适合远程开发的配置，目标是：

- SSH 断开后任务继续运行。
- pane/window/session 操作尽量顺手，部分借鉴已有 zellij 配置的直达快捷键体验。
- 参考社区常用 tmux 配置和插件，但不要完整照搬 zellij 或整套复杂配置。

初始检查发现用户级 tmux 配置不存在：

```sh
ls -l /Users/chesszyh987/.tmux.conf /Users/chesszyh987/.config/tmux/tmux.conf 2>/dev/null
```

该命令没有输出，说明两个常见配置路径都不存在。

## 2. Environment and Scope（环境与范围）

环境证据：

```sh
tmux -V
# tmux 3.6a

which tmux
# /opt/homebrew/bin/tmux
```

涉及范围：

- 新建配置文件：`/Users/chesszyh987/.tmux.conf`
- 新建插件目录：`/Users/chesszyh987/.tmux/plugins`
- 新建恢复数据目录：`/Users/chesszyh987/.tmux/resurrect`
- 没有修改 `/Users/chesszyh987/.config/tmux/tmux.conf`
- 没有覆盖已有 tmux 配置，因为两个常见配置路径在开始时均不存在

用户明确理解远程任务不间断的关键点：真正的不间断必须在服务器端 tmux 中运行任务。本次配置的目标就是该服务器端 tmux。

## 3. Symptoms and Reproduction（症状与复现）

主要症状不是运行时崩溃，而是配置缺失和插件安装过程中的一次失败。

插件安装第一次失败：

```sh
/Users/chesszyh987/.tmux/plugins/tpm/bin/install_plugins
```

输出：

```text
unknown variable: TMUX_PLUGIN_MANAGER_PATH
FATAL: Tmux Plugin Manager not configured in tmux.conf
Aborting.
```

随后直接把 source 和 show-environment 串在同一个 tmux 命令中，也出现过同类现象：

```sh
tmux source-file /Users/chesszyh987/.tmux.conf \; show-environment -g TMUX_PLUGIN_MANAGER_PATH
```

输出：

```text
unknown variable: TMUX_PLUGIN_MANAGER_PATH
```

这说明问题不只是 `.tmux.conf` 文件内容是否存在，还涉及 TPM 何时把 `TMUX_PLUGIN_MANAGER_PATH` 写入 tmux 全局环境。

## 4. Investigation Timeline（排查时间线）

1. 确认 tmux 用户配置文件不存在：

```sh
ls -l /Users/chesszyh987/.tmux.conf /Users/chesszyh987/.config/tmux/tmux.conf 2>/dev/null
```

结果无输出。

2. 确认 tmux 版本和安装路径：

```sh
tmux -V
# tmux 3.6a

which tmux
# /opt/homebrew/bin/tmux
```

3. 查看默认 tmux key table 和全局选项，确认默认状态：

```sh
tmux list-keys -T prefix
tmux show-options -g
```

关键默认状态包括 `prefix C-b`、`history-limit 2000`、`mouse off`、`base-index 0`。

4. 查看已有 zellij 配置：

```sh
sed -n '1,220p' /Users/chesszyh987/.config/zellij/config.kdl
```

观察到用户已使用 `Alt-h/j/k/l`、pane/tab/session 模式等快捷键习惯。因此 tmux 配置借鉴直达导航思路，但保持 tmux 的 prefix 模型。

5. 写入 `/Users/chesszyh987/.tmux.conf`，包含核心 tmux 选项、快捷键、状态栏和 TPM 插件声明。

6. 创建插件目录并 clone TPM：

```sh
mkdir -p /Users/chesszyh987/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm /Users/chesszyh987/.tmux/plugins/tpm
```

7. 第一次运行 TPM 安装器失败，错误为 `TMUX_PLUGIN_MANAGER_PATH` 未设置。

8. 阅读 TPM 脚本定位依赖：

```sh
sed -n '1,220p' /Users/chesszyh987/.tmux/plugins/tpm/bin/install_plugins
sed -n '1,240p' /Users/chesszyh987/.tmux/plugins/tpm/scripts/helpers/plugin_functions.sh
sed -n '1,100p' /Users/chesszyh987/.tmux/plugins/tpm/tpm
rg -n "TMUX_PLUGIN_MANAGER_PATH|configured" /Users/chesszyh987/.tmux/plugins/tpm
```

证据显示：

- `install_plugins` 通过 tmux 全局环境读取 `TMUX_PLUGIN_MANAGER_PATH`。
- TPM 的 `tpm` 脚本会设置这个变量。
- `.tmux.conf` 末尾使用 `run -b '~/.tmux/plugins/tpm/tpm'`，这是后台异步执行。

9. 单独 source 配置并等待后，变量出现：

```sh
tmux source-file /Users/chesszyh987/.tmux.conf
sleep 1
tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH
# TMUX_PLUGIN_MANAGER_PATH=/Users/chesszyh987/.tmux/plugins/
```

10. 重新运行插件安装器成功：

```sh
/Users/chesszyh987/.tmux/plugins/tpm/bin/install_plugins
```

输出显示：

```text
Already installed "tpm"
Installing "tmux-sensible"
  "tmux-sensible" download success
Installing "tmux-resurrect"
  "tmux-resurrect" download success
Installing "tmux-continuum"
  "tmux-continuum" download success
```

11. 用独立 socket 启动临时 tmux server 验证配置解析：

```sh
tmux -L report-tmux-check -f /Users/chesszyh987/.tmux.conf new-session -d -s config-check -c /Users/chesszyh987 'sleep 60'
tmux -L report-tmux-check show-options -gqv @continuum-restore
tmux -L report-tmux-check kill-server
```

输出：

```text
on
```

12. 将配置重新 source 到当前已运行的 tmux server：

```sh
tmux source-file /Users/chesszyh987/.tmux.conf
```

13. 手动触发一次 resurrect 保存，建立初始恢复点：

```sh
tmux run-shell /Users/chesszyh987/.tmux/plugins/tmux-resurrect/scripts/save.sh
```

## 5. Root Cause（根因）

原始问题的根因是服务器上没有用户级 tmux 配置，因此默认 tmux 不具备远程开发所需的顺手快捷键、大历史、鼠标、剪贴板、恢复插件和自动保存策略。

调试过程中插件安装失败的根因是 TPM 安装器依赖 tmux 全局环境变量 `TMUX_PLUGIN_MANAGER_PATH`。该变量由 TPM 的 `tpm` 脚本设置，而 `.tmux.conf` 通过 `run -b` 后台执行 TPM。因此在首次安装插件前或刚刚 source 配置的同一条 tmux 命令内，变量可能尚未存在，导致：

```text
unknown variable: TMUX_PLUGIN_MANAGER_PATH
FATAL: Tmux Plugin Manager not configured in tmux.conf
```

这不是插件仓库不可访问，也不是 `.tmux.conf` 中 `@plugin` 声明缺失，而是 TPM 初始化环境尚未完成。

## 6. Changes Made（修改内容）

创建文件：

- `/Users/chesszyh987/.tmux.conf`

创建目录和插件：

- `/Users/chesszyh987/.tmux/plugins/tpm`
- `/Users/chesszyh987/.tmux/plugins/tmux-sensible`
- `/Users/chesszyh987/.tmux/plugins/tmux-resurrect`
- `/Users/chesszyh987/.tmux/plugins/tmux-continuum`
- `/Users/chesszyh987/.tmux/resurrect`

主要配置项：

```tmux
set -g prefix C-b
set -g prefix2 C-a
set -g history-limit 200000
set -g mouse on
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g set-clipboard on
setw -g mode-keys vi
```

核心快捷键：

```tmux
bind - split-window -v -c "#{pane_current_path}"
bind | split-window -h -c "#{pane_current_path}"
bind s split-window -v -c "#{pane_current_path}"
bind v split-window -h -c "#{pane_current_path}"
bind -n M-h if-shell -F "#{pane_at_left}" "previous-window" "select-pane -L"
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l if-shell -F "#{pane_at_right}" "next-window" "select-pane -R"
bind P display-popup -E -d "#{pane_current_path}" -w 90% -h 80%
```

持久化插件配置：

```tmux
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-save-interval '10'
set -g @continuum-restore 'on'
```

恢复进程列表被刻意保持保守：

```tmux
set -g @resurrect-processes 'ssh mosh-client psql mysql sqlite3 redis-cli python python3 ipython jupyter'
```

曾考虑把 `make`、`pytest`、`docker-compose`、`kubectl` 等命令加入 resurrect 自动恢复列表，但最终移除。原因是这些命令在服务器重启后自动重跑可能有副作用。普通长任务只要仍在 tmux server 中运行，SSH 断开不会影响它们；resurrect/continuum 主要处理 tmux server 重启后的布局和部分保守进程恢复。

## 7. Verification（验证）

验证插件目录：

```sh
find /Users/chesszyh987/.tmux/plugins -maxdepth 1 -type d -print | sort
```

关键结果：

```text
/Users/chesszyh987/.tmux/plugins/tmux-continuum
/Users/chesszyh987/.tmux/plugins/tmux-resurrect
/Users/chesszyh987/.tmux/plugins/tmux-sensible
/Users/chesszyh987/.tmux/plugins/tpm
```

验证当前 tmux server 关键选项：

```sh
tmux show-options -g | rg '^(prefix|prefix2|history-limit|mouse|base-index|renumber-windows|detach-on-destroy|status-right) '
tmux show-options -s | rg '^set-clipboard '
```

关键结果：

```text
base-index 1
detach-on-destroy off
history-limit 200000
mouse on
prefix C-b
prefix2 C-a
renumber-windows on
set-clipboard on
```

验证 TPM 和 resurrect key binding：

```sh
tmux list-keys -T prefix | rg ' I | U | M-u|C-s|C-r|split-window|new-window|display-popup|source-file'
```

关键结果：

```text
bind-key    -T prefix I       run-shell /Users/chesszyh987/.tmux/plugins/tpm/bindings/install_plugins
bind-key    -T prefix U       run-shell /Users/chesszyh987/.tmux/plugins/tpm/bindings/update_plugins
bind-key    -T prefix M-u     run-shell /Users/chesszyh987/.tmux/plugins/tpm/bindings/clean_plugins
bind-key    -T prefix C-r     run-shell /Users/chesszyh987/.tmux/plugins/tmux-resurrect/scripts/restore.sh
bind-key    -T prefix C-s     run-shell /Users/chesszyh987/.tmux/plugins/tmux-resurrect/scripts/save.sh
```

验证免 prefix 导航：

```sh
tmux list-keys -T root | rg 'M-h|M-j|M-k|M-l|M-z'
```

关键结果：

```text
bind-key -T root M-h if-shell -F "#{pane_at_left}" previous-window "select-pane -L"
bind-key -T root M-j select-pane -D
bind-key -T root M-k select-pane -U
bind-key -T root M-l if-shell -F "#{pane_at_right}" next-window "select-pane -R"
bind-key -T root M-z resize-pane -Z
```

验证 continuum/resurrect 配置：

```sh
tmux show-options -gqv @continuum-save-interval
tmux show-options -gqv @continuum-restore
tmux show-options -gqv @resurrect-processes
```

输出：

```text
10
on
ssh mosh-client psql mysql sqlite3 redis-cli python python3 ipython jupyter
```

验证恢复点存在：

```sh
ls -la /Users/chesszyh987/.tmux/resurrect
```

关键结果：

```text
last -> tmux_resurrect_20260414T150122.txt
pane_contents.tar.gz
tmux_resurrect_20260414T145038.txt
tmux_resurrect_20260414T150122.txt
```

## 8. Problems Encountered During Debugging（调试中遇到的问题）

1. TPM 安装器首次失败。

错误：

```text
unknown variable: TMUX_PLUGIN_MANAGER_PATH
FATAL: Tmux Plugin Manager not configured in tmux.conf
Aborting.
```

解决：先 `tmux source-file /Users/chesszyh987/.tmux.conf`，等待 TPM 的 `run -b` 初始化完成，再运行 `install_plugins`。

2. 同一条 tmux 命令内 source 配置并立即读取 `TMUX_PLUGIN_MANAGER_PATH` 不可靠。

原因：`.tmux.conf` 中 `run -b '~/.tmux/plugins/tpm/tpm'` 是后台异步执行。`show-environment` 可能早于 TPM 初始化执行。

3. macOS/BSD `date` 不支持 GNU 风格参数。

技能要求报告头使用 `date --iso-8601=seconds`，但本机输出：

```text
date: illegal option -- -
usage: date [-jnRu] [-I[date|hours|minutes|seconds|ns]] ...
```

实际使用兼容命令生成等价 ISO 时间：

```sh
date -Iseconds
# 2026-04-14T15:04:35+08:00
```

4. resurrect 自动恢复进程列表需要保守。

一开始的候选列表包含构建、测试和容器命令。后续调整为仅恢复交互式或低副作用进程，避免服务器重启后自动重新执行可能产生副作用的任务。

## 9. Reuse Notes and Lessons（复用说明与经验）

- 远程开发中，任务不间断的核心是任务必须运行在远程服务器上的 tmux server 内，而不是本地终端或本地 tmux 中。
- `tmux-resurrect` 和 `tmux-continuum` 解决的是 tmux server 重启后的布局、pane 内容、shell 和部分进程恢复，不等同于对任意命令的安全自动重启。
- TPM 的 `install_plugins` 依赖 tmux 全局环境变量。首次部署时，clone TPM 后最好先 source 配置，确认 `TMUX_PLUGIN_MANAGER_PATH` 已存在，再安装插件。
- 对于 zellij 用户，tmux 可以通过 `Alt-h/j/k/l`、popup、choose-tree、状态栏提示等方式改善手感，但不应把 tmux 强行改造成 zellij 的模式系统。
- 恢复进程列表应按项目逐步添加。例如确认某个 dev server 自动重启是安全的，再添加 resurrect 规则。

## 10. Appendix: Reusable Commands（附录：可复用命令）

检查 tmux 配置路径：

```sh
ls -l ~/.tmux.conf ~/.config/tmux/tmux.conf 2>/dev/null
```

检查 tmux 版本和路径：

```sh
tmux -V
which tmux
```

安装 TPM：

```sh
mkdir -p ~/.tmux/plugins
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
```

加载配置并确认 TPM 路径：

```sh
tmux source-file ~/.tmux.conf
sleep 1
tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH
```

安装插件：

```sh
~/.tmux/plugins/tpm/bin/install_plugins
```

用独立 tmux socket 验证配置解析：

```sh
tmux -L tmux-config-check -f ~/.tmux.conf new-session -d -s config-check -c "$HOME" 'sleep 60'
tmux -L tmux-config-check show-options -gqv @continuum-restore
tmux -L tmux-config-check kill-server
```

查看关键选项：

```sh
tmux show-options -g | rg '^(prefix|prefix2|history-limit|mouse|base-index|renumber-windows|detach-on-destroy|status-right) '
tmux show-options -s | rg '^set-clipboard '
```

查看关键快捷键：

```sh
tmux list-keys -T root | rg 'M-h|M-j|M-k|M-l|M-z'
tmux list-keys -T prefix | rg ' I | U | M-u|C-s|C-r|split-window|new-window|display-popup|source-file'
```

手动保存/恢复 tmux 环境：

```sh
tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh
tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/restore.sh
```

查看 resurrect 保存结果：

```sh
ls -la ~/.tmux/resurrect
readlink ~/.tmux/resurrect/last
```

## 11. User Manual（用户使用手册）

### 11.1 核心概念

这份配置的使用模型是：远程服务器上长期运行一个 tmux server，日常所有开发任务都放进这个 tmux server 的 session/window/pane 中。SSH 客户端断开时，tmux server 和其中的进程仍在服务器上继续运行；下次 SSH 登录后重新 attach 即可。

建议把主要工作 session 固定命名为 `main`：

```sh
tmux new -As main
```

含义：

- 如果 `main` session 已存在，则直接 attach。
- 如果 `main` session 不存在，则创建一个新的 `main` session。
- 这是远程开发最推荐的入口命令。

tmux 操作有两类快捷键：

- prefix 快捷键：先按 `Ctrl-b` 或 `Ctrl-a`，松开后再按后续键。
- root 快捷键：不用 prefix，直接按，例如 `Alt-h/j/k/l`。

本配置保留 tmux 默认 `Ctrl-b`，并额外加入 `Ctrl-a`。这样既兼容默认文档，也兼容很多社区配置和肌肉记忆。

### 11.2 启动、断开和恢复连接

首次进入：

```sh
tmux new -As main
```

临时离开但让任务继续跑：

```text
prefix d
```

其中 `prefix` 是 `Ctrl-b` 或 `Ctrl-a`。断开后，当前 pane 里的进程仍继续运行。

重新连接：

```sh
tmux new -As main
```

查看已有 session：

```sh
tmux ls
```

连接指定 session：

```sh
tmux attach -t main
```

杀掉当前 pane：

```text
prefix x
```

杀掉当前 window：

```text
prefix X
```

这两个操作都有确认提示，避免误杀长期任务。

### 11.3 Window 使用方式

window 适合按工作主题划分，例如：

- `editor`：编辑器
- `server`：开发服务器
- `test`：测试或日志
- `ops`：数据库、SSH、kubectl 等操作

新建 window：

```text
prefix c
```

或：

```text
prefix Ctrl-c
```

新 window 会继承当前 pane 的工作目录。

切换 window：

```text
prefix n    # 下一个 window
prefix p    # 上一个 window
prefix 1    # 跳到第 1 个 window
prefix 2    # 跳到第 2 个 window
```

本配置启用了：

```tmux
set -g base-index 1
set -g renumber-windows on
```

因此 window 从 1 开始编号，并在关闭 window 后自动重新编号。

打开 window/session 树：

```text
prefix w    # window tree
prefix S    # session tree
```

### 11.4 Pane 使用方式

pane 适合同一个主题下的并行视图。例如一个 window 里左边编辑器、右上运行服务、右下看日志。

上下分屏：

```text
prefix -
prefix s
```

左右分屏：

```text
prefix |
prefix v
```

新 pane 会继承当前 pane 的工作目录，避免每次都重新 `cd`。

prefix 方式移动 pane：

```text
prefix h    # 左
prefix j    # 下
prefix k    # 上
prefix l    # 右
```

免 prefix 方式移动 pane：

```text
Alt-h       # 左；如果已经在最左侧，则切到上一个 window
Alt-j       # 下
Alt-k       # 上
Alt-l       # 右；如果已经在最右侧，则切到下一个 window
```

调整 pane 大小：

```text
prefix H/J/K/L
Alt-Shift-h/j/k/l
```

当前 pane 全屏/恢复：

```text
prefix z
Alt-z
```

同步输入到当前 window 的所有 pane：

```text
prefix m
```

状态栏会显示 `SYNC`。这个功能适合同时在多台机器执行只读命令；执行破坏性命令前必须确认是否还处于同步模式。

### 11.5 Popup Shell

打开当前目录的临时 popup shell：

```text
prefix P
```

典型用途：

- 临时跑一个命令，不打乱当前 pane 布局。
- 快速查看文件、git 状态、日志。
- 临时开一个 shell 后退出，原布局保持不变。

退出 popup：

```sh
exit
```

### 11.6 Copy Mode 和滚动

进入 copy mode：

```text
prefix [
```

vi 风格操作：

```text
j/k              # 上下移动
Ctrl-f/Ctrl-b    # 翻页
/                # 向下搜索
?                # 向上搜索
n/N              # 下一个/上一个匹配
v                # 开始选择
Ctrl-v           # 矩形选择
y                # 复制并退出 copy mode
Enter            # 复制并退出 copy mode
Escape           # 取消
```

本配置启用：

```tmux
set -g set-clipboard on
setw -g mode-keys vi
```

在支持 OSC52/系统剪贴板的终端中，tmux 复制内容会尽量同步到系统剪贴板。若某些 SSH 客户端或终端不支持 OSC52，tmux 内部 buffer 仍然可用，但系统剪贴板可能不同步。

### 11.7 状态栏含义

左侧：

```text
#S
```

显示当前 session 名称。

中间：

```text
#I:#W
```

显示 window 编号和名称。

右侧可能出现：

```text
PREFIX    # 已按下 prefix，等待下一个键
SYNC      # 当前 window 开启 synchronize-panes
ZOOM      # 当前 pane 已全屏
hostname  # 当前主机名
时间       # YYYY-MM-DD HH:MM
```

`tmux-continuum` 也会通过 `status-right` 周期性触发自动保存，因此看到 `status-right` 中出现 continuum 脚本是正常现象。

### 11.8 持久化与恢复

SSH 断开但服务器未重启：

- 不需要 resurrect。
- 直接重新 SSH 登录后运行 `tmux new -As main`。
- 原来的进程仍在对应 pane 中继续运行。

tmux server 或服务器重启后：

- `tmux-continuum` 会尝试自动恢复最近一次保存的 tmux 环境。
- 如未自动恢复，可手动触发：

```text
prefix Ctrl-r
```

手动保存当前 tmux 环境：

```text
prefix Ctrl-s
```

也可以用命令保存：

```sh
tmux run-shell ~/.tmux/plugins/tmux-resurrect/scripts/save.sh
```

保存文件位置：

```text
~/.tmux/resurrect/
```

检查最近保存点：

```sh
ls -la ~/.tmux/resurrect
readlink ~/.tmux/resurrect/last
```

注意：resurrect/continuum 不是通用进程守护系统。它们适合恢复 tmux 布局、pane 路径、pane 内容、shell 和少量安全进程。关键生产任务建议仍使用 systemd、supervisor、launchd、Docker restart policy、Kubernetes 或对应服务管理工具。

### 11.9 插件维护

安装 `.tmux.conf` 中声明但尚未安装的插件：

```text
prefix I
```

更新插件：

```text
prefix U
```

清理 `.tmux.conf` 中已删除但目录仍存在的插件：

```text
prefix Alt-u
```

命令行方式安装插件：

```sh
~/.tmux/plugins/tpm/bin/install_plugins
```

如果出现 `TMUX_PLUGIN_MANAGER_PATH` 相关错误，先执行：

```sh
tmux source-file ~/.tmux.conf
sleep 1
tmux show-environment -g TMUX_PLUGIN_MANAGER_PATH
```

确认变量存在后再运行安装器。

### 11.10 修改配置的推荐流程

编辑配置：

```sh
vim ~/.tmux.conf
```

加载配置：

```text
prefix r
```

或命令行：

```sh
tmux source-file ~/.tmux.conf
```

修改后建议用独立 socket 验证，避免污染当前工作 session：

```sh
tmux -L tmux-config-check -f ~/.tmux.conf new-session -d -s config-check -c "$HOME" 'sleep 60'
tmux -L tmux-config-check kill-server
```

### 11.11 macOS 终端注意事项

如果 `Alt-h/j/k/l` 没有生效，通常是终端没有把 Option/Alt 作为 Meta 发送。常见处理方式：

- iTerm2：Profile 设置里将 Option key 配置为 Esc+ 或 Meta。
- macOS Terminal：设置中启用 Use Option as Meta key。
- SSH 客户端或 Web Terminal：检查是否拦截了 Alt 快捷键。

如果复制不能同步到系统剪贴板，优先检查终端是否支持 OSC52，以及 SSH 链路是否允许该控制序列通过。

## 12. Configuration References（配置参考来源）

本次配置主要参考官方文档和社区长期维护的 tmux 插件。下面记录来源、采用点和没有采用的部分，方便后续维护时判断为什么这样配置。

### 12.1 tmux 官方文档

来源：

- tmux manual: https://man7.org/linux/man-pages/man1/tmux.1.html
- tmux Getting Started wiki: https://github.com/tmux/tmux/wiki/Getting-Started

采用点：

- 保留 tmux 的 prefix 操作模型。
- 使用 `new-session`、`attach-session`、`source-file`、`show-options`、`list-keys` 等标准命令验证配置。
- 使用 `copy-mode-vi`、`resize-pane -Z`、`display-popup`、`choose-tree` 等 tmux 原生命令，而不是为基础能力额外引入插件。

配置中的对应项：

```tmux
bind r source-file ~/.tmux.conf \; display-message "Reloaded ~/.tmux.conf"
bind P display-popup -E -d "#{pane_current_path}" -w 90% -h 80%
bind z resize-pane -Z
bind w choose-tree -Zw
bind S choose-tree -Zs
```

### 12.2 TPM

来源：

- Tmux Plugin Manager: https://github.com/tmux-plugins/tpm

采用点：

- 使用 `set -g @plugin ...` 声明插件。
- 使用 `run -b '~/.tmux/plugins/tpm/tpm'` 在配置末尾加载 TPM。
- 使用 TPM 默认快捷键：`prefix I` 安装、`prefix U` 更新、`prefix Alt-u` 清理。

配置中的对应项：

```tmux
set -g @plugin 'tmux-plugins/tpm'
run -b '~/.tmux/plugins/tpm/tpm'
```

注意事项：

- TPM 的首次安装可能需要先 source 配置并等待 `TMUX_PLUGIN_MANAGER_PATH` 初始化。
- TPM 应放在插件声明之后、配置文件末尾附近。

### 12.3 tmux-sensible

来源：

- tmux-sensible: https://github.com/tmux-plugins/tmux-sensible

采用点：

- 社区认可的一组保守默认项。
- `escape-time`、`history-limit`、`display-time`、`status-interval`、`focus-events`、`aggressive-resize` 等方向与本配置一致。

本配置做了更适合远程开发的调整：

```tmux
set -s escape-time 10
set -g history-limit 200000
set -g display-time 2500
set -g status-interval 5
set -g focus-events on
setw -g aggressive-resize on
```

差异说明：

- `history-limit` 提高到 `200000`，适合长时间日志和远程开发。
- 没有使用旧 macOS 时代的 `reattach-to-user-namespace` 配置，因为当前 tmux 是 3.6a，且 `set-clipboard` 已可直接使用。
- 保留本地显式配置，即使插件未加载，也能获得关键行为。

### 12.4 tmux-resurrect

来源：

- tmux-resurrect: https://github.com/tmux-plugins/tmux-resurrect
- restoring programs 文档：https://github.com/tmux-plugins/tmux-resurrect/blob/master/docs/restoring_programs.md

采用点：

- 保存和恢复 tmux session/window/pane 布局。
- 保存 pane 内容和 shell history。
- 通过 `prefix Ctrl-s` 手动保存，通过 `prefix Ctrl-r` 手动恢复。
- 配置有限的 `@resurrect-processes`，只自动恢复低副作用交互进程。

配置中的对应项：

```tmux
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @resurrect-dir '~/.tmux/resurrect'
set -g @resurrect-capture-pane-contents 'on'
set -g @resurrect-save-shell-history 'on'
set -g @resurrect-strategy-vim 'session'
set -g @resurrect-strategy-nvim 'session'
set -g @resurrect-processes 'ssh mosh-client psql mysql sqlite3 redis-cli python python3 ipython jupyter'
```

没有采用的部分：

- 没有默认自动恢复构建、测试、容器、部署类命令。
- 没有加入复杂项目级恢复规则，避免误重启有副作用进程。

### 12.5 tmux-continuum

来源：

- tmux-continuum: https://github.com/tmux-plugins/tmux-continuum

采用点：

- 周期性自动保存 tmux 环境。
- 启动 tmux server 时尝试自动恢复。

配置中的对应项：

```tmux
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @continuum-save-interval '10'
set -g @continuum-restore 'on'
```

设计取舍：

- 自动保存间隔为 10 分钟，兼顾恢复点新鲜度和后台开销。
- 手动保存仍保留，重要操作前可以 `prefix Ctrl-s`。

### 12.6 gpakosz / Oh my tmux

来源：

- Oh my tmux / gpakosz `.tmux`: https://github.com/gpakosz/.tmux

参考点：

- `Ctrl-a` 作为第二 prefix，同时保留默认 `Ctrl-b`。
- 分屏继承当前路径。
- vi 风格 pane 导航和 copy-mode。
- 状态栏显示 prefix、同步、主机等上下文信息。

没有采用整套配置的原因：

- Oh my tmux 是完整框架，功能丰富但覆盖范围较大。
- 本次目标是服务器远程开发配置，优先保持可读、可控、少依赖。
- 没有引入 Powerline 字体、天气、电池、PathPicker、Urlscan 等额外能力。

配置中的对应思想：

```tmux
set -g prefix2 C-a
bind - split-window -v -c "#{pane_current_path}"
bind | split-window -h -c "#{pane_current_path}"
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R
```

### 12.7 Zellij Keybindings

来源：

- Zellij keybindings 文档：https://zellij.dev/documentation/keybindings
- 本机已有配置：`/Users/chesszyh987/.config/zellij/config.kdl`

参考点：

- `Alt-h/j/k/l` 直达移动。
- pane、tab、resize 等操作强调可发现性和低按键成本。
- 状态提示当前模式或状态。

没有完全模仿的原因：

- tmux 的核心交互是 prefix + command，而 zellij 是 mode + action。
- 强行把 tmux 改成完整 mode 系统会增加维护成本，也会偏离 tmux 社区文档和默认心智模型。

配置中的对应项：

```tmux
bind -n M-h if-shell -F "#{pane_at_left}" "previous-window" "select-pane -L"
bind -n M-j select-pane -D
bind -n M-k select-pane -U
bind -n M-l if-shell -F "#{pane_at_right}" "next-window" "select-pane -R"
bind -n M-z resize-pane -Z
```

### 12.8 本配置的总体原则

本配置最终采用的原则是：

- 优先使用 tmux 原生命令实现基础操作。
- 只为持久化和合理默认值引入插件。
- 保留 `Ctrl-b` 以兼容官方文档和默认习惯，添加 `Ctrl-a` 提升效率。
- 借鉴 zellij 的低按键成本，但不复制 zellij 的模式系统。
- 对自动恢复保持保守，避免把恢复工具变成隐式任务重启器。
