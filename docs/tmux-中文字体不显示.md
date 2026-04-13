# Tmux中文字体不显示

## Question

如何解决Fedora hyprland远程机器使用kitty或者ptyxis ssh到本机macmini之后，再启动tmux，远程机器tmux窗口中的中文无法正常显示，均显示为下划线？使用macbookair远程连接到本机macmini，就不会出现tmux字体显示问题。

## Answer

这个现象大概率不是“字体坏了”，而是 `tmux` 把当前终端判断成了“非 UTF-8”，所以把所有 UTF-8 字符直接回退成下划线。`tmux` 官方 FAQ 明确写了：如果它认为终端不兼容 UTF-8，UTF-8 字符就会被替换成 underscores。你补充的现象也很吻合这个判断：同一台 `macmini`，`MacBookAir -> ssh -> tmux` 正常，`Fedora -> kitty/ptyxis -> ssh -> tmux` 异常，说明问题更像是 Fedora 这一侧传过去的终端环境变量不同。

先这样验证，在 Fedora 里 `ssh` 到 `macmini` 后，先不要进 `tmux`：

```bash
echo "$TERM"
locale | egrep '^(LANG|LC_CTYPE|LC_ALL)='
printf '中文测试\n'
tmux -u
```

如果 `tmux -u` 进去以后中文立刻正常了，根因基本就确认了：就是 UTF-8 检测/传递问题。

最直接的解决办法有 3 个，按优先级排：

1. 临时/最快修复

```bash
alias tmux='tmux -u'
```

2. 正规修复 SSH locale 传递  
   Fedora 客户端确认本地 locale 是 UTF-8：

```bash
locale
```

至少应该看到类似 `LANG=zh_CN.UTF-8`、`LANG=en_US.UTF-8` 或 `LC_CTYPE=...UTF-8`。  
然后在 Fedora 的 `~/.ssh/config` 里给这台 `macmini` 加：

```sshconfig
Host macmini
  SendEnv LANG LC_*
```

在 `macmini` 的 `/etc/ssh/sshd_config` 里确认有：

```sshconfig
AcceptEnv LANG LC_*
```

改完重启 `sshd` 或重新开关“Remote Login”。

3. 如果 Fedora 传过去的 locale 值本身和 macOS 不合拍，就在 `macmini` 登录后强制设 UTF-8 再启动 tmux  
   先手工测试：

```bash
export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
tmux
```

如果这样就好了，再把这两行放进 `macmini` 的 shell 登录配置里，只对 SSH 会话生效也可以。

再补一个次要但值得检查的点：如果你是从 `kitty` 连过去，`TERM` 很可能是 `xterm-kitty`。远端 `macmini` 如果没有这个 terminfo，也会引出各种兼容性问题。检查：

```bash
echo "$TERM"
infocmp "$TERM"
```

如果 `TERM=xterm-kitty` 且 `infocmp` 找不到，就按 kitty 官方文档把 terminfo 拷到 `macmini`。因为 macOS 上 `tic` 不能直接吃 stdin，建议这样：

```bash
# Fedora 本机
infocmp -a xterm-kitty > /tmp/xterm-kitty.terminfo
scp /tmp/xterm-kitty.terminfo macmini:/tmp/

# macmini
tic -x -o ~/.terminfo /tmp/xterm-kitty.terminfo
```

另外，`~/.tmux.conf` 里建议用：

```tmux
set -g default-terminal "tmux-256color"
```

不要把 tmux 里面的 `default-terminal` 设成 `xterm-kitty`。

如果你愿意，我可以直接给你一套最小排查清单，你把 Fedora 连上 `macmini` 后几条命令的输出贴过来，我能基本一次性定位。

参考：

- tmux FAQ: https://github.com/tmux/tmux/wiki/FAQ
- kitty SSH/terminfo 文档: https://sw.kovidgoyal.net/kitty/kittens/ssh/
- OpenSSH `sshd_config` `AcceptEnv`: https://man.openbsd.org/sshd_config
