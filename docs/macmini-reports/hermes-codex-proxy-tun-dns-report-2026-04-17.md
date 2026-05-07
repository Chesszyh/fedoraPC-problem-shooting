# Hermes Codex API Timeout 代理与 DNS 排障报告

生成时间: 2026-04-17T13:34:24+0800

## 1. Problem Description

本地部署的 Hermes Agent 使用 `openai-codex` provider 调用 Codex backend 时反复失败，典型错误为：

```text
API call failed (attempt 1/3): APITimeoutError
Provider: openai-codex  Model: gpt-5.4
Endpoint: https://chatgpt.com/backend-api/codex
Error: Request timed out.
```

用户环境中 Clash Verge Rev 已开启系统代理，混合代理端口为 `127.0.0.1:7897`。最初未开启 TUN，后来开启 TUN 后仍出现 API timeout。最终问题在不改 Hermes 源码的前提下，通过系统网络配置解决。

## 2. Environment and Scope

- 工作目录：`/Users/chesszyh987/.hermes`
- Hermes 源码目录：`/Users/chesszyh987/.hermes/hermes-agent`
- 当前源码分支：`main`
- 当前 HEAD：`816e3e37 test(feishu): cover new SDK event handler registrations`
- Hermes provider：`openai-codex`
- Codex endpoint：`https://chatgpt.com/backend-api/codex`
- Clash Verge Rev：
  - mixed-port：`7897`
  - system proxy：已开启
  - TUN：最终已开启
  - Clash fake-ip DNS：`127.0.0.1:53` 可返回 `198.18.0.x`
- Tailscale：
  - 之前启用了 Tailscale DNS
  - 最终设置为 `accept-dns=false`
- Hermes gateway：
  - launchd plist：`/Users/chesszyh987/Library/LaunchAgents/ai.hermes.gateway.plist`
  - 当前 PID：`9982`

本报告只记录本地网络与配置排障。敏感信息如 token、cookie、OAuth 凭据、API key、代理节点完整凭据均不记录。

## 3. Symptoms and Reproduction

### 3.1 Hermes API 调用超时

最小 Codex 请求失败时的命令：

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/hermes chat -Q -t '' --max-turns 1 -q '只回复 OK 两个字母。'
```

失败结果：

```text
API call failed after 3 retries: Request timed out.
```

### 3.2 显式走 Clash HTTP 代理时可到达 HTTP 层

```bash
curl -sS -I -L --max-time 15 \
  -x http://127.0.0.1:7897 \
  https://chatgpt.com/backend-api/codex
```

预期未授权/挑战响应，例如 `403` 或 `401`，说明代理和目标 HTTP 路径可达。

实际观察到：

```text
proxy_http_code=403 total=0.162281 remote=127.0.0.1
```

### 3.3 不显式走 HTTP proxy 时出现 TLS EOF 或 timeout

在 TUN 初开但 DNS 仍异常时，模拟 Hermes 当前 custom transport 路径：

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
  curl -sS -I -L --max-time 15 https://chatgpt.com/backend-api/codex
```

曾观察到：

```text
curl: (35) LibreSSL SSL_connect: SSL_ERROR_SYSCALL in connection to chatgpt.com:443
direct_http_code=000
```

同时 Python/httpx custom transport 路径曾出现：

```text
ConnectError: [SSL: UNEXPECTED_EOF_WHILE_READING] EOF occurred in violation of protocol
```

## 4. Investigation Timeline

### 4.1 检查 Hermes 是否继承代理环境变量

发现当前 shell 有代理变量：

```text
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
```

但 launchd 启动的 Hermes gateway 不可靠继承 shell/system proxy 环境。因此曾在 `/Users/chesszyh987/.hermes/.env` 中加入：

```text
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
HTTP_PROXY=http://127.0.0.1:7897
HTTPS_PROXY=http://127.0.0.1:7897
ALL_PROXY=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
NO_PROXY=127.0.0.1,localhost
no_proxy=127.0.0.1,localhost
```

该配置能让普通 httpx/OpenAI SDK default transport 走代理，但对 Hermes 当前实际请求路径仍不够。

### 4.2 发现 Hermes 当前源码会注入 custom HTTPTransport

当前 Hermes upstream `main` 的 `run_agent.py` 会在创建 OpenAI client 时注入自定义 `httpx.HTTPTransport`，用于 TCP keepalive。这个 transport 会绕过 httpx 默认 `trust_env` proxy 处理路径。

验证对照：

```text
default_httpx: status=403 elapsed=0.16s
custom_transport_like_hermes: ConnectTimeout: timed out elapsed=40.03s
```

因此，单纯在 Hermes `.env` 里设置 `HTTP_PROXY/HTTPS_PROXY`，无法保证当前 Hermes Codex 请求走 Clash HTTP proxy。

### 4.3 曾尝试源码补丁，但最终撤回

曾在本地做过小范围源码补丁：当存在 proxy env vars 时不注入 custom transport，并加了回归测试。补丁验证后可以让 Hermes 请求成功。

但用户希望不改 Hermes 代码，并且后来关闭了相关 PR、删除 fork、删除本地分支。因此最终方案回到纯配置层。

当前仓库状态确认：

```text
## main...origin/main
 M scripts/whatsapp-bridge/package-lock.json
```

当前仅剩无关 lockfile 改动，Hermes 源码没有保留该代理补丁。

### 4.4 开启 Clash TUN 后仍失败

用户开启 Clash Verge Rev TUN 后，配置显示：

```yaml
enable_tun_mode: true
tun:
  enable: true
  stack: gvisor
  auto-route: true
```

Clash 日志也显示 TUN 已启动：

```text
[TUN] Tun adapter listening at: utun6([198.18.0.1/30],[fdfe:dcba:9876::1/126]), mtu: 9000, auto route: true, auto redir: false, ip stack: gVisor
```

但 Hermes 真实请求仍然超时。这说明问题不只是“是否开启 TUN”。

### 4.5 发现系统 DNS 被 Tailscale 接管并返回错误 IP

系统/Python 实际解析 `chatgpt.com` 时，曾返回明显异常的地址：

```text
name: chatgpt.com
ip_address: 157.240.16.50
```

Python 也拿到同样结果：

```text
('157.240.16.50', 443)
```

Clash service 日志对应显示 TUN 捕获的是错误目标 IP：

```text
[TCP] 198.18.0.1:57616 --> 104.244.46.85:443 match Match using Proxy[tuic-udp-8443]
```

这类 IP 不是正常的 `chatgpt.com` 解析结果。TUN 捕获并转发了连接，但连接目标 IP 错误，TLS SNI 与目标 IP 不匹配，导致 TLS EOF 或超时。

### 4.6 Clash DNS 本身是正常的

直接查询 Clash DNS：

```bash
dig @127.0.0.1 -p 53 +short chatgpt.com
```

返回：

```text
198.18.0.4
```

这说明 Clash fake-ip DNS 正常，问题在系统解析路径没有使用它。

### 4.7 确认 Tailscale DNS 接管

Tailscale DNS 状态显示：

```text
Tailscale DNS: enabled.
Tailscale is configured to handle DNS queries on this device.
Run 'tailscale set --accept-dns=false' to revert to your system default DNS resolver.
```

同时系统 DNS 已配置成 `127.0.0.1`，但 Tailscale DNS 仍接管实际解析。

## 5. Root Cause

根因是两个配置/实现层叠加：

1. Hermes 当前 upstream 代码为 OpenAI/Codex client 注入 custom `httpx.HTTPTransport`。该路径不会自动使用 `HTTP_PROXY/HTTPS_PROXY` 环境变量，因此在未开启 TUN 时，Hermes Codex 请求会绕过 Clash HTTP proxy，尝试直连 `chatgpt.com`。

2. 开启 Clash TUN 后，TUN 可以捕获直连流量，但 Tailscale DNS 仍接管了系统 DNS，导致 `chatgpt.com` 被解析到错误 IP。TUN 捕获到的是错误 IP 的 TLS 连接，最终表现为 TLS EOF 或 Hermes API timeout。

症状是 `APITimeoutError`，但最终原因不是 Codex token、模型名或 Hermes provider 配置错误，而是“custom transport 绕过 env proxy + Tailscale DNS 污染/接管导致 TUN 目标 IP 错误”。

## 6. Changes Made

### 6.1 Hermes `.env` 代理变量

文件：

```text
/Users/chesszyh987/.hermes/.env
```

加入代理变量：

```text
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
HTTP_PROXY=http://127.0.0.1:7897
HTTPS_PROXY=http://127.0.0.1:7897
ALL_PROXY=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
NO_PROXY=127.0.0.1,localhost
no_proxy=127.0.0.1,localhost
```

注意：这对默认 httpx/OpenAI SDK 路径有用，但对当前 Hermes custom transport 路径不是充分条件。

### 6.2 Clash Verge Rev TUN

用户在 Clash Verge Rev 中开启 TUN。

确认文件：

```text
/Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml
/Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml
```

关键状态：

```yaml
enable_tun_mode: true
tun:
  enable: true
```

### 6.3 Wi-Fi DNS 改为 Clash DNS

执行：

```bash
networksetup -setdnsservers Wi-Fi 127.0.0.1
```

确认：

```bash
networksetup -getdnsservers Wi-Fi
```

输出：

```text
127.0.0.1
```

### 6.4 关闭 Tailscale DNS 接管

执行：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --accept-dns=false
```

确认：

```text
Tailscale DNS: disabled.
```

影响：这会影响 Tailscale MagicDNS，例如 `*.taile68dad.ts.net` 这类尾网域名解析。需要时可以恢复。

### 6.5 重启 Hermes gateway

执行：

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/hermes gateway restart
```

确认：

```text
✓ Gateway service is loaded
PID = 9982
```

## 7. Verification

### 7.1 系统 DNS 当前返回 Clash fake-ip

```bash
dscacheutil -q host -a name chatgpt.com
```

输出：

```text
name: chatgpt.com
ip_address: 198.18.0.4
```

Python 解析：

```bash
./venv/bin/python - <<'PY'
import socket
print(socket.getaddrinfo('chatgpt.com', 443, type=socket.SOCK_STREAM))
PY
```

输出：

```text
[... ('198.18.0.4', 443) ...]
```

### 7.2 无显式代理的直连请求已由 TUN 接管

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
  curl -sS -I -L --max-time 15 \
  https://chatgpt.com/backend-api/codex
```

输出：

```text
direct_http_code=403 total=0.174835 remote=198.18.0.4
```

`403` 是未带真实认证的 HTTP 层响应，证明网络已到达目标服务/Cloudflare 层，不再是连接超时。

### 7.3 模拟 Hermes custom transport 路径成功

使用 `httpx.Client(transport=httpx.HTTPTransport(...))` 模拟当前 Hermes 客户端创建方式，不依赖 env proxy：

```text
custom_transport_no_env status=403 elapsed=0.21s
```

这证明即使 Hermes 绕过 env proxy，只要 TUN + DNS 正确，连接也能成功进入 Clash。

### 7.4 Hermes Codex 真实最小请求成功

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/hermes chat -Q -t '' --max-turns 1 -q '只回复 OK 两个字母。'
```

输出：

```text
session_id: 20260417_132857_7cfa93
OK
```

## 8. Problems Encountered During Debugging

### 8.1 “系统代理已开启”不等于后台进程一定使用代理

macOS 系统代理主要面向遵循系统网络设置的应用。launchd 后台服务、Python/httpx、OpenAI SDK 是否使用代理取决于环境变量、库默认行为、transport 实现等。

### 8.2 Hermes `.env` 代理变量不是充分条件

Hermes 会加载 `/Users/chesszyh987/.hermes/.env`，但当前 Codex/OpenAI client 注入了 custom `HTTPTransport`，该路径不走 httpx 默认环境代理处理。

### 8.3 TUN 开启后仍可能失败

TUN 解决的是“流量捕获”，不是“DNS 正确性”。如果系统解析已经把域名解析到错误 IP，TUN 只会把错误 IP 的连接转发出去，TLS 仍会失败。

### 8.4 `dig @127.0.0.1` 正常不代表系统实际解析正常

Clash DNS 单独查询正常：

```text
198.18.0.4
```

但系统 resolver/Python 实际解析曾仍返回错误 IP。必须用 `dscacheutil` 和 Python `socket.getaddrinfo()` 验证真实应用路径。

### 8.5 Tailscale DNS 是隐藏干扰源

`networksetup -getdnsservers Wi-Fi` 显示 `127.0.0.1` 后，系统仍可能被 Tailscale DNS extension 接管。需要用：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale dns status
```

确认 Tailscale DNS 是否启用。

### 8.6 管理员权限限制

曾考虑用 `/etc/resolver/chatgpt.com` 和 `/etc/resolver/openai.com` 做 per-domain resolver，但当前会话无权限创建 `/etc/resolver`：

```text
mkdir: /etc/resolver: Permission denied
```

因此最终选择关闭 Tailscale DNS 接管，而不是写系统 resolver 文件。

## 9. Reuse Notes and Lessons

- 如果 Hermes/Codex 出现 `APITimeoutError`，先区分三层：
  1. HTTP proxy 显式请求是否可达；
  2. Hermes 当前 transport 是否绕过 env proxy；
  3. TUN 捕获后的 DNS/IP 是否正确。
- 不要只看 `HTTP_PROXY/HTTPS_PROXY` 是否存在。custom `httpx.HTTPTransport` 可能绕过它。
- TUN 模式需要配套 DNS。Clash fake-ip 模式下，应用实际解析应得到 `198.18.0.x`，而不是污染公网 IP。
- 在 macOS 上验证实际 DNS 路径，优先用：
  - `dscacheutil -q host -a name <domain>`
  - Python `socket.getaddrinfo()`
  - `scutil --dns`
- 如果同时使用 Tailscale 和 Clash，Tailscale DNS 可能抢占系统 resolver。必要时可临时关闭：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --accept-dns=false
```

恢复命令：

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --accept-dns=true
```

- 当前最终方案没有改 Hermes 源码。升级 Hermes 后，只要 Clash TUN、系统 DNS 和 Tailscale DNS 状态保持一致，理论上不应再次触发同一类 timeout。

## 10. Appendix: Reusable Commands

### Hermes 最小 Codex 验证

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/hermes chat -Q -t '' --max-turns 1 -q '只回复 OK 两个字母。'
```

### 检查 Hermes gateway

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/hermes gateway status
./venv/bin/hermes gateway restart
```

### 检查 Clash HTTP proxy 是否可达

```bash
curl -sS -I -L --max-time 15 \
  -x http://127.0.0.1:7897 \
  https://chatgpt.com/backend-api/codex
```

### 检查不显式代理时是否被 TUN 接管

```bash
env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u all_proxy \
  curl -sS -I -L --max-time 15 \
  https://chatgpt.com/backend-api/codex
```

### 检查 Clash DNS

```bash
dig @127.0.0.1 -p 53 +short chatgpt.com
dig @127.0.0.1 -p 53 +short openai.com
```

### 检查系统实际 DNS

```bash
dscacheutil -q host -a name chatgpt.com
scutil --dns | sed -n '1,120p'
```

### 检查 Python 应用实际解析

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./venv/bin/python - <<'PY'
import socket
print(socket.getaddrinfo('chatgpt.com', 443, type=socket.SOCK_STREAM))
PY
```

### 设置 Wi-Fi DNS 为 Clash DNS

```bash
networksetup -setdnsservers Wi-Fi 127.0.0.1
networksetup -getdnsservers Wi-Fi
```

### 刷新 macOS DNS 缓存

```bash
dscacheutil -flushcache
killall -HUP mDNSResponder
```

### 检查 Tailscale DNS

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale dns status
/Applications/Tailscale.app/Contents/MacOS/Tailscale debug prefs
```

### 关闭或恢复 Tailscale DNS 接管

```bash
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --accept-dns=false
/Applications/Tailscale.app/Contents/MacOS/Tailscale set --accept-dns=true
```

### 查看 Clash Verge Rev TUN 状态

```bash
sed -n '16,75p' "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/verge.yaml"
sed -n '60,76p' "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml"
tail -n 120 "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/logs/service/service_latest.log"
```

