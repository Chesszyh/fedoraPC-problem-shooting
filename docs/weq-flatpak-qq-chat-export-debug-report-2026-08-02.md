# WeQ 导出 Flatpak Linux QQ 聊天记录排障简报

生成时间: 2026-08-02T19:37:49+08:00

## 1. 问题描述

目标是使用 `/home/chesszyh/Project/WeQ` 解密用户自己的 Flatpak Linux QQ 本地数据库，并通用导出个人或群组聊天记录。旧代理留下的 `/home/chesszyh/Project/WeQ/HANDOFF.md` 完成了部分环境定位，但没有取得数据库密钥，也没有生成聊天导出。

本报告只保留失败原因和调试证据。最终可复用流程位于 `/home/chesszyh/.codex/skills/weq-export-qq-chats/SKILL.md`。

## 2. 环境和范围

- Fedora/Hyprland，QQ 通过 Flatpak 应用 `com.qq.QQ` 运行。
- WeQ 工作区：`/home/chesszyh/Project/WeQ`。
- QQ 数据位于 Flatpak 用户数据目录；账号、联系人、群号、UID 和密钥均不写入本报告。
- 数据库仅以只读方式打开；现有持久密钥保留，不进行例行清理。
- 不修改聊天数据库，不提交或发布导出的私密内容。

## 3. 现象和复现

旧代理主要遇到以下现象：

- 向 Flatpak QQ 的运行中进程注入时出现 `SIGSEGV`。
- 宿主 namespace 找不到 `mojo.<pid>.control.sock`。
- 进入 QQ namespace 后虽然能看到 socket，请求仍返回 `Connection refused`。
- `injectAndGetStatusEmbedded` 得到 `loggedIn=false, uin=0`，与宿主侧在线探测矛盾。
- 临时改成 CommonJS loader 后能读到登录列表，但 quick-login 报“登录状态已过期，请重新登录”；后续还出现“下载最新 QQ”。

这些现象可从 `/home/chesszyh/Project/WeQ/HANDOFF.md` 复核。

## 4. 调查时间线

1. 旧代理确认了 Flatpak 应用、数据根、消息数据库和 native 模块可加载，排除了依赖安装与基本路径错误。
2. 旧代理尝试宿主 PID 注入、切换 PID/mount/network namespace，以及控制 socket 请求；均未形成可靠取钥通道。
3. 旧代理发现仓库 `type: module` 会使 QQ 期望的 CommonJS loader 失效；改用 `.cjs` 后 loader 能启动，但仍受登录流程阻断。
4. 后续调试放弃把运行中 Flatpak 进程注入作为主路径，改为使用同一安装中的 QQ 主程序启动独立扫码取钥流程。
5. 从当前安装的 `major.node` 动态解析 `appid` 和 `QUA`，并显式传入 Flatpak 数据根，解决“下载最新 QQ”所代表的客户端身份参数不匹配问题。
6. 密钥成功取得并保存后，先验证密钥，再以只读方式打开数据库；导出脚本同时覆盖历史 UID 分区、按消息 ID 去重，并生成 TXT、JSONL 和元数据。
7. 第一次导出后发现近期消息不全；等待 QQ 完成本地同步后重新导出，记录由 358 条增加到 403 条。新增 45 条是新近同步到本地数据库的行，而非导出器漏读。
8. 最终把发现、复用密钥、必要时扫码、批量导出和完整性检查收敛为通用 Skill。

## 5. 根因

失败并非单一的“QQ 未登录”：

- **运行中注入路径不可靠**：宿主与 Flatpak 沙箱的 PID、mount 和 socket namespace 不一致。宿主侧能探测在线，不代表 native 控制 socket 可从同一上下文访问。
- **备用登录参数发生漂移**：quick-login 能读到账号列表，但使用的客户端身份上下文不能完成当前登录。提示“下载最新 QQ”实际对应 `appid/QUA` 与已安装 QQ 不匹配，不能简单认定 Flatpak 包本身必须升级。
- **同步完整性与导出完整性是两件事**：`complete: true` 只能证明当前本地数据库行全部导出，不能证明 QQ 已把服务端近期历史同步到本地。

## 6. 所做更改

- 保留项目内通用 CLI：
  - `/home/chesszyh/Project/WeQ/scripts/extract-qq-key.mts`
  - `/home/chesszyh/Project/WeQ/scripts/export-chats.mts`
- 创建可复用 Skill：`/home/chesszyh/.codex/skills/weq-export-qq-chats/`。
- Skill 不写死账号、联系人、群号、UID、Flatpak commit 或数据库密钥。
- 密钥默认保存于权限受限的用户数据目录并优先复用；只有密钥缺失或校验失败时才要求停止精确 PID 并扫码。
- 本报告加入 `/home/chesszyh/Documents/Reports/docs/index.md` 的“开发工具与应用”分类。

## 7. 验证

- Skill 通过 `quick_validate.py` 结构校验。
- 三个 Skill TypeScript 脚本通过 Biome 检查。
- QQ 在线时运行密钥提取入口返回 `reused: true`，没有停止 QQ 或要求再次扫码。
- 实际私聊前向测试导出 403 条；`rawMessageCount`、`exportedUniqueCount` 与 JSONL 唯一 `msgId` 数均为 403，且 `complete: true`。
- 临时测试目录已删除；WeQ 工作区已有未跟踪文件和历史导出保持不变。

## 8. 调试中遇到的问题

- 旧代理在 namespace 注入路径上进行了多轮低收益尝试；这些尝试证明了该路径不可靠，但不能继续作为部署主方案。
- ESM/CommonJS loader 差异是一个真实问题，但修复 loader 后仍有登录参数漂移，因此它不是完整根因。
- 登录错误文案具有误导性：“下载最新 QQ”需要先核对当前安装中的 `appid/QUA`，不能直接升级并破坏已验证环境。
- 初次导出的近期空缺容易误判为导出器丢消息；必须区分“本地数据库是否全部导出”和“数据库是否已同步完整”。
- WeQ 的 `nt_helper.node` 存在约 30 天构建过期检查；固定 QQ 版本只能减少兼容漂移，不能让流程永久免维护。

## 9. 复用说明和经验

- 后续直接调用 `$weq-export-qq-chats`，目标使用 `c2c:<QQ号>` 或 `group:<群号>`，可一次传入多个目标。
- 首先运行检查并复用已验证密钥；不要每次删除密钥或重复扫码。
- 怀疑近期消息缺失时，先让 QQ 完成同步，再比较两次 JSONL 的 `msgId` 集合和时间范围；不要先阅读或泄露正文。
- 固定 QQ 版本后仍需关注 native helper 过期、密钥轮换、Flatpak runtime 变化和本地同步延迟。
- 不再扩展旧 `HANDOFF.md`；成功流程以 Skill 为唯一操作说明，本报告只承担简要复盘用途。

## 10. 附录：可复用命令

检查环境和现有密钥：

```bash
WEQ_REPO=/absolute/path/to/WeQ
SKILL_DIR=/home/chesszyh/.codex/skills/weq-export-qq-chats
rtk pnpm --dir "$WEQ_REPO" exec tsx "$SKILL_DIR/scripts/inspect.mts" "$WEQ_REPO"
```

仅在密钥缺失或失效、且精确停止 QQ 主进程后取钥：

```bash
rtk pnpm --dir "$WEQ_REPO" exec tsx "$SKILL_DIR/scripts/extract-key.mts" "$WEQ_REPO" <uin>
```

批量导出个人与群聊：

```bash
rtk pnpm --dir "$WEQ_REPO" exec tsx "$SKILL_DIR/scripts/export-chats.mts" \
  "$WEQ_REPO" <uin> <output-root> c2c:<QQ号> group:<群号>
```

详细边界和故障分流见 `/home/chesszyh/.codex/skills/weq-export-qq-chats/references/troubleshooting.md`。
