生成时间: 2026-04-17T14:04:48+08:00

# Playwright Chromium 安装卡住问题报告

## 1. Problem Description

在 `/Users/chesszyh987/.hermes` 目录执行 `npx playwright install chromium` 时，命令几乎没有有效输出，也没有开始明显下载；更换代理节点后现象不变。需要确认问题是网络、代理、目录上下文，还是本机 Playwright 缓存状态导致。

## 2. Environment and Scope

- 操作系统：macOS
- 工作目录：`/Users/chesszyh987/.hermes`
- 实际 Node 项目目录：`/Users/chesszyh987/.hermes/hermes-agent`
- Node：`v22.17.0`
- npm / npx：`11.5.2`
- Playwright CLI：`/Users/chesszyh987/.hermes/hermes-agent/node_modules/.bin/playwright`
- Playwright 版本：`1.59.1`
- 默认浏览器缓存目录：`/Users/chesszyh987/Library/Caches/ms-playwright`
- 代理环境：npm 与系统已配置 `127.0.0.1:7897`

本次排查只处理 Playwright 浏览器安装问题，不涉及 Hermes 源码修改。

## 3. Symptoms and Reproduction

复现命令：

```bash
cd /Users/chesszyh987/.hermes
npx playwright install chromium
```

复现现象：

- 表面上“没有反应”，用户看不到正常下载进度。
- 在 `.hermes` 根目录执行时，Playwright 会提示当前目录并不是已安装依赖的项目目录。
- 在真实项目目录 `/Users/chesszyh987/.hermes/hermes-agent` 内，命令也会卡住，但没有明显网络报错。

关键现象：

```text
WARNING: It looks like you are running 'npx playwright install' without first installing your project's dependencies.
```

## 4. Investigation Timeline

1. 先确认 Node/npm/npx 基本可用，排除本地运行时损坏。
2. 搜索当前工作区内的 `package.json`，确认真正的 Node 项目不在 `.hermes` 根目录，而在 `/Users/chesszyh987/.hermes/hermes-agent`。
3. 验证项目本地已有 Playwright 依赖和 CLI：

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./node_modules/.bin/playwright --version
```

得到：

```text
Version 1.59.1
```

4. 检查默认浏览器缓存目录 `~/Library/Caches/ms-playwright`，发现历史浏览器文件和标记文件为 `root` 所有。
5. 验证 npm registry 可访问，确认不是节点或 npm 出口问题。
6. 使用临时用户可写目录做对照试验：

```bash
PLAYWRIGHT_BROWSERS_PATH=/tmp/hermes-pw-browsers-test \
  ./node_modules/.bin/playwright install chromium
```

该命令立即开始下载，证明 Playwright CDN、代理链路、Node 环境都正常。
7. 因为临时目录能立即下载，而默认缓存目录会卡住，根因被收敛到 `~/Library/Caches/ms-playwright` 的权限/状态异常。
8. 使用管理员权限删除并重建默认缓存目录，再在真实项目目录重试安装。
9. 安装恢复正常，浏览器成功下载到默认路径，且目录所有权恢复为当前用户。

## 5. Root Cause

根因由两部分组成：

1. **目录上下文不对**
   - 用户最初在 `/Users/chesszyh987/.hermes` 根目录执行 `npx playwright install chromium`。
   - 这个目录本身不是 Playwright 依赖所在项目目录，所以会触发 Playwright 的依赖警告，造成“命令不对劲”的第一层混淆。

2. **默认浏览器缓存目录被 `root` 污染**
   - `~/Library/Caches/ms-playwright` 下已有旧的浏览器安装目录，且所有者为 `root`。
   - Playwright 在默认路径上处理现有缓存时无法正常清理/覆盖，表现为安装流程卡住或无明显输出。
   - 这不是网络问题，因为改用临时的用户可写目录后，下载会立刻开始。

因此，真正导致“无法下载”的核心原因不是代理节点，而是**默认缓存目录权限异常**；而在错误目录执行命令放大了排查难度。

## 6. Changes Made

执行了以下修复：

1. 删除并重建默认缓存目录：

```bash
sudo rm -rf "$HOME/Library/Caches/ms-playwright"
mkdir -p "$HOME/Library/Caches/ms-playwright"
chown "$USER":staff "$HOME/Library/Caches/ms-playwright"
```

2. 在真实项目目录重新安装 Chromium：

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./node_modules/.bin/playwright install chromium
```

3. 未修改 Hermes 源码，未修改 Playwright 包版本。

## 7. Verification

### 7.1 默认路径安装恢复

重新执行安装后，Playwright 立即进入下载流程，并输出正常进度：

```text
pw:install downloading Chrome for Testing 147.0.7727.15
```

安装完成后的关键输出：

```text
SUCCESS installing Chrome Headless Shell 147.0.7727.15
validation passed for chromium
validation passed for ffmpeg
validation passed for chromium-headless-shell
```

### 7.2 默认缓存目录所有权恢复正常

验证命令：

```bash
ls -ld "$HOME/Library/Caches/ms-playwright" "$HOME/Library/Caches/ms-playwright"/*
```

结果要点：

```text
drwxr-xr-x@ ... chesszyh987 staff ... /Users/chesszyh987/Library/Caches/ms-playwright
drwxr-xr-x@ ... chesszyh987 staff ... /Users/chesszyh987/Library/Caches/ms-playwright/chromium-1217
drwxr-xr-x@ ... chesszyh987 staff ... /Users/chesszyh987/Library/Caches/ms-playwright/chromium_headless_shell-1217
```

### 7.3 项目目录 dry-run 正常

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./node_modules/.bin/playwright install --dry-run chromium
```

输出正确列出安装位置：

```text
Install location: /Users/chesszyh987/Library/Caches/ms-playwright/chromium-1217
```

### 7.4 根目录 dry-run 仍会警告，但不再是故障

```bash
cd /Users/chesszyh987/.hermes
npx --yes playwright install --dry-run chromium
```

结果会提示该目录不是已安装 Playwright 依赖的项目目录。这是使用方式提醒，不再是下载故障本身。

## 8. Problems Encountered During Debugging

- 最初容易把问题归因为代理节点或 CDN 出口，因为表面症状是“不下载”。
- `.hermes` 根目录与 `hermes-agent` 项目目录并存，容易误以为“当前目录”就是正确执行位置。
- 默认缓存目录里残留的是旧版本浏览器且为 `root` 所有，不是简单的“文件缺失”，而是“历史安装状态损坏”。
- 普通 `rm -rf ~/Library/Caches/ms-playwright` 无法清掉所有内容，会报大量 `Permission denied`，进一步证明目录权限异常。

## 9. Reuse Notes and Lessons

- Playwright 安装问题不要先假设是网络；先验证：
  - 当前目录是不是实际 Node 项目目录；
  - Playwright CLI 是否来自项目本地 `node_modules/.bin`；
  - 默认缓存目录是否可写；
  - 临时 `PLAYWRIGHT_BROWSERS_PATH` 是否能立即下载。
- 如果临时目录可下载，而默认目录不行，优先检查 `~/Library/Caches/ms-playwright` 的所有权和历史残留。
- 在多项目工作区中，优先从实际项目目录执行：

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
npx playwright install chromium
```

- 如果未来再次出现类似问题，最快的判别手段是：
  1. `ls -ld ~/Library/Caches/ms-playwright*`
  2. 用临时 `PLAYWRIGHT_BROWSERS_PATH` 做一次对照安装

## 10. Appendix: Reusable Commands

### A. 确认真实项目目录

```bash
find /Users/chesszyh987/.hermes -name package.json -maxdepth 3
```

### B. 确认 Playwright CLI 来自本地项目

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./node_modules/.bin/playwright --version
```

### C. 检查默认缓存目录权限

```bash
ls -ld "$HOME/Library/Caches/ms-playwright" "$HOME/Library/Caches/ms-playwright"/*
```

### D. 用临时目录判断是否为默认缓存目录问题

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
PLAYWRIGHT_BROWSERS_PATH=/tmp/hermes-pw-browsers-test \
  ./node_modules/.bin/playwright install chromium
```

### E. 清理损坏的默认缓存并重建

```bash
sudo rm -rf "$HOME/Library/Caches/ms-playwright"
mkdir -p "$HOME/Library/Caches/ms-playwright"
chown "$USER":staff "$HOME/Library/Caches/ms-playwright"
```

### F. 正确执行安装

```bash
cd /Users/chesszyh987/.hermes/hermes-agent
./node_modules/.bin/playwright install chromium
```
