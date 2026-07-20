# Fedora 上 Nekopara Vol.1、Bottles 与 LunaTranslator 多层兼容问题排障报告

生成时间: 2026-07-16T22:05:30+08:00

## 1. 问题描述

在 Fedora 43 + Hyprland 主机上直接运行 `Nekopara Vol.1` 的 Windows 版本时，游戏在序章收尾处完全卡死，画面和输入均无响应。为了绕过系统 Wine 的问题，随后改用 Bottles + Soda 9.0-1，又依次出现以下故障：

- Bottles 选择 EXE 后无可见反应；
- 游戏启动后整台桌面明显卡顿；
- 全屏窗口只有左上约四分之一正常绘制，其余区域黑屏；
- LunaTranslator 中文界面显示为方块字；
- LunaTranslator 能发现 `nekopara_vol1.exe`，但确认 HOOK 后自身异常退出。

这不是一个单点缺少 DLL 的问题，而是旧 KiriKiri/DirectShow 游戏、Wine 媒体管线、高刷高分屏、Bottles Flatpak 权限和跨位数 HOOK 注入叠加形成的兼容链。综合成本后，最终决定将游戏和 LunaTranslator 一并迁移到 Windows 虚拟机，而不是继续扩大 Wine 侧改动。

## 2. 环境与范围

主机与显示环境：

- Fedora 43，Hyprland + XWayland；
- NVIDIA GPU，显示器分辨率 `2560×1600`，刷新率约 `240 Hz`；
- 物理内存约 `15 GiB`，事发时仍有约 `8.5 GiB` 可用；
- 游戏目录：`/home/chesszyh/Games/Nekopara/NekoPara Vol.1`；
- 游戏存档目录：`/home/chesszyh/Games/Nekopara/NekoPara Vol.1/savedata`；
- LunaTranslator：`/home/chesszyh/Games/LunaTranslator_x64`。

相关软件：

- 系统 Wine：`wine-11.0`；
- Bottles：Flatpak `com.usebottles.bottles`；
- Bottle：`Nekopara`，Windows 10、win64；
- Soda runner：`wine-experimental.bleeding.edge.9.0.93696.20240429 (TkG Plain)`；
- LunaTranslator：`10.16.0.11`，64 位；
- 游戏主程序：32 位 PE，KiriKiri Z `1.2.0.3`；
- 关键插件：`plugin/krmovie.dll`、`plugin/AlphaMovie.dll`。

游戏是 32 位程序，LunaTranslator 是 64 位程序，但 Luna 包内存在 `files/LunaSubprocess32.exe` 和 `files/LunaHook/LunaHook32.dll`，设计上具备注入 32 位游戏的能力。

## 3. 症状与复现

### 3.1 系统 Wine 下的序章末尾卡死

1. 通过文件管理器的 Wine Windows Program Loader 启动 `nekopara_vol1.exe`；
2. 正常游玩约 1 小时 20 分钟；
3. 到达序章收尾、即将播放 OP/过场视频的位置；
4. 画面完全静止，鼠标和键盘均无法使游戏继续。

注意：进程的 `ELAPSED≈01:22` 表示总运行时间，不等于已经卡死 1 小时 22 分钟。排障过程中曾误读该值，之后根据视频线程的创建时间和用户说明完成纠正。

### 3.2 Bottles 首次启动无反应

Bottles 的文件选择器允许选中游戏 EXE，但其 Flatpak 权限中没有 `/home/chesszyh/Games`。因此 Bottle 无法持续读取同目录的 `data.xp3`、插件和其他资源，程序启动后立即结束。

### 3.3 Bottles + DXVK 导致桌面卡顿和四分之一画面

启用 DXVK 后，游戏进程约占用 `91% CPU`，`wineserver` 另占约 `14%`。GPU 利用率约 `30%`，没有显存耗尽或驱动报错。`vmstat` 显示游戏运行时每秒约 `22–27 万` 次上下文切换；暂停游戏后下降到约 `3–5.5 万` 次，恢复游戏后立即重新升高。

游戏窗口接近全屏 `2548×1553`，但旧 D3D9 游戏仍只按约 `1280×720` 在左上角绘制，剩余区域为黑色。

### 3.4 LunaTranslator 方块字和 HOOK 崩溃

Luna 界面配置使用：

```json
"fonttype": "MS Shell Dlg 2",
"fonttype2": "MS Shell Dlg 2",
"settingfonttype": "MS Shell Dlg 2"
```

Bottle 注册表最初把 `MS Shell Dlg 2` 回退到 Tahoma，而 Wine Fonts 目录只有 Arial、Times New Roman 和 Courier New，没有实际的中文字体文件，故中文界面显示为方块。

从终端启动 Luna 并在游戏运行时执行 HOOK，捕获到：

```text
ntsync requested but unavailable, falling back to fsync
wine: Unhandled page fault on write access to 0000000000920000
at address 00006FFFFFA3DEC2 (thread 03bc), starting debugger...
```

故障地址位于 Wine 的 `ucrtbase.dll` 映射范围。改用 ESync 后再次 HOOK 仍退出，说明同步方式不是最终根因，Soda 9 与当前 LunaTranslator 注入器之间存在运行时兼容问题。

## 4. 调查时间线

1. **确认进程仍存活**：系统 Wine 下游戏未崩溃退出，而是保留 64 个线程并停止响应。
2. **定位视频播放路径**：进程加载 `krmovie.dll`、`AlphaMovie.dll`、`quartz.dll`、`winegstreamer.dll`、`wmvcore.dll`、`wmvdecod.dll` 和 `mfplat.dll`。
3. **锁定 ASF/WMV 管线**：出现 `wine_qz_graph_w`、`asfdemux4:sink`、`multiqueue4:src` 等线程，一个新线程持续占用约 `99.6%` 单核 CPU。由此确认卡点是序章收尾视频，而非剧情脚本等待输入。
4. **建立 Bottles 环境**：创建 win64 Gaming Bottle，runner 为 Soda 9.0-1，并安装 d3dx9、字体、Mono 和 Gecko 等依赖。
5. **排查启动无反应**：`flatpak info --show-permissions` 显示 Bottles 不具备 Games 目录权限；沙箱内 `ls` 也无法访问游戏和 LunaTranslator 路径。
6. **授权后复测游戏**：游戏能够启动，但 DXVK 在 240 Hz 屏幕上形成高频渲染/事件风暴。
7. **用暂停对照确认桌面卡顿源**：`SIGSTOP` 游戏后上下文切换量立即下降，`SIGCONT` 后恢复异常，排除 OOM、Swap 抖动和 GPU 驱动故障。
8. **关闭 DXVK/VKD3D**：使旧 D3D9 游戏退回 WineD3D；游戏可启动，避免继续使用存在高刷缩放问题的 DXVK 路径。
9. **诊断 Luna 字体**：确认系统与 Flatpak内存在 Noto CJK，但 Bottle 的 Windows Fonts 目录没有中文字体，单纯把 Luna 的字体名称改为 Noto 仍显示方块。
10. **捕获 HOOK 崩溃**：通过 `bottles-cli` 启动 Luna，得到 NTSync 回退和 `ucrtbase.dll` 页错误；切到 ESync 后仍复现。
11. **停止继续堆叠兼容层**：考虑到 Windows 虚拟机能够同时消除媒体、全屏和注入差异，决定迁移到 Windows VM。

## 5. 根因

### 5.1 序章收尾卡死

游戏在此处通过 KiriKiri `krmovie.dll` 调用 DirectShow/Quartz 播放打包在 `data.xp3` 中的 ASF/WMV 视频。Wine 11 的 Quartz → winegstreamer → GStreamer 管线已经创建 ASF demux 和 WMV 解码组件，但进入忙循环/停滞状态；游戏主线程等待视频结束，因而画面和输入一起假死。

### 5.2 Bottles 无反应

Bottles Flatpak 默认没有获得 `/home/chesszyh/Games` 的文件系统权限。文件选择门户只能完成选择动作，不能替代程序运行期间对整个游戏目录的持续访问。

### 5.3 桌面卡顿和黑屏区域

DXVK 已正常加载，并非软件渲染失败。问题是 2014 年的固定分辨率 D3D9 游戏在 240 Hz、2560×1600 的 XWayland 全屏窗口中产生高频呈现与事件切换，同时交换链只绘制约 1280×720 的左上区域。高上下文切换拖慢桌面，交换链/窗口尺寸不一致造成大面积黑屏。

### 5.4 Luna 方块字

Wine 注册表存在 `SimSun`、Microsoft YaHei 等字体名称，但对应字体文件最初并不存在。Tahoma/Arial 也没有中文 glyph。单独把 Luna 配置中的字体名称改成 Noto，不能保证 Wine/Qt 将该宿主字体作为 Windows 字体加载；必须把字体文件放进 Bottle 并注册。

### 5.5 Luna HOOK 后退出

HOOK 需要 64 位 Luna 主程序协调 32 位辅助进程并向 32 位游戏写入 DLL。Soda 9 能列出游戏进程，但在确认注入后于 Wine `ucrtbase.dll` 中发生写访问页错误。ESync 复测仍退出，说明 NTSync 回退仅是伴随警告，核心问题是旧 runner 与新 LunaTranslator 注入链不兼容。

## 6. 已实施变更

### 6.1 Bottles 访问授权

为 Bottles 授权 Games 目录，使游戏与翻译器可在同一个 Bottle 中读取完整目录：

```bash
flatpak override --user \
  --filesystem=/home/chesszyh/Games \
  com.usebottles.bottles
```

### 6.2 Bottle 图形与同步配置

当前配置文件：

```text
/home/chesszyh/.var/app/com.usebottles.bottles/data/bottles/bottles/Nekopara/bottle.yml
```

关键状态：

```yaml
Runner: soda-9.0-1
Windows: win10
dxvk: false
vkd3d: false
sync: esync
virtual_desktop: false
wayland: false
```

DXVK 和 VKD3D 已关闭。NTSync 改为 ESync，但该改动未能解决 HOOK 崩溃。

### 6.3 Luna 字体设置

修改文件：

```text
/home/chesszyh/Games/LunaTranslator_x64/userconfig/config.json
```

三处字体设置改为 `Noto Sans CJK SC`。随后将宿主字体复制到 Bottle：

```text
/home/chesszyh/.var/app/com.usebottles.bottles/data/bottles/bottles/Nekopara/drive_c/windows/Fonts/NotoSansCJK-Regular.ttc
```

并注册：

```text
Noto Sans CJK SC (TrueType) = NotoSansCJK-Regular.ttc
MS Shell Dlg 2 = Noto Sans CJK SC
```

用户在“只改字体名称、尚未安装字体文件”阶段复测仍为方块；完成字体文件复制和注册后，因随后决定迁移虚拟机，尚未再次验证 UI。

### 6.4 最终迁移决策

不再继续安装 Windows Media Player、原生 Quartz/UCRT 或更多 Wine runner。计划把以下完整目录复制到 Windows VM 的本地磁盘：

```text
/home/chesszyh/Games/Nekopara/NekoPara Vol.1
/home/chesszyh/Games/LunaTranslator_x64
```

建议目标路径：

```text
C:\Games\Nekopara Vol.1
C:\Tools\LunaTranslator
```

## 7. 验证

### 已验证

- 游戏存档位于游戏目录 `savedata/`，不会随 Bottle 删除；
- 系统 Wine 的卡死发生在 ASF/WMV 视频管线创建后；
- Bottles 首次无反应由 Flatpak 目录不可见直接解释；
- 游戏是导致桌面高上下文切换的直接来源，暂停/恢复对照成立；
- DXVK 已关闭，游戏能够通过 Soda/WineD3D 启动；
- Luna HOOK 在 Soda 9 + ESync 下仍可复现页错误退出；
- Noto CJK 字体文件最终已复制进 Bottle并写入字体注册表。

### 尚未验证

- 安装并注册 Noto 后 Luna 界面是否完全恢复中文；
- Windows VM 中 OP/ED 视频是否正常播放；
- Windows VM 中 LunaTranslator 是否能稳定注入 `nekopara_vol1.exe`；
- “繁体中文 → 简体中文 + 繁简转换”是否能以内嵌或悬浮字幕方式完整工作。

因此本次结论是“完成根因分层并选择更稳的运行边界”，不是宣称 Linux/Wine 路径已经完全修复。

## 8. 排障过程中遇到的问题

### 8.1 把进程运行时长误认为卡死时长

`ps` 的 `ELAPSED` 是进程总生命周期。用户说明卡死刚发生后，及时修正为“已游玩约 1 小时 20 分钟，刚到视频节点卡死”。后续应结合线程创建时间、日志时间和用户操作时间判断卡死持续时间。

### 8.2 过早把问题概括为“缺少解码器”

进程实际上已加载 `libgstasf.so`、`libgstlibav.so`、`wmvcore.dll` 和 `wmvdecod.dll`。因此不是简单缺包，而是已有解码管线在该文件/runner 组合中停滞。

### 8.3 文件选择器成功不等于 Flatpak 可运行

门户允许选择单个文件，容易误以为应用已经获得目录权限。旧游戏通常还需要同目录档案包、DLL 和可写存档，必须在沙箱内实际 `ls`/`test -r` 验证。

### 8.4 只修改字体名称无效

宿主机 `fc-list` 能找到 Noto CJK，不代表 Wine Qt 应用能按同一 Windows 字体名称使用它。需同时确认 Wine Fonts 目录和 `HKLM\...\Fonts` 注册项。

### 8.5 把 NTSync 回退当成唯一崩溃原因

Soda 9 明确输出 NTSync 不可用并回退 FSync，但切到 ESync 后 HOOK 仍退出。警告与根因必须通过复测区分，不能只看日志中第一条显眼错误。

### 8.6 持续修补的边际收益快速下降

先后出现媒体、权限、图形、高刷、字体、同步和注入问题。当每修复一层又暴露下一层，且 Windows VM 能一次性恢复应用原生假设时，应及时停止扩大宿主 Wine 修改面。

## 9. 复用说明与经验

1. **KiriKiri 游戏在章节切换处卡死时优先查视频线程**：搜索 `wine_qz_graph`、`asfdemux`、`winegstreamer`、`krmovie`，不要先归因于存档。
2. **确认进程仍活着再决定是否强退**：检查线程、CPU、打开的 XP3 和存档时间；本次 `savedata` 已在视频前更新。
3. **Flatpak 应用必须从沙箱内部验证路径**：GUI 文件选择成功不是充分条件。
4. **高刷屏上的旧 D3D9 游戏先关闭 DXVK测试**：若表现为单核高占用、上下文切换爆炸和交换链缩放异常，WineD3D 可能更稳。
5. **HOOK 工具与游戏必须位于同一 Wine prefix/wineserver**：不同 Bottle 或系统 Wine 无法可靠互相发现和注入。
6. **字体问题检查文件与注册表两端**：注册表有字体名称但实际文件不存在，是 Wine 中常见的“看似已装”假象。
7. **注入崩溃优先换 runner 或运行边界**：不要无依据地连续安装 WMP、Quartz、VC Runtime 和 DLL 覆盖。
8. **迁移 Windows VM 时复制完整目录到 VM 本地磁盘**：共享目录只用于传输，不直接运行，避免 HOOK、文件锁和缓存写入差异。
9. **虚拟机显示建议 1920×1080、60 Hz**：该游戏不需要 240 Hz；如虚拟化软件提供 3D 加速，可开启。
10. **VM 中先普通权限启动两者**：先游戏、后 Luna；仅当注入权限确实不足时，才让二者同时以管理员权限运行。

## 10. 附录：可复用命令

### 10.1 查看 Wine 游戏和媒体线程

```bash
ps -eo pid,ppid,stat,etime,cmd | rg -i 'nekopara|wine|wineserver'
ps -L -p <PID> -o pid,tid,stat,pcpu,wchan:28,comm
lsof -p <PID> | rg -i 'xp3|krmovie|wmv|asf|winegstreamer'
rg -i 'quartz|winegstreamer|wmv|krmovie|asfdemux' /proc/<PID>/maps
```

### 10.2 检查系统压力与上下文切换

```bash
free -h
vmstat 1 5
nvidia-smi
ps -eo pid,pcpu,pmem,rss,cmd --sort=-pcpu | head
```

临时暂停/恢复单个游戏进程进行对照：

```bash
kill -STOP <PID>
vmstat 1 5
kill -CONT <PID>
```

### 10.3 检查 Bottles Flatpak 权限

```bash
flatpak info --show-permissions com.usebottles.bottles

flatpak run --command=sh com.usebottles.bottles -lc \
  'ls -ld "/home/chesszyh/Games/Nekopara/NekoPara Vol.1"'
```

授权 Games 目录：

```bash
flatpak override --user \
  --filesystem=/home/chesszyh/Games \
  com.usebottles.bottles
```

### 10.4 从终端捕获 Bottle 程序输出

```bash
flatpak run --command=bottles-cli com.usebottles.bottles \
  run -b Nekopara \
  -e /home/chesszyh/Games/LunaTranslator_x64/LunaTranslator.exe
```

### 10.5 检查 Wine 字体

```bash
find ~/.var/app/com.usebottles.bottles/data/bottles/bottles/Nekopara/drive_c/windows/Fonts \
  -maxdepth 1 -type f -printf '%f\n' | sort

rg -i 'Noto Sans CJK|MS Shell Dlg|SimSun|YaHei' \
  ~/.var/app/com.usebottles.bottles/data/bottles/bottles/Nekopara/system.reg
```

### 10.6 Windows VM 迁移检查清单

```text
1. 退出 Linux 下正在运行的游戏和 LunaTranslator。
2. 复制完整游戏目录，确认 savedata/ 存在。
3. 复制完整 LunaTranslator_x64 目录，保留 userconfig/。
4. 在 VM 本地 NTFS 磁盘运行，不从共享目录直接运行。
5. 先启动游戏，再启动 LunaTranslator。
6. HOOK 选择 nekopara_vol1.exe。
7. 源语言选繁体中文，目标选简体中文，只启用“繁简转换”。
8. 验证 OP/ED、HOOK、字幕线路和存档后，再删除 Linux Bottle。
```

参考资料：

- [NEKOPARA Vol.1 ProtonDB 兼容报告](https://www.protondb.com/app/333600)
- [LunaTranslator 基本用法](https://docs.lunatranslator.org/zh/basicuse.html)
- [LunaTranslator 下载、启动与 HOOK 注入说明](https://docs.lunatranslator.org/zh/README.html)
