生成时间: 2026-04-14T02:36:43+08:00

# Discord 网页端无法打开 App 的问题报告

## 1. Problem Description

Firefox 中从 Discord 网页端点击“打开 App”后，浏览器尝试跳转到：

```text
discord:///invite-proxy/1436768679780941874
```

但 Firefox 报错：

```text
无法理解该网址
Firefox 无法连接到 discord:///invite-proxy/1436768679780941874 的服务器。
```

目标是让 Fedora 桌面环境能正确识别 `discord:` URL scheme，并把它交给本地 Discord 客户端处理。

## 2. Environment and Scope

- 系统：Fedora
- 浏览器：Firefox
- 用户目录：`/home/chesszyh`
- Discord 可执行文件：`/home/chesszyh/Applications/Discord/Discord`
- 涉及配置：
  - `/home/chesszyh/.local/share/applications/discord.desktop`
  - `/home/chesszyh/.config/mimeapps.list`
  - `/home/chesszyh/.local/share/applications/mimeinfo.cache`

## 3. Symptoms and Reproduction

复现方式：

1. 打开 Discord 网页端。
2. 点击网页提供的“打开 App”入口。
3. Firefox 尝试打开 `discord:///invite-proxy/1436768679780941874`。
4. Firefox 报“无法理解该网址”。

该错误说明桌面环境或浏览器没有找到能处理 `discord:` scheme 的本地应用。

## 4. Investigation Timeline

1. 检查 `discord:` scheme 的默认处理器：

   ```bash
   xdg-mime query default x-scheme-handler/discord
   ```

   初始结果为空，说明没有注册 `x-scheme-handler/discord`。

2. 搜索本地 desktop entry 和 MIME 配置：

   ```bash
   rg -n "x-scheme-handler/discord|Discord|discord" \
     ~/.local/share/applications \
     ~/.config/mimeapps.list \
     ~/.local/share/applications/mimeapps.list \
     /usr/share/applications
   ```

   发现已有一个 server-specific handler：

   ```text
   x-scheme-handler/discord-1216669957799018608=discord-1216669957799018608.desktop
   ```

   但缺少通用的：

   ```text
   x-scheme-handler/discord
   ```

3. 检查现有 Discord launcher：

   ```bash
   sed -n '1,120p' ~/.local/share/applications/discord.desktop
   ```

   原 launcher 指向旧路径：

   ```ini
   Exec=/usr/share/discord/Discord
   ```

   并且没有声明：

   ```ini
   MimeType=x-scheme-handler/discord;
   ```

4. 确认用户实际 Discord 可执行文件存在：

   ```bash
   file ~/Applications/Discord/Discord
   ```

   结果显示它是可执行的 Linux ELF 文件。

## 5. Root Cause

根因有两个：

1. 系统没有为通用 `discord:` URL scheme 注册默认应用。
2. 本地 `discord.desktop` 是旧配置，`Exec` 指向 `/usr/share/discord/Discord`，不是当前实际存在的 `/home/chesszyh/Applications/Discord/Discord`。

`discord-1216669957799018608.desktop` 只处理 `discord-1216669957799018608:` 这种特定 scheme，不能处理网页端发出的 `discord:` scheme。

## 6. Changes Made

修改文件：

```text
/home/chesszyh/.local/share/applications/discord.desktop
```

关键内容改为：

```ini
Exec=/home/chesszyh/Applications/Discord/Discord %U
MimeType=x-scheme-handler/discord;
```

刷新 desktop database：

```bash
update-desktop-database ~/.local/share/applications
```

注册默认 URL handler：

```bash
xdg-mime default discord.desktop x-scheme-handler/discord
```

注册结果写入：

```text
/home/chesszyh/.config/mimeapps.list
```

新增或确认存在：

```ini
x-scheme-handler/discord=discord.desktop
```

## 7. Verification

验证默认 handler：

```bash
xdg-mime query default x-scheme-handler/discord
```

结果：

```text
discord.desktop
```

验证 GLib/GIO 视角下的 handler：

```bash
gio mime x-scheme-handler/discord
```

结果：

```text
Default application for “x-scheme-handler/discord”: discord.desktop
Registered applications:
	discord.desktop
Recommended applications:
	discord.desktop
```

验证 desktop entry：

```bash
desktop-file-validate ~/.local/share/applications/discord.desktop
```

命令退出码为 0，没有输出错误。

验证关键配置：

```bash
rg -n "^Exec=|^MimeType=|x-scheme-handler/discord" \
  ~/.local/share/applications/discord.desktop \
  ~/.config/mimeapps.list \
  ~/.local/share/applications/mimeinfo.cache
```

结果包含：

```text
/home/chesszyh/.local/share/applications/discord.desktop:6:Exec=/home/chesszyh/Applications/Discord/Discord %U
/home/chesszyh/.local/share/applications/discord.desktop:10:MimeType=x-scheme-handler/discord;
/home/chesszyh/.config/mimeapps.list:126:x-scheme-handler/discord=discord.desktop
/home/chesszyh/.local/share/applications/mimeinfo.cache:27:x-scheme-handler/discord=discord.desktop;
```

## 8. Problems Encountered During Debugging

- 一开始系统中存在一个看起来像 Discord 相关的 handler：`discord-1216669957799018608.desktop`，但它不是 `discord:` 通用 scheme 的 handler。
- `discord.desktop` 文件存在，但内容陈旧，`Exec` 指向不存在或不适用的 `/usr/share/discord/Discord`。
- Firefox 的错误信息表现为“无法理解该网址”，真正问题不在 Discord invite 链接本身，而在 Linux 桌面环境的 URL scheme 注册。

## 9. Reuse Notes and Lessons

- Linux 桌面应用处理自定义 URL scheme 依赖 `.desktop` 文件的 `MimeType` 和 XDG MIME 默认应用配置。
- 对 `discord:///...` 这种链接，应检查 `x-scheme-handler/discord`，不是只搜索 `discord` 字符串。
- AppImage、手动安装或移动过路径的应用，常见问题是 `.desktop` 文件还指向旧的可执行文件路径。
- Firefox 报“不理解该网址”时，优先检查：
  - `xdg-mime query default x-scheme-handler/<scheme>`
  - `.desktop` 文件是否有 `MimeType=x-scheme-handler/<scheme>;`
  - `.desktop` 文件的 `Exec` 是否能接收 `%u` 或 `%U`

## 10. Appendix: Reusable Commands

检查 scheme 默认处理器：

```bash
xdg-mime query default x-scheme-handler/discord
gio mime x-scheme-handler/discord
```

搜索相关配置：

```bash
rg -n "x-scheme-handler/discord|Discord|discord" \
  ~/.local/share/applications \
  ~/.config/mimeapps.list \
  ~/.local/share/applications/mimeapps.list \
  /usr/share/applications
```

检查 Discord launcher：

```bash
sed -n '1,120p' ~/.local/share/applications/discord.desktop
desktop-file-validate ~/.local/share/applications/discord.desktop
```

刷新 desktop database：

```bash
update-desktop-database ~/.local/share/applications
```

注册默认 handler：

```bash
xdg-mime default discord.desktop x-scheme-handler/discord
```

手动测试链接：

```bash
xdg-open 'discord:///invite-proxy/1436768679780941874'
```
