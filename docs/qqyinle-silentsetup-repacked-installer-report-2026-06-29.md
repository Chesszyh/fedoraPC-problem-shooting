# qqyinle.com.cn SilentSetup.exe 重新打包安装器安全分析报告

生成时间: 2026-06-29T14:08:20+08:00

## 1. Problem Description（问题描述）

用户从 `https://www.qqyinle.com.cn/` 下载了疑似盗版 QQ 音乐安装包 `SilentSetup.exe`，需要判断该 Windows EXE 是否为木马或恶意安装器。宿主机为 Fedora，允许按需安装分析工具。

本次分析目标不是运行安装 QQ 音乐，而是回答三个问题：

- 下载站点和腾讯官方 QQ 音乐下载链路是否一致。
- 外层安装器是否为腾讯签名的官方原始安装器。
- 静态解包与隔离动态观察中是否出现异常 payload、额外进程或可疑行为。

## 2. Environment and Scope（环境与范围）

分析目录：

```text
/tmp/qqyinle.com.cn-exe
```

主要样本：

```text
/tmp/qqyinle.com.cn-exe/SilentSetup.exe
SHA256: e1ff9f5b54c19c2b473d06c6bb14536c480885b545d8f9dce689465d53816ee5
大小: 107,961,504 bytes
类型: PE32 GUI, Intel i386, Nullsoft Installer self-extracting archive
```

使用工具：

```text
file
sha256sum
7z
strings
exiftool
objdump
pedump
osslsigncode
yara
python3-pefile
wine
bwrap
strace
curl
rg
```

隔离方式：

- 静态分析优先，不直接在宿主真实环境安装。
- 动态观察使用 `bwrap --unshare-net` 断网隔离。
- 使用临时 Wine prefix，避免污染用户常用 Wine 环境。
- 动态运行限时，观察释放文件、子进程和加载行为，不继续完成安装。

## 3. Symptoms and Reproduction（现象与复现）

用户可见现象：

- 下载目录中只有 `SilentSetup.exe`。
- Wine 初始化时弹出 Wine Mono setup；用户点击 `Install` 后立刻出现 `install failed`。
- 鼠标移入 Wine 窗口后消失，无法继续操作 GUI。

关键复现命令：

```bash
file SilentSetup.exe
sha256sum SilentSetup.exe
7z l -slt SilentSetup.exe
7z x -y -oanalysis-evidence/extracted SilentSetup.exe
osslsigncode verify -in SilentSetup.exe
osslsigncode verify -in analysis-evidence/extracted/QQMusic_Setup_2228.exe
```

`file` 识别结果：

```text
SilentSetup.exe: PE32 executable for MS Windows 4.00 (GUI), Intel i386, Nullsoft Installer self-extracting archive, 5 sections
```

7z 解包后主要文件：

```text
HWSignature.dll         14,336 bytes
ImageMagik.dll      6,155,648 bytes
QQMusic_Setup_2228.exe 104,572,968 bytes
proxy.exe              2,371 bytes
sgfeedbackhelper.exe 3,292,544 bytes
```

## 4. Investigation Timeline（调查时间线）

1. 读取本机 `RTK.md`，确认 shell 命令需加 `rtk` 前缀。
2. 查询历史记忆中同类 Fedora/Wine 可疑 EXE 分析流程，采用“静态优先、隔离动态观察第二”的边界。
3. 对 `SilentSetup.exe` 做 `file`、`sha256sum`、`exiftool`、`objdump`，确认它是 NSIS 自解压安装器，外层 PE 无 Authenticode 签名。
4. 使用 `7z l -slt` 与 `7z x` 解包，发现其内嵌腾讯签名 QQ 音乐安装器，同时额外包含 Sogou 组件、无签名 `HWSignature.dll` 和非 PE `proxy.exe`。
5. 安装 `osslsigncode`、`yara`、`python3-pefile`、`mingw-nsis-base`、`mingw32-nsis`、`mingw64-nsis` 等工具补齐签名与规则检查能力。
6. 抓取 `https://www.qqyinle.com.cn/download` 页面和腾讯官方 `https://y.qq.com/download/index.html` 页面，比较下载链路。
7. 用 `bwrap --unshare-net`、临时 Wine prefix 和 `strace` 运行外层安装器，观察其实际释放和启动行为。
8. 用户报告 Wine Mono setup 弹窗和 install failed，确认该弹窗来自 Wine prefix 初始化，不是样本自身安装 UI。
9. 动态运行中观察到外层安装器将文件释放到 `C:\Program Files (x86)\Tencent\`，并启动 `sgfeedbackhelper.exe` 与 `QQMusic_Setup_2228.exe`。
10. 停止相关 Wine 进程，整理证据摘要和当前目录报告。
11. 将摘要证据复制到 Reports 仓库的 `evidence/qqyinle-silentsetup-2026-06-29/`，写入本报告并更新首页索引。

## 5. Root Cause（根因）

根因是 `qqyinle.com.cn` 提供的不是腾讯官方原始 QQ 音乐安装包，而是第三方重新打包的 NSIS 安装器。

证据链：

- `qqyinle.com.cn` 下载页是 WordPress 站点，页面下载按钮指向 `https://xpofn.tos-cn-guangzhou.volces.com/SilentSetup.zip`。
- 腾讯官方 QQ 音乐下载页为 `https://y.qq.com/download/index.html`，Windows PC 下载入口指向 `https://dldir.y.qq.com/music/clntupate/QQMusic_YQQWinPCDL.exe`。
- 外层 `SilentSetup.exe` 无签名，且 PE checksum 异常。
- 内层 `QQMusic_Setup_2228.exe` 有腾讯有效签名，说明第三方很可能把官方安装器作为 payload 重新包进了自己的外壳。
- 外层额外携带并释放 `HWSignature.dll`、`proxy.exe`、`sgfeedbackhelper.exe`、`ImageMagik.dll`。
- `HWSignature.dll` 无签名，导出 `DLLGenHWID`、`GenHWID` 等硬件 ID 相关函数，导入 `VirtualAlloc`、`VirtualProtect`、`LoadLibraryA`、`GetProcAddress`，并包含 `proxy.exe` 字符串。
- `proxy.exe` 不是 PE 文件，签名工具无法识别，内容呈高熵 blob 特征。
- 动态观察确认 `sgfeedbackhelper.exe` 加载 `HWSignature.dll` 并访问 `proxy.exe`。

因此，样本的可信边界不应按“内含腾讯签名 QQ 音乐安装器”判断，而应按“外层无签名第三方安装器额外投放和执行未知组件”判断。

## 6. Changes Made（变更）

本次未修改系统持久配置，也未在真实 Windows 环境或常用 Wine prefix 中安装样本。

安装的分析工具：

```bash
sudo dnf install -y osslsigncode yara python3-pefile
sudo dnf install -y mingw-nsis-base mingw32-nsis mingw64-nsis
```

创建的工作目录文件：

```text
/tmp/qqyinle.com.cn-exe/analysis-evidence/
/tmp/qqyinle.com.cn-exe/analysis-report-20260629.md
```

复制到 Reports 仓库的摘要证据：

```text
/home/chesszyh/Documents/Reports/evidence/qqyinle-silentsetup-2026-06-29/dynamic-summary.txt
/home/chesszyh/Documents/Reports/evidence/qqyinle-silentsetup-2026-06-29/hashes-and-files.txt
/home/chesszyh/Documents/Reports/evidence/qqyinle-silentsetup-2026-06-29/signature-summary.txt
/home/chesszyh/Documents/Reports/evidence/qqyinle-silentsetup-2026-06-29/source-page-summary.txt
```

新增报告：

```text
/home/chesszyh/Documents/Reports/docs/qqyinle-silentsetup-repacked-installer-report-2026-06-29.md
```

## 7. Verification（验证）

签名验证摘要：

```text
SilentSetup.exe: No signature found; invalid PE checksum; Failed
HWSignature.dll: No signature found; Failed
QQMusic_Setup_2228.exe: Tencent Technology (Shenzhen) Company Limited; Succeeded
ImageMagik.dll: Beijing Sogou Technology Development Co., Ltd.; Succeeded
sgfeedbackhelper.exe: Beijing Sogou Technology Development Co., Ltd.; Succeeded
proxy.exe: unsupported input file type; Failed
```

动态观察摘要：

```text
C:\Program Files (x86)\Tencent\sgfeedbackhelper.exe
C:\Program Files (x86)\Tencent\proxy.exe
C:\Program Files (x86)\Tencent\QQMusic_Setup_2228.exe
C:\Program Files (x86)\Tencent\ImageMagik.dll
C:\Program Files (x86)\Tencent\HWSignature.dll
```

进程观察摘要：

```text
CreateProcessInternalW ... "C:\Program Files (x86)\Tencent\sgfeedbackhelper.exe"
CreateProcessInternalW ... "C:\Program Files (x86)\Tencent\QQMusic_Setup_2228.exe"
Loaded "C:\Program Files (x86)\Tencent\HWSignature.dll"
newfstatat ... "C:\Program Files (x86)\Tencent\proxy.exe"
```

运行状态检查：

```bash
ps -ef | rg -i "wine|SilentSetup|QQMusic|wineserver|QQMusic_Setup|sgfeedback|HWSignature"
```

最终检查时未发现继续运行的 Wine/QQMusic 相关进程。

## 8. Problems Encountered During Debugging（调试中遇到的问题）

1. Fedora 仓库中没有直接名为 `nsis` 的包。

最初执行 `sudo dnf install -y osslsigncode yara python3-pefile nsis` 失败，原因是 `nsis` 包名不存在。随后拆分安装可用工具，并通过 `dnf search nsis` 找到 `mingw-nsis-base`、`mingw32-nsis`、`mingw64-nsis`。

2. Wine Mono setup 弹窗造成误导。

用户点击 Wine Mono setup 的 `Install` 后出现 `install failed`。日志显示这是 Wine 新建 prefix 时运行 `control.exe appwiz.cpl install_mono`，并非样本自身安装失败。由于动态环境使用 `--unshare-net` 断网隔离，Wine 无法下载 Mono，失败符合预期。

3. Wine/Wayland 鼠标捕获问题影响 GUI 操作。

用户报告鼠标移入 Wine 窗口后消失。该问题与 Wine/Wayland 窗口捕获或光标渲染有关，不需要继续通过 GUI 操作样本；后续改为日志、strace 和文件系统证据判断。

4. 动态证据目录膨胀。

临时 Wine prefix 使 `analysis-evidence/` 达到约 3.8G。正式报告只复制 72K 摘要证据到 Reports 仓库，避免把完整 Wine 环境纳入长期文档仓库。

5. 动态运行无法证明“无害”。

本次无网络隔离和 Wine 环境限制了真实行为展开。没有观察到外联或持久化完成，只能说明在该隔离条件下未观察到，不能作为安全结论。

## 9. Reuse Notes and Lessons（复用说明与经验）

- 遇到下载站伪装成大厂官网时，先比较下载链路和 Authenticode 签名，不要只看界面文案。
- 对可疑 Windows 安装器，应先用 `file`、`sha256sum`、`7z l -slt`、`osslsigncode verify` 做静态检查。
- 第三方重新打包样本常见模式是“内含真实官方签名安装器 + 外层无签名壳 + 额外 payload”。可信判断应落在外层执行链上。
- Wine 的 Mono/MSHTML 初始化弹窗属于环境噪声，不应误判为样本弹窗。
- Wine 动态观察必须使用临时 prefix；不要在常用 Wine prefix 中运行可疑样本。
- 对报告归档，保留摘要证据通常比保存整个 Wine prefix 更可复用。

## 10. Appendix: Reusable Commands（附录：可复用命令）

基础指纹：

```bash
file SilentSetup.exe
sha256sum SilentSetup.exe
exiftool SilentSetup.exe
objdump -x SilentSetup.exe
```

解包：

```bash
mkdir -p analysis-evidence/extracted
7z l -slt SilentSetup.exe
7z x -y -oanalysis-evidence/extracted SilentSetup.exe
```

签名验证：

```bash
osslsigncode verify -in SilentSetup.exe
osslsigncode verify -in analysis-evidence/extracted/HWSignature.dll
osslsigncode verify -in analysis-evidence/extracted/QQMusic_Setup_2228.exe
osslsigncode verify -in analysis-evidence/extracted/sgfeedbackhelper.exe
```

字符串搜索：

```bash
strings -a -n 6 SilentSetup.exe > analysis-evidence/static/SilentSetup.strings.ascii.txt
strings -a -el -n 6 SilentSetup.exe > analysis-evidence/static/SilentSetup.strings.utf16le.txt
rg -n -i "https?://|qqmusic|tencent|cmd\.exe|powershell|startup|runonce|appdata|proxy" analysis-evidence/static/*.txt
```

来源页面对比：

```bash
curl -L --max-time 30 -s https://www.qqyinle.com.cn/download -o analysis-evidence/static/qqyinle-download.html
curl -L --max-time 30 -s https://y.qq.com/download/index.html -o analysis-evidence/static/yqq-download.html
rg -n "SilentSetup.zip|xpofn|volces|WordPress|QQMusic_YQQWinPCDL.exe|dldir.y.qq.com" analysis-evidence/static/*.html
```

隔离动态观察示例：

```bash
mkdir -p analysis-evidence/dynamic/input analysis-evidence/dynamic/home analysis-evidence/dynamic/tmp analysis-evidence/dynamic/out analysis-evidence/dynamic/sample
cp SilentSetup.exe analysis-evidence/dynamic/input/SilentSetup.exe

bwrap --unshare-net --die-with-parent \
  --dev-bind / / \
  --tmpfs /tmp \
  --bind "$(readlink -f analysis-evidence/dynamic/tmp)" /tmp \
  --bind "$(readlink -f analysis-evidence/dynamic/home)" "$(readlink -f analysis-evidence/dynamic/home)" \
  --ro-bind "$(readlink -f analysis-evidence/dynamic/input)" "$(readlink -f analysis-evidence/dynamic/sample)" \
  --bind "$(readlink -f analysis-evidence/dynamic/out)" "$(readlink -f analysis-evidence/dynamic/out)" \
  --setenv HOME "$(readlink -f analysis-evidence/dynamic/home)" \
  --setenv WINEPREFIX "$(readlink -f analysis-evidence/dynamic/home/wineprefix)" \
  --setenv WINEDLLOVERRIDES "mscoree,mshtml=" \
  --setenv WINEDEBUG "+process,+loaddll" \
  timeout 120s strace -ff -tt -o "$(readlink -f analysis-evidence/dynamic/out/strace)" \
  wine "$(readlink -f analysis-evidence/dynamic/sample/SilentSetup.exe)" /S
```

进程残留检查：

```bash
ps -ef | rg -i "wine|SilentSetup|QQMusic|wineserver|QQMusic_Setup|sgfeedback|HWSignature"
```
