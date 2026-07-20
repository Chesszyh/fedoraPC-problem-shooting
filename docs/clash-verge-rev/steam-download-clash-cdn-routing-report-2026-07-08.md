# Steam 下载速度偏低与 Clash Verge Rev 规则/CDN 调度排障报告

生成时间: 2026-07-08T23:42:22+08:00

## 1. Problem Description

Fedora 上 Steam 下载《ATRI -My Dear Moments-》时速度长期只有约 `5 MB/s`，明显低于历史上可达到的 `30-40 MB/s`。用户同时观察到 Clash Verge Rev TUN 模式下：

- 规则模式时下载速度甚至可能低于 `1 MB/s`。
- 全局模式时约 `3-5 MB/s`。
- 后续切换 Steam 下载地区到 `China - Shanghai` 后仍只有约 `6 MB/s`。

本次排障目标是确认瓶颈来自 Steam CDN、Clash Verge Rev 规则、TUN/fake-ip、系统网络链路、磁盘写入，还是 Steam 自身解包/校验阶段，并尽量恢复更合理的直连下载链路。

## 2. Environment and Scope

- 主机：Lenovo Legion Y9000P IRX8
- 系统：Fedora Linux 43 Workstation
- 内核：`Linux 7.1.3-100.fc43.x86_64`
- 网络：Wi-Fi `wlp0s20f3`，SSID `CMCC-mzP2-5G`
- 代理客户端：Clash Verge Rev + `verge-mihomo`
- Clash mixed-port：`127.0.0.1:7897`
- Clash TUN 接口：`Meta`
- Steam 路径：`/home/chesszyh/.local/share/Steam`
- Steam 目标应用：`AppID 1230140`，即 `ATRI -My Dear Moments-`

本报告只覆盖本机 Steam 下载链路和 Clash Verge Rev 规则排障，不评估运营商侧限速、路由器 QoS、Steam 全球 CDN 当时整体健康状态。

## 3. Symptoms and Reproduction

可复现现象：

1. Steam 下载速度在 UI 中显示约 `5 MB/s` 到 `6 MB/s`。
2. Steam `content_log.txt` 中对应速率为几十 Mbps，例如：

```text
Current download rate: 31.681 Mbps
Current download rate: 35.239 Mbps
```

3. 换算后约为 `4-5 MB/s`，和 UI 观察基本一致。
4. Clash 规则修复前，Steam 的下载源和目录服务曾出现以下现象：

```text
cache10-sgp1.steamcontent.com
cache7-sgp1.steamcontent.com
cmp2-sgp1.steamserver.net
```

5. 规则修复后，Steam 连接切换为直连，且目录服务和下载 CDN 发生变化：

```text
cmp1-hkg1.steamserver.net -> DIRECT
dl.steam.clngaa.com -> DIRECT
st.dl.eccdnx.com -> DIRECT
xz.pphimalayanrt.com -> DIRECT
```

## 4. Investigation Timeline

### 4.1 初始 Steam 配置检查

检查 Steam 配置和日志：

```bash
rg -n "CellIDServerOverride|CurrentCellID|Rate|RecentDownloadRate" config/config.vdf
tail -n 220 logs/content_log.txt
```

发现：

- 初始 `CellIDServerOverride` 为 `35`。
- Steam 配置中存在 `Rate = 30000`，约等于 `30 MB/s` 下载上限。
- 这个限速不是当时 `5 MB/s` 的直接原因，但会阻止后续恢复到超过 `30 MB/s` 的速度。

### 4.2 Clash/TUN 与代理环境检查

检查路由、TUN、进程和连接：

```bash
ip -br addr
ip route
ip rule
ss -tpn state established
ps -eo pid,ppid,comm,args | rg -i 'steam|clash|verge|mihomo|tun'
```

发现：

- 系统存在 Clash TUN 接口 `Meta`。
- DNS 和 fake-ip 使用 `198.18.0.0/16`。
- Steam 进程存在大量连接到 `127.0.0.1:7897`。

进一步检查 Steam 进程环境：

```bash
tr '\0' '\n' < /proc/<steam-pid>/environ | rg -i 'proxy|no_proxy'
```

发现 Steam 继承了 shell 代理环境：

```text
http_proxy=http://127.0.0.1:7897
https_proxy=http://127.0.0.1:7897
all_proxy=http://127.0.0.1:7897
```

代理变量来源为：

```text
/home/chesszyh/.zshenv
```

这解释了为什么 Steam 即使在 TUN 模式之外，也可能主动走 mixed-port。

### 4.3 规则模式下的实际命中检查

通过 Mihomo Unix socket 查询运行时连接：

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/connections | jq ...
```

早期观察到：

```text
cache7-sgp1.steamcontent.com -> GLOBAL -> 新加坡 hy2 节点
cache10-sgp1.steamcontent.com -> GLOBAL -> 新加坡 hy2 节点
api.steampowered.com -> GLOBAL -> 新加坡 hy2 节点
cmp2-sgp1.steamserver.net -> GLOBAL -> 新加坡 hy2 节点
```

随后切到规则模式后，下载本体 `steamcontent.com` 已经能命中 `DIRECT`，但 `steamserver.net`、`steampowered.com`、`steamstatic.com` 仍会被订阅规则命中到代理策略组。

这说明问题不是单一的“是否开代理”，而是 Steam 下载链路中不同域名被拆分到了不同路径：

- 下载本体可能直连。
- 目录服务、商店/API、静态资源仍可能走代理。
- Steam CDN 源列表可能因此受代理出口和 DNS/fake-ip 影响。

### 4.4 下载地区切换到 China - Shanghai

用户将 Steam 下载地区切到 `China - Shanghai` 后，检查配置：

```bash
rg -n "CellIDServerOverride|CurrentCellID|Rate|RecentDownloadRate" config/config.vdf
```

结果：

```text
CellIDServerOverride = 47
CurrentCellID = 47
RecentDownloadRate = 6279238
```

这说明地区设置确实生效，约 `6.0 MB/s` 的观察也被 Steam 配置记录确认。

但 Steam 日志显示，`CellID 47` 并不一定返回上海或国内最优源：

```text
Got 11 download sources ... (CellID 47 / Launcher 0)
Created download interface ... cache8-tyo3.steamcontent.com
```

即使选择上海，Steam 一度仍调度到东京 `tyo3` CDN。

### 4.5 磁盘与 CPU 检查

使用：

```bash
iostat -dx 1 5
pidstat -p <steam-pid> -d -u 1 5
```

发现：

- NVMe/Btrfs 没有被打满，`%util` 低。
- Steam 进程可能接近吃满一个 CPU 核。
- 写入速度在 `5-8 MB/s` 左右波动。

结论：磁盘不是主瓶颈；Steam 解包/校验会影响瞬时速度，但无法解释规则修复前代理链路差异。

### 4.6 规则修复与热重载

修改 Clash Verge Rev 当前订阅使用的规则增强文件：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml
```

同时修改当前生成配置：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml
```

在规则最前面加入 Steam 相关域名直连规则，并通过 Mihomo API 热重载：

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -H 'Content-Type: application/json' \
  -X PUT \
  -d '{"path":"/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml","force":true}' \
  http://localhost/configs
```

热重载返回：

```text
HTTP 204
```

### 4.7 Steam 重启后的最终链路

用户通过 rofi 重启 Steam 后，速度提升到约 `10 MB/s`。

再次检查运行时连接，确认：

```text
cmp1-hkg1.steamserver.net     DomainSuffix steamserver.net     DIRECT
store.steampowered.com        DomainSuffix steampowered.com    DIRECT
api.steampowered.com          DomainSuffix steampowered.com    DIRECT
shared.steamstatic.com        DomainSuffix steamstatic.com     DIRECT
community.steamstatic.com     DomainSuffix steamstatic.com     DIRECT
```

下载 CDN 切到国内/中国区常见源：

```text
st.dl.eccdnx.com
dl.steam.clngaa.com
xz.pphimalayanrt.com
```

并出现跳转到国内移动网段的实际下载地址，例如：

```text
36.137.18.59
39.135.x.x
39.137.x.x
112.29.252.215
223.76.x.x
```

Steam 日志中后续更新任务速率：

```text
Current download rate: 57.539 Mbps
```

约等于 `7.2 MB/s`，UI 瞬时显示约 `10 MB/s`。

## 5. Root Cause

根因不是单一因素，而是多层叠加：

1. Steam 进程从 `/home/chesszyh/.zshenv` 继承了 `http_proxy`、`https_proxy`、`all_proxy`，导致 Steam 主动使用 `127.0.0.1:7897`。
2. Clash Verge Rev 规则中，`steamcontent.com` 已经有直连规则，但 `steamserver.net`、`steampowered.com`、`steamstatic.com`、`steamcommunity.com` 等域名仍会被后续规则命中到代理策略组。
3. Steam 下载链路依赖多类域名：目录服务、商店/API、静态资源、内容 CDN。部分走代理、部分直连会使 CDN 调度不稳定。
4. Steam 下载地区切换到 `China - Shanghai` 后，只是设置了 `CellID 47`，并不保证最终一定使用上海 CDN；排障中曾返回东京 `cache8-tyo3` 源。
5. 修复规则后，目录服务与内容下载均直连，Steam 调度切换到 `hkg1` 目录服务和国内 CDN，速度从约 `5-6 MB/s` 提升到约 `7-10 MB/s`。

剩余未恢复到历史 `30-40 MB/s` 的原因更可能是当前 Steam CDN/运营商路径、下载任务大小、并发连接、解包/校验阶段或 Steam 当时 CDN 负载，而不是 Clash 代理绕路。

## 6. Changes Made

### 6.1 持久规则增强

文件：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml
```

新增在 `prepend:` 最前面的规则：

```yaml
- DOMAIN-SUFFIX,steamcontent.com,DIRECT
- DOMAIN-SUFFIX,steamserver.net,DIRECT
- DOMAIN-SUFFIX,steampowered.com,DIRECT
- DOMAIN-SUFFIX,steamstatic.com,DIRECT
- DOMAIN-SUFFIX,steamcommunity.com,DIRECT
- DOMAIN-SUFFIX,steamusercontent.com,DIRECT
- DOMAIN-SUFFIX,steamgames.com,DIRECT
- DOMAIN-SUFFIX,valvesoftware.com,DIRECT
- DOMAIN,steampipe.akamaized.net,DIRECT
- DOMAIN,steamcommunity-a.akamaihd.net,DIRECT
- DOMAIN,steamstore-a.akamaihd.net,DIRECT
- DOMAIN,steamusercontent-a.akamaihd.net,DIRECT
- DOMAIN,steamuserimages-a.akamaihd.net,DIRECT
```

### 6.2 当前生成配置同步

文件：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml
```

同样在 `rules:` 最前面加入上述 Steam 直连规则，避免等待 Clash Verge Rev 再次生成配置。

### 6.3 备份文件

修改前创建了备份：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml.bak-steam-direct-20260708
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml.bak-steam-direct-20260708
```

### 6.4 运行时热重载

通过 Mihomo API 加载当前配置文件，返回 `HTTP 204`，说明热重载成功。

## 7. Verification

### 7.1 YAML 语法验证

```bash
python3 - <<'PY'
import yaml
for p in [
    '/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml',
    '/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml',
]:
    with open(p, 'r', encoding='utf-8') as f:
        yaml.safe_load(f)
    print('ok', p)
PY
```

结果：

```text
ok .../profiles/ryguEitH4tBd.yaml
ok .../clash-verge.yaml
```

### 7.2 运行时规则顺序验证

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/rules | jq -r '.rules[0:20][] | [.type,.payload,.proxy] | @tsv'
```

确认前几条为：

```text
DomainSuffix  steamcontent.com       DIRECT
DomainSuffix  steamserver.net        DIRECT
DomainSuffix  steampowered.com       DIRECT
DomainSuffix  steamstatic.com        DIRECT
DomainSuffix  steamcommunity.com     DIRECT
```

### 7.3 Steam 重启后连接验证

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/connections | jq ...
```

确认：

```text
cmp1-hkg1.steamserver.net -> DIRECT
store.steampowered.com -> DIRECT
api.steampowered.com -> DIRECT
shared.steamstatic.com -> DIRECT
dl.steam.clngaa.com -> DIRECT
```

### 7.4 Steam 日志验证

```bash
tail -n 120 /home/chesszyh/.local/share/Steam/logs/content_log.txt
```

关键结果：

```text
Got 3 download sources ... (CellID 47 / Launcher 0)
Created download interface ... st.dl.eccdnx.com
Created download interface ... dl.steam.clngaa.com
Created download interface ... xz.pphimalayanrt.com
Current download rate: 57.539 Mbps
```

### 7.5 用户可见结果

Steam 重启后，下载速度从约 `5-6 MB/s` 提升到约 `10 MB/s`。虽然没有恢复到历史 `30-40 MB/s`，但代理绕路和目录服务走代理的问题已被修正。

## 8. Problems Encountered During Debugging

1. `127.0.0.1:7897` 不能直接等同于“最终走代理”。在 Clash TUN/mixed-port/fake-ip 场景下，连接进入本地端口后仍可能根据规则 `DIRECT` 出站。
2. 已建立连接不会因为规则热重载自动迁移。必须完全重启 Steam，旧连接才会重新按新规则建立。
3. Steam 下载地区不是严格地理绑定。`China - Shanghai` 对应 `CellID 47`，但曾返回东京 `cache8-tyo3` 源。
4. Steam 下载 UI 的 MB/s 和日志中的 Mbps 需要换算。`57.539 Mbps` 约等于 `7.2 MB/s`。
5. 下载任务末尾可能进入校验、提交、切 depot、暂停队列等阶段，速度会瞬时下降，不应只用某一秒作为结论。
6. 系统代理和 shell 环境代理是两回事。GNOME system proxy 可能为 `none`，但 Steam 仍可能继承 `.zshenv` 中的 `http_proxy` 等变量。
7. Clash Verge Rev 的当前生成配置可能会被订阅更新或配置重生成覆盖，因此必须改持久的 profile enhancement rules，而不只改 `clash-verge.yaml`。

## 9. Reuse Notes and Lessons

- 遇到 Steam 下载慢时，先区分“内容 CDN 慢”和“目录服务/调度路径被代理影响”。
- 对 Steam，至少应把以下域名放在 Clash 规则最前面直连：

```yaml
- DOMAIN-SUFFIX,steamcontent.com,DIRECT
- DOMAIN-SUFFIX,steamserver.net,DIRECT
- DOMAIN-SUFFIX,steampowered.com,DIRECT
- DOMAIN-SUFFIX,steamstatic.com,DIRECT
- DOMAIN-SUFFIX,steamcommunity.com,DIRECT
- DOMAIN-SUFFIX,steamusercontent.com,DIRECT
```

- 若 Steam 从 shell 启动，检查 `.zshenv`、`.profile`、systemd user environment 是否注入代理变量。
- 规则调整后应重启 Steam，而不是只观察热重载后的旧连接。
- `CellIDServerOverride` 可以证明 Steam 下载地区是否被写入，但不能证明最终 CDN 一定在该城市。
- 判断速度瓶颈时同时看：
  - Steam `content_log.txt`
  - Clash `/connections`
  - `ss -tpn`
  - `pidstat`
  - `iostat`
  - Wi-Fi 链路状态

## 10. Appendix: Reusable Commands

### Steam 配置与日志

```bash
cd /home/chesszyh/.local/share/Steam
rg -n "CellIDServerOverride|CurrentCellID|TimeCellIDSet|Rate|RecentDownloadRate" config/config.vdf
tail -n 160 logs/content_log.txt
```

### 查看 Steam 进程和环境代理

```bash
pgrep -a steam
tr '\0' '\n' < /proc/<steam-pid>/environ | rg -i 'proxy|no_proxy'
```

### 查看 Clash 运行时模式

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/configs | jq '{mode: .mode, mixedPort: .["mixed-port"], tun: .tun.enable}'
```

### 查看 Steam 相关连接命中

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/connections |
  jq -r '.connections[]
    | select((.metadata.host // "") | test("steam|steamcontent|steamserver|steampowered|steamstatic"; "i"))
    | [.metadata.host,.metadata.destinationIP,.metadata.destinationPort,.rule,.rulePayload,(.chains|join(" -> ")),(.download|tostring)]
    | @tsv'
```

### 查看运行时规则顺序

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -sS http://localhost/rules |
  jq -r '.rules[0:30][] | [.type,.payload,.proxy] | @tsv'
```

### 热重载 Mihomo 配置

```bash
curl --unix-socket /tmp/verge/verge-mihomo.sock \
  -H 'Authorization: Bearer <redacted>' \
  -H 'Content-Type: application/json' \
  -X PUT \
  -d '{"path":"/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml","force":true}' \
  http://localhost/configs
```

### 磁盘与 CPU 辅助判断

```bash
iostat -dx 1 5
pidstat -p <steam-pid> -d -u 1 5
```

### 网络链路状态

```bash
iw dev wlp0s20f3 link
ip -br addr
ip route
ip rule
```
