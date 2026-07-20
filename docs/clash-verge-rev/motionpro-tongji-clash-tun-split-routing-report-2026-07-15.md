生成时间: 2026-07-15T23:42:49+08:00

# Fedora 上 MotionPro 同济 VPN 与 Clash Verge Rev TUN 共存排障报告

## 1. 问题描述

主机需要同时满足两类互相冲突的网络需求：

- 使用 MotionPro 连接 `vpn.tongji.cn`，访问同济内网目标 `<TONGJI_INTERNAL_IP>`；
- 保持 Clash Verge Rev 的 TUN 模式开启，使国内外普通网站继续按 Clash 规则访问。

初始状态下，MotionPro 一旦连接便接管默认路由，Codex 和浏览器会立即失去外网。经过第一轮分流后，命令行直连内网已经成功，但 Chrome 访问 `http://<TONGJI_INTERNAL_IP>/` 仍返回空响应体的 `HTTP ERROR 502`。

本次修复最终同时解决了以下问题：

1. MotionPro 网关被 Clash Fake-IP 解析为 `198.18.0.x`；
2. MotionPro 全隧道删除物理默认路由，抢走 Clash 节点的真实出站；
3. MotionPro 自身的数据连接被再次送入 Clash TUN，形成“VPN 套 VPN”；
4. Chrome 使用显式 HTTP 代理时，mihomo 的普通 `DIRECT` 仍选错出口。

> 报告已省略学号、密码、订阅 URL、Clash 控制密钥、Cookie、临时 VPN 地址和完整内网目标 IP。复用命令时请自行设置 `<TONGJI_INTERNAL_IP>`。

## 2. 环境和范围

| 项目 | 实际环境 |
| --- | --- |
| 操作系统 | Fedora Linux 43，Hyprland/Wayland |
| 校园 VPN 客户端 | MotionPro Linux 客户端，网关 `vpn.tongji.cn:443` |
| 代理客户端 | Clash Verge Rev 2.5.1 |
| mihomo 内核 | Mihomo Meta v1.19.25，gVisor TUN |
| Clash TUN 接口 | `Meta`，地址位于 `198.18.0.0/30` |
| MotionPro 接口 | `tun0`，点对点 peer 为 `1.1.1.1` |
| Clash 显式代理 | 本机 mixed-port `127.0.0.1:7897` |
| 配置目录 | `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev` |
| 自动分流服务 | `tongji-vpn-split-route.service` |

排障范围只包括本机路由、DNS、mihomo 规则和 MotionPro/Clash 的共存方式，没有修改同济服务端配置，也没有读取或更改登录凭据。

## 3. 现象和复现

### 3.1 MotionPro 最初无法正确连接

MotionPro 日志反复显示：

```text
connecting to 198.18.0.46
ssl connect failed, error: ... Connection reset by peer
```

`198.18.0.46` 属于 Clash Fake-IP 地址池，而不是真实同济 VPN 网关。

### 3.2 MotionPro 连接后外网中断

连接后路由表被改成：

```text
default via 1.1.1.1 dev tun0
```

MotionPro 日志还明确记录服务端下发的是全隧道：

```text
network: 0.0.0.0/0.0.0.0
```

它会删除 Wi-Fi 默认路由及多个本地网段路由，再把全部 IPv4 流量送入 `tun0`。这会连带影响 mihomo 节点和 Codex 的真实网络连接。

### 3.3 初步拆分后内网仍超时

只添加目标主机路由后，抓包可见 TCP SYN 已从 `tun0` 发出，但没有返回：

```text
<VPN_ASSIGNED_IP>.<ephemeral> > <TONGJI_INTERNAL_IP>.443: Flags [S]
```

恢复 MotionPro 原始全隧道路由做对照，结果仍然超时，说明问题不只是目标路由写法。

### 3.4 命令行成功但 Chrome 返回 502

同一个 HTTP 请求出现两种结果：

```text
# 不使用显式代理，直接走内核路由
HTTP/1.1 200 OK

# 使用 http://127.0.0.1:7897
HTTP/1.1 502 Bad Gateway
Content-Length: 0
```

Chrome 继承了本机代理环境，访问内网 IP 时会先进入 mihomo mixed-port，因此仅修正 Linux 路由还不够。

## 4. 调查时间线

1. 检查进程、接口、主路由表、策略路由和 systemd-resolved，确认 Clash 的 `Meta` 已运行，MotionPro 初始未连接。
2. 从 MotionPro 日志发现客户端实际连接 `198.18.0.46`，确认 `vpn.tongji.cn` 被 Fake-IP 污染。
3. 将 `vpn.tongji.cn` 同时加入 `fake-ip-filter` 和 `DIRECT` 规则；重新加载后解析结果变为真实网关地址。
4. 重启残留的 `vpnd`，清除其缓存的 Fake-IP；MotionPro 随后能够建立 `tun0`。
5. 捕获 MotionPro 连接后的路由变化，确认它删除物理默认路由并添加 `default via 1.1.1.1 dev tun0`。
6. 在 mihomo TUN 中排除 `<TONGJI_INTERNAL_IP>/32`，并编写自动分流服务：只把内网目标交给 `tun0`，普通默认路由恢复到 Wi-Fi。
7. 验证 Google 已恢复，但内网目标仍没有返回；抓包确认请求确实进入 `tun0`。
8. 检查 `ss -ntup`，发现 `vpnd` 的长连接源地址仍是 `198.18.0.1`，而物理连接实际由 `verge-mihomo` 代发。MotionPro 数据面仍嵌套在 Clash TUN 中。
9. 将同济 VPN 网关段 `202.120.189.0/24` 加入 `inet4-route-exclude-address`。修复后 `vpnd` 直接从物理 Wi-Fi 地址连接真实网关，内网 HTTP/HTTPS 均返回 `200`。
10. 用户在 Chrome 中继续看到 502。对比直连与 mixed-port 请求后，确认 Chrome 显式代理路径中的普通 `DIRECT` 仍绑定物理出口。
11. 依据当前 mihomo 配置语法新增 `type: direct`、`interface-name: tun0` 的 `Tongji-VPN` 节点，并将内网 IP 规则指向该节点。
12. Chrome 刷新后成功访问；mihomo 连接链显示 `Tongji-VPN`，最终完成双路径回归。

## 5. 根因

这不是单一的“两张 TUN 网卡冲突”，而是四层叠加问题。

### 5.1 DNS/Fake-IP 层

MotionPro 需要直接建立 TLS VPN，但 `vpn.tongji.cn` 最初被 Clash DNS 返回为 `198.18.0.x`。MotionPro 将 Fake-IP 当成真实网关，TLS 因此被重置。

仅添加规则级 `DIRECT` 不够：在 DNS 已返回 Fake-IP 的情况下，客户端仍然没有真实目标。必须同时设置 `fake-ip-filter` 和规则级直连。

### 5.2 Linux 默认路由层

同济 VPN 策略是 `0.0.0.0/0` 全隧道。MotionPro 会主动删除现有默认路由并添加 `tun0` 默认路由，因此 Clash 节点、Codex 及普通直连流量都会被送入校 VPN。

需要持续把物理默认路由恢复，同时为目标内网 IP 创建更精确的 `/32` 路由。由于 MotionPro 有路由监控线程，一次性执行 `ip route` 不够可靠，必须使用常驻服务快速纠正。

### 5.3 MotionPro 数据面嵌套层

即使内网 IP 已排除，MotionPro 到真实 VPN 网关的连接仍可能被 Clash TUN 捕获。决定性证据是：

```text
vpnd          198.18.0.1:<port> -> 202.120.189.x:443
verge-mihomo  <LAN_IP>:<port>   -> 202.120.189.x:443
```

这表示 MotionPro 自身先进入 `Meta`，再由 mihomo 发往网关。VPN 表面显示 `connected`，但内网数据面没有正常返回。

将 `202.120.189.0/24` 从 TUN 自动路由排除后，连接变为：

```text
vpnd  <LAN_IP>:<port> -> 202.120.189.x:443
```

此时 MotionPro 真正直接运行在物理网络上，内网请求开始返回。

### 5.4 Chrome 显式 HTTP 代理层

TUN 路由排除只作用于直接进入 Linux 网络栈的连接。Chrome 使用 `127.0.0.1:7897` 时，请求首先进入 mihomo 应用层代理；普通 `DIRECT` 会按 mihomo 的默认物理接口选择发送，无法使用 MotionPro 的 `tun0`，于是 mixed-port 返回 `502 Bad Gateway`。

最终必须为 Chrome 路径增加专用出站：

```yaml
- name: Tongji-VPN
  type: direct
  udp: true
  interface-name: tun0
```

并使用：

```yaml
- IP-CIDR,<TONGJI_INTERNAL_IP>/32,Tongji-VPN,no-resolve
```

## 6. 已实施的变更

### 6.1 Clash Verge Rev 持久化增强配置

修改了以下文件：

- `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/md3vwVh0HaoX.yaml`
  - Fake-IP 排除 `vpn.tongji.cn`；
  - TUN 路由排除同济内网目标和 `202.120.189.0/24`。
- `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/ryguEitH4tBd.yaml`
  - VPN 网关域名和网关段直连；
  - 内网目标交给 `Tongji-VPN`。
- `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/pGkmF9isacfk.yaml`
  - 新增绑定 `tun0` 的命名直连节点 `Tongji-VPN`。
- `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/Merge.yaml`
  - 同步通用 Fake-IP/TUN 排除项。
- `/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml`
  - 当前运行时配置同步了上述项目。

### 6.2 自动分流服务

源码保存在：

```text
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/scripts/tongji-vpn-split-route.sh
/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/systemd/tongji-vpn-split-route.service
```

系统安装位置：

```text
/usr/local/libexec/tongji-vpn-split-route
/etc/systemd/system/tongji-vpn-split-route.service
```

服务会记住非 `tun0`/`Meta` 的物理上行网关，以约 50ms 周期检查路由。在 `tun0` 存在时，它会：

1. 从 `tun0` 的 peer 动态取得下一跳；
2. 将 `<TONGJI_INTERNAL_IP>/32` 指向该 peer；
3. 删除 MotionPro 添加的全局 `tun0` 默认路由；
4. 恢复物理默认网关，使用独立 metric `4242`；
5. 在 VPN 断开后清理自己的临时默认路由。

服务已设置开机自启：

```text
enabled
active
```

## 7. 验证

### 7.1 路由验证

连接 MotionPro 后：

```text
<TONGJI_INTERNAL_IP> via 1.1.1.1 dev tun0
8.8.8.8 via 198.18.0.2 dev Meta table 2022
default via <LAN_GATEWAY> dev <WIFI_INTERFACE> metric 4242
```

这证明三类流量被分开：同济内网走 MotionPro、普通客户端流量进入 Clash、Clash 和 MotionPro 的真实网关从物理网发出。

### 7.2 VPN 传输验证

修复前：

```text
vpnd source = 198.18.0.1
```

修复后：

```text
vpnd source = <LAN_IP>
```

后者证明 MotionPro 不再嵌套于 Clash TUN。

### 7.3 HTTP/HTTPS 验证

最终回归结果：

| 验证路径 | 结果 |
| --- | --- |
| 内网 HTTP，直连内核路由 | `HTTP 200` |
| 内网 HTTPS，直连内核路由 | `HTTP 200` |
| 内网 HTTP，经 `127.0.0.1:7897`，等价 Chrome 路径 | `HTTP 200` |
| mihomo 实际连接链 | `Tongji-VPN` |
| Google `generate_204` | `HTTP 204` |
| 百度 HTTPS | `HTTP 200` |
| MotionPro 状态 | `VPN Status: connected` |
| 自动分流服务 | `enabled`、`active` |

Chrome 在不修改浏览器代理配置、不关闭 Clash TUN 的情况下成功加载同济内网页面。

## 8. 调试过程中遇到的问题

### 8.1 只修 Fake-IP 不足以实现双 VPN 共存

修复域名解析后 MotionPro 可以连接，但它仍会抢占默认路由。DNS 修复只是第一层，不等于完整分流。

### 8.2 只给内网目标添加路由仍没有返回

最初认为目标 `/32` 指向 `tun0` 即可。抓包却只有 SYN、没有响应；因为 MotionPro 自身的数据连接仍被 Clash TUN 接管。必须同时排除 VPN 网关段。

### 8.3 恢复 MotionPro 原始全隧道仍超时

曾临时恢复 `default via 1.1.1.1 dev tun0` 做受控对照，内网仍然超时。这个失败排除了“自动分流脚本写错目标路由”这一假设，并把调查方向转向 VPN 外层连接。

### 8.4 `dev tun0` 与点对点 peer

早期目标路由仅写为 `dev tun0`。虽然包能发出，最终脚本仍改为读取 `peer 1.1.1.1` 并显式使用 `via <peer> dev tun0`，更符合 MotionPro 创建的点对点路由语义。

### 8.5 mihomo REST 热加载保留了 TUN 开关状态

使用 `/configs` 热加载后，API 一度显示：

```json
{"tun":{"enable":false}}
```

尝试用错误的 PATCH body 打开 TUN 又得到：

```text
HTTP/1.1 400 Bad Request
{"message":"Body invalid"}
```

最终通过重启 Clash Verge 前端和 `clash-verge-service`，让应用按持久设置重新生成运行时配置。

### 8.6 核心重启存在新旧进程竞态

重启后第一次探测可能命中即将退出的旧 API，随即出现 `127.0.0.1:7897 connection refused` 或 TUN 尚未创建。可靠验证条件应同时包括：

- `127.0.0.1:9097` API 可访问；
- `127.0.0.1:7897` 已监听；
- `.tun.enable == true`；
- `Meta` 接口存在。

### 8.7 `vpn_cmdline --stop` 会影响 MotionPro GUI 生命周期

停止旧重连时，MotionPro 日志显示 GUI 以命令行模式退出。重新启动时还需要给旧版 Qt 指定：

```text
QT_QPA_PLATFORM=xcb
```

否则会出现找不到 `wayland;xcb` 平台插件的错误。后续需要用户点击连接/断开时，统一先用 `notify-send` 提醒，避免交互状态不一致。

### 8.8 Chrome 的 502 不是目标服务器返回

直连 HTTP 返回完整 HTML 和 `200`，而 mixed-port 返回空 body 的 `502`。如果只看 Chrome 页面，很容易误判为同济 nginx 故障。必须分别测试直连路径和显式代理路径。

## 9. 复用说明和经验

1. **双 VPN 问题要拆成控制面、数据面和应用代理层。** “显示 connected”只证明控制面完成，不代表内网数据面可用。
2. **Fake-IP 排除和规则级直连需要成对配置。** 前者保证域名得到真实 IP，后者决定代理策略。
3. **VPN 客户端本身的网关必须绕过 Clash TUN。** 否则会出现 VPN 套 VPN，最直接的判断方法是检查 `vpnd` socket 的本地源地址是否属于 `198.18.0.0/16`。
4. **全隧道 VPN 的路由监控会反复改表。** 需要常驻、幂等的路由修正器，而不是只执行一次 `ip route`。
5. **命令行直连成功不代表 Chrome 成功。** 浏览器可能走显式 HTTP/SOCKS 代理；应使用 `curl --proxy` 复现浏览器路径。
6. **需要把应用层代理流量送入另一个 TUN 时，使用命名 direct 节点加 `interface-name`。** 普通 `DIRECT` 只表示“不走远程代理”，并不保证使用目标 VPN 接口。
7. **验证必须覆盖断开、连接和重启。** 至少检查 MotionPro 状态、路由决策、mihomo 连接链、内网 HTTP、国外 HTTPS 和 systemd 服务状态。
8. **切换 Clash 订阅时要同步增强配置。** 本次专用节点和规则位于当前订阅的 proxies/rules enhancement 文件；换用另一订阅后，应将等价增强项迁移过去。

## 10. 附录：可复用命令

以下命令中的 `<TONGJI_INTERNAL_IP>` 应替换为实际目标；不要把账号、密码、Cookie 或 Clash 控制密钥写入报告或终端历史。

### 10.1 查看进程、接口和路由

```bash
rtk proxy pgrep -a -f 'MotionPro|vpnd|clash-verge|verge-mihomo'
rtk proxy ip -brief address
rtk proxy ip route show table all
rtk proxy ip rule show
rtk proxy ip route get <TONGJI_INTERNAL_IP>
rtk proxy ip route get 8.8.8.8
```

### 10.2 检查 MotionPro 状态和真实连接

```bash
rtk proxy /opt/MotionPro/vpn_cmdline --status
rtk proxy sudo ss -ntup | rg 'vpnd|202\.120\.189\.'
rtk proxy strings /var/log/MotionPro/MotionPro_$(date +%F).log \
  | rg -i 'network:|route config|AddRT|dns server|connecting to'
```

若 `vpnd` 的本地地址是 `198.18.0.x`，说明 MotionPro 仍被 Clash TUN 捕获。

### 10.3 分别测试直连和 Chrome 等价路径

```bash
# 绕过显式代理，直接验证内核路由
rtk proxy env -u http_proxy -u https_proxy -u all_proxy \
  -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY \
  curl --noproxy '*' -I --connect-timeout 8 "http://<TONGJI_INTERNAL_IP>/"

# 明确经过 Clash mixed-port，复现 Chrome 路径
rtk proxy curl --proxy http://127.0.0.1:7897 --noproxy '' \
  -I --connect-timeout 8 "http://<TONGJI_INTERNAL_IP>/"
```

### 10.4 查看 mihomo 是否命中专用出站

```bash
rtk proxy curl -sS -H 'Authorization: Bearer <REDACTED>' \
  http://127.0.0.1:9097/connections \
  | jq -r '.connections[]
      | select(.metadata.destinationIP == "<TONGJI_INTERNAL_IP>")
      | [.metadata.destinationPort, .metadata.process, .chains[0]]
      | @tsv'
```

预期链首为：

```text
Tongji-VPN
```

### 10.5 验证自动分流服务

```bash
rtk proxy systemctl status tongji-vpn-split-route.service --no-pager
rtk proxy systemctl is-enabled tongji-vpn-split-route.service
rtk proxy journalctl -u tongji-vpn-split-route.service --since '10 minutes ago' --no-pager
```

### 10.6 验证 mihomo 配置并安全重启

```bash
CLASH_DIR="$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev"

rtk proxy /usr/bin/verge-mihomo -t -d "$CLASH_DIR" \
  -f "$CLASH_DIR/clash-verge.yaml"

# 重启后不要只判断进程存在，还应等待 7897、9097、Meta 和 tun.enable 全部就绪。
rtk proxy ss -lnt | rg ':7897 |:9097 '
rtk proxy ip link show Meta
```

### 10.7 需要用户操作 MotionPro 时发送通知

```bash
rtk proxy notify-send -a Codex -u critical \
  '请操作同济 VPN' \
  '请在 MotionPro 中点击连接或断开，完成后继续验证。'
```
