生成时间: 2026-07-21T00:52:19+08:00

# Floway 部署到 Cloudflare Workers 后 Codex 403、Placement 522 与滥用举报事件报告

## 1. 问题描述

本次事件原本要将本地项目 `/home/chesszyh/Applications/Floway` 部署到 Cloudflare Workers，并通过自定义域名提供私有 LLM API 网关。部署后，Floway 的网页和控制面一度可用，但 `codex` provider 无法拉取 ChatGPT/Codex 模型列表：同一份 OAuth 凭据在本机直连请求成功，从 Worker 发出时却收到 OpenAI 返回的 `403` HTML challenge 页面。

为了验证是否是 Cloudflare Worker 所在地区不受 OpenAI 支持，先后尝试美国、德国和日本的 targeted placement。三次尝试都没有进入 Floway 应用，而是在 Cloudflare 边缘直接返回 `522`。移除 placement、重新部署和回滚代码版本均未恢复原 Worker 服务，只能新建 `floway-recovery` Worker 恢复入口。

新 Worker 恢复后，再次执行受管理员认证保护的 Codex 模型列表探测，仍得到相同的 OpenAI `403`。约十几分钟后，Cloudflare 发来 `Network abuse` 举报通知，指向该 Worker 的规范 `workers.dev` 地址。最终决定停止本项目的 Cloudflare 运行面：移除自定义域名绑定，关闭两个 Floway Worker 的 `workers.dev` 入口和 cron，但保留 Worker 代码及 D1、R2、KV 数据。

## 2. 环境和范围

- 项目：Floway，LLM API gateway。
- 本地仓库：`/home/chesszyh/Applications/Floway`。
- 技术栈：Hono、TypeScript、pnpm、Vue/Vite、Cloudflare Workers、D1、R2、KV、Durable Objects、Images。
- Cloudflare Worker：`floway`、`floway-recovery`。
- 生产入口：报告中统一记作 `<FLOWAY_DOMAIN>`。
- Cloudflare 账户、数据库、KV、R2 标识：已脱敏。
- Wrangler：本次执行时为 `4.81.0`。
- 事件日期：2026-07-20 至 2026-07-21，时区 `Asia/Shanghai`。
- 本次只操作 Floway 对应的 Worker、域名和定时任务；未触碰账户内其他项目。

本报告不会记录以下敏感内容：Cloudflare OAuth token、`ADMIN_KEY`、Codex OAuth token、完整 `auth.json`、会话 token、API key、Cloudflare account ID、D1/KV/R2 资源 ID，以及滥用报告的直接面板链接和报告编号。

## 3. 现象与复现

### 3.1 Worker 内 Codex `/models` 返回 403

Floway 控制面的模型刷新操作返回 HTTP 500，内部错误保留了真实上游状态：

```text
Codex /models fetch failed: 403 <html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style global>body{font-family:Arial,Helvetica,sans-serif}...
```

对照请求表明：

- 使用相同 OAuth 凭据从本机请求，上游模型列表返回 HTTP 200。
- 从默认 Cloudflare Worker 请求，上游返回 HTTP 403 和 challenge HTML。
- 因此凭据格式和 OAuth token 本身不是首要差异；运行时出口路径才是关键变量。

### 3.2 Targeted placement 后整个入口返回 522

依次为 Worker 设置以下 placement：

```json
{ "region": "aws:us-east-1" }
{ "region": "aws:eu-central-1" }
{ "region": "aws:ap-northeast-1" }
```

三个地区均出现一致结果：自定义域名持续返回 Cloudflare `522`，连静态首页都无法进入，说明失败发生在 Floway 请求处理之前。删除 placement 字段、重新发布以及回滚到原先正常的 Worker 版本后仍持续 `522`。

### 3.3 滥用通知

恢复 Worker 上线并再次执行 Codex 模型列表探测后，Cloudflare 发出自动邮件：

```text
Cloudflare received an Network abuse regarding:
floway-recovery[.]<account-subdomain>[.]workers[.]dev

Reported URLs:
hxxps://floway-recovery[.]<account-subdomain>[.]workers[.]dev
```

通知中的 `Logs or other evidence of abuse` 为空，因此仅凭邮件无法确定举报方，也无法证明第三方实际访问过该 URL。

### 3.4 最终停用后的外部信号

```text
floway workers.dev:          enabled=false, previews_enabled=false
floway cron schedules:       []
floway-recovery workers.dev: enabled=false, previews_enabled=false
floway-recovery schedules:   []
Floway custom domains:       []
```

停用后 `<FLOWAY_DOMAIN>` 已无法建立正常 TLS/HTTP 连接，`floway-recovery.<account-subdomain>.workers.dev` 返回 404。

## 4. 调查时间线

1. 已执行 `pnpm i` 的 Floway 工作区被配置为 Cloudflare Workers 生产部署，绑定 D1、R2、KV、Images 和 Durable Objects，并使用自定义域名。
2. 完成远端 D1 migration 检查；61 个 migration 均已应用，没有待执行 migration。
3. 初始 Worker 网页返回 200，但 `codex` provider 模型列表请求返回 OpenAI 403 challenge HTML；相同凭据本机请求返回 200。
4. 记录初始可回滚版本 `93c0f27b-6eca-4d41-a9d3-edffbdd34550`。
5. 部署美国东部 placement，版本 `2131cd3b-75fd-49ff-a756-83fd586e2ea1`；入口持续 522。
6. 部署德国 placement，版本 `ff1524c0-9c73-4911-894b-5231b829f75c`；入口持续 522。
7. 部署日本 placement，版本 `694ae277-3242-4da5-bffb-9b45df5cac8e`；入口持续 522。
8. 删除 placement 配置并重新部署，版本 `55298329-646d-4938-acc4-333ff5d65117`；522 未消失。
9. 回滚到 `93c0f27b-6eca-4d41-a9d3-edffbdd34550`；522 仍未消失，证明问题不是当前代码包本身。
10. 检查 Wrangler 实现，发现 `placement.mode = "off"` 会在上传前转换成 `undefined`，即“不发送 placement 字段”，无法强制清除远端状态。
11. 通过 Worker settings API 尝试 `{ "placement": { "mode": "off" } }`，API 返回 `invalid placement mode: off`；改发 `{ "placement": null }` 后 API 接受，版本元数据中的 placement 也为空，但原 Worker 仍为 522。
12. 删除并重建原自定义域名绑定，另建临时探针域名，两个域名均持续 522，进一步把故障边界收敛到原 `floway` Worker 服务。
13. 新建干净服务 `floway-recovery` 并绑定相同存储及域名，发布版本 `f61e9f36-18b9-4988-8d0a-2f0bb33a7466`；复制 `ADMIN_KEY` 后产生 secret change 版本 `94b2fd8c-0727-49a0-b1f3-17a7ff2fc2c9`。
14. 新服务连续 20 次首页检查均返回 200。旧 `floway` 的 `workers.dev` 与 cron 被关闭，避免双实例定时任务。
15. 在新服务中执行真实反馈回路：管理员登录返回 200，Codex `list-models` 返回 500，内部上游错误仍是 OpenAI 403 challenge；随后注销临时会话。
16. 约十几分钟后收到 Cloudflare `Network abuse` 自动通知。
17. 核查 D1：生产库没有有效 API key，举报窗口后没有 `usage_requests` 数据面用量记录，只有一个有效用户；没有证据表明第三方通过 Floway 发起模型请求。
18. 用户决定停止本项目。最终移除 `<FLOWAY_DOMAIN>` 的 Worker 绑定，清空 `floway` 和 `floway-recovery` 的 cron，关闭两个 Worker 的 `workers.dev` 和 preview 入口，保留存储和代码。

## 5. 根因

本事件包含三个相互关联但不能混为一谈的原因层次。

### 5.1 Codex 403：Worker 出口被 OpenAI 风控

最强证据是“同一凭据、本机 200、Worker 403”。403 响应不是 JSON API 错误，而是 HTML challenge 页面，说明 OpenAI 前置反滥用/机器人系统拦截了 Cloudflare Worker 的出口请求。

这不等价于“新加坡不在 OpenAI 支持地区”。默认请求虽然观察到 `SIN` 边缘标识，但新加坡本身属于受支持地区；而 targeted placement 失败在 Floway 执行前，未能形成一次有效的跨地区上游对照实验。

Cloudflare 的 Workers 安全文档说明，Worker 出站 HTTP 请求由平台代理转发，并带有能够追溯到具体 Worker 的标识。这解释了为什么上游可以按 Worker 来源实施阻断或提交投诉：<https://developers.cloudflare.com/workers/reference/security-model/>。

### 5.2 Placement 522：远端服务状态未被普通部署/回滚清理

美国、德国、日本三次 placement 都让整个入口在应用执行前 522。代码回滚没有恢复，API 显示 placement 已清空后也没有恢复；新建相同代码和绑定的 `floway-recovery` 却立即恢复 200。因此最符合证据的解释是：targeted placement 使原 `floway` 服务进入了异常的 Cloudflare 调度/路由状态，该状态不属于普通 Worker 代码版本，无法通过 `wrangler rollback` 清除。

这部分是基于差分实验得出的工程判断，并非 Cloudflare 官方对该服务给出的根因确认。

### 5.3 Network abuse：网关行为可能被归类为代理服务

无法从空白 evidence 确认具体举报者，因此“由 OpenAI 自动投诉”只能作为高概率推断，不能写成已确认事实。但时间线高度相关：新 Worker 执行受认证保护的 OpenAI/Codex 出站探测后，十几分钟内收到 Network abuse 通知。

Floway 不是公开 VPN，也不是无认证开放代理；生产 D1 当时没有有效 API key，也没有数据面使用记录。然而它在功能上是把客户端 LLM API 请求转发到第三方上游的网关，可能被 Cloudflare 的规则或投诉方归类为“similar proxy service”。Cloudflare Self-Serve Subscription Agreement 中明确禁止使用服务提供 VPN 或类似代理服务：<https://www.cloudflare.com/terms/>。

Cloudflare 对 Workers 这类托管服务可直接限制内容，并允许账户所有者申请复审：<https://www.cloudflare.com/trust-hub/abuse-approach/>。

## 6. 已执行的变更

### 6.1 Cloudflare 远端状态

- 创建并多次发布 `floway` placement 测试版本。
- 创建恢复服务 `floway-recovery`。
- 将 `ADMIN_KEY` 安全复制到恢复服务，过程中未打印 secret。
- 自定义域名一度从 `floway` 转移到 `floway-recovery`。
- 清空旧 `floway` cron，并关闭其 `workers.dev`。
- 最终清空 `floway-recovery` cron，并关闭其 `workers.dev` 和 preview。
- 最终删除 Floway 的自定义域名绑定。
- 删除临时探针域名。
- 未删除 `floway`、`floway-recovery` Worker 代码。
- 未删除 D1、R2、KV、Images 或 Durable Object 数据。
- 未改动账户内其他 Worker 和其他项目资源。

### 6.2 本地文件

- `/home/chesszyh/Applications/Floway/wrangler.jsonc` 是 gitignored 的个人配置，当前 Worker 名为 `floway-recovery`，仍声明自定义域名和 cron。若再次执行 `pnpm run deploy`，会重新启用当前已停用的入口和定时任务。
- `/home/chesszyh/Applications/Floway/wrangler.example.jsonc` 在本次部署准备中增加了自定义域名 route 占位配置；该修改仍未提交。
- `.serena/` 是原有未跟踪内容，本次未修改。
- 本次没有创建 Git commit 或 Pull Request。

## 7. 验证

### 7.1 恢复服务曾经可用

新建 `floway-recovery`、完成 secret 配置后执行连续检查：

```text
20/20 requests: HTTP 200
```

同时验证真实控制路径：

```text
login_http=200
models_http=500
error.message=Codex /models fetch failed: 403 <html>...
```

这证明恢复服务的 Floway 控制面正常，而 Codex 失败仍来自上游。

### 7.2 未发现第三方数据面滥用

D1 只读查询结果：

```text
active_keys=0
usage_requests after incident window=[]
active_users=1
```

该结果不能证明 Cloudflare 没有观察到任何网络异常，但能证明没有 API key 可用于正常的 Floway 数据面调用，也没有 Floway 记录的模型请求用量。

### 7.3 最终停用确认

Cloudflare API 最终复查：

```json
{
  "floway": {
    "workers_dev": false,
    "previews_enabled": false,
    "schedules": []
  },
  "floway-recovery": {
    "workers_dev": false,
    "previews_enabled": false,
    "schedules": []
  },
  "floway_domains": []
}
```

外部访问复查：

```text
<FLOWAY_DOMAIN>: unavailable
floway-recovery.<account-subdomain>.workers.dev: HTTP 404
```

## 8. 调试过程中遇到的问题

### 8.1 把“换国家”误当成可直接验证的单变量

Targeted placement 不只是改变出站地区；在本环境中它使整个自定义域名 522。由于请求未进入 Floway，三次测试并没有真正验证美国、德国或日本出口能否访问 OpenAI。

### 8.2 Wrangler 的 `mode: off` 语义具有误导性

Wrangler `4.81.0` 的 `parseConfigPlacement()` 对 `mode === "off"` 返回 `undefined`。因此配置中写 `off` 或直接删除 placement，上传时都表现为“不发送字段”，无法可靠地把已有远端 placement 改成关闭状态。

Cloudflare settings API 又不接受 `placement.mode=off`：

```text
invalid placement mode: off
```

发送 `placement: null` 能清空 API 元数据，但仍没有修复原 Worker 服务的 522。

### 8.3 代码版本回滚不是服务配置回滚

`wrangler rollback <VERSION_ID>` 成功把活动代码版本切回已知正常版本，但未清除 placement 相关的服务异常。以后看到“部署版本已回滚”不能直接推导“域名路由和调度状态也已回滚”。

### 8.4 删除并立即重建域名绑定没有修复

先尝试删除后立即重建自定义域名，随后又让域名实际消失十余秒再重建，两次均保持 522。临时新 hostname 指向同一 `floway` 服务同样 522，排除了单一 hostname 缓存作为主要原因。

### 8.5 曾把 1042 过早解释成滥用封禁

访问关闭后的 `workers.dev` 地址曾看到 `error code: 1042`。Cloudflare 官方错误表说明，1042 的含义是 Worker 尝试 fetch 同一 zone 的另一个 Worker，而不是“因滥用被封”。因此该信号不能单独证明处罚状态：<https://developers.cloudflare.com/workers/observability/errors/>。

### 8.6 本机代理会让网络观测变得混乱

本机 Clash/Fake-IP 环境会让 `curl` 显示 `127.0.0.1` 或 `fdfe:dcba:...` 形式的远端地址。诊断中使用 `curl --noproxy "*"` 尽量绕过显式代理，但 Fake-IP/TUN 仍可能影响地址显示。HTTP 状态、Cloudflare API 元数据和 D1 记录比 `remote_ip` 更可靠。

## 9. 复用说明与经验

1. 对 OpenAI-compatible relay，必须分别验证模型发现和一次真实生成；“网页能开”不能证明上游可用。
2. 收到 HTML 403 时先对比同凭据的本机直连请求。若本机 200、Worker 403，应优先怀疑平台出口风控，而不是重复刷新 OAuth token。
3. Cloudflare placement 适合把 Worker 靠近后端，但不是通用的出口国家选择器。变更前必须准备独立恢复服务，不能只依赖代码版本回滚。
4. 部署前记录活动版本、D1 migration 状态和可复制的回滚命令；涉及 migration 时还要保存 D1 Time Travel bookmark。
5. `wrangler rollback` 只覆盖 Worker 版本；域名、cron、workers.dev、placement 和其他服务级设置应单独核验。
6. LLM API gateway 即使要求认证，也可能被云平台归类为代理服务。生产前应先检查平台条款和上游对云函数出口的政策。
7. Cloudflare Worker 的出站请求可追溯到具体 Worker。不要通过反复换 Worker 名称来规避投诉或 mitigation，这可能放大账户风险。
8. 若必须运行 Floway，优先考虑 Node 目标部署到 VPS，并使用 DNS-only 记录，避免把第三方 LLM 流量再次经过 Cloudflare Worker/CDN 代理层。
9. 当前只是远端停用，不是删除。D1、R2、KV 和 Worker 代码仍保留，适合后续审计或迁移。
10. 当前本地 `wrangler.jsonc` 仍包含 route 和 cron，任何未来部署都可能重新启用服务；重新执行前应先明确审查意图和 Cloudflare 复审结果。

## 10. 附录：可复用命令

以下命令均使用占位符，不应把 token 或 secret 写入 shell history。

### 10.1 检查部署和 migration

```bash
pnpm wrangler deployments list
pnpm wrangler d1 migrations list <D1_DATABASE_NAME> --remote
```

### 10.2 检查 Worker 的 cron

```bash
curl -sS \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/scripts/<WORKER_NAME>/schedules" \
  | jq '{success, schedules: .result.schedules, errors}'
```

### 10.3 清空指定 Worker 的 cron

```bash
curl -sS -X PUT \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  -H "Content-Type: application/json" \
  --data '[]' \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/scripts/<WORKER_NAME>/schedules"
```

### 10.4 检查和关闭 `workers.dev`

```bash
curl -sS \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/scripts/<WORKER_NAME>/subdomain"

curl -sS -X POST \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  -H "Content-Type: application/json" \
  --data '{"enabled":false,"previews_enabled":false}' \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/scripts/<WORKER_NAME>/subdomain"
```

### 10.5 只列出属于 Floway 的自定义域名

```bash
curl -sS \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/domains" \
  | jq '[.result[] | select(.service == "floway" or .service == "floway-recovery") | {id, hostname, service, enabled}]'
```

### 10.6 删除一个已经确认的自定义域名绑定

删除前必须先用上一条命令核对精确 ID，不能使用未解析变量、通配符或账户级批量删除。

```bash
curl -sS -X DELETE \
  -H "Authorization: Bearer $CLOUDFLARE_TOKEN" \
  "https://api.cloudflare.com/client/v4/accounts/<CF_ACCOUNT_ID>/workers/domains/<DOMAIN_BINDING_ID>"
```

### 10.7 检查是否存在 Floway 数据面使用

```bash
pnpm wrangler d1 execute <D1_DATABASE_NAME> --remote --json --command \
  "SELECT hour, SUM(requests) AS requests, COUNT(DISTINCT key_id) AS keys
   FROM usage_requests
   WHERE hour >= '<UTC_START_TIME>'
   GROUP BY hour
   ORDER BY hour;"
```

### 10.8 绕过显式代理检查 HTTP 状态

```bash
curl --noproxy "*" -sS -o /dev/null \
  -w '%{http_code} %{time_total}\n' \
  --max-time 20 \
  https://<FLOWAY_DOMAIN>/
```

### 10.9 重新启用前的最低检查清单

```text
1. 确认 Cloudflare abuse report 的复审结果和明确政策边界。
2. 审查 wrangler.jsonc 中的 name、routes、triggers 和 placement。
3. 确认不会恢复 workers.dev 或重复 cron。
4. 检查 D1 migration diff 并准备回滚版本/Time Travel bookmark。
5. 使用不包含真实凭据的最小探针先验证入口。
6. 不要再次用 Cloudflare Worker 反复探测已返回 challenge 的 OpenAI 端点。
```
