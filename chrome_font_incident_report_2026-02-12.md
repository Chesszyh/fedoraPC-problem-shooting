# Chrome 中文字体故障修复报告

- 日期：2026-02-12
- 环境：Fedora Linux 43（Wayland），Google Chrome 145.0.7632.45
- 现象：Chrome 中文出现方块字（tofu），Firefox 正常；后续在一次字体替换过程中，waybar/VSCode/浏览器曾短暂崩溃。

## 1. 故障现象

1. Chrome 侧边栏与字体预览中的中文显示为方块。
2. 仅“霞鹜文楷”相关字体异常，其他中文字体可正常显示。
3. Firefox 同期可正常显示中文，说明系统中文渲染链路总体可用。

## 2. 排查结论

1. `~/.local/share/fonts` 中原有霞鹜字体文件为旧版本（约 19MB）。
2. 用户重新下载的字体文件为新版本（约 25MB），哈希与旧文件不同。
3. 旧版霞鹜字体在当前 Chrome 版本下存在兼容性问题（或触发特定渲染路径问题），导致仅该字体在 Chrome 中表现为方块。

## 3. 处置动作

1. 备份旧字体：
   - `~/.local/share/fonts/LXGWWenKai-Regular.ttf.bak-20260212`
   - `~/.local/share/fonts/LXGWWenKaiMono-Regular.ttf.bak-20260212`
2. 覆盖安装新字体：
   - `~/Downloads/fonts/LXGWWenKai-Regular.ttf` -> `~/.local/share/fonts/LXGWWenKai-Regular.ttf`
   - `~/Downloads/fonts/LXGWWenKaiMono-Regular.ttf` -> `~/.local/share/fonts/LXGWWenKaiMono-Regular.ttf`
3. 重建字体缓存：
   - `fc-cache -rv ~/.local/share/fonts`
4. 重启相关 GUI 应用后验证：Chrome/Firefox 中文显示恢复正常。

## 4. 为什么出现“瞬时崩溃”

1. 本次为在线热替换字体文件并同步刷新 fontconfig 缓存。
2. 在字体文件被覆盖和缓存刷新窗口期，桌面程序（waybar、VSCode、浏览器）可能读取到临时不一致状态，导致崩溃或重启。
3. 程序重启后重新加载完整字体与新缓存，状态恢复稳定。

## 5. 最终结果

1. 字体故障已修复。
2. Chrome 中文显示恢复正常。
3. Firefox 及其他应用在重启后恢复正常。

## 6. 后续建议

1. 字体升级尽量采用“冷切换”：先关闭主要 GUI 程序，再替换字体、执行 `fc-cache`，最后重启会话。
2. 保留本次备份文件至少 7 天，确认稳定后再清理。
3. 如后续再次异常，优先临时切换 `Noto Sans CJK SC`/`Source Han Sans CN`，再排查特定字体兼容性。

