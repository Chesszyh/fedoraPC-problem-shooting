# CLIProxyAPI Codex 非流式 `content:null` 问题排查报告

生成时间: 2026-04-14T02:19:02+08:00

## 1. Problem Description

本次排查的问题是：在 CLIProxyAPI 中使用 `codex` 类型账号，通过 OpenAI-compatible `/v1/chat/completions` 调用 GPT-5 系列模型时，非流式请求返回 HTTP `200 OK`，但响应中的 `choices[0].message.content` 为 `null`；同一请求改为 `stream=true` 时可以正常看到文本输出，例如 `OK`。

用户在 `git pull` 并重新编译后观察到该问题似乎消失，因此需要确认：

- 本地 pull 前后到底跨过了哪些提交。
- GitHub issue `router-for-me/CLIProxyAPI#2583` 是否描述同一问题。
- 到底是哪一个提交的哪一处改动修复了该问题。

## 2. Environment and Scope

仓库路径：

```bash
/home/chesszyh/cliproxyapi/refs/source-code-plus
```

当前 HEAD：

```text
1d8e68ad15920875ae09d8b3941bfaa7a330eba6
```

pull 前提交：

```text
75da02af556c7f58052f692da0f203dac5220ef5
```

本次排查关注范围：

- Codex executor 非流式执行路径。
- OpenAI-compatible `/v1/chat/completions` 非流式响应转换。
- GitHub issue `#2583` 与关闭该 issue 的提交。

关键文件：

```text
/home/chesszyh/cliproxyapi/refs/source-code-plus/internal/runtime/executor/codex_executor.go
/home/chesszyh/cliproxyapi/refs/source-code-plus/internal/runtime/executor/codex_executor_stream_output_test.go
/home/chesszyh/cliproxyapi/refs/source-code-plus/internal/translator/codex/openai/chat-completions/codex_openai_response.go
```

## 3. Symptoms and Reproduction

issue `#2583` 中给出的最小复现请求是：

```bash
curl -sS http://127.0.0.1:8317/v1/chat/completions \
  -H 'Authorization: Bearer <proxy-api-key>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"gpt-5.4-mini",
    "messages":[{"role":"user","content":"Say ok"}]
  }'
```

异常表现：

```json
{
  "choices": [
    {
      "message": {
        "role": "assistant",
        "content": null,
        "reasoning_content": null,
        "tool_calls": null
      },
      "finish_reason": "stop",
      "native_finish_reason": "stop"
    }
  ]
}
```

同一请求如果启用 `stream=true`，可以在 SSE delta 中看到正常文本，例如：

```text
data: {"choices":[{"delta":{"role":"assistant","content":"Ok"}}]}
```

这说明模型实际产生了文本，问题不在上游模型是否回答，而在代理的非流式聚合或转换路径。

## 4. Investigation Timeline

1. 检查本地 reflog，确认最近一次 pull 是 fast-forward：

```text
1d8e68ad HEAD@{2026-04-14 01:22:49 +0800}: pull: Fast-forward
75da02af HEAD@{2026-04-02 23:14:14 +0800}: pull: Fast-forward
```

2. 检查 `ORIG_HEAD`，确认 pull 前提交为：

```text
75da02af556c7f58052f692da0f203dac5220ef5
```

3. 生成 pull 跨过的提交列表：

```bash
git log --oneline --decorate --reverse 75da02af..1d8e68ad
```

结果显示本次 pull 跨过 `131` 个提交。完整列表保存于：

```text
/tmp/cliproxyapi-pull-75da02af-to-1d8e68ad.txt
```

4. 在跨过的提交中筛选相关路径：

```bash
git log --oneline --decorate --reverse 75da02af..1d8e68ad -- \
  internal/runtime/executor/codex_executor.go \
  internal/runtime/executor/codex_executor_stream_output_test.go \
  internal/translator/codex/openai/chat-completions/codex_openai_response.go
```

相关结果只有：

```text
c8b7e2b8 fix(executor): ensure empty stream completions use output_item.done as fallback
```

5. 阅读 GitHub issue `#2583`，确认 issue 标题和用户症状一致：

```text
bug: codex 非流式 /v1/chat/completions 返回 200 但 message.content 为 null
```

6. issue 正文指出的根因是：Codex non-stream 路径被代理侧强制改为 `stream=true`；executor 读取完整 SSE 后只取最后一条 `response.completed`；前面的输出事件被丢弃；如果 `response.completed.response.output` 为空，则最终 OpenAI-compatible 响应保留 `content:null`。

7. issue 页面显示该 issue 被提交 `c8b7e2b8d6f24462b724925dfe4f984ae6b9e302` 关闭。

8. 阅读 `c8b7e2b8` diff，确认其改动集中在 `internal/runtime/executor/codex_executor.go`，并新增回归测试 `internal/runtime/executor/codex_executor_stream_output_test.go`。

## 5. Root Cause

根因不是客户端请求构造错误，也不是上游模型未生成文本，而是 CLIProxyAPI 的 Codex 非流式执行路径与上游 SSE 响应结构之间存在不匹配。

旧逻辑的问题链路：

1. 用户发起非流式 `/v1/chat/completions` 请求。
2. Codex executor 内部向上游发起的请求实际按流式 SSE 读取。
3. executor 读取完整 SSE 后，只把 `response.completed` 事件交给 `TranslateNonStream(...)`。
4. 如果上游最终的 `response.completed.response.output` 是空数组，即使前面已经通过 `response.output_item.done` 或 delta 事件输出过文本，translator 也拿不到文本。
5. OpenAI chat completions 非流式 translator 的模板默认包含 `choices[0].message.content = null`。
6. translator 只有从 `response.output[].content[].type == "output_text"` 提取到文本时才会覆盖该字段。
7. 因为 `response.output` 为空，覆盖没有发生，最终返回 `content:null`。

关键转换代码位于：

```text
internal/translator/codex/openai/chat-completions/codex_openai_response.go
```

该文件中的非流式转换函数会读取：

```text
response.output[*].content[*].type == "output_text"
```

因此修复点应在 executor 层保证传入 translator 的 `response.completed.response.output` 包含已完成的输出项。

## 6. Changes Made

本次排查没有修改项目代码，只定位了已经由上游合入的修复。

真正修复问题的提交：

```text
c8b7e2b8d6f24462b724925dfe4f984ae6b9e302
fix(executor): ensure empty stream completions use output_item.done as fallback
Fixed: #2583
```

该提交的核心改动：

- 在 `codex_executor.go` 中读取 SSE 时，不再只等待 `response.completed`。
- 新增 `outputItemsByIndex` 和 `outputItemsFallback`，收集 `response.output_item.done` 事件中的 `item`。
- 当遇到 `response.completed` 时，检查 `response.output` 是否不存在、不是数组或为空数组。
- 如果最终 `response.output` 为空且之前收集到了 output items，则用 `sjson.SetRawBytes` 构造 `response.output` 数组。
- 对有 `output_index` 的 item 按索引排序后写入，保证输出顺序稳定。
- 将 patched `completedData` 传给 `sdktranslator.TranslateNonStream(...)`。

关键旧逻辑：

```go
line = bytes.TrimSpace(line[5:])
if gjson.GetBytes(line, "type").String() != "response.completed" {
    continue
}
out := sdktranslator.TranslateNonStream(ctx, to, from, req.Model, originalPayload, body, line, &param)
```

关键新逻辑：

```go
if eventType == "response.output_item.done" {
    itemResult := gjson.GetBytes(eventData, "item")
    outputIndexResult := gjson.GetBytes(eventData, "output_index")
    if outputIndexResult.Exists() {
        outputItemsByIndex[outputIndexResult.Int()] = []byte(itemResult.Raw)
    } else {
        outputItemsFallback = append(outputItemsFallback, []byte(itemResult.Raw))
    }
    continue
}
```

以及：

```go
shouldPatchOutput := (!outputResult.Exists() || !outputResult.IsArray() || len(outputResult.Array()) == 0) &&
    (len(outputItemsByIndex) > 0 || len(outputItemsFallback) > 0)

if shouldPatchOutput {
    completedDataPatched, _ = sjson.SetRawBytes(completedDataPatched, "response.output", []byte(`[]`))
    ...
    completedData = completedDataPatched
}

out := sdktranslator.TranslateNonStream(ctx, to, from, req.Model, originalPayload, body, completedData, &param)
```

新增的回归测试：

```text
internal/runtime/executor/codex_executor_stream_output_test.go
```

测试构造的上游响应是：

- 先发 `response.output_item.done`，其中 `item.content[0].text` 为 `"ok"`。
- 再发 `response.completed`，其中 `response.output` 是空数组。
- 断言 executor 的非流式输出中 `choices[0].message.content == "ok"`。

## 7. Verification

运行直接覆盖该修复的测试：

```bash
GOTOOLCHAIN=auto go test -run TestCodexExecutorExecute_EmptyStreamCompletionOutputUsesOutputItemDone ./internal/runtime/executor
```

结果：

```text
ok  	github.com/router-for-me/CLIProxyAPI/v6/internal/runtime/executor	(cached)
```

同时运行相关 OpenAI chat completions translator 测试：

```bash
GOTOOLCHAIN=auto go test -run 'TestConvertCodexResponseToOpenAI_(ToolCallChunkOmitsNullContentFields|ToolCallArgumentsDeltaOmitsNullContentFields)' ./internal/translator/codex/openai/chat-completions
```

结果：

```text
ok  	github.com/router-for-me/CLIProxyAPI/v6/internal/translator/codex/openai/chat-completions	(cached)
```

注意：直接 `go test` 曾失败，因为本地默认 Go 版本为 `1.25.9`，而仓库 `go.mod` 要求 `go >= 1.26.0`。使用 `GOTOOLCHAIN=auto` 后测试通过。

失败信息：

```text
go: go.mod requires go >= 1.26.0 (running go 1.25.9; GOTOOLCHAIN=local)
```

## 8. Problems Encountered During Debugging

1. 初看最近 20 个提交时，没有直接看到 `chat/completions content:null` 字样，容易误判为没有相关修复。

2. 另一个相关提交 `d475aaba` 也涉及 `content:null`，但它修的是流式 tool call chunk 中不要输出 `delta.content:null`，不是本次非流式最终 `message.content:null` 的根因。

3. issue 正文中提到的理想修复方案是聚合 `response.output_text.delta`、reasoning delta 和 tool-call 参数增量；但主线实际合入的是更小的 fallback 修复：使用 `response.output_item.done` 补齐空的 `response.completed.response.output`。这两者不能混淆。

4. 本地默认 Go 工具链版本低于项目要求，直接运行测试会失败，需要使用：

```bash
GOTOOLCHAIN=auto go test ...
```

5. pull 跨过的提交较多，共 `131` 个，需要用路径限定筛选相关提交，否则容易被大量无关 Qwen、Claude、Antigravity、docs 变更干扰。

## 9. Reuse Notes and Lessons

1. 当非流式 API 实际底层使用 SSE 流式上游时，不能假设最终 completed event 一定包含完整输出。应检查上游协议是否通过 `output_item.done` 或 delta 事件承载正文。

2. 看到 `choices[0].message.content = null` 时，需要区分两类问题：

- translator 模板默认值没有被覆盖。
- 上游或 executor 传给 translator 的源数据本身缺少可提取字段。

3. 对 OpenAI-compatible non-stream 响应，关键证据不是 HTTP 状态码，而是传入 translator 的 `response.output` 是否含有 `output_text`。

4. 对 GitHub issue 与本地代码进行归因时，应优先查：

- issue 关闭事件指向的 commit。
- pull 前后的 commit range。
- 相关路径在 range 内的修改记录。
- 新增回归测试是否复现了用户症状。

5. 本次问题的最终判断：

```text
用户 pull 后问题消失，是因为本地从 75da02af 更新到 1d8e68ad 的过程中包含了 c8b7e2b8。
c8b7e2b8 在 Codex executor 非流式路径中把 response.output_item.done 作为 response.completed.output 为空时的 fallback。
这使 translator 能从 response.output 中提取 output_text，从而覆盖默认 content:null。
```

## 10. Appendix: Reusable Commands

### 确认 pull 前后边界

```bash
git reflog --date=iso -n 30
git rev-parse HEAD ORIG_HEAD
```

### 列出 pull 跨过的提交

```bash
git log --oneline --decorate --reverse ORIG_HEAD..HEAD
git rev-list --count ORIG_HEAD..HEAD
```

本次固定边界版本：

```bash
git log --oneline --decorate --reverse 75da02af..1d8e68ad
git rev-list --count 75da02af..1d8e68ad
```

### 筛选和 Codex 非流式问题相关的提交

```bash
git log --oneline --decorate --reverse 75da02af..1d8e68ad -- \
  internal/runtime/executor/codex_executor.go \
  internal/runtime/executor/codex_executor_stream_output_test.go \
  internal/translator/codex/openai/chat-completions/codex_openai_response.go
```

### 查看修复提交 diff

```bash
git show c8b7e2b8d6f24462b724925dfe4f984ae6b9e302 -- \
  internal/runtime/executor/codex_executor.go \
  internal/runtime/executor/codex_executor_stream_output_test.go
```

### 查看 issue 关闭提交是否在当前分支

```bash
git merge-base --is-ancestor c8b7e2b8d6f24462b724925dfe4f984ae6b9e302 HEAD && echo yes
git branch --contains c8b7e2b8d6f24462b724925dfe4f984ae6b9e302
git tag --contains c8b7e2b8d6f24462b724925dfe4f984ae6b9e302 --sort=creatordate
```

### 运行直接回归测试

```bash
GOTOOLCHAIN=auto go test -run TestCodexExecutorExecute_EmptyStreamCompletionOutputUsesOutputItemDone ./internal/runtime/executor
```

### 运行相关 translator 测试

```bash
GOTOOLCHAIN=auto go test -run 'TestConvertCodexResponseToOpenAI_(ToolCallChunkOmitsNullContentFields|ToolCallArgumentsDeltaOmitsNullContentFields)' ./internal/translator/codex/openai/chat-completions
```

### 复现 issue 请求

```bash
curl -sS http://127.0.0.1:8317/v1/chat/completions \
  -H 'Authorization: Bearer <proxy-api-key>' \
  -H 'Content-Type: application/json' \
  -d '{
    "model":"gpt-5.4-mini",
    "messages":[{"role":"user","content":"Say ok"}]
  }'
```
