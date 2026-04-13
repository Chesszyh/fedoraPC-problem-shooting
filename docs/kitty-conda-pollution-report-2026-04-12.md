# Kitty 终端 Conda 污染问题报告

生成时间: `2026-04-12T16:35:04+08:00`

## 1. 问题描述

本文记录一次 Fedora + Hyprland + kitty 终端环境中的排障过程。问题的核心是 Miniforge/conda 污染了交互式 shell 环境，进而影响了终端基础能力。

本次会话中实际排查了两个用户可见的问题：

1. 在 kitty 中执行 `clear` 会报错：

```text
terminals database is inaccessible
```

2. kitty 中默认启动的交互式 `zsh` 会意外进入 conda `base` 环境，导致 `PATH` 被污染，Miniforge 工具覆盖了 Fedora 的系统工具。

本次处理的目标是：

- 找出真正的污染来源
- 去掉不必要的临时兜底逻辑
- 保留一个后续可复用、可复查的稳定修复方案

## 2. 环境与范围

- 主机系统：Fedora Workstation + Hyprland
- 终端：kitty
- Shell：`zsh`
- 涉及的 Python 发行版：Miniforge，路径为 `/home/chesszyh/.miniforge3`
- 主要涉及的配置文件：
  - [~/.zshrc](/home/chesszyh/.zshrc)
  - [~/.condarc](/home/chesszyh/.condarc)
  - [kitty.conf](/home/chesszyh/.config/kitty/kitty.conf)

本报告仅针对本地 Fedora 机器，不涉及本次对话中前面提到的远程 mac mini 中文显示问题。

## 3. 现象与复现

### 现象 A：kitty 中 `clear` 执行失败

观察到的报错：

```text
terminals database is inaccessible
```

当时用于取证的命令：

```bash
printf 'TERM=%s\nTERMINFO=%s\n' "$TERM" "$TERMINFO"
infocmp -x "$TERM"
clear
```

异常时的关键状态：

- `TERM=xterm-kitty`
- `TERMINFO=/usr/lib64/kitty/terminfo`
- `infocmp` 报错：

```text
infocmp: couldn't open terminfo file (null).
```

### 现象 B：交互式 shell 意外进入 conda `base`

用于查看实际进程环境的命令：

```bash
tr '\0' '\n' </proc/<pid>/environ | rg '^(CONDA|PATH=|TERM=|SHELL=)'
```

在交互式 shell 链路中观察到：

- `CONDA_DEFAULT_ENV=base`
- `CONDA_PREFIX=/home/chesszyh/.miniforge3`
- `CONDA_SHLVL=1`
- `PATH` 中包含：
  - `/home/chesszyh/.miniforge3/bin`
  - `/home/chesszyh/.miniforge3/condabin`

## 4. 排查时间线

### 第一步：确认到底执行的是哪个 `clear`

先检查实际执行的 `clear`、`infocmp`、`tic`：

```bash
which clear infocmp tic
command -V clear
command -V infocmp
```

结果：

- `clear` 实际是 `/home/chesszyh/.miniforge3/bin/clear`
- `infocmp` 实际是 `/home/chesszyh/.miniforge3/bin/infocmp`
- `tic` 实际是 `/home/chesszyh/.miniforge3/bin/tic`

这一步已经说明，Fedora 自带的 ncurses 终端工具被 Miniforge 版本抢到了前面。

### 第二步：验证 Fedora 系统工具本身是否正常

继续对比系统版和 Miniforge 版工具行为：

```bash
/usr/bin/clear >/dev/null && echo ok
/usr/bin/infocmp xterm-kitty | sed -n '1,6p'
```

结果：

- Fedora 的 `/usr/bin/clear` 可以正常工作
- Fedora 的 `/usr/bin/infocmp xterm-kitty` 可以正常读取：
  `/usr/lib64/kitty/terminfo/x/xterm-kitty`

这说明 terminal 和 terminfo 数据库本身没有坏，真正的问题是 shell 选错了工具。

### 第三步：追查为什么 Miniforge 在 PATH 前面

检查 [~/.zshrc](/home/chesszyh/.zshrc) 后发现：

```zsh
export PATH="$HOME/.miniforge3/bin:$PATH"
```

这行配置会在所有 shell 中全局把 Miniforge 工具放到系统工具前面。

### 第四步：先做最小可用修复，恢复终端基础能力

为了尽快恢复 `clear` 等终端能力工具，我先在 [~/.zshrc](/home/chesszyh/.zshrc) 中加入别名，强制走系统版工具：

- `clear=/usr/bin/clear`
- `infocmp=/usr/bin/infocmp`
- `tic=/usr/bin/tic`

这一步先把 `clear` 的直接故障恢复了。

### 第五步：去掉最明显的 PATH 污染

随后删除了 [~/.zshrc](/home/chesszyh/.zshrc) 中手写的 Miniforge 全局 PATH 注入：

```zsh
export PATH="$HOME/.miniforge3/bin:$PATH"
```

这一改动减少了污染范围，但后续排查中看起来 conda `base` 似乎仍然在自动激活。

### 第六步：一度误判为“父环境继承污染”，并加入临时清理块

在这个阶段，我曾临时在 [~/.zshrc](/home/chesszyh/.zshrc) 中加入一个 cleanup block，用来在 conda 初始化前剥离继承进来的 `CONDA_*` 变量和 Miniforge PATH 条目。

这个 workaround 当时在症状层面是有效的，但它建立在一个未经证实的假设上：

- `base` 是从父进程环境继承进来的

这个假设后来被证据推翻。

### 第七步：直接检查 Hyprland 和 kitty 的真实进程环境

为了验证“父环境污染”这个假设，我直接读取真实桌面和终端进程的环境：

```bash
tr '\0' '\n' </proc/2935/environ | rg '^(CONDA|PATH=|SHELL=)'
tr '\0' '\n' </proc/154222/environ | rg '^(CONDA|PATH=|SHELL=)'
```

关键发现：

- Hyprland 进程环境是干净的
- kitty 进程环境也是干净的
- 两者都没有 `CONDA_*`
- 两者的 `PATH` 里也没有 Miniforge 条目

这一步直接否定了“桌面父环境污染传给 kitty”这个推论。

### 第八步：继续检查 kitty 实际启动出来的 shell

接着查看 kitty 内部实际启动的 `zsh` 进程，以及其下层 `node/codex` 进程环境：

```bash
tr '\0' '\n' </proc/154228/environ | rg '^(CONDA|PATH=|TERM=|ZDOTDIR=|SHLVL=)'
tr '\0' '\n' </proc/155133/environ | rg '^(CONDA|PATH=|TERM=|SHELL=)'
```

发现：

- kitty 顶层 `zsh` 进程初始环境是干净的
- 后续用于 Codex 的交互子进程环境里出现了 conda `base`

这意味着问题发生在 shell 启动逻辑阶段，而不是桌面层级或 kitty 父进程层级。

### 第九步：直接检查 conda hook 到底输出了什么

为了彻底确认 conda 自己的行为，我直接检查 shell hook：

```bash
/home/chesszyh/.miniforge3/bin/conda shell.bash hook | rg 'conda activate|auto_activate'
/home/chesszyh/.miniforge3/bin/conda config --show auto_activate_base
```

得到关键证据：

```text
conda activate 'base'
auto_activate: True
```

这一步是整个问题的决定性证据。

说明 conda 的 shell hook 本身就在启动时主动注入：

```text
conda activate 'base'
```

原因是 conda 配置中 `auto_activate_base` 仍然开启。

### 第十步：撤销 workaround，改成真正的源头修复

在根因被证实后，我撤掉了此前临时加入的 cleanup block，不再依赖 shell 启动时的环境清洗。

随后把 conda 的持久配置改为：

[~/.condarc](/home/chesszyh/.condarc)

```yaml
auto_activate_base: false
```

## 5. 根因总结

本次问题最终由两个相关但不同的原因共同造成。

### 根因 1：`~/.zshrc` 中存在全局 Miniforge PATH 注入

[~/.zshrc](/home/chesszyh/.zshrc) 中原本存在：

```zsh
export PATH="$HOME/.miniforge3/bin:$PATH"
```

这导致 Miniforge 的 `clear`、`infocmp`、`tic` 覆盖了 Fedora 系统工具。

这正是 `clear` 报错的直接环境背景。

### 根因 2：conda 配置仍允许自动激活 `base`

当时 conda 配置中实际状态为：

```text
auto_activate: True
```

因此 `conda shell.bash hook` 会直接输出：

```text
conda activate 'base'
```

这说明 `base` 不是从 `Hyprland`、`kitty` 或 `.bashrc` 继承来的，而是 conda 自己在 `zsh` 启动阶段通过 hook 激活的。

## 6. 实际修改

### 最终保留的修改

1. 删除了 [~/.zshrc](/home/chesszyh/.zshrc#L141) 中手写的 Miniforge PATH 注入。
2. 保留了 [~/.zshrc](/home/chesszyh/.zshrc#L159) 中终端能力工具的系统别名：
   - `clear=/usr/bin/clear`
   - `infocmp=/usr/bin/infocmp`
   - `tic=/usr/bin/tic`
3. 在 [~/.condarc](/home/chesszyh/.condarc#L3) 中加入：

```yaml
auto_activate_base: false
```

### 调试期间添加、最后撤回的修改

- 曾临时在 `~/.zshrc` 中加入一个清理继承环境的 cleanup block，用于剥离 `CONDA_*` 和 Miniforge PATH 项。该逻辑在根因确认后已删除，因为它不是源头修复。

## 7. 验证

### 使用过的验证命令

```bash
/home/chesszyh/.miniforge3/bin/conda config --show auto_activate_base
env -i HOME=$HOME USER=$USER PATH=/usr/bin:/bin:/usr/sbin:/sbin /home/chesszyh/.miniforge3/bin/conda shell.bash hook | rg 'conda activate|auto_activate'
zsh -ic 'alias clear; clear >/dev/null && echo clear_ok || echo clear_fail'
```

### 已确认结果

- `auto_activate_base` 现在已经是 `False`
- 在干净环境下，conda hook 不再输出 `conda activate 'base'`
- `clear` 现在解析到 `/usr/bin/clear`
- `clear` 在 kitty 中可以正常执行

补充说明：

- `zsh -ic` 的自动化验证输出中还夹带了 `powerlevel10k/gitstatus` 的非目标告警。这些告警与 conda 污染问题无关，也不影响 `clear` 已恢复的结论。

## 8. 排障过程中遇到的问题

### 问题 1：当前自动化进程本身带来的误导

在某个阶段，当前运行中的 Codex 进程环境里已经带有 conda 变量。如果把这个进程当成真相来源，就很容易误判成“父环境已经污染”。

后来证明这个判断不可靠，因为观察点选错了。

修正方式：

- 不要只看当前工具进程
- 直接查看 `/proc/<pid>/environ`
- 分别核对 `Hyprland`、`kitty`、`zsh` 等真实进程边界

### 问题 2：在根因完全确认前加入了 workaround

临时 cleanup block 在症状层面确实有效，但它把问题当作“父环境继承污染”处理，而这并不是真正的根因。

修正方式：

- 临时修复可以接受
- 但在有更强证据后，应及时回退 workaround
- 最终应以最小、最直接的源头修复替代症状补丁

### 问题 3：两个问题有关联，但并不是同一个问题

`clear` 报错和 conda `base` 自动激活都与 Miniforge 污染有关，但它们不是同一层面的故障：

- `clear` 报错主要是错误工具被 PATH 抢占
- `base` 自动激活主要是 conda hook 行为

如果过早把它们视为同一个 bug，会掩盖掉机制上的差异。

修正方式：

- 分开分析“终端工具被覆盖”与“conda 启动时自动激活”这两条链路

## 9. 复用建议与经验总结

### 类似问题的复用排查清单

1. 先确认当前实际执行的到底是哪个程序：

```bash
which clear infocmp tic python conda
command -V clear
```

2. 再对比系统工具和 Miniforge 工具是否行为不同：

```bash
/usr/bin/clear
/usr/bin/infocmp xterm-kitty
```

3. 直接查看真实进程环境，而不是猜：

```bash
tr '\0' '\n' </proc/<pid>/environ | rg '^(CONDA|PATH=|TERM=|SHELL=)'
```

4. 直接检查 conda hook 输出：

```bash
/home/chesszyh/.miniforge3/bin/conda shell.bash hook | rg 'conda activate|auto_activate'
/home/chesszyh/.miniforge3/bin/conda config --show auto_activate_base
```

5. 优先修根因，再删除中途的 workaround。

### 本次排障的关键经验

- `PATH` 污染会悄悄替换掉 `clear`、`infocmp`、`tic` 这类基础终端工具。
- 桌面父环境干净，不代表交互式 shell 一定干净；shell 启动 hook 依然可能在后续阶段污染环境。
- `conda shell.bash hook` 不应被当作黑盒，直接看它的输出往往能最快锁定问题。
- `/proc/<pid>/environ` 是判断环境变量到底在哪一层注入的最快办法。
- 临时 workaround 可以辅助定位问题，但在根因清楚之后应及时撤掉，避免留下无谓复杂度。

## 10. 最终结论

本次 kitty 终端中的 conda 污染问题，最终确认由两部分组成：

- `~/.zshrc` 中手写的 Miniforge `bin` 全局注入
- conda 配置中开启的 `auto_activate_base`

最终稳定修复方案是：

- 删除全局 Miniforge `bin` 注入
- 保留终端能力工具对 Fedora 系统版本的固定映射
- 在 `~/.condarc` 中关闭 conda `base` 自动激活

这样处理后，conda 仍然可以通过 `conda activate ...` 正常使用，但默认交互式终端不再被 `base` 污染。

## 11. 附录：可直接复用命令清单

### A. 确认当前实际执行的是哪个工具

```bash
which clear infocmp tic python conda
command -V clear
command -V infocmp
command -V tic
```

### B. 检查终端能力与 terminfo

```bash
printf 'TERM=%s\nTERMINFO=%s\nTERMINFO_DIRS=%s\n' "$TERM" "$TERMINFO" "$TERMINFO_DIRS"
infocmp -x "$TERM"
/usr/bin/infocmp xterm-kitty | sed -n '1,6p'
/usr/bin/clear >/dev/null && echo system_clear_ok || echo system_clear_fail
```

### C. 检查 shell 启动配置中是否有 Miniforge 污染

```bash
rg -n "miniforge3|condabin|conda|CONDA_" ~/.zshrc ~/.bashrc ~/.profile ~/.zshenv ~/.zsh_alias ~/.zsh_fedora ~/.secret -g '!**/*.zwc'
nl -ba ~/.zshrc | sed -n '136,180p'
```

### D. 直接检查真实进程环境

```bash
tr '\0' '\n' </proc/<pid>/environ | rg '^(CONDA|PATH=|TERM=|SHELL=|SHLVL=|ZDOTDIR=)'
ps -o pid,ppid,comm,args= -p <pid>
pstree -aps <pid>
```

### E. 检查桌面环境与 kitty 父链是否被污染

```bash
systemctl --user show-environment | rg '^(CONDA|PATH=)'
loginctl session-status | sed -n '1,120p'
tr '\0' '\n' </proc/<hyprland-pid>/environ | rg '^(CONDA|PATH=|SHELL=)'
tr '\0' '\n' </proc/<kitty-pid>/environ | rg '^(CONDA|PATH=|SHELL=)'
```

### F. 直接检查 conda hook 与配置

```bash
/home/chesszyh/.miniforge3/bin/conda shell.bash hook | rg 'conda activate|auto_activate'
/home/chesszyh/.miniforge3/bin/conda config --show auto_activate_base
env -i HOME=$HOME USER=$USER PATH=/usr/bin:/bin:/usr/sbin:/sbin /home/chesszyh/.miniforge3/bin/conda shell.bash hook | rg 'conda activate|auto_activate'
```

### G. 验证修复是否生效

```bash
zsh -ic 'echo CONDA_DEFAULT_ENV=${CONDA_DEFAULT_ENV:-<empty>}; echo CONDA_SHLVL=${CONDA_SHLVL:-<empty>}; which python; which clear'
zsh -ic 'alias clear; clear >/dev/null && echo clear_ok || echo clear_fail'
zsh -ic 'conda activate base >/dev/null 2>&1; echo after_activate=${CONDA_DEFAULT_ENV:-<empty>}; which python'
```
