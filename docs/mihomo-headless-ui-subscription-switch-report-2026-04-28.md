生成时间: 2026-04-28T18:19:23+00:00

# Mihomo Headless 部署、UI 后端连接与多订阅切换排障报告

## Problem Description

本次排障的目标不是单一报错修复，而是把一台 Ubuntu Server 上的 Mihomo headless 代理系统从“能跑”推进到“可维护、可切换、可复用”的状态，覆盖以下问题：

1. 用 Mihomo 复刻类似 Clash Verge Rev 的无头代理能力。
2. 解决 MetaCubeXD 面板打开后提示“无法连接后端，请检查地址是否正确以及后端是否正在运行”。
3. 处理 SSH 本地转发端口写反与本地端口冲突问题。
4. 去掉对另一台机器 `192.168.1.5:7897` 的临时下载代理依赖，改为使用本机 `127.0.0.1:7890`。
5. 支持多条订阅源登记，并允许手动切换当前使用的订阅来源。

本报告记录的是完整证据链，包括错误假设、临时方案、根因、改动位置和后续复用方法。

## Environment and Scope

- 目标机器：Ubuntu Server 25.10，`x86_64`，`systemd`
- 代理内核：`mihomo v1.19.23`
- 面板：MetaCubeXD，通过 `external-ui` 由 Mihomo 自身提供
- 当前监听：
  - `127.0.0.1:7890`：mixed proxy
  - `127.0.0.1:9090`：RESTful API / UI
- 当前运行模式：`mode: rule`
- 当前 TUN 状态：未启用，`/etc/mihomo/config.yaml` 中 `tun` 为 `None`
- 当前已登记订阅源：4 条
- 当前选中并已应用订阅源：`1 / dash`

涉及的主要本地文件：

- `/etc/mihomo/config.yaml`
- `/etc/mihomo/deploy.env`
- `/etc/mihomo/ui/config.js`
- `/etc/systemd/system/mihomo.service`
- `/etc/systemd/system/mihomo-config-sync.service`
- `/etc/systemd/system/mihomo-config-sync.timer`
- `/usr/local/bin/mihomo-sync-config`
- `/usr/local/bin/mihomo-subscription`
- `/home/chesszyh/mihomo-deploy/.env`
- `/home/chesszyh/mihomo-deploy/.env.example`
- `/home/chesszyh/mihomo-deploy/scripts/sync-subscription-config.py`
- `/home/chesszyh/mihomo-deploy/scripts/mihomo-subscription`
- `/home/chesszyh/mihomo-deploy/scripts/install-host.sh`
- `/home/chesszyh/mihomo-deploy/templates/mihomo.service`

报告中已对订阅 token、敏感路径片段和不适合公开的订阅凭据做脱敏处理。

## Symptoms and Reproduction

### 1. 面板可打开，但提示无法连接后端

现象：

```text
无法连接后端，请检查地址是否正确以及后端是否正在运行。
```

已知事实：

- `http://127.0.0.1:9090/ui/` 返回 `200`
- `http://127.0.0.1:9090/version` 在带 `Authorization: Bearer <redacted>` 时返回 Mihomo 版本
- UI 内的 `config.js` 最初为：

```javascript
window.__METACUBEXD_CONFIG__ = {
  defaultBackendURL: '',
}
```

### 2. SSH 转发失败，误以为是远端 API 异常

复现命令：

```bash
ssh -L 9090:127.0.0.1:9091 chesszyh@192.168.1.13
```

典型报错：

```text
mux_client_forward: forwarding request failed: Port forwarding failed
bind [127.0.0.1]:9090: Address already in use
Could not request local forwarding.
```

### 3. 部署初期依赖另一台机器的 Clash Verge Rev 代理

在 `/etc/mihomo/deploy.env` 中曾存在：

```text
HTTP_PROXY=http://192.168.1.5:7897
HTTPS_PROXY=http://192.168.1.5:7897
ALL_PROXY=http://192.168.1.5:7897
```

这意味着订阅同步、GitHub 下载和 geodata 下载都临时依赖另一台机器。

### 4. 订阅逻辑最初不支持手动选择来源

初始同步脚本行为是：

- 按顺序读取 `MIHOMO_SUBSCRIPTION_URL_N`
- 自动选择第一个可用返回
- 不记录“当前选中的订阅源”
- 不提供手动切换入口

### 5. 对第二条订阅的直觉判断不准确

第二条订阅源在这台机器上即便通过本地或上游代理请求，也持续返回：

```text
403 text/html; charset=UTF-8
```

因此不能把“多个订阅都导入”简单理解成“多个订阅都已经过可用性验证”。

## Investigation Timeline

### 2026-04-18：确认 headless 方案并完成第一版宿主机部署

1. 确认 `mihomo + metacubexd + systemd` 是最接近 Clash Verge Rev 的 headless 方案。
2. 发现当前主机已有 `nginx`、数据库和现有业务，直接启用 TUN 有较高风险，因此先采用 `proxy-only` 思路。
3. 编写部署材料：
   - `/home/chesszyh/mihomo-deploy/README.md`
   - `/home/chesszyh/mihomo-deploy/.env`
   - `/home/chesszyh/mihomo-deploy/scripts/install-host.sh`
   - `/home/chesszyh/mihomo-deploy/templates/mihomo.service`
4. 初版曾尝试把订阅作为 `proxy-providers` 处理，后续发现这是错误方向。

### 2026-04-18：发现订阅返回的是完整 Clash 配置，而不是 provider 列表

证据：

- 第 1 条和第 3 条订阅都能解析为完整 YAML
- 顶层包含 `proxies`、`proxy-groups`、`rules`
- 不包含 `proxy-providers`

结论：

- 不能再把这类订阅“塞进自己手写的 provider 框架里”
- 应改为“抓取完整订阅配置，再做本机安全覆盖”

### 2026-04-18：把同步机制改成“订阅配置接管 + 本机覆盖”

新增：

- `/home/chesszyh/mihomo-deploy/scripts/sync-subscription-config.py`
- `/home/chesszyh/mihomo-deploy/templates/mihomo-config-sync.service`
- `/home/chesszyh/mihomo-deploy/templates/mihomo-config-sync.timer`

行为改为：

1. 拉取订阅 YAML
2. 校验 `proxies` 与 `proxy-groups`
3. 覆盖为本机安全参数：
   - `allow-lan: false`
   - `bind-address: 127.0.0.1`
   - `external-controller: 127.0.0.1:9090`
   - `secret: <redacted>`
   - `mixed-port: 7890`
4. 写回 `/etc/mihomo/config.yaml`
5. 通过 systemd timer 定时同步

### 2026-04-18：首次安装时 geodata 下载卡住

现象：

- Mihomo 日志卡在 `Can't find MMDB, start download`
- 进程存在到外部地址的 `SYN-SENT`
- REST API 一度返回 `502`

错误假设：

- 误以为 Mihomo 核心或 systemd 启动参数异常

最终确认：

- 根因是默认 geodata 下载源在该环境下不可达，不是 Mihomo 本身坏了

修复：

- 在同步脚本中加入更稳定的 `geox-url`
- 使用 `testingcf.jsdelivr.net` / GitHub releases 作为 geodata 源

### 2026-04-18：UI 打开但无法自动连接后端

证据链：

1. `curl http://127.0.0.1:9090/version` 带密钥可返回 `{"meta":true,"version":"v1.19.23"}`
2. `curl http://127.0.0.1:9090/ui/` 返回 `200`
3. `curl http://127.0.0.1:9090/ui/config.js` 显示 `defaultBackendURL: ''`

结论：

- UI 资源本身是好的
- 后端 API 也是好的
- 问题出在 UI 缺少默认后端地址

修复：

- 把 `/etc/mihomo/ui/config.js` 改成：

```javascript
window.__METACUBEXD_CONFIG__ = {
  defaultBackendURL: window.location.origin,
}
```

### 2026-04-18：SSH 转发失败并非 API 坏掉，而是命令写反且本地端口被占

错误命令：

```bash
ssh -L 9090:127.0.0.1:9091 chesszyh@192.168.1.13
```

正确思路：

- 远端 API 在 `127.0.0.1:9090`
- 本地 `9090` 已被占用时，应改用另一个本地端口

推荐命令：

```bash
ssh -L 9091:127.0.0.1:9090 chesszyh@192.168.1.13
```

### 2026-04-21：确认项目具备 TUN/全局接管能力，但默认不启用

检查结果：

- `/dev/net/tun` 存在
- `nftables` 可用
- `net.ipv4.ip_forward = 1`
- Mihomo 服务已具备 `CAP_NET_ADMIN`

随后在同步脚本中加入 TUN 开关：

- `MIHOMO_ENABLE_TUN`
- `MIHOMO_TUN_STACK`
- `MIHOMO_TUN_AUTO_ROUTE`
- `MIHOMO_TUN_AUTO_REDIRECT`
- `MIHOMO_TUN_STRICT_ROUTE`
- `MIHOMO_TUN_EXCLUDE_INTERFACE`

并离线生成候选配置，通过：

```bash
sudo /usr/local/bin/mihomo -t -d /etc/mihomo -f /home/chesszyh/mihomo-deploy/build/tun-check-config.yaml
```

说明：

- 项目层面支持 TUN/全局模式
- 线上仍保持 `proxy-only`，未直接切换，避免影响现有服务器业务

### 2026-04-21：移除对另一台机器 `192.168.1.5:7897` 的临时依赖

证据：

- `127.0.0.1:7890` 可稳定代理：
  - `https://www.gstatic.com/generate_204` -> `204`
  - `http://cp.cloudflare.com/generate_204` -> `204`

调整：

1. 把 `/etc/mihomo/deploy.env` 中的：
   - `HTTP_PROXY`
   - `HTTPS_PROXY`
   - `ALL_PROXY`
   从 `192.168.1.5:7897` 改为 `127.0.0.1:7890`
2. 把 `mihomo.service` 从 `EnvironmentFile=/etc/mihomo/deploy.env` 中摘出来，避免 Mihomo 启动时代理到自己造成环路
3. 保留 `mihomo-config-sync.service` 读取 `deploy.env`，让订阅同步和下载任务走本机代理

### 2026-04-28：把多订阅切换从“自动挑第一个可用”改成“显式活动源 + 手动切换”

新增环境变量：

- `MIHOMO_SUBSCRIPTION_NAME_1..4`
- `MIHOMO_SUBSCRIPTION_URL_1..4`
- `MIHOMO_ACTIVE_SUBSCRIPTION`

新增命令：

- `/usr/local/bin/mihomo-subscription`

支持：

```bash
mihomo-subscription list
mihomo-subscription current
mihomo-subscription set <index>
mihomo-subscription sync
```

当前登记的 4 条源为：

1. `dash` -> `https://dash.xn--cp3a08l.com/api/v1/pq/<redacted>`
2. `dp3` -> `https://dp3.config-sync.com/api/v1/client/subscribe?token=<redacted>`
3. `cloudflare-1` -> `https://cf.chesszyh.xyz/sub?token=<redacted>`
4. `fedora` -> `http://35.243.92.145:48735/sub/<redacted>?format=clash`

### 2026-04-28：验证手动切换链路

实际测试了：

1. `1 -> 4`
2. `4 -> 1`

验证点：

- `selected` 会立即更新
- `mihomo-config-sync.service` 会被触发
- `/etc/mihomo/config.yaml` 中 `mihomo-deploy-meta` 会同步为对应源
- `http://127.0.0.1:9090/version` 仍可访问
- `http://127.0.0.1:9090/ui/` 仍返回 `200`

## Root Cause

本次问题不是单点故障，而是几层配置漂移叠加：

### 1. 对订阅格式的初始假设错误

最初假设这些订阅返回的是 `proxy-provider` 数据，但实际上返回的是完整 Clash 配置。这个错误假设会导致：

- 配置模型选错
- provider 与 groups/rules 的关系处理错误
- 后续“多订阅合并”与“手动切源”设计方向偏掉

### 2. UI 错误不是后端宕机，而是前端没有默认后端地址

后端 API 一直是好的。真正的问题是 `config.js` 中 `defaultBackendURL` 为空，导致 UI 首次打开时无法自动知道要连哪个 backend。

### 3. SSH 隧道错误来自本地端口与远端端口概念混淆

错误地把远端 API 端口写成了 `9091`，同时又试图绑定本地已占用的 `9090`，于是报错表象看起来像“远端服务坏了”。

### 4. 下载卡住的根因是 geodata 源可达性，不是 Mihomo 核心故障

首次安装时卡在 geodata 下载，导致启动初期 API 短暂异常。真正原因是默认下载源在该环境下不可达。

### 5. “自动选第一个可用订阅”不等价于“可维护的多订阅管理”

自动 fallback 对首装有用，但对于长期维护会带来两个问题：

- 无法知道“现在到底用的是哪条源”
- 用户无法手动指定切换到哪条源

因此最终需要显式引入：

- `selected`：用户选中的源
- `applied`：最后成功应用的源

## Changes Made

### 系统层变更

- 更新 `/etc/mihomo/deploy.env`
  - 增加 4 条订阅的名称与 URL
  - 增加 `MIHOMO_ACTIVE_SUBSCRIPTION`
  - 下载代理改为本机 `127.0.0.1:7890`
- 更新 `/etc/mihomo/config.yaml`
  - 引入 `mihomo-deploy-meta`
  - 记录当前应用源索引、名称和登记源集合
- 更新 `/etc/mihomo/ui/config.js`
  - 设置 `defaultBackendURL: window.location.origin`
- 更新 `/etc/systemd/system/mihomo.service`
  - 去除对 `/etc/mihomo/deploy.env` 的直接环境继承，避免 Mihomo 自代理

### 部署脚本与模板变更

- `/home/chesszyh/mihomo-deploy/.env`
- `/home/chesszyh/mihomo-deploy/.env.example`
- `/home/chesszyh/mihomo-deploy/scripts/sync-subscription-config.py`
- `/home/chesszyh/mihomo-deploy/scripts/mihomo-subscription`
- `/home/chesszyh/mihomo-deploy/scripts/install-host.sh`
- `/home/chesszyh/mihomo-deploy/templates/mihomo.service`

### 新增能力

- 多订阅登记
- 手动切换活动订阅
- `selected` / `applied` 状态分离
- TUN 候选配置生成
- geodata 源自定义

## Verification

### 当前服务状态

```bash
sudo systemctl status mihomo
sudo systemctl status mihomo-config-sync.timer
```

结果：

- `mihomo.service` 为 `active (running)`
- `mihomo-config-sync.timer` 为 `active (waiting)`

### 当前面板与 API

```bash
curl --noproxy '*' -H 'Authorization: Bearer <redacted>' http://127.0.0.1:9090/version
curl --noproxy '*' -o /dev/null -w 'ui %{http_code}\n' http://127.0.0.1:9090/ui/
```

结果：

- `/version` 返回 `{"meta":true,"version":"v1.19.23"}`
- `/ui/` 返回 `200`

### 当前订阅状态

```bash
mihomo-subscription list
mihomo-subscription current
```

结果：

- 已登记 4 条源
- 当前 `selected=1`
- 当前 `applied_index=1`
- 当前 `applied_name=dash`

### 当前运行模式

```bash
sudo python3 - <<'PY'
import yaml
with open('/etc/mihomo/config.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
print(data.get('mode'))
print(data.get('tun'))
print(data.get('mixed-port'))
PY
```

结果：

- `mode` 为 `rule`
- `tun` 为 `None`
- `mixed-port` 为 `7890`

### 代理环境变量可用性

```bash
set -a
source /etc/mihomo/deploy.env
set +a
curl -m 20 -fsS -o /dev/null -w 'env_https_proxy %{http_code}\n' https://www.gstatic.com/generate_204
curl -m 20 -fsS -o /dev/null -w 'env_http_proxy %{http_code}\n' http://cp.cloudflare.com/generate_204
```

结果：

- `env_https_proxy 204`
- `env_http_proxy 204`

### 手动切换链路

已实测：

```bash
mihomo-subscription set 4
mihomo-subscription current
mihomo-subscription set 1
mihomo-subscription current
```

结果：

- 可成功切到第 `4` 条 `fedora`
- 可成功切回第 `1` 条 `dash`
- 切换后 API/UI 持续可用

## Problems Encountered During Debugging

1. 有些订阅 URL 返回的 `Content-Type` 是 `text/html`，但正文仍然是可解析的 YAML，不能仅凭 `Content-Type` 判断是否是有效订阅。
2. 第二条 `dp3` 订阅在当前环境下即使经过代理也返回 `403`，因此“已导入”与“可用性已验证”必须分开表述。
3. 对 root 拥有的文件直接写补丁会失败，例如 `/etc/mihomo/ui/config.js`，需要先复制到工作区再 `sudo install` 覆盖回去。
4. `mihomo -t` 如果不复用 `/etc/mihomo` 目录，会重新触发 geodata 下载，看起来像“测试命令卡死”，但这不是线上服务故障。
5. `mihomo-subscription current` 初版在非 root 下读不到 `/etc/mihomo/config.yaml`，导致只能显示 `selected`，后来补成了自动 `sudo` 回退。
6. 这套多订阅切换逻辑不是 MetaCubeXD 原生能力，因此 UI 面板里看不到“订阅源 1/2/3/4 切换入口”，必须通过额外脚本操作。

## Reuse Notes and Lessons

1. 遇到“订阅导入”问题，先判断订阅到底返回的是：
   - 完整 Clash 配置
   - 还是 provider list
   这一步决定后续全部架构。
2. Headless 代理在服务器上要优先区分：
   - 显式代理模式
   - TUN/全局接管模式
   不要一开始就直接切全局。
3. 面板“无法连接后端”时，不要先怀疑后端挂了；要优先查：
   - `/version`
   - `/ui/`
   - `/ui/config.js`
4. SSH 隧道问题先分清三件事：
   - 远端监听地址
   - 本地占用端口
   - 是否写反了本地/远端端口
5. 多订阅场景下必须保留两类状态：
   - 用户选中的源
   - 最后真正成功应用的源
   否则排障时很难解释“为什么配置文件和用户预期不一致”。
6. 如果 Mihomo 自身也读取外部代理环境变量，就可能出现启动阶段自代理、自环路或 geodata 下载异常。服务进程本身和同步/下载进程的环境要分离。

## Appendix: Reusable Commands

### 查看当前订阅源状态

```bash
mihomo-subscription list
mihomo-subscription current
```

### 切换订阅源

```bash
mihomo-subscription set 1
mihomo-subscription set 2
mihomo-subscription set 3
mihomo-subscription set 4
```

### 手动同步当前选中的源

```bash
mihomo-subscription sync
sudo systemctl status mihomo-config-sync.service --no-pager --full
```

### 检查 Mihomo 与 UI

```bash
curl --noproxy '*' -H 'Authorization: Bearer <redacted>' http://127.0.0.1:9090/version
curl --noproxy '*' -o /dev/null -w 'ui %{http_code}\n' http://127.0.0.1:9090/ui/
curl --noproxy '*' http://127.0.0.1:9090/ui/config.js
```

### 推荐 SSH 转发方式

```bash
ssh -L 9091:127.0.0.1:9090 chesszyh@192.168.1.13
```

然后本地打开：

```text
http://127.0.0.1:9091/ui/
```

### 检查当前活动配置

```bash
sudo python3 - <<'PY'
import yaml
with open('/etc/mihomo/config.yaml', encoding='utf-8') as f:
    data = yaml.safe_load(f)
print(data.get('mihomo-deploy-meta', {}))
print(data.get('mode'))
print(data.get('tun'))
print(data.get('mixed-port'))
PY
```

### 验证本机 mixed proxy 是否可用于下载

```bash
set -a
source /etc/mihomo/deploy.env
set +a
curl -m 20 -fsS -o /dev/null -w 'env_https_proxy %{http_code}\n' https://www.gstatic.com/generate_204
curl -m 20 -fsS -o /dev/null -w 'env_http_proxy %{http_code}\n' http://cp.cloudflare.com/generate_204
```

### 验证 TUN 候选配置

```bash
cd /home/chesszyh/mihomo-deploy
set -a
source .env
set +a
MIHOMO_ENABLE_TUN=true MIHOMO_RELOAD_ON_CHANGE=false ./scripts/sync-subscription-config.py build/tun-check-config.yaml
sudo /usr/local/bin/mihomo -t -d /etc/mihomo -f /home/chesszyh/mihomo-deploy/build/tun-check-config.yaml
```
