生成时间: 2026-04-21T14:01:09+08:00

# Hyprland 会话缺失 NO_PROXY 导致 Tailscale WebUI 502 排障报告

## 1. Problem Description

问题表现为：在 Fedora + Hyprland + Clash Verge Rev TUN 模式环境中，从当前 Linux 机器访问 Mac mini 的 Tailscale 地址：

```text
http://100.111.131.49:8021/webui/#/logs
```

浏览器返回：

```text
HTTP ERROR 502
100.111.131.49 目前无法处理此请求
```

但访问同一台 Mac mini 的局域网地址：

```text
http://192.168.1.5:8021/webui/#/logs
```

可以正常打开。

本次目标是确认 502 的真实来源，并将修复做成持久化配置，避免以后每次切换代理节点供应商都重新处理一次。

## 2. Environment and Scope

本次排查涉及的主要环境：

- Linux 客户端：Fedora + Hyprland
- 代理软件：Clash Verge Rev，`tun` 模式开启
- 远端目标：Mac mini，Tailscale IP 为 `100.111.131.49`
- WebUI 服务端口：`8021`
- Tailscale CGNAT 网段：`100.64.0.0/10`

本次重点检查范围：

- Tailscale 节点互通是否正常
- `curl` 和浏览器是否被系统代理或 TUN 误导流
- Clash 规则是否已包含 Tailscale 直连
- Hyprland 图形会话启动环境是否完整继承 `NO_PROXY`

本次实际修改的本机文件：

```text
/home/chesszyh/.config/environment.d/95-tailscale-no-proxy.conf
/home/chesszyh/.zshenv
/home/chesszyh/.config/hypr/UserConfigs/ENVariables.conf
```

与问题相关但不是最终根因的本地 Clash 配置目录：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/
```

## 3. Symptoms and Reproduction

最关键的对照复现如下：

### 3.1 默认环境下 `curl` 失败

```bash
curl -v http://100.111.131.49:8021/webui/
```

现象：

- 请求走了 `http_proxy=http://127.0.0.1:7897`
- 返回 `HTTP/1.1 502 Bad Gateway`

### 3.2 显式绕过代理后成功

```bash
curl -v --noproxy '*' http://100.111.131.49:8021/webui/
```

现象：

- 直接走 Tailscale
- 返回 `HTTP/1.1 200 OK`

### 3.3 加上 `NO_PROXY` 后也成功

```bash
NO_PROXY=100.64.0.0/10,100.111.131.49 curl -s -o /dev/null -w '%{http_code}\n' \
  http://100.111.131.49:8021/webui/
```

现象：

```text
200
```

这三组现象已经足够说明：服务本身可达，失败路径来自客户端代理链。

## 4. Investigation Timeline

1. 先确认问题不是 Mac mini 服务端本身异常。

   已知前置证据表明：

   - Mac mini 本机访问 `127.0.0.1:8021`、`192.168.1.5:8021`、`100.111.131.49:8021` 都返回 `200`
   - `tailscale status` 显示 Linux 到 Mac mini 为 `active; direct`
   - Mac mini 反向 `tailscale ping` Linux 也正常
   - Docker 容器日志中没有看到 Linux 浏览器访问 Tailscale 地址时对应的 `/webui/` 请求

   这一步把怀疑范围从“远端服务或 Tailscale 不通”收缩到了“本机请求没有真正打到服务”。

2. 比较默认 `curl` 与 `--noproxy` 行为。

   结论很直接：

   - 默认 `curl` 会使用本地代理 `127.0.0.1:7897`
   - `--noproxy '*'` 时立即恢复 `200`

3. 检查代理环境变量。

   发现当前会话存在：

   ```text
   http_proxy=http://127.0.0.1:7897
   https_proxy=http://127.0.0.1:7897
   all_proxy=http://127.0.0.1:7897
   ```

   当时没有对应的 `NO_PROXY/no_proxy`。

4. 检查 Clash/Mihomo 运行状态和当前配置。

   已确认本机运行了：

   - `clash-verge-service`
   - `verge-mihomo`

   并且当前生成配置里已经存在：

   ```text
   IP-CIDR,100.64.0.0/10,DIRECT,no-resolve
   ```

   这一步很重要，因为它说明“缺少 Clash Tailscale 直连规则”并不是这次浏览器 502 的充分解释。

5. 做最小化浏览器级对照实验。

   使用全新临时用户目录启动 headless Chrome：

   - 只带 `http_proxy/https_proxy/all_proxy`，不带 `NO_PROXY` 时，复现 Chromium 错误页
   - 带同样代理变量，但补上 `NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net` 时，可以拿到真实 WebUI HTML
   - 完全去掉代理环境变量时，也能拿到真实 WebUI HTML

   这一步确认：浏览器本身没有问题，故障点是浏览器启动时继承到的环境变量。

6. 检查扩展和 GNOME 代理配置，排除旁支。

   排查中曾发现历史上装过 Proxy SwitchyOmega 扩展，但其在配置中是禁用状态，之后用户也明确已移除。

   同时检查了：

   ```bash
   gsettings get org.gnome.system.proxy mode
   ```

   返回 `none`。后续虽补过 `ignore-hosts`，但由于当前桌面是 Hyprland，这条线不是主修复路径。

7. 对比 systemd user 环境、Hyprland 进程环境和新开 shell 环境。

   - `systemctl --user show-environment` 中可以看到 `NO_PROXY/no_proxy`
   - 但 `Hyprland` 进程环境里只有：

     ```text
     http_proxy=http://127.0.0.1:7897
     https_proxy=http://127.0.0.1:7897
     all_proxy=http://127.0.0.1:7897
     ```

     没有 `NO_PROXY/no_proxy`

   - 当时新开 `zsh` 也只有三组代理变量，没有 `NO_PROXY/no_proxy`

   这一步把根因定位到图形会话和 shell 的上游环境来源，而不是单个浏览器进程缓存。

8. 继续向上追到真实环境来源。

   检查结果：

   - `/home/chesszyh/.zshenv` 中长期导出了 `http_proxy/https_proxy/all_proxy`
   - 同文件没有导出 `NO_PROXY/no_proxy`
   - `/home/chesszyh/.config/hypr/UserConfigs/ENVariables.conf` 也没有为 Hyprland 显式设置 `NO_PROXY/no_proxy`

   这解释了为什么即使 `pkill -9 chrome` 后重新启动，新的 Chrome 仍然报 `502`：它只是再次从错误的父会话环境继承了同样不完整的代理变量。

## 5. Root Cause

根因不是 Tailscale 链路，不是 Mac mini 上的 WebUI 服务，不是 Docker 端口暴露，也不是 Clash 配置里完全缺少 Tailscale 直连规则。

最终根因是：

1. 当前 Linux 图形会话默认带有：

   ```text
   http_proxy=http://127.0.0.1:7897
   https_proxy=http://127.0.0.1:7897
   all_proxy=http://127.0.0.1:7897
   ```

2. 这些变量会让 `curl`、Chrome 等应用优先把 HTTP 请求送到本地代理。
3. Tailscale 私网地址 `100.111.131.49` 没有进入 `NO_PROXY/no_proxy` 例外列表。
4. 因此访问 `http://100.111.131.49:8021/...` 时，请求并没有直接走 Tailscale，而是先被送进本地代理 `127.0.0.1:7897`。
5. 这个本地代理对该目标返回了 `502 Bad Gateway`，所以浏览器展示 502 错页。
6. 仅仅重启 Chrome 无法解决，因为 Chrome 的父会话环境本身就是错的。

一句话概括：

`Hyprland 会话继承了带代理但不带 NO_PROXY 的环境 -> 浏览器访问 Tailscale HTTP 地址时被送进本地代理 -> 本地代理返回 502`

## 6. Changes Made

### 6.1 为 systemd user 环境补充持久化 `NO_PROXY`

文件：

```text
/home/chesszyh/.config/environment.d/95-tailscale-no-proxy.conf
```

内容：

```text
NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
no_proxy=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
```

作用：

- 给 systemd user 服务和后续导入环境提供统一旁路规则

### 6.2 修正 shell / 登录环境的根源配置

文件：

```text
/home/chesszyh/.zshenv
```

新增：

```text
export NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
export no_proxy="$NO_PROXY"
```

作用：

- 保证以后任何继承用户 shell 环境的程序，不再只拿到三组代理变量

### 6.3 修正 Hyprland 图形会话环境

文件：

```text
/home/chesszyh/.config/hypr/UserConfigs/ENVariables.conf
```

新增：

```text
env = NO_PROXY,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
env = no_proxy,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
```

作用：

- 保证 Hyprland 会话内新启动的图形应用直接继承同样的旁路规则

### 6.4 当前会话的临时同步

为了不必等到下一次完全重登才验证，还执行了：

```bash
hyprctl keyword env "NO_PROXY,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net"
hyprctl keyword env "no_proxy,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net"
systemctl --user import-environment http_proxy https_proxy all_proxy NO_PROXY no_proxy
dbus-update-activation-environment --systemd http_proxy https_proxy all_proxy NO_PROXY no_proxy
```

说明：

- 这些命令用于当前活跃会话的同步验证
- 长期生效仍以 `.zshenv` 和 `ENVariables.conf` 为准

### 6.5 二级保险：保留 Clash 侧 Tailscale 直连规则

本次排查前后，Clash 配置侧也保留了 Tailscale 直连与 fake-ip 过滤规则，作为旁路链路的二级保险。

这不是浏览器 502 的主根因，但建议继续保留：

- `IP-CIDR,100.64.0.0/10,DIRECT,no-resolve`
- `IP-CIDR6,fd7a:115c:a1e0::/48,DIRECT,no-resolve`
- `DOMAIN-SUFFIX,ts.net,DIRECT`
- `DOMAIN-SUFFIX,beta.tailscale.net,DIRECT`

## 7. Verification

### 7.1 新开 shell 已自动带 `NO_PROXY`

```bash
zsh -lc 'env | rg "^(http_proxy|https_proxy|all_proxy|NO_PROXY|no_proxy)="'
```

结果中已同时看到：

```text
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
no_proxy=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
```

### 7.2 新环境下 `curl` 直接返回 200

```bash
zsh -lc 'curl -s -o /dev/null -w "%{http_code}\n" http://100.111.131.49:8021/webui/'
```

结果：

```text
200
```

### 7.3 新环境下 headless Chrome 返回真实 WebUI HTML

```bash
zsh -lc '
browser=$(command -v google-chrome-stable || command -v google-chrome || command -v chromium)
tmp=$(mktemp -d)
"$browser" --headless --disable-gpu --no-sandbox --user-data-dir="$tmp" \
  --dump-dom http://100.111.131.49:8021/webui/ | sed -n "1,8p"
rm -rf "$tmp"
'
```

输出前几行包含：

```html
<!DOCTYPE html>
<html lang="en" class="performance-mode-quality">
...
<title>Nekro Agent WebUI</title>
```

这说明在正确环境下，浏览器访问路径已经命中真实服务，而不是 502 错页。

### 7.4 仍需重登一次图形会话

虽然当前会话已经做了临时同步，但从根上说，真正决定日后行为的是新的 Hyprland 登录会话。  
因此最终验证动作应是：

1. 退出当前 Hyprland 会话
2. 重新登录
3. 打开浏览器访问：

```text
http://100.111.131.49:8021/webui/#/logs
```

预期结果是直接打开 WebUI，不再返回 `HTTP ERROR 502`。

## 8. Problems Encountered During Debugging

1. 最初很容易把问题归咎为“Clash 没有配 Tailscale 直连”，但实际生成配置里已经存在 `100.64.0.0/10,DIRECT`。

2. 一度把“重启 Chrome 后仍失败”解释成浏览器缓存代理配置，这个说法不完整。更准确的解释是：父会话环境本身就缺 `NO_PROXY`，所以每次重启都会重新继承错误配置。

3. 排查过程中查看了 GNOME 的 `gsettings`，但用户实际桌面是 Fedora + Hyprland，这条线不是主修复路径。它可以作为补充检查，但不应被当成根修。

4. 曾检查过历史代理扩展 Proxy SwitchyOmega。这个方向在证据不足时容易干扰判断，最终确认并非主因。

5. `systemctl --user show-environment` 中已经有 `NO_PROXY`，但 Hyprland 进程环境里却没有，说明“systemd user 环境已正确”不等于“当前图形会话也已正确继承”。这是本次排查中最容易误判的点。

## 9. Reuse Notes and Lessons

1. 只要 HTTP 目标是 Tailscale 私网地址，就应默认把 `100.64.0.0/10` 放进 `NO_PROXY/no_proxy`，而不是按单个节点 IP 手工追加。

2. 对于开启了全局 `http_proxy/https_proxy/all_proxy` 的桌面环境，排查“某个内网服务浏览器 502”时，第一优先级不是服务端日志，而是先做这组对照：

   ```bash
   curl -v <URL>
   curl -v --noproxy '*' <URL>
   ```

3. 如果 `--noproxy '*'` 成功，而默认访问失败，基本就可以直接沿“代理环境变量 / 浏览器启动环境 / 桌面会话环境”这条链往上追。

4. 仅修改 `~/.config/environment.d/*.conf` 对“已经启动的图形会话”通常不够；如果父会话已经启动，往往还需要：

   - 重新导入当前会话环境进行临时验证
   - 最终重新登录桌面会话确保根修生效

5. 对 Hyprland + uwsm 这类桌面环境，图形应用是否继承到正确代理变量，关键在会话启动链，而不是浏览器本身。

6. Clash 侧的 `DIRECT` 规则可以作为二级保险，但它不能替代应用层的 `NO_PROXY/no_proxy`。只要应用显式使用 `http_proxy`，请求就可能先被送给本地代理，连 Clash 分流都来不及参与。

## 10. Appendix: Reusable Commands

### 10.1 快速判断是不是代理导致的 Tailscale 访问失败

```bash
curl -v http://100.111.131.49:8021/webui/
curl -v --noproxy '*' http://100.111.131.49:8021/webui/
```

### 10.2 查看当前会话代理变量

```bash
env | grep -i proxy
systemctl --user show-environment | rg '^(http_proxy|https_proxy|all_proxy|NO_PROXY|no_proxy)='
```

### 10.3 查看 Hyprland 进程实际继承了什么

```bash
pidof Hyprland
tr '\0' '\n' < /proc/$(pidof Hyprland)/environ | rg '^(http_proxy|https_proxy|all_proxy|NO_PROXY|no_proxy|DESKTOP_SESSION|XDG_CURRENT_DESKTOP)='
```

### 10.4 查看 shell 根环境来源

```bash
nl -ba ~/.zshenv | sed -n '1,80p'
zsh -lc 'env | rg "^(http_proxy|https_proxy|all_proxy|NO_PROXY|no_proxy)="'
```

### 10.5 当前会话临时补齐旁路变量

```bash
hyprctl keyword env "NO_PROXY,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net"
hyprctl keyword env "no_proxy,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net"
systemctl --user import-environment http_proxy https_proxy all_proxy NO_PROXY no_proxy
dbus-update-activation-environment --systemd http_proxy https_proxy all_proxy NO_PROXY no_proxy
```

### 10.6 持久化修复模板

在 `~/.zshenv` 中加入：

```bash
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897
export all_proxy=http://127.0.0.1:7897
export NO_PROXY=localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
export no_proxy="$NO_PROXY"
```

在 `~/.config/hypr/UserConfigs/ENVariables.conf` 中加入：

```text
env = NO_PROXY,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
env = no_proxy,localhost,127.0.0.1,::1,100.64.0.0/10,.ts.net,.beta.tailscale.net
```
