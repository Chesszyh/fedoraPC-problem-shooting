# Codex 切换 provider 后旧会话无法 Resume 排障报告

生成时间: 2026-05-12T22:18:33+08:00

## 1. Problem Description

在 Codex CLI 从 ChatGPT/OpenAI 登录模式切换到本地 `cliproxyapi` provider 后，用户发现以前通过 ChatGPT 账号登录产生的对话无法从 `/resume` 或 `codex resume --all` 中方便恢复。切换到本地 provider 之后新产生的会话可以正常 resume，但旧 provider 的会话在默认列表中不可见。

用户目标不是简单切回 OpenAI provider，而是希望能够查到旧 `openai` provider 会话的 UUID，然后用当前本地 `cpa` provider 继续恢复这些旧会话。

## 2. Environment and Scope

- 主配置目录：`/home/chesszyh/.codex`
- Codex 配置文件：`/home/chesszyh/.codex/config.toml`
- 当前默认 provider：`cpa`
- 当前本地 provider 地址：`http://127.0.0.1:8317/v1`
- Codex 状态库：`/home/chesszyh/.codex/state_5.sqlite`
- Codex 文本日志：`/home/chesszyh/.codex/log/codex-tui.log`
- 用户 shell：`zsh`
- 新增工具脚本：`/home/chesszyh/.local/bin/codex-resume-provider`
- 新增别名位置：`/home/chesszyh/.zsh_alias`

本报告只覆盖本地 Codex CLI 会话发现、provider 过滤和恢复工具封装，不覆盖 `cliproxyapi` 服务自身的模型转发质量或账号计费逻辑。

## 3. Symptoms and Reproduction

现象：

- `codex resume --all` 只能看到切换到 `cpa` provider 之后的新会话。
- 旧的 ChatGPT/OpenAI 登录会话没有出现在 picker 中。
- `--all` 的效果表现为“跨目录”，但没有跨 provider。
- 用户不知道如何方便定位旧 provider 会话 UUID。

可复现检查：

```bash
cd /home/chesszyh/.codex
codex resume --all
```

预期是看到所有 provider 的所有会话；实际只看到当前 provider 相关会话。

查询状态库可见 provider 分布：

```bash
sqlite3 -header -column ~/.codex/state_5.sqlite \
  "select model_provider, source, count(*) n,
          min(datetime(created_at,'unixepoch','localtime')) first,
          max(datetime(updated_at,'unixepoch','localtime')) last
   from threads
   group by model_provider, source
   order by last desc;"
```

本次排查时观察到关键分布：

```text
cpa     cli     36 条   2026-05-07 16:35:39 到 2026-05-12 22:18:56
openai  cli    163 条   2025-10-14 17:39:41 到 2026-05-07 16:28:44
openai  exec   194 条   2026-03-25 15:47:35 到 2026-05-07 16:17:32
```

这证明旧会话仍在数据库里，只是默认恢复入口没有按用户期望展示。

## 4. Investigation Timeline

1. 检查 `~/.codex` 目录结构，确认会话数据主要存在于 `state_5.sqlite`、`session_index.jsonl` 和 `sessions/YYYY/MM/DD/*.jsonl`。
2. 针对 DBNet 会话缺失问题，使用 `rg` 搜索 `DBNet`、`workspace/DBNet` 和会话 ID，确认对应 rollout 文件仍存在。
3. 查询 `state_5.sqlite` 的 `threads` 表，确认目标 DBNet 会话有完整 `cwd`、`rollout_path`、`updated_at` 记录。
4. 查看 `codex resume --help`，确认 `--all` 的描述是 “disables cwd filtering and shows CWD column”，并未承诺跨 provider。
5. 搜索 GitHub issue，找到 `openai/codex#19318`，其标题为 `codex resume --all still filters by the current model provider`，与本地现象一致。
6. 确认当前 `config.toml` 中 `model_provider = "cpa"`，而旧会话 `model_provider = "openai"`。
7. 决定绕开 picker 的 provider 限制，直接查询 `state_5.sqlite`，取出旧 provider 的 UUID，再调用 `codex resume -c "model_provider=\"cpa\"" <UUID>`。
8. 实现 `codex-resume-provider` 脚本，支持当前目录、全目录、目录树、关键词过滤、只列出、交互选择和跨 provider resume。
9. 加入 zsh 别名 `cxr`、`cxr-list`、`cxr-all`。
10. 验证脚本语法、别名加载和查询输出。

## 5. Root Cause

根因是 Codex CLI 的 resume picker 当前会受 `model_provider` 过滤影响。`--all` 只取消 cwd 过滤，不取消当前 provider 过滤。

因此，当当前配置为：

```toml
model_provider = "cpa"
```

旧的：

```text
model_provider = openai
```

会话不会出现在默认 picker 中。会话文件和数据库记录没有丢失，问题在于发现入口的过滤条件不符合用户预期。

GitHub issue `openai/codex#19318` 说明这是已知行为/限制，且该 issue 当前不是一个已计划修复的问题。

另一个容易混淆的点是 `session_index.jsonl` 并不总是完整反映所有可恢复会话；更可靠的数据源是 `~/.codex/state_5.sqlite` 的 `threads` 表。

## 6. Changes Made

新增脚本：

```text
/home/chesszyh/.local/bin/codex-resume-provider
```

脚本能力：

- 默认查找 `openai` provider 会话。
- 默认用 `cpa` provider 执行 `codex resume`。
- 默认只查当前目录精确匹配的 `cwd`。
- 支持 `--all` 跨目录查找。
- 支持 `--tree` 查当前目录及子目录。
- 支持 `--list` 只列 UUID，不启动 Codex。
- 支持关键词过滤 title、cwd、id。
- 有 `fzf` 时使用交互选择；没有 `fzf` 时回退到编号选择。

当前脚本最终执行形式：

```bash
codex resume -c "model_provider=\"cpa\"" "$session_id" --yolo
```

新增 zsh 别名：

```text
/home/chesszyh/.zsh_alias
```

追加内容：

```bash
alias cxr="codex-resume-provider"
alias cxr-list="codex-resume-provider --list"
alias cxr-all="codex-resume-provider --all"
```

注意：`~/.zsh_alias` 中已有其他别名含本地服务 token 形式的配置，本报告不复制那些敏感值。

## 7. Verification

语法和权限检查：

```bash
chmod +x /home/chesszyh/.local/bin/codex-resume-provider
bash -n /home/chesszyh/.local/bin/codex-resume-provider
zsh -n /home/chesszyh/.zsh_alias
```

别名加载检查：

```bash
zsh -lc 'source ~/.zsh_alias >/dev/null 2>&1 || true; alias cxr; alias cxr-list; alias cxr-all'
```

得到：

```text
cxr=codex-resume-provider
cxr-list='codex-resume-provider --list'
cxr-all='codex-resume-provider --all'
```

当前 `.codex` 目录下查询旧 `openai` 会话：

```bash
/home/chesszyh/.local/bin/codex-resume-provider --list --limit 5
```

能够列出旧 `openai` provider 会话，例如：

```text
2026-04-23 23:19:59  019da50b-30dd-7292-bf07-c762b4589c48  /home/chesszyh/.codex  当前我的codex已经在官方默认配置基础上做了哪些自定义配置？
```

DBNet 目录下的验证显示，该目录目前没有 `openai` provider 会话，但有 `cpa` provider 会话：

```bash
/home/chesszyh/.local/bin/codex-resume-provider --from cpa --list --limit 10
```

输出包含：

```text
2026-05-12 17:17:04  019e1688-5be0-76f0-8ca7-e7a3d387c85e  /home/chesszyh/Project/Information-Security/CV/hw/bighw/workspace/DBNet  那我如果去autodl租显卡呢？越快跑完越好，不考虑价格
```

这说明脚本的目录过滤、provider 过滤和 UUID 输出都正常。

## 8. Problems Encountered During Debugging

- 初始判断容易误以为 `codex resume --all` 应该列出所有 provider 的所有会话，但实际 `--all` 只取消 cwd 过滤。
- `session_index.jsonl` 不适合作为唯一真相来源。某些会话在 `state_5.sqlite` 中存在，但索引文件不一定体现。
- 并行验证脚本时，一条测试命令抢在 `chmod +x` 之前执行，出现了一次 `permission denied`。顺序重跑后权限正常。
- DBNet 会话最初被认为可能是旧 `openai` provider 会话，但数据库确认它已经是 `cpa` provider，因此默认 `cxr` 不会列出它。这个结论避免了继续在错误 provider 下搜索。
- 写报告时发现 `~/Documents/Reports` 已有未提交改动：`docs/index.md` 已是 modified，且有一个未跟踪的 Clash Verge 报告。后续只追加本报告链接，避免改动无关内容。

## 9. Reuse Notes and Lessons

- 查 Codex 历史会话时，优先用 `~/.codex/state_5.sqlite` 的 `threads` 表，不要只依赖 `/resume` picker 或 `session_index.jsonl`。
- provider 切换后，旧会话没有消失；通常只是 picker 按当前 provider 过滤。
- 当前目录过滤和 provider 过滤是两个维度：`--all` 只解决目录维度，不解决 provider 维度。
- 想用新 provider 续旧会话时，关键是先拿到旧会话 UUID，再用 `-c model_provider=...` 覆盖恢复时的 provider。
- 对于本机长期使用，封装成 `cxr` 比每次手写 sqlite 查询更稳。
- 如果目录下查不到预期会话，应同时检查 `--all`、`--tree`、`--from` 和具体 `cwd` 是否完全一致。

## 10. Appendix: Reusable Commands

### 查询 provider 分布

```bash
sqlite3 -header -column ~/.codex/state_5.sqlite \
  "select model_provider, source, count(*) n,
          min(datetime(created_at,'unixepoch','localtime')) first,
          max(datetime(updated_at,'unixepoch','localtime')) last
   from threads
   group by model_provider, source
   order by last desc;"
```

### 查询当前目录旧 OpenAI 会话

```bash
cxr-list
```

### 交互选择当前目录旧 OpenAI 会话并用 CPA 恢复

```bash
cxr
```

### 跨目录搜索旧 OpenAI 会话

```bash
cxr-all <关键词>
```

### 查询当前目录及子目录

```bash
cxr --tree
```

### 指定来源和目标 provider

```bash
codex-resume-provider --from openai --to cpa
codex-resume-provider --from cpa --to cpa --list
```

### 直接用 UUID 和 CPA provider 恢复

```bash
codex resume -c 'model_provider="cpa"' <UUID>
```

如果需要保持当前脚本的 yolo 行为：

```bash
codex resume -c 'model_provider="cpa"' <UUID> --yolo
```
