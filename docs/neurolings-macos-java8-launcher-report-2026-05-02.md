生成时间: 2026-05-02T22:41:37+08:00

# Neuro 桌宠在 macOS 上的 Java 8、启动器与菜单排障报告

## 1. Problem Description（问题描述）

本次任务的目标有四部分：

1. 在 macOS 上配置 Java 8 运行环境。
2. 配置一个通用的 `extract` zsh 解压函数。
3. 解压并验证 `Neurosama-desktop-pet` 相关桌宠资源是否能在 macOS 上启动。
4. 为常用形态生成可被 Spotlight 检索的一键启动 `.app`，并提供稳定的关闭入口。

排障过程中又出现了两个衍生问题：

1. 用户在 macOS 菜单栏顶部图标上使用 `Ctrl + 左键` 时，没有弹出菜单，反而继续召唤出了更多桌宠。
2. 用户无法稳定关闭已经在运行中的 Neurolings 进程。

本报告记录从环境配置、兼容性验证、启动器设计到菜单根因定位与停止入口落地的完整证据链。

## 2. Environment and Scope（环境与范围）

- 操作系统：macOS
- Shell：`zsh`
- 初始工作目录：`/Users/chesszyh/Downloads/Neurosama-desktop-pet`
- 最终资源目录：`/Users/chesszyh/Applications/Neurosama-desktop-pet`
- Java 发行版：Temurin 8
- Homebrew 路径：`/opt/homebrew/bin/brew`
- 解压工具：`/opt/homebrew/bin/unar`

本次实际修改或新增的本地文件：

- `/Users/chesszyh/.zshrc`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/The-Neuroling-Collection/run-on-mac.command`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/neuro_shim/run-on-mac.command`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/evil_neuro_shim/run-on-mac.command`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-neuron.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-eviling.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-weuron.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/stop-neurolings.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/neuron/conf/settings.properties`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/eviling/conf/settings.properties`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/weuron/conf/settings.properties`
- `/Users/chesszyh/Applications/Neuron.app`
- `/Users/chesszyh/Applications/Eviling.app`
- `/Users/chesszyh/Applications/Weuron.app`
- `/Users/chesszyh/Applications/Stop Neurolings.app`

本次处理的压缩包：

- `The-Neuroling-Collection.zip`
- `neuro_shim.rar`
- `evil_neuro_shim.rar`

## 3. Symptoms and Reproduction（症状与复现）

### 3.1 初始环境没有 Java 运行时

在开始时执行：

```bash
java -version
```

得到系统错误：

```text
The operation couldn’t be completed. Unable to locate a Java Runtime.
```

这说明本机没有可用 Java Runtime，桌宠 jar 无法直接启动。

### 3.2 系统只能直接处理 zip，不能处理 rar

初始状态只有：

```bash
command -v unzip
```

存在，而 `unar`、`unrar`、`7z` 均不存在，因此 `*.rar` 无法直接解压。

### 3.3 两个 `Shimeji-ee.jar` 在 macOS 上直接启动失败

在 `neuro_shim` 和 `evil_neuro_shim` 目录中执行：

```bash
java -jar Shimeji-ee.jar
```

都会在短时间内退出，并报出同一类错误：

```text
java.lang.ClassNotFoundException: com.group_finity.mascot.mac.NativeFactoryImpl
```

这说明这两个 jar 不具备 macOS 原生实现。

### 3.4 用户在菜单栏图标上 `Ctrl + 左键` 时继续增加桌宠

预期行为是弹出菜单；实际行为是继续召唤新桌宠。这意味着 macOS 上该输入没有被当前 `TrayIcon` 实现识别为弹出菜单事件。

### 3.5 用户没有稳定的关闭入口

在菜单无法稳定弹出的前提下，用户既无法通过图标菜单点 `Dismiss All`，也不知道当前运行的 Java 进程该如何安全关闭。

## 4. Investigation Timeline（调查时间线）

### 4.1 确认压缩包和本机基础环境

先检查当前目录与现有工具：

```bash
rg --files -g '*.{zip,rar,7z,tar,gz,bz2,xz,jar,app,dmg}' .
java -version
/usr/libexec/java_home -V
command -v brew
command -v unzip
command -v unar
```

结论：

- 当前目录下确实只有三个待处理压缩包。
- Homebrew 已存在。
- Java Runtime 不存在。
- `unzip` 存在，但 `unar` 不存在。

### 4.2 安装 Java 8 与通用解压工具

执行：

```bash
brew install --cask temurin@8
brew install unar
```

安装后验证：

```bash
java -version
/usr/libexec/java_home -v 1.8
command -v unar
```

得到结论：

- Java 8 安装成功，路径为 `/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home`
- `unar` 安装成功，可用于 `rar` 解压。

### 4.3 将 Java 8 与 `extract()` 写入 `~/.zshrc`

在 `/Users/chesszyh/.zshrc` 末尾增加：

- `JAVA_HOME`
- `PATH`
- `extract()` 函数

随后通过新的交互式 shell 验证：

```bash
zsh -ic 'echo $JAVA_HOME; java -version; whence -f extract'
```

确认：

- `JAVA_HOME` 已固定为 Temurin 8
- `extract` 函数可在新终端直接使用

### 4.4 解压三个桌宠压缩包

使用：

```bash
extract The-Neuroling-Collection.zip neuro_shim.rar evil_neuro_shim.rar
```

完成后发现：

- `The-Neuroling-Collection` 解压成功
- 两个 rar 也成功解压
- `neuro_shim` 目录初始解压结果带有尾随空格，后续已修正为正常目录名

### 4.5 验证哪个 jar 真的能在 macOS 上运行

分别对以下目标做短时启动测试：

```bash
java -jar The-Neuroling-Collection/Neurolings.jar
java -jar neuro_shim/Shimeji-ee.jar
java -jar evil_neuro_shim/Shimeji-ee.jar
```

结果分化明显：

- `Neurolings.jar` 能持续运行
- 两个 `Shimeji-ee.jar` 都因缺失 `com.group_finity.mascot.mac.NativeFactoryImpl` 而失败

### 4.6 检查 jar 内容，确认兼容性根因

进一步执行：

```bash
jar tf The-Neuroling-Collection/Neurolings.jar | rg 'mac|NativeFactory'
jar tf neuro_shim/Shimeji-ee.jar | rg 'mac|NativeFactory'
```

结论：

- `Neurolings.jar` 内含 `com/group_finity/mascot/mac/NativeFactoryImpl.class`
- 两个 `Shimeji-ee.jar` 只带 `generic` 和 `win` 实现，没有 `mac`

至此可以确定：`neuro_shim.rar` 和 `evil_neuro_shim.rar` 不是“各自独立可运行的 mac 引擎”，而是 Windows 风格资源包。

### 4.7 用一个已验证可运行的引擎去加载不同资源

针对 `neuro_shim` 和 `evil_neuro_shim`，改用：

```bash
cd <resource-dir>
java -jar ../The-Neuroling-Collection/Neurolings.jar
```

验证结果表明，这两个资源目录在 macOS 下可以被 `Neurolings.jar` 正常加载。

### 4.8 先落地一批 `run-on-mac.command`

为了避免每次手写命令，先在各目录中增加：

- `The-Neuroling-Collection/run-on-mac.command`
- `neuro_shim/run-on-mac.command`
- `evil_neuro_shim/run-on-mac.command`

这一步解决了“能运行但不好启动”的问题，但还没有解决 Spotlight 搜索入口和稳定关闭入口。

### 4.9 将整个资源目录迁移到 `~/Applications`

用户后续明确要求不要继续依赖下载目录，于是执行整体迁移：

```bash
mv /Users/chesszyh/Downloads/Neurosama-desktop-pet \
   /Users/chesszyh/Applications/Neurosama-desktop-pet
```

迁移后，下载目录中的原始路径已经不存在，资源统一固定在 `~/Applications/Neurosama-desktop-pet`。

### 4.10 为 Spotlight 设计独立 `.app` 启动器

最初生成过 `Neuroling.app` 与 `Evil Neuroling.app`，后又根据用户要求调整为：

- `Neuron.app`
- `Eviling.app`
- `Weuron.app`

实现方式不是把资源打进 `.app` 包，而是：

1. 为每种形态建立独立的 `runtimes/<shape>` 目录。
2. 复制 `conf/`，并用软链接复用 `img/`、`lib/`、`Neurolings.jar`。
3. 在各自 `conf/settings.properties` 中固定：
   - `AlwaysShowShimejiChooser=false`
   - `ActiveShimeji=<目标形态>`
4. 用 `osacompile` 生成 Spotlight 可检索的 `.app`，内部调用各自的 shell 启动脚本。

### 4.11 调查托盘菜单为什么不弹

对 `Neurolings.jar` 进行反编译：

```bash
javap -classpath The-Neuroling-Collection/Neurolings.jar -p -c 'com.group_finity.mascot.Main$1'
```

关键证据：

- `mouseReleased()` 先判断 `MouseEvent.isPopupTrigger()`
- 如果不是 popup trigger，则继续看 `MouseEvent.getButton()`
- 当 `getButton() == 1` 时，直接执行 `Main.createMascot()`

也就是说：

1. 托盘图标左键点击在程序里被硬编码为“召唤一个新桌宠”
2. 只有 AWT 自己识别为弹出菜单事件时，才会进入菜单分支

这就解释了为什么用户在 macOS 上 `Ctrl + 左键` 时没有弹菜单，反而增加了桌宠：在该环境里，这个输入组合没有被 `TrayIcon` 实现稳定识别为 `popup trigger`。

### 4.12 提供稳定关闭入口，并修复第一次停止脚本的误判

最初实现的 `Stop Neurolings.app` 通过进程命令行做匹配，但验证时发现失败：

- `ps` 里 Java 命令行只显示为 `java -jar Neurolings.jar`
- 不带运行时路径，因此基于完整路径的 `pkill -f` 无法命中

随后改为：

1. `pgrep -f '^java -jar Neurolings\.jar$'` 找候选 Java 进程
2. 用 `lsof -a -p <pid> -d cwd -Fn` 读取进程当前工作目录
3. 只对工作目录位于本项目：
   - `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/*`
   - `/Users/chesszyh/Applications/Neurosama-desktop-pet/The-Neuroling-Collection`
   的进程执行 `kill`

这一步之后，`Stop Neurolings.app` 才真正具备可复用性，而且不会误杀其他 Java 程序。

## 5. Root Cause（根因）

本次问题不是单点故障，而是三类根因叠加：

### 5.1 环境根因：macOS 初始没有 Java 8，也没有 rar 解压工具

这导致桌宠资源在最开始既不能完整解压，也不能启动。

### 5.2 兼容性根因：`neuro_shim` 与 `evil_neuro_shim` 自带 jar 不是 macOS 版本

两个资源包中的 `Shimeji-ee.jar` 都缺失 `com.group_finity.mascot.mac.NativeFactoryImpl`。它们本质上是资源包，不是可在 macOS 上独立运行的完整引擎。

### 5.3 交互根因：托盘图标左键逻辑被硬编码为“召唤桌宠”

通过反编译可知：

- `popup trigger` 才会弹菜单
- `button 1` 会直接进入 `createMascot()`

因此在 macOS 上如果 `Ctrl + 左键` 没有被 AWT `TrayIcon` 判成 popup trigger，就会误走左键召唤分支。这不是 shell 启动脚本或 `.app` 包装的问题，而是 `Neurolings.jar` 内部的 GUI 事件分发逻辑。

## 6. Changes Made（已做修改）

### 6.1 Shell 与环境

在 `/Users/chesszyh/.zshrc` 中增加：

- `JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-8.jdk/Contents/Home`
- `PATH="$JAVA_HOME/bin:$PATH"`
- 通用 `extract()` 解压函数

### 6.2 资源目录布局

资源从：

```text
/Users/chesszyh/Downloads/Neurosama-desktop-pet
```

迁移到：

```text
/Users/chesszyh/Applications/Neurosama-desktop-pet
```

并在其中保留：

- `The-Neuroling-Collection`
- `launchers`
- `runtimes/neuron`
- `runtimes/eviling`
- `runtimes/weuron`

### 6.3 启动器

新增 shell 启动脚本：

- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-neuron.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-eviling.sh`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/launch-weuron.sh`

新增 Spotlight 启动入口：

- `/Users/chesszyh/Applications/Neuron.app`
- `/Users/chesszyh/Applications/Eviling.app`
- `/Users/chesszyh/Applications/Weuron.app`

### 6.4 停止入口

新增：

- `/Users/chesszyh/Applications/Neurosama-desktop-pet/launchers/stop-neurolings.sh`
- `/Users/chesszyh/Applications/Stop Neurolings.app`

### 6.5 运行时配置

分别固定形态：

- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/neuron/conf/settings.properties`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/eviling/conf/settings.properties`
- `/Users/chesszyh/Applications/Neurosama-desktop-pet/runtimes/weuron/conf/settings.properties`

三处统一设置为：

- `AlwaysShowShimejiChooser=false`
- `ActiveShimeji=<对应形态>`

## 7. Verification（验证）

### 7.1 Java 8 与解压工具

验证命令：

```bash
java -version
/usr/libexec/java_home -v 1.8
command -v unar
zsh -ic 'whence -f extract'
```

验证结论：

- Java 8 正常可用
- `unar` 可用
- `extract` 已在新 zsh 会话中生效

### 7.2 资源目录迁移

验证命令：

```bash
test -e /Users/chesszyh/Downloads/Neurosama-desktop-pet && echo EXISTS || echo MISSING
test -d /Users/chesszyh/Applications/Neurosama-desktop-pet && echo PRESENT
```

验证结论：

- 下载目录中的原始项目目录已不存在
- 运行资源已经固定在 `~/Applications`

### 7.3 三个 Spotlight 启动器加载正确形态

验证方式：

```bash
open /Users/chesszyh/Applications/Neuron.app
open /Users/chesszyh/Applications/Eviling.app
open /Users/chesszyh/Applications/Weuron.app
```

对应日志关键行：

```text
loadConfiguration Neuron Read Action File (./img/Neuron/conf/actions.xml)
loadConfiguration Eviling Read Action File (./img/Eviling/conf/actions.xml)
loadConfiguration Weuron Read Action File (./img/Weuron/conf/actions.xml)
```

这说明三者都已经固定到正确形态。

### 7.4 停止入口可用

验证方式：

1. 先启动 `Neuron.app`
2. 再执行 `open /Users/chesszyh/Applications/Stop\ Neurolings.app`
3. 用 `ps` 检查残留进程

验证结果：

```text
== Processes after stop ==
```

为空，说明当前这套桌宠进程已经被全部清理。

## 8. Problems Encountered During Debugging（调试中遇到的问题）

### 8.1 初始误判：以为 `neuro_shim.jar` 和 `evil_neuro_shim.jar` 是独立可运行引擎

实际并不是。它们的资源可以复用，但 jar 本身没有 macOS 实现。

### 8.2 初始停止方案失败

第一次尝试按完整路径匹配 Java 进程失败，因为 `ps` 中只显示：

```text
java -jar Neurolings.jar
```

没有运行时路径，导致 `pkill -f` 条件过窄。

### 8.3 macOS 托盘事件与直觉不一致

从用户视角看，`Ctrl + 左键` 理应等价于右键；但在这份 AWT `TrayIcon` 实现里，这个假设不成立。这个差异只有在反编译事件处理逻辑后才能确认，靠表面点击现象很容易误判为脚本或配置问题。

## 9. Reuse Notes and Lessons（复用说明与经验）

1. 遇到这类旧 Java 桌宠项目，不要先假设“每个压缩包里的 jar 都是可运行引擎”，应先用 `jar tf` 检查是否带有目标平台实现。
2. 对于 Spotlight 入口，优先采用“资源目录固定 + 独立运行时目录 + 轻量 `.app` 包装”的方案。这样排障、改配置和替换形态都比较直接。
3. 对于停止脚本，不要只看命令行参数；如果进程启动命令很短，应用当前工作目录往往比命令行更可靠。
4. 对于 Java AWT 托盘交互问题，优先反编译 `mouseReleased()` 等事件函数，避免在 macOS 事件语义上盲猜。

## 10. Appendix: Reusable Commands（附录：可复用命令）

### 10.1 环境检查

```bash
java -version
/usr/libexec/java_home -v 1.8
command -v unar
zsh -ic 'whence -f extract'
```

### 10.2 安装 Java 8 与解压工具

```bash
brew install --cask temurin@8
brew install unar
```

### 10.3 解压桌宠资源

```bash
cd /Users/chesszyh/Downloads/Neurosama-desktop-pet
extract The-Neuroling-Collection.zip neuro_shim.rar evil_neuro_shim.rar
```

### 10.4 检查 jar 是否含 macOS 实现

```bash
jar tf The-Neuroling-Collection/Neurolings.jar | rg 'mac|NativeFactory'
jar tf neuro_shim/Shimeji-ee.jar | rg 'mac|NativeFactory'
jar tf evil_neuro_shim/Shimeji-ee.jar | rg 'mac|NativeFactory'
```

### 10.5 查看托盘图标事件逻辑

```bash
javap -classpath /Users/chesszyh/Applications/Neurosama-desktop-pet/The-Neuroling-Collection/Neurolings.jar \
  -p -c 'com.group_finity.mascot.Main$1'
```

### 10.6 直接启动与关闭

```bash
open /Users/chesszyh/Applications/Neuron.app
open /Users/chesszyh/Applications/Eviling.app
open /Users/chesszyh/Applications/Weuron.app
open /Users/chesszyh/Applications/Stop\ Neurolings.app
```

### 10.7 手工检查残留进程

```bash
ps -Ao pid,command | rg 'Neurolings\.jar'
```

### 10.8 通过工作目录定位当前这套桌宠进程

```bash
for pid in $(pgrep -f '^java -jar Neurolings\.jar$'); do
  lsof -a -p "$pid" -d cwd -Fn
done
```
