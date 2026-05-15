生成时间: 2026-05-15T20:02:26+08:00

# CPA 8317 通过 Cloudflare Tunnel 有限公网暴露排障报告

## 1. Problem Description

本次目标是在个人电脑没有公网 IP 的情况下，将本机 CLIProxyAPI（下称 CPA）`8317` 端口有限暴露给异地朋友使用。朋友应当能通过 Cloudflare 托管域名访问模型 API，例如：

```text
Base URL: https://cpa.chesszyh.xyz/v1
Authorization: Bearer <CPA_API_KEY>
```

同时必须满足两个边界：

- 公网只用于模型 API 调用，不应暴露 CPA 管理面板和管理 API。
- 本机、局域网、Tailscale 私有网仍可按原方式访问本地 CPA 服务和管理面板。

会话后半段还处理了关联服务 `cpa-usage-keeper`：CPA 管理密码从弱密码改成强密码后，keeper 的 `.env` / 容器环境也需要同步，否则使用统计同步会因为旧 management key 失败。

## 2. Environment and Scope

关键环境：

- 主机路径：`/home/chesszyh/cliproxyapi`
- CPA systemd user service：`/home/chesszyh/.config/systemd/user/cliproxyapi.service`
- CPA 运行二进制：`/home/chesszyh/cliproxyapi/cli-proxy-api`
- CPA 版本：`v7.0.6-8-ga0f4037d`
- CPA 本地端口：`:8317`
- Cloudflare Tunnel 配置：`/home/chesszyh/.cloudflared/config.yml`
- Cloudflare Tunnel systemd user service：`/home/chesszyh/.config/systemd/user/cloudflared-cpa.service`
- Tunnel 名称：`cpa-8317`
- 公网域名：`cpa.chesszyh.xyz`
- 使用统计容器：`cpa-usage-keeper`
- keeper 数据目录：`/home/chesszyh/.cli-proxy-api/usage-keeper`
- keeper 持久环境文件：`/home/chesszyh/cliproxyapi/cpa-usage-keeper.env`

敏感信息处理：

- CPA API key、CPA management key、keeper 登录密码、Cloudflare token 和 Tunnel credentials 均不在本报告中明文记录。
- 报告中的 `<CPA_API_KEY>`、`<MANAGEMENT_KEY>`、`<REDACTED_PASSWORD>` 均为占位符。

## 3. Symptoms and Reproduction

初始需求是让朋友通过域名调用本机 CPA 聚合模型。配置过程中出现过以下现象。

Cloudflare DNS route 起初落到错误 zone：

```text
Added CNAME cpa.chesszyh.xyz.neurosama.uk which will route to this tunnel
```

这说明当前 `cloudflared` 登录证书并没有选中 `chesszyh.xyz` zone。更新 certificate 后，重新 route DNS 的输出变为正确：

```text
Added CNAME cpa.chesszyh.xyz which will route to this tunnel
```

`cloudflared` 初次运行时使用 QUIC，受到本机透明代理 / fake-ip 环境影响，连接 Cloudflare edge 失败：

```text
Failed to dial a quic connection
timeout: no recent network activity
```

本机普通 `curl https://cpa.chesszyh.xyz/...` 也受到 fake-ip 影响，TLS 报错：

```text
TLS connect error: error:0A000126:SSL routines::unexpected eof while reading
```

此外，用户后来明确收敛需求：不是要把管理面板暴露给朋友，而是“朋友能通过域名，走我本地的 8317 端口调用 CPA 的模型就行”。因此公网管理路径必须在 Tunnel 层直接拦截。

最后，修改 CPA management key 后，`cpa-usage-keeper` 容器仍使用旧环境变量，日志出现 Redis usage queue 认证失败：

```text
redis drain pull failed
fetch redis usage: redis queue auth failed: ERR IP banned due to too many failed attempts
```

## 4. Investigation Timeline

1. 检查本机 CPA 服务，确认 `cliproxyapi.service` 已运行，版本为 `v7.0.6-8-ga0f4037d`，监听 `:8317`。

2. 检查 `cloudflared`，发现已安装且已有旧 tunnel `Fedora`，但 `~/.cloudflared` 初始只有 `cert.pem`，没有本次 CPA 专用 tunnel 配置。

3. 创建新 tunnel：

```bash
cloudflared tunnel create cpa-8317
```

生成 tunnel credentials：

```text
/home/chesszyh/.cloudflared/1013dc45-8f42-493f-9aec-af1762fb94e7.json
```

4. 第一次执行 DNS route 时，Cloudflare 输出的记录名是 `cpa.chesszyh.xyz.neurosama.uk`，判断为证书绑定 zone 错误，暂停等待用户重新登录并选择正确 zone。

5. 用户更新 Cloudflare tunnel certificate 后，重新执行：

```bash
cloudflared tunnel route dns cpa-8317 cpa.chesszyh.xyz
```

输出变为正确的 `cpa.chesszyh.xyz`。

6. 为 tunnel 写入 `~/.cloudflared/config.yml`，最初 catch-all 直接转发所有路径到 `http://127.0.0.1:8317`。

7. 发现本机网络环境将 Cloudflare edge / 外部域名解析到 `198.18.0.x` fake-ip，QUIC 连接超时。将 systemd user service 改为 `--protocol http2` 并显式设置本地 HTTP 代理环境变量后，tunnel 成功注册 edge 连接。

8. 用户指出管理面板不应该暴露公网，只需要朋友能调用模型 API。于是将 ingress 改为先拦截 `/management.html` 与 `/v0/management*`，再把剩余路径转发到本机 `8317`。

9. 使用 `curl --resolve cpa.chesszyh.xyz:443:104.16.0.1` 绕过本机 DNS/fake-ip 验证公网行为：

```text
models:200 4496
mgmt:404 0
panel:404 0
```

10. 修改 CPA management key 后，检查 `cpa-usage-keeper`，发现容器仍有旧环境变量：

```text
LOGIN_PASSWORD=<old weak password>
CPA_MANAGEMENT_KEY=<old weak password>
```

11. 创建持久 env 文件 `/home/chesszyh/cliproxyapi/cpa-usage-keeper.env`，用新强密码同步 `LOGIN_PASSWORD` 与 `CPA_MANAGEMENT_KEY`，重建容器并保留原 SQLite 数据目录。

12. keeper 因旧密码失败触发 CPA Redis usage queue 临时 IP ban。重启 CPA 后，keeper 同步恢复，状态接口返回：

```json
{"running":true,"sync_running":true,"timezone":"Asia/Shanghai","last_status":"completed"}
```

## 5. Root Cause

本次问题不是单一配置错误，而是多个边界混在一起导致的。

第一层根因是 Cloudflare certificate / zone 选择错误。`cloudflared tunnel route dns` 会根据当前证书对应的 zone 创建 DNS 记录，证书选错时即使命令成功，也会创建到错误域名下。

第二层根因是本机代理 / fake-ip 网络环境影响了 `cloudflared`。QUIC 直连 Cloudflare edge 时命中了 `198.18.0.x` fake-ip，导致 timeout。切换到 `--protocol http2` 并让 `cloudflared` 走本机 HTTP 代理后，edge 连接恢复。

第三层根因是 tunnel ingress 默认 catch-all 会把所有路径都转发到本机 CPA。如果不先拦截管理路径，公网用户就能访问 `/management.html` 与 `/v0/management/*`，安全边界不符合“只给朋友调用模型 API”的目标。

第四层根因是 CPA management key 改强后，`cpa-usage-keeper` 的容器环境仍保留旧值。由于 keeper 用 management key 读取 Redis usage queue，旧密码连续失败触发了 CPA 的临时 IP ban。

## 6. Changes Made

Cloudflare Tunnel 配置写入：

```text
/home/chesszyh/.cloudflared/config.yml
```

最终关键 ingress 形态：

```yaml
ingress:
  - hostname: cpa.chesszyh.xyz
    path: /management.html
    service: http_status:404
  - hostname: cpa.chesszyh.xyz
    path: /v0/management*
    service: http_status:404
  - hostname: cpa.chesszyh.xyz
    service: http://127.0.0.1:8317
  - service: http_status:404
```

Cloudflare Tunnel systemd user service 写入：

```text
/home/chesszyh/.config/systemd/user/cloudflared-cpa.service
```

关键点：

```ini
ExecStart=/usr/bin/cloudflared tunnel --protocol http2 --config /home/chesszyh/.cloudflared/config.yml run
```

并显式设置代理环境变量，让 `cloudflared` 通过本机代理建立 HTTP/2 连接。

CPA management key 已改强。报告不记录真实值。CPA 重启后配置文件内自动保存为 bcrypt hash。

keeper 持久 env 文件新增：

```text
/home/chesszyh/cliproxyapi/cpa-usage-keeper.env
```

其中 `CPA_MANAGEMENT_KEY` 与 `LOGIN_PASSWORD` 已同步为新强密码，报告中不记录明文。

重建 keeper 容器时保留原数据目录：

```text
/home/chesszyh/.cli-proxy-api/usage-keeper:/data
```

因此历史 SQLite 统计数据未丢失。

另外，写入了复用 handoff 文档：

```text
/home/chesszyh/cliproxyapi/HANDOFF.md
```

用于在另一台机器上复现 `ai.chesszyh.xyz -> 本机 8317` 的配置流程。

## 7. Verification

CPA 服务状态：

```text
cliproxyapi.service active (running)
CLIProxyAPI Version: v7.0.6-8-ga0f4037d
API server started successfully on: :8317
```

Cloudflare Tunnel 状态：

```text
cpa-8317 2026-05-15T10:48:49Z 1xhkg12, 1xsjc01
```

公网 API 验证，使用 CPA API key：

```bash
API_KEY='<CPA_API_KEY>'
curl --noproxy '*' \
  --resolve cpa.chesszyh.xyz:443:104.16.0.1 \
  -sS -o /tmp/cpa-public-models-report.json \
  -w 'models:%{http_code} %{size_download}\n' \
  -H "Authorization: Bearer ${API_KEY}" \
  https://cpa.chesszyh.xyz/v1/models
```

结果：

```text
models:200 4496
```

公网管理 API 拦截验证：

```text
mgmt:404 0
panel:404 0
```

keeper 状态验证：

```text
cpa-usage-keeper Up ... (healthy) 0.0.0.0:8318->8080/tcp
```

keeper API 状态：

```json
{"running":true,"sync_running":true,"timezone":"Asia/Shanghai","last_status":"completed"}
```

## 8. Problems Encountered During Debugging

错误假设一：以为 `cloudflared tunnel route dns cpa-8317 cpa.chesszyh.xyz` 成功就表示 DNS 已在正确 zone。实际上输出中出现 `cpa.chesszyh.xyz.neurosama.uk`，说明证书/zone 错了。

错误假设二：最初把整个 `cpa.chesszyh.xyz` catch-all 转发到 `8317`，这会让管理路径也进入公网暴露面。后来根据用户澄清改为“只暴露模型 API，管理路径公网 404”。

错误假设三：用本机普通 `curl` 验证公网域名。由于本机网络存在 fake-ip / 代理栈，普通 `curl` 得到 TLS EOF，不能代表外部用户真实访问。后续改用 `curl --resolve ...:104.16.0.1` 直接命中 Cloudflare edge 验证。

错误假设四：只改 CPA management key 就完成安全加固。实际上 keeper 还保存旧 management key，导致后台 Redis usage queue 同步失败并触发临时 IP ban。

## 9. Reuse Notes and Lessons

Cloudflare Tunnel 的 DNS route 一定要看完整输出。正确输出必须是目标域名本身，而不是被拼到另一个 zone 后面。

Tunnel ingress 规则顺序是安全边界的一部分。管理路径必须放在 catch-all 转发规则之前。

如果本机有 Clash、WARP、TUN、fake-ip 或透明代理，`cloudflared` 的 QUIC 直连可能失败。可优先尝试：

```bash
cloudflared tunnel --protocol http2 --config <config.yml> run
```

如果 `cloudflared` 服务由 systemd 启动，代理环境变量要写进 service 文件；不要假设交互 shell 的代理变量会自动传给 user service。

CPA management key 改动后，所有依赖 management API / Redis usage queue 的伴随服务都要同步更新。`cpa-usage-keeper` 至少需要同步：

```text
CPA_MANAGEMENT_KEY
LOGIN_PASSWORD
```

重建 keeper 容器时必须保留数据卷：

```text
/home/chesszyh/.cli-proxy-api/usage-keeper:/data
```

否则可能丢失历史统计数据库。

## 10. Appendix: Reusable Commands

检查 CPA：

```bash
systemctl --user status cliproxyapi --no-pager
curl -i http://127.0.0.1:8317/v1/models
```

创建 tunnel：

```bash
cloudflared tunnel login
cloudflared tunnel create cpa-8317
cloudflared tunnel route dns cpa-8317 cpa.chesszyh.xyz
```

验证 tunnel：

```bash
cloudflared tunnel --config /home/chesszyh/.cloudflared/config.yml ingress validate
cloudflared tunnel info cpa-8317
systemctl --user status cloudflared-cpa --no-pager
```

公网 API 验证：

```bash
API_KEY='<CPA_API_KEY>'
curl --noproxy '*' \
  --resolve cpa.chesszyh.xyz:443:104.16.0.1 \
  -sS -o /tmp/cpa-public-models.json \
  -w '%{http_code} %{size_download}\n' \
  -H "Authorization: Bearer ${API_KEY}" \
  https://cpa.chesszyh.xyz/v1/models
```

公网管理路径拦截验证：

```bash
curl --noproxy '*' --resolve cpa.chesszyh.xyz:443:104.16.0.1 \
  -sS -o /tmp/cpa-public-panel.txt \
  -w 'panel:%{http_code} %{size_download}\n' \
  https://cpa.chesszyh.xyz/management.html

curl --noproxy '*' --resolve cpa.chesszyh.xyz:443:104.16.0.1 \
  -sS -o /tmp/cpa-public-management.json \
  -w 'mgmt:%{http_code} %{size_download}\n' \
  -H "Authorization: Bearer <MANAGEMENT_KEY>" \
  https://cpa.chesszyh.xyz/v0/management/config
```

keeper 重建参考：

```bash
docker stop cpa-usage-keeper
docker rm cpa-usage-keeper
docker run -d \
  --name cpa-usage-keeper \
  --restart unless-stopped \
  --add-host host.docker.internal:host-gateway \
  --env-file /home/chesszyh/cliproxyapi/cpa-usage-keeper.env \
  -p 8318:8080 \
  -v /home/chesszyh/.cli-proxy-api/usage-keeper:/data \
  ghcr.io/willxup/cpa-usage-keeper:latest
```

keeper 状态验证：

```bash
docker ps --filter name=cpa-usage-keeper
curl -sS -b /tmp/keeper.cookies http://127.0.0.1:8318/api/v1/status
curl -sS -b /tmp/keeper.cookies http://127.0.0.1:8318/api/v1/usage/overview
```
