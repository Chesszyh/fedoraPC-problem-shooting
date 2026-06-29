# DevSpace MCP 接入 ChatGPT 时 Cloudflare Bot Fight Mode 拦截 DCR 问题报告

生成时间: 2026-06-20T19:42:55+08:00

## Problem Description

在本机部署 `@waishnav/devspace` 后，目标是让 ChatGPT Web 通过 MCP 连接本机允许目录，并使用正式公网地址：

```text
https://chatgpt.chesszyh.xyz/mcp
```

DevSpace 本地服务、Cloudflare Tunnel、OAuth metadata 和 Dynamic Client Registration endpoint 初步都能从本机访问，但 ChatGPT Web 创建自定义 MCP 应用时持续报错：

```text
创建连接器时出错
Dynamic client registration failed: registration endpoint returned 403
```

最终确认根因不是 DevSpace OAuth 配置、不是 MCP URL 填错、不是 `/register` 本身不可用，而是 Cloudflare Free 版 Bot Fight Mode 拦截了 ChatGPT 后端对正式域名的 Dynamic Client Registration 请求。关闭 Bot Fight Mode 后，正式域名连接立即成功。

## Environment and Scope

主机与项目：

```text
Host: Fedora / Hyprland workstation
Project: /home/chesszyh/Downloads/chatgpt-mcp/devspace
Package: @waishnav/devspace@1.0.1
Node: v22.22.2
DevSpace local MCP: http://127.0.0.1:7676/mcp
Formal public MCP: https://chatgpt.chesszyh.xyz/mcp
Cloudflare account ID: e149721e64f8066c79e9b8fd3f5b596b
Cloudflare zone: chesszyh.xyz
Cloudflare zone ID: 068cfc544d02c934ee7012e7d1324ef8
Cloudflare tunnel: devspace-mcp
Tunnel ID: 2a52672e-2e1f-4f19-b7ea-469334370ab5
```

本地持久化配置与服务：

```text
/home/chesszyh/.cloudflared/devspace-mcp.yml
/home/chesszyh/.config/systemd/user/cloudflared-devspace-mcp.service
/home/chesszyh/.config/systemd/user/devspace-mcp.service
/home/chesszyh/.npm-global/lib/node_modules/@waishnav/devspace/dist/server.js
```

安全边界：

- DevSpace `allowedRoots` 限定为 `/home/chesszyh/Documents/ChatGPT-MCP`。
- Cloudflare API token、DevSpace Owner password、OAuth client tokens 均需脱敏，不应写入报告。
- 报告中不记录临时 `trycloudflare.com` 完整主机名，避免发布仍可能被复用的临时入口。

## Symptoms and Reproduction

### ChatGPT Web 报错

ChatGPT Web 创建新应用时填写：

```text
名称: DevSpace
服务器 URL: https://chatgpt.chesszyh.xyz/mcp
身份验证: OAuth
注册方法: 动态客户端注册 (DCR)
默认作用域: devspace
OIDC: 关闭
```

点击创建后出现：

```text
Dynamic client registration failed: registration endpoint returned 403
```

### DevSpace 侧日志

正式域名失败时，DevSpace 只收到 discovery 请求，未收到 ChatGPT 后端的 DCR 注册请求：

```text
GET /.well-known/oauth-protected-resource/mcp -> 200
GET /.well-known/oauth-authorization-server -> 200
GET /.well-known/openid-configuration -> 200
```

缺失关键请求：

```text
POST /register
```

这说明 `403` 没有进入本机 DevSpace 服务，失败发生在 Cloudflare 边缘层或 ChatGPT 到边缘层之间。

### 本机公网验证正常

从本机经 Cloudflare 正式域名请求：

```bash
curl -i https://chatgpt.chesszyh.xyz/.well-known/oauth-authorization-server

curl -i https://chatgpt.chesszyh.xyz/register \
  -H 'content-type: application/json' \
  --data '{"redirect_uris":["https://chatgpt.com/connector/oauth/test-callback"],"client_name":"probe","grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}'

curl -i https://chatgpt.chesszyh.xyz/mcp
```

预期结果：

```text
/.well-known/oauth-authorization-server -> HTTP/2 200
/register -> HTTP/2 201
/mcp -> HTTP/2 401 Missing Authorization header
```

`/mcp` 的 401 是正常的 OAuth 保护资源响应，表示服务已经到达 DevSpace，只是缺少 bearer token。

## Investigation Timeline

### 1. 创建正式 Cloudflare Tunnel 和 DNS

创建独立 tunnel：

```bash
cloudflared tunnel create devspace-mcp
cloudflared tunnel route dns devspace-mcp chatgpt.chesszyh.xyz
```

写入 tunnel 配置：

```yaml
tunnel: 2a52672e-2e1f-4f19-b7ea-469334370ab5
credentials-file: /home/chesszyh/.cloudflared/2a52672e-2e1f-4f19-b7ea-469334370ab5.json
protocol: http2

ingress:
  - hostname: chatgpt.chesszyh.xyz
    service: http://127.0.0.1:7676
  - service: http_status:404
```

创建用户服务：

```text
/home/chesszyh/.config/systemd/user/cloudflared-devspace-mcp.service
```

服务运行后 Cloudflare 侧能看到 connector，公网 `/mcp` 能返回 DevSpace 的 401。

### 2. 配置 DevSpace public base URL

持久化 DevSpace 公网地址：

```bash
devspace config set publicBaseUrl https://chatgpt.chesszyh.xyz
```

最终配置：

```json
{
  "host": "127.0.0.1",
  "port": 7676,
  "allowedRoots": [
    "/home/chesszyh/Documents/ChatGPT-MCP"
  ],
  "publicBaseUrl": "https://chatgpt.chesszyh.xyz"
}
```

### 3. 排除 MCP URL 填写错误

确认 ChatGPT Web 表单里填写的是完整 MCP endpoint：

```text
https://chatgpt.chesszyh.xyz/mcp
```

不是：

```text
https://chatgpt.chesszyh.xyz
```

但 ChatGPT 仍报 DCR 403。

### 4. 修补 DevSpace OAuth discovery 兼容性

ChatGPT Web 曾探测：

```text
GET /.well-known/openid-configuration
```

而 DevSpace 原始实现只提供：

```text
/.well-known/oauth-protected-resource/mcp
/.well-known/oauth-authorization-server
```

因此对全局安装的 DevSpace 入口做了兼容补丁：

```text
/home/chesszyh/.npm-global/lib/node_modules/@waishnav/devspace/dist/server.js
```

补充行为：

- `GET /.well-known/openid-configuration` 返回 OAuth authorization server metadata。
- `GET /` 返回同一份 metadata。
- `POST /` 也按 DCR 注册处理，兼容错误地把 issuer 根路径当注册端点的客户端。
- 请求日志增加 `originalUrl`、`url`、`baseUrl`，便于定位 Express router 嵌套路由下的真实路径。

这些改动让 discovery 阶段全部返回 200，但正式域名仍然在 ChatGPT Web 创建时返回 DCR 403。

### 5. 修复 DevSpace 与 Cloudflare `X-Forwarded-For` 的 rate-limit 校验

Cloudflare Tunnel 会带 `X-Forwarded-For`。DevSpace 使用 `express-rate-limit` 时出现过两类校验问题：

```text
ERR_ERL_UNEXPECTED_X_FORWARDED_FOR
ERR_ERL_PERMISSIVE_TRUST_PROXY
```

处理方式：

- systemd 环境添加 `DEVSPACE_TRUST_PROXY=true`。
- 将 DevSpace 内部 Express `trust proxy` 从全信任改为只信任 loopback：

```js
app.set("trust proxy", "loopback");
```

之后本机模拟带 `X-Forwarded-For` 的 `/register` 请求能返回 201。

### 6. 用 Quick Tunnel 隔离 Cloudflare Zone 安全策略

为了区分 DevSpace 问题和 `chesszyh.xyz` zone 安全策略问题，临时启动 Cloudflare Quick Tunnel 指向独立端口：

```bash
cloudflared tunnel --url http://127.0.0.1:7677 --protocol http2
```

并启动一份临时 DevSpace：

```bash
PORT=7677 \
DEVSPACE_PUBLIC_BASE_URL='https://<redacted>.trycloudflare.com' \
DEVSPACE_ALLOWED_HOSTS='localhost,127.0.0.1,::1,<redacted>.trycloudflare.com' \
DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS='chatgpt.com,chat.openai.com,openai.com,platform.openai.com' \
DEVSPACE_TRUST_PROXY=true \
devspace serve
```

ChatGPT Web 使用 Quick Tunnel URL 创建应用成功：

```text
https://<redacted>.trycloudflare.com/mcp
```

这一步是关键证据：同一台机器、同一个 DevSpace、同一套 OAuth/DCR 流程，换成 `trycloudflare.com` 就成功，说明正式域名失败来自 `chesszyh.xyz` 的 Cloudflare zone 安全策略。

### 7. 创建 Cloudflare WAF Skip 规则

使用具备 WAF 写权限的 Cloudflare API token 创建 zone ruleset：

```text
Ruleset: DevSpace MCP security bypass
Ruleset ID: 20d989c482b642e7a0caea4357e955b3
Rule ID: 103117342b734f7a9c638a44fecd8d9b
Phase: http_request_firewall_custom
Action: skip
```

初始规则只覆盖 MCP/OAuth 路径，之后放宽到整个子域名：

```text
http.host eq "chatgpt.chesszyh.xyz"
```

跳过：

```text
http_ratelimit
http_request_sbfm
http_request_firewall_managed
bic
securityLevel
uaBlock
zoneLockdown
hot
rateLimit
waf
```

规则创建成功后，本机通过正式域名仍可验证：

```text
GET  /.well-known/oauth-authorization-server -> 200
POST /register -> 201
GET  /mcp -> 401
```

但 ChatGPT Web 仍报 DCR 403。

### 8. 关闭 Free 版 Bot Fight Mode

用户最终在 Cloudflare Dashboard 找到：

```text
https://dash.cloudflare.com/e149721e64f8066c79e9b8fd3f5b596b/chesszyh.xyz/security/settings?tabs=bot-traffic
```

关闭：

```text
Bot Fight Mode
```

关闭后，ChatGPT Web 使用正式域名立即连接成功。

## Root Cause

根因是 Cloudflare Free 版 Bot Fight Mode 拦截了 ChatGPT 后端对 `chatgpt.chesszyh.xyz` 的 Dynamic Client Registration 请求。

重要区分：

- DevSpace 本地服务没有坏。
- Cloudflare Tunnel 没有坏。
- DNS 没有坏。
- `/register` endpoint 没有坏。
- ChatGPT 表单中的 MCP URL 没有填错。
- WAF Skip 规则创建成功，但无法绕过 Free 版 Bot Fight Mode。

Cloudflare 的 WAF Skip 规则可以跳过 WAF Managed Rules、Rate Limiting、Super Bot Fight Mode、Browser Integrity Check、Security Level 等产品，但 Free 版 Bot Fight Mode 不在 Ruleset Engine 的可跳过范围内。因此即便 Skip 规则覆盖整个 `chatgpt.chesszyh.xyz`，ChatGPT 的 DCR POST 仍可能在 Bot Fight Mode 层被拦，且请求不会进入本机 DevSpace 日志。

最终修复是关闭 `chesszyh.xyz` 的 Bot Fight Mode。

## Changes Made

### 本机 DevSpace 与 Cloudflare Tunnel 配置

创建或修改：

```text
/home/chesszyh/.cloudflared/devspace-mcp.yml
/home/chesszyh/.config/systemd/user/cloudflared-devspace-mcp.service
/home/chesszyh/.config/systemd/user/devspace-mcp.service
/home/chesszyh/.npm-global/lib/node_modules/@waishnav/devspace/dist/server.js
```

`cloudflared-devspace-mcp.service` 负责正式 tunnel：

```text
cloudflared tunnel --protocol http2 --config /home/chesszyh/.cloudflared/devspace-mcp.yml run
```

`devspace-mcp.service` 负责托管 DevSpace：

```text
ExecStart=/home/chesszyh/.npm-global/bin/devspace serve
Environment=DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS=chatgpt.com,chat.openai.com,openai.com,platform.openai.com
Environment=DEVSPACE_TRUST_PROXY=true
```

### DevSpace 全局包兼容补丁

在：

```text
/home/chesszyh/.npm-global/lib/node_modules/@waishnav/devspace/dist/server.js
```

加入：

- `/.well-known/openid-configuration` 兼容。
- 根路径 `/` metadata 兼容。
- 根路径 `POST /` DCR 兼容。
- 请求日志增加 `originalUrl`、`url`、`baseUrl`。
- `trust proxy` 改为 `"loopback"`。

注意：这些是对全局安装包的本地补丁，后续 `npm install -g @waishnav/devspace` 或版本升级可能覆盖。若新版 DevSpace 已原生支持这些能力，应优先回到上游版本。

### Cloudflare 配置

创建 WAF Skip ruleset：

```text
Ruleset ID: 20d989c482b642e7a0caea4357e955b3
Rule ID: 103117342b734f7a9c638a44fecd8d9b
```

关闭 Cloudflare Dashboard 中的：

```text
Bot Fight Mode
```

这是最终让正式域名连接成功的关键改动。

## Verification

### 本地服务状态

```bash
systemctl --user status devspace-mcp.service --no-pager
systemctl --user status cloudflared-devspace-mcp.service --no-pager
```

期望：

```text
Active: active (running)
```

### DevSpace doctor

```bash
devspace doctor
```

关键输出：

```text
Local MCP URL: http://127.0.0.1:7676/mcp
Public MCP URL: https://chatgpt.chesszyh.xyz/mcp
Allowed roots: /home/chesszyh/Documents/ChatGPT-MCP
Allowed hosts: localhost, 127.0.0.1, ::1, chatgpt.chesszyh.xyz
```

### 正式域名端点

```bash
curl -i https://chatgpt.chesszyh.xyz/.well-known/oauth-protected-resource/mcp
curl -i https://chatgpt.chesszyh.xyz/.well-known/oauth-authorization-server
curl -i https://chatgpt.chesszyh.xyz/.well-known/openid-configuration
```

期望均返回 `200`。

```bash
curl -i https://chatgpt.chesszyh.xyz/register \
  -H 'content-type: application/json' \
  --data '{"redirect_uris":["https://chatgpt.com/connector/oauth/test-callback"],"client_name":"probe","grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}'
```

期望：

```text
HTTP/2 201
```

```bash
curl -i https://chatgpt.chesszyh.xyz/mcp
```

期望：

```text
HTTP/2 401
WWW-Authenticate: Bearer ...
```

### ChatGPT Web 验证

在 ChatGPT Web 新建应用：

```text
服务器 URL: https://chatgpt.chesszyh.xyz/mcp
身份验证: OAuth
注册方法: 动态客户端注册 (DCR)
默认作用域: devspace
OIDC: 关闭
```

创建成功后会进入 DevSpace Owner password 授权页。授权后 ChatGPT 可调用 DevSpace MCP 工具。

## Problems Encountered During Debugging

### 错误假设 1：MCP URL 填错

早期日志中 ChatGPT 请求了 `/` 和 `/.well-known/openid-configuration`，容易误判为用户在 ChatGPT Web 中填了 origin 而不是 `/mcp`。截图确认实际填写的是：

```text
https://chatgpt.chesszyh.xyz/mcp
```

因此 URL 填写不是根因。

### 错误假设 2：DevSpace 不支持 ChatGPT 需要的 OAuth discovery

DevSpace 原生缺少 `/.well-known/openid-configuration`，确实造成过 discovery 兼容问题，但补齐后 ChatGPT 仍报 DCR 403。说明 discovery 不是最终根因。

### 错误假设 3：Cloudflare WAF Skip 规则足够解决

WAF Skip 规则创建成功，并验证本机正式域名 `/register` 返回 201，但 ChatGPT Web 仍失败。最终发现 Free 版 Bot Fight Mode 不能被 WAF Skip 跳过。

### 错误假设 4：正式域名服务不可达

正式域名的 `/.well-known/*`、`/register`、`/mcp` 从本机都能正常访问。Quick Tunnel 能成功连接进一步证明 DevSpace 和 MCP 服务本身无问题。

### API token 权限限制

Cloudflare API token 可以创建 WAF ruleset，但不能：

- 读取安全事件 GraphQL analytics。
- 修改 Zone Settings。
- 读取或修改 Bot Fight Mode settings。

因此最终关闭 Bot Fight Mode 需要用户在 Dashboard 手动完成。

## Reuse Notes and Lessons

1. 判断 MCP DCR 失败时，不要只看 ChatGPT 弹窗。必须同时看 DevSpace 日志是否收到 `POST /register`。
2. 如果 DevSpace 日志只出现 `GET /.well-known/*`，没有 `POST /register`，说明注册请求没有到达 origin。
3. `trycloudflare.com` Quick Tunnel 是隔离 Cloudflare 自定义 zone 安全策略的有效手段。同一 origin 换 quick tunnel 成功，基本可以确认正式 zone 的安全产品在拦截。
4. Cloudflare Free 版 Bot Fight Mode 不能被 WAF Skip 规则绕过。要么关闭它，要么不要把需要 server-to-server POST 的 API 放在受它影响的 hostname 下。
5. DevSpace `GET /mcp -> 401 Missing Authorization header` 是正常状态，不是服务失败。
6. Cloudflare Tunnel 正式配置建议继续使用 named tunnel 和 systemd 服务；Quick Tunnel 只适合诊断和临时测试，重启后地址不可依赖。
7. 对全局 npm 包的补丁要记录清楚，因为后续升级会覆盖。
8. 排障时要脱敏 Cloudflare API token、DevSpace Owner password、OAuth authorization header 和临时 tunnel 主机名。

## Appendix: Reusable Commands

### 查看 DevSpace 与 Tunnel 状态

```bash
systemctl --user status devspace-mcp.service --no-pager
systemctl --user status cloudflared-devspace-mcp.service --no-pager
cloudflared tunnel info devspace-mcp
devspace doctor
```

### 查看 DevSpace 请求日志

```bash
journalctl --user -u devspace-mcp.service --since '10 minutes ago' --no-pager
```

重点看：

```text
originalUrl
status
userAgent
ip
```

以及是否存在：

```text
POST /register
```

### 验证 OAuth metadata

```bash
curl -i https://chatgpt.chesszyh.xyz/.well-known/oauth-protected-resource/mcp
curl -i https://chatgpt.chesszyh.xyz/.well-known/oauth-authorization-server
curl -i https://chatgpt.chesszyh.xyz/.well-known/openid-configuration
```

### 验证 Dynamic Client Registration

```bash
curl -i https://chatgpt.chesszyh.xyz/register \
  -H 'content-type: application/json' \
  --data '{"redirect_uris":["https://chatgpt.com/connector/oauth/test-callback"],"client_name":"probe","grant_types":["authorization_code","refresh_token"],"response_types":["code"],"token_endpoint_auth_method":"none"}'
```

### 验证 MCP protected resource

```bash
curl -i https://chatgpt.chesszyh.xyz/mcp
```

正常响应：

```text
HTTP/2 401
WWW-Authenticate: Bearer error="invalid_token", error_description="Missing Authorization header"
```

### 创建 Quick Tunnel 做隔离测试

```bash
cloudflared tunnel --url http://127.0.0.1:7677 --protocol http2
```

另开一个 DevSpace：

```bash
PORT=7677 \
DEVSPACE_PUBLIC_BASE_URL='https://<redacted>.trycloudflare.com' \
DEVSPACE_ALLOWED_HOSTS='localhost,127.0.0.1,::1,<redacted>.trycloudflare.com' \
DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS='chatgpt.com,chat.openai.com,openai.com,platform.openai.com' \
DEVSPACE_TRUST_PROXY=true \
devspace serve
```

### 查询 Cloudflare WAF ruleset

```bash
CF_TOKEN='<redacted>'
ZONE_ID='068cfc544d02c934ee7012e7d1324ef8'

curl -sS "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/rulesets/phases/http_request_firewall_custom/entrypoint" \
  -H "Authorization: Bearer $CF_TOKEN" \
  -H "Content-Type: application/json"
```

### Dashboard 关闭 Bot Fight Mode

```text
Cloudflare Dashboard
-> chesszyh.xyz
-> Security
-> Settings
-> Bot Traffic
-> Bot Fight Mode: Off
```

或直接进入：

```text
https://dash.cloudflare.com/<account-id>/chesszyh.xyz/security/settings?tabs=bot-traffic
```
