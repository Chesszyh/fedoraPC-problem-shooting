# GCP x-ui 面板经 Clash TUN 访问 ERR_CONNECTION_CLOSED 排障报告

生成时间: 2026-05-07T22:30:40+08:00

## Problem Description

在 Google Cloud 新加坡 VM 上部署 `3x-ui`/`x-ui` 后，安装流程已完成 Let's Encrypt 证书签发，`x-ui` 服务也显示运行正常，但客户端浏览器访问面板 HTTPS 地址时报错：

```text
无法访问此网站
<redacted-panel-domain> 意外终止了连接。
ERR_CONNECTION_CLOSED
```

用户客户端环境启用了 Clash Verge Rev 的 TUN 模式，当前订阅为“赔钱机场”。SSH 别名 `gcp-sg` 可以直接连通云服务器。

本报告保留排障证据链。面板用户名、密码、WebBasePath、订阅 token、Clash secret、私钥路径内容和完整面板 URL 已脱敏。

## Environment and Scope

- 客户端：Fedora 桌面，Clash Verge Rev + verge-mihomo，TUN 设备名 `Meta`
- 客户端工作目录：`/home/chesszyh/Downloads/3x-ui`
- Clash 运行配置目录：`/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev`
- 服务端：Google Cloud VM，新加坡区域，Ubuntu
- 服务端访问方式：`ssh gcp-sg`
- 面板服务：`x-ui v2.9.4`
- 面板端口：`32797/tcp`
- 面板域名：`<redacted-panel-domain>`
- VM 公网 IP：`<redacted-vm-public-ip>`
- GCP 防火墙规则：`allow-x-ui-panel`

本次问题只涉及客户端到 x-ui 管理面板的访问链路、Clash TUN 路由、GCP 防火墙和 acme.sh 续期 reload 配置；未改动 xray 入站业务配置。

## Symptoms and Reproduction

浏览器访问面板 HTTPS URL 失败，错误为 `ERR_CONNECTION_CLOSED`。

客户端 `curl` 通过 Clash HTTP mixed-port 访问时，CONNECT 成功，但 TLS 握手阶段被提前关闭：

```bash
curl -vkI https://<redacted-panel-domain>:32797/<redacted-webbasepath>/
```

关键输出：

```text
CONNECT <redacted-panel-domain>:32797 HTTP/1.1
HTTP/1.1 200 Connection established
TLS connect error: unexpected eof while reading
```

绕过 HTTP 代理、直接连接 VM 公网 IP 时也曾出现 TLS EOF：

```bash
curl -vkI --noproxy '*' \
  --resolve <redacted-panel-domain>:32797:<redacted-vm-public-ip> \
  https://<redacted-panel-domain>:32797/<redacted-webbasepath>/
```

关键输出：

```text
TLS connect error: unexpected eof while reading
```

服务端本机访问 `127.0.0.1:32797` 能完成 TLS 握手，说明 x-ui 本身不是完全不可用：

```bash
ssh gcp-sg 'curl -vkI --connect-timeout 5 https://127.0.0.1:32797/<redacted-webbasepath>/'
```

`HEAD` 请求返回过 `404 Not Found`，但后续 `GET` 验证返回 `200 text/html`。因此 `HEAD 404` 是 x-ui 对 HEAD/路径处理的表现，不是最终根因。

## Investigation Timeline

1. 确认服务端监听和 x-ui 状态。

   ```bash
   ssh gcp-sg 'sudo ss -ltnp | grep -E ":(32797|2096|80)" || true; sudo x-ui settings; sudo systemctl status x-ui --no-pager -l'
   ```

   证据：

   ```text
   LISTEN *:32797 users:(("x-ui",...))
   Panel is secure with SSL
   Web server running HTTPS on [::]:32797
   ```

   结论：证书路径已经写入面板，x-ui 正在 HTTPS 模式监听 `32797`。

2. 检查 GCP 防火墙。

   ```bash
   gcloud compute firewall-rules list \
     --format='table(name,network,direction,priority,sourceRanges.list(),allowed[].map().firewall_rule().list(),targetTags.list())'
   ```

   发现 `allow-x-ui-panel` 初始只允许旧的单一源 IP 访问 `tcp:32797`。这是一个合理嫌疑，但后续放宽后仍然失败，说明不是唯一原因。

3. 测试客户端当前出口 IP。

   ```bash
   curl -s https://ifconfig.me
   curl -s --noproxy '*' https://ifconfig.me
   ```

   两者一度显示同一个出口 IP，但这不能证明目标端口流量没有被 TUN 接管，因为 Clash fake-ip/TUN 会影响按目的地址的实际路由。

4. 服务端抓包确认流量是否到达 VM。

   服务端缺少 `tcpdump`，先安装：

   ```bash
   ssh gcp-sg 'sudo apt-get update >/dev/null && sudo apt-get install -y tcpdump >/dev/null'
   ```

   抓包：

   ```bash
   ssh gcp-sg 'sudo timeout 12 tcpdump -ni any tcp port 32797 -vv'
   ```

   在失败阶段抓到：

   ```text
   0 packets captured
   ```

   结论：客户端发起的失败连接没有进入 VM，问题位于 VM 前面的入口链路、GCP 防火墙匹配或客户端 TUN/代理路径。

5. 检查客户端到 VM 公网 IP 的路由。

   ```bash
   ip route get <redacted-vm-public-ip>
   ip addr
   ```

   关键证据：

   ```text
   <redacted-vm-public-ip> via 198.18.0.2 dev Meta table 2022 src 198.18.0.1
   ```

   结论：访问 VM 公网 IP 的流量被 Clash TUN 路由到 `Meta`，而不是直接走物理网卡。SSH 正常是因为 Clash 规则里已有 `PROCESS-NAME,ssh,DIRECT`。

6. 检查 Clash Verge Rev 当前订阅和规则增强文件。

   ```bash
   sed -n '1,260p' ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml
   sed -n '1,80p' ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml
   ```

   证据：

   ```text
   current: R0tpI5O8bG8B
   name: 赔钱机场
   option:
     rules: ryguEitH4tBd
   ```

   现有规则中包含：

   ```yaml
   - PROCESS-NAME,ssh,DIRECT
   ```

   结论：SSH 正常和浏览器失败可以同时成立，因为 SSH 被规则绕过，而浏览器访问面板域名/IP 没有绕过。

7. 添加 DIRECT 规则并重新加载 mihomo。

   修改了当前订阅的规则增强文件：

   ```text
   /home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml
   ```

   添加：

   ```yaml
   - DOMAIN,<redacted-panel-domain>,DIRECT
   - IP-CIDR,<redacted-vm-public-ip>/32,DIRECT,no-resolve
   ```

   发现仅修改增强模板后，当前运行用的生成配置没有立即重建，因此同步修改了：

   ```text
   /home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml
   ```

   并通过 mihomo API reload：

   ```bash
   curl -sS -X PUT \
     -H 'Authorization: Bearer <redacted-clash-secret>' \
     -H 'Content-Type: application/json' \
     --data '{"path":"/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml","force":true}' \
     http://127.0.0.1:9097/configs
   ```

   验证运行规则中已出现：

   ```text
   Domain <redacted-panel-domain> DIRECT
   IPCIDR <redacted-vm-public-ip>/32 DIRECT
   ```

8. 再次抓包和访问验证。

   重新访问后，服务端 `tcpdump` 能抓到客户端到 `32797` 的 TCP/TLS 流量：

   ```text
   In  <client-direct-public-ip> > 10.x.x.x.32797: Flags [S]
   Out 10.x.x.x.32797 > <client-direct-public-ip>: Flags [S.]
   ```

   客户端 `GET` 面板首页返回：

   ```bash
   curl -sk --connect-timeout 10 \
     -o /tmp/xui-page.html \
     -w '%{http_code} %{content_type} %{url_effective}\n' \
     https://<redacted-panel-domain>:32797/<redacted-webbasepath>/
   ```

   结果：

   ```text
   200 text/html; charset=utf-8
   ```

9. 收紧 GCP 防火墙。

   排障中临时把 `allow-x-ui-panel` 放宽到 `0.0.0.0/0`，确认不是服务端应用问题后，收紧到当前直连出口 IP：

   ```bash
   gcloud compute firewall-rules update allow-x-ui-panel \
     --source-ranges=<client-direct-public-ip>/32 \
     --quiet
   ```

   验证：

   ```text
   <client-direct-public-ip>/32 tcp ['32797']
   ```

10. 修复 acme.sh 续期 reload 配置。

    安装日志中证书签发成功，但第一次执行 reload 时 `x-ui.service` 尚未创建，导致：

    ```text
    Failed to restart x-ui.service: Unit x-ui.service not found.
    Reload error for: <redacted-panel-domain>
    ```

    在 x-ui 服务安装完成后，重新安装证书并设置续期 reload：

    ```bash
    ssh gcp-sg 'sudo /root/.acme.sh/acme.sh --install-cert \
      -d <redacted-panel-domain> --ecc \
      --key-file /root/cert/<redacted-panel-domain>/privkey.pem \
      --fullchain-file /root/cert/<redacted-panel-domain>/fullchain.pem \
      --reloadcmd "systemctl restart x-ui"'
    ```

    输出：

    ```text
    Running reload cmd: systemctl restart x-ui
    Reload successful
    ```

## Root Cause

根因是客户端 Clash Verge Rev TUN 模式把访问 x-ui 面板域名和 VM 公网 IP 的流量路由进了 `Meta` TUN，并交给当前机场节点处理。该代理路径对 `32797` 这类非标准 HTTPS 端口的连接在 TLS 握手阶段关闭，导致浏览器表现为 `ERR_CONNECTION_CLOSED`。

服务端 x-ui 和证书不是根因：

- `x-ui settings` 显示面板已启用 SSL。
- `systemctl status x-ui` 显示 Web server 运行在 HTTPS `32797`。
- 服务端本机能和 `127.0.0.1:32797` 完成 TLS 握手。
- 添加 DIRECT 规则后，同一个 URL 的 `GET` 返回 `200 text/html`。

GCP 防火墙是相关风险点，但不是最终根因。最初规则只允许一个旧源 IP，可能造成访问失败；但放宽后失败仍存在，并且服务端抓包在 TUN 代理路径下为 `0 packets captured`。最终证据显示客户端到目标 IP 的路由走 `dev Meta`，DIRECT 规则生效后服务端能抓到真实流量并访问成功。

## Changes Made

客户端 Clash 配置：

- 修改 `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml`
- 修改 `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml`

新增规则：

```yaml
- DOMAIN,<redacted-panel-domain>,DIRECT
- IP-CIDR,<redacted-vm-public-ip>/32,DIRECT,no-resolve
```

GCP 防火墙：

- 临时放宽 `allow-x-ui-panel` 到 `0.0.0.0/0` 用于排除防火墙问题。
- 最终收紧到 `<client-direct-public-ip>/32`，只允许当前客户端直连出口访问 `tcp:32797`。

服务端证书续期配置：

- 重新执行 acme.sh `--install-cert`
- 设置 `--reloadcmd "systemctl restart x-ui"`
- 验证 reload 成功，`x-ui.service` 重启后仍为 active。

服务端工具：

- 安装 `tcpdump` 用于抓包排障。

## Verification

确认 x-ui 服务：

```bash
ssh gcp-sg 'sudo x-ui status | sed -n "1,18p"'
```

关键结果：

```text
Active: active (running)
Web server running HTTPS on [::]:32797
```

确认 Clash 运行规则：

```bash
curl -s \
  -H 'Authorization: Bearer <redacted-clash-secret>' \
  http://127.0.0.1:9097/rules | jq '.rules[0:12]'
```

关键结果：

```text
Domain <redacted-panel-domain> DIRECT
IPCIDR <redacted-vm-public-ip>/32 DIRECT
```

确认面板 URL：

```bash
curl -sk --connect-timeout 10 \
  -o /dev/null \
  -w '%{http_code} %{content_type}\n' \
  https://<redacted-panel-domain>:32797/<redacted-webbasepath>/
```

结果：

```text
200 text/html; charset=utf-8
```

确认 GCP 防火墙：

```bash
gcloud compute firewall-rules describe allow-x-ui-panel \
  --format='value(sourceRanges,allowed[].IPProtocol,allowed[].ports[])'
```

结果：

```text
<client-direct-public-ip>/32 tcp ['32797']
```

确认 acme.sh reload：

```bash
ssh gcp-sg 'sudo /root/.acme.sh/acme.sh --list | sed -n "1,5p"'
```

证书记录显示 Let's Encrypt ECC 证书存在，并带有下次续期时间。重新安装证书时已输出：

```text
Reload successful
```

## Problems Encountered During Debugging

- `HEAD` 请求返回 `404 Not Found`，容易误判为 WebBasePath 或面板路径错误。后续 `GET` 返回 `200 text/html`，说明 `HEAD 404` 不是本次故障的根因。
- GCP 防火墙初始源 IP 限制看起来像主因，但放宽规则后 TLS EOF 仍存在。必须结合服务端抓包和客户端路由判断。
- `curl --noproxy '*'` 只能绕过环境变量里的 HTTP 代理，不能绕过 Clash TUN 的内核路由。因此即使加了 `--noproxy`，流量仍可能走 `Meta`。
- 服务端最初没有 `tcpdump`，需要安装后才能确认数据包是否进入 VM。
- 修改 Clash Verge 的规则增强模板后，运行中的 `clash-verge.yaml` 没有自动合成更新；需要确认 mihomo API `/rules` 中实际加载的规则，而不是只看模板文件。
- acme.sh 首次 reload 失败是因为证书签发时 `x-ui.service` 尚未创建。该问题不会阻止当前证书使用，但会影响后续自动续期后的服务重载。

## Reuse Notes and Lessons

- 对启用 TUN 的代理客户端，`curl --noproxy` 不等于直连。要看 `ip route get <目标 IP>` 是否走物理网卡，还是走 `Meta`/TUN 设备。
- 当 SSH 正常而浏览器访问同一主机失败时，优先检查 Clash 规则中是否已有 `PROCESS-NAME,ssh,DIRECT`，不要据此推断所有流量都能直连。
- 面板类服务建议同时做两层限制：客户端代理规则设为 DIRECT，云防火墙只允许可信源 IP。
- 排查云上端口访问时，服务端 `tcpdump` 的证据价值高于浏览器错误页。`0 packets captured` 说明问题在应用之前。
- x-ui 安装时如果先签证书、后创建 systemd unit，acme.sh 的 reload 可能失败。安装完成后应重新执行一次 `--install-cert`，写入稳定的 reload 命令。
- 如果客户端公网 IP 会变化，GCP 防火墙绑定单个 `/32` 会导致之后无法访问面板。届时需要更新 `source-ranges`，或使用 Tailscale/Cloudflare Tunnel/SSH 隧道等更稳定的访问入口。

## Appendix: Reusable Commands

### 服务端状态检查

```bash
ssh gcp-sg 'sudo ss -ltnp | grep -E ":(32797|2096|80)" || true'
ssh gcp-sg 'sudo x-ui settings'
ssh gcp-sg 'sudo systemctl status x-ui --no-pager -l | sed -n "1,35p"'
```

### 客户端路由与出口检查

```bash
dig +short <panel-domain> A
curl -s https://ifconfig.me
curl -s --noproxy '*' https://ifconfig.me
ip route get <vm-public-ip>
```

### 访问验证

```bash
curl -vkI https://<panel-domain>:32797/<webbasepath>/
curl -sk --connect-timeout 10 \
  -o /dev/null \
  -w '%{http_code} %{content_type}\n' \
  https://<panel-domain>:32797/<webbasepath>/
```

### 服务端抓包

```bash
ssh gcp-sg 'sudo apt-get update >/dev/null && sudo apt-get install -y tcpdump >/dev/null'
ssh gcp-sg 'sudo timeout 12 tcpdump -ni any tcp port 32797 -vv'
```

### Clash Verge Rev 规则检查与 reload

```bash
sed -n '1,260p' ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml
sed -n '1,120p' ~/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/<rules-enhancement>.yaml
```

```bash
curl -s \
  -H 'Authorization: Bearer <clash-secret>' \
  http://127.0.0.1:9097/rules | jq '.rules[0:20]'
```

```bash
curl -sS -X PUT \
  -H 'Authorization: Bearer <clash-secret>' \
  -H 'Content-Type: application/json' \
  --data '{"path":"/home/<user>/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml","force":true}' \
  http://127.0.0.1:9097/configs
```

### GCP 防火墙

```bash
gcloud compute firewall-rules list \
  --format='table(name,network,direction,priority,sourceRanges.list(),allowed[].map().firewall_rule().list(),targetTags.list())'
```

```bash
gcloud compute firewall-rules update allow-x-ui-panel \
  --source-ranges=<client-direct-public-ip>/32 \
  --quiet
```

```bash
gcloud compute firewall-rules describe allow-x-ui-panel \
  --format='value(sourceRanges,allowed[].IPProtocol,allowed[].ports[])'
```

### acme.sh 证书 reload 修复

```bash
ssh gcp-sg 'sudo /root/.acme.sh/acme.sh --install-cert \
  -d <panel-domain> --ecc \
  --key-file /root/cert/<panel-domain>/privkey.pem \
  --fullchain-file /root/cert/<panel-domain>/fullchain.pem \
  --reloadcmd "systemctl restart x-ui"'
```

```bash
ssh gcp-sg 'sudo /root/.acme.sh/acme.sh --list | sed -n "1,5p"'
```
