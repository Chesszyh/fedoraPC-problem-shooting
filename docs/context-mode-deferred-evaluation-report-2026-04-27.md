# context-mode 项目暂缓采用复查记录

生成时间: 2026-04-27T02:10:02+08:00

## 1. Problem Description（问题描述）

本次不是故障修复，而是一次项目评估后的暂缓采用记录。

评估对象为本地仓库：

```text
/home/chesszyh/Downloads/context-mode
```

初步判断：`context-mode` 项目设计完整，目标明确，适合在 AI 编程会话上下文成本较高、模型额度紧张、需要跨平台 hook 和本地检索记忆时再深入使用。

当前决策：本月 GPT Plus 额度完全够用，暂时不启动该项目；下个月如额度不够用，再回来复查和试用。

## 2. Environment and Scope（环境与范围）

- 当前工作目录：`/home/chesszyh/Downloads/context-mode`
- 项目名称：`context-mode`
- 包版本：`1.0.98`
- 项目类型：TypeScript / Node.js ESM MCP 插件与本地工具服务
- 主要入口：`server.bundle.mjs`、`cli.bundle.mjs`、`src/server.ts`、`src/cli.ts`
- 相关子系统：MCP tools、sandbox executor、SQLite FTS5 knowledge base、session continuity hooks、Insight dashboard
- 本次未执行安装、部署、真实 MCP 客户端接入或长期运行测试

## 3. Symptoms and Reproduction（现象与复现）

没有运行时故障需要复现。

本次触发因素是使用场景判断：

- 该项目可减少 AI 工具调用产生的大量上下文输出。
- 当前用户 GPT Plus 额度充足，暂时没有强需求通过该项目节省上下文或模型额度。
- 因此采用策略从“立即启动”调整为“保留评估结果，下月额度紧张时复查”。

后续复查可复现本次评估流程：

```bash
cd /home/chesszyh/Downloads/context-mode
sed -n '1,220p' README.md
sed -n '1,260p' package.json
rg -n 'server\\.registerTool\\(|class ContentStore|class SessionDB|class PolyglotExecutor' src
```

## 4. Investigation Timeline（调查时间线）

- 读取项目根目录结构，确认仓库包含 `src/`、`hooks/`、`configs/`、`insight/`、`tests/`、`skills/`、`README.md`、`package.json` 等关键内容。
- 读取 `package.json`，确认项目定位为 MCP plugin，目标是减少上下文窗口占用，并支持 Claude Code、Gemini CLI、VS Code Copilot、OpenCode、Codex CLI 等平台。
- 读取 `README.md`，确认项目核心能力包括 context saving、session continuity、think in code、output compression。
- 检查 `src/server.ts`，确认 MCP server 注册了 `ctx_execute`、`ctx_execute_file`、`ctx_index`、`ctx_search`、`ctx_fetch_and_index`、`ctx_batch_execute`、`ctx_stats`、`ctx_doctor`、`ctx_upgrade`、`ctx_purge`、`ctx_insight`。
- 检查 `src/executor.ts` 和 `src/runtime.ts`，确认项目支持多语言沙箱执行和运行时检测。
- 检查 `src/store.ts`，确认本地知识库基于 SQLite FTS5、BM25、porter/trigram 双索引、RRF、模糊纠错和邻近度重排。
- 检查 `src/session/`，确认项目通过事件数据库、事件提取和 resume snapshot 实现会话连续性。
- 检查 `src/adapters/` 和 `hooks/`，确认项目对多平台 hook 协议做了抽象和适配。
- 检查 `insight/`，确认该项目带本地 analytics dashboard。
- 最终判断：项目值得保留，但当前没有立即采用的资源压力。

## 5. Root Cause（根因）

根因不是技术缺陷，而是需求时机不匹配。

直接原因：本月 GPT Plus 额度完全够用，当前没有迫切需求引入额外 MCP server、hooks、SQLite 本地索引和跨平台配置。

深层原因：`context-mode` 的收益主要出现在上下文窗口频繁被大输出污染、模型额度紧张、长会话需要恢复状态、多工具平台需要统一上下文策略的场景。当前使用压力不足以抵消引入和维护新工具链的成本。

## 6. Changes Made（已做变更）

未修改 `context-mode` 项目源码。

本次只新增个人报告记录，并更新 Reports 首页索引：

```text
/home/chesszyh/Documents/Reports/docs/context-mode-deferred-evaluation-report-2026-04-27.md
/home/chesszyh/Documents/Reports/docs/index.md
```

## 7. Verification（验证）

已完成静态验证：

- 仓库结构存在，且项目不是空壳。
- `package.json` 描述、scripts、exports、bin 和依赖与 README 定位一致。
- `src/server.ts` 中存在 MCP tool 注册。
- `src/store.ts` 中存在 FTS5 内容库实现。
- `src/session/` 中存在会话事件、快照和恢复相关实现。
- `insight/` 中存在本地 dashboard server 和 React 前端。

本次未做的验证：

- 未运行 `npm test`。
- 未执行 `context-mode doctor`。
- 未实际接入 Claude Code、Codex CLI、Gemini CLI 或 OpenCode。
- 未压测上下文节省比例。

## 8. Problems Encountered During Debugging（调试中遇到的问题）

本次没有调试故障。

需要避免的误判：

- 不应把“暂缓采用”误写成“项目不可用”。
- 不应把 README 中的节省比例当作本机实测结果。
- 不应在没有真实接入 MCP 客户端的情况下声称 hooks 和 session continuity 已在本机验证通过。
- 不应为了节省额度而提前引入额外复杂度；工具链收益应由实际使用压力驱动。

## 9. Reuse Notes and Lessons（复用笔记与经验）

下个月复查时优先回答这些问题：

- GPT Plus 或其他模型额度是否真的成为瓶颈？
- 当前 AI 编程会话是否经常被测试输出、日志、网页内容、Playwright snapshot、GitHub issue 列表污染上下文？
- 是否有长会话 compact 后丢失上下文的问题？
- 是否需要跨 Claude Code、Codex CLI、Gemini CLI、OpenCode 等平台统一上下文策略？
- 是否愿意接受本地 SQLite 数据库、hook 配置和 MCP server 常驻带来的维护成本？

建议复查路径：

1. 先运行 `context-mode doctor` 或源码版 doctor，确认本机依赖和 hooks 状态。
2. 选择一个最常用平台接入，不要一开始多平台全装。
3. 用一个真实的大输出任务测试 `ctx_execute`、`ctx_batch_execute`、`ctx_search` 是否明显降低上下文占用。
4. 若收益明确，再考虑 session continuity 和 Insight dashboard。

## 10. Appendix: Reusable Commands（附录：可复用命令）

### 查看项目定位

```bash
cd /home/chesszyh/Downloads/context-mode
sed -n '1,220p' README.md
sed -n '1,260p' package.json
```

### 查看核心 MCP 工具注册

```bash
cd /home/chesszyh/Downloads/context-mode
rg -n 'server\\.registerTool\\(' src/server.ts
```

### 查看核心实现分层

```bash
cd /home/chesszyh/Downloads/context-mode
rg -n 'class PolyglotExecutor|class ContentStore|class SessionDB|buildResumeSnapshot|extractEvents' src
```

### 查看平台适配器

```bash
cd /home/chesszyh/Downloads/context-mode
find src/adapters -maxdepth 2 -type f -print | sort
find hooks -maxdepth 3 -type f -print | sort
find configs -maxdepth 3 -type f -print | sort
```

### 后续如决定试用

```bash
cd /home/chesszyh/Downloads/context-mode
npm test
npm run build
node cli.bundle.mjs doctor
```
