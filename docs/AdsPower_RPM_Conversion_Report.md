# AdsPower Global .deb 转 .rpm 转换及安装问题解决报告

**日期：** 2026年3月6日
**操作环境：** Linux (x86_64)
**目标文件：** AdsPower-Global-7.12.29-x64.deb

## 1. 遇到的问题

### 问题 A：RPM 构建失败 (Empty Summary)
在使用 `alien -r` 直接转换时，`rpmbuild` 报错：
`错误：行 5：空的标签：Summary:`
这是因为原始 .deb 包的元数据中缺少概要描述，导致生成的 .spec 文件不符合 RPM 规范。

### 问题 B：安装时依赖冲突 (Unresolvable Dependencies)
在初步解决 Summary 问题并生成 RPM 后，使用 `dnf install` 安装时出现大量无法满足的依赖：
- `ld-linux-armhf.so.3` (ARM 架构)
- `ld-linux-riscv64-lp64d.so.1` (RISC-V 架构)
- `libc.so.7(FBSD_1.0)` (FreeBSD 系统)
这些依赖是由于 `rpmbuild` 自动扫描了软件包内包含的多平台二进制文件而错误生成的。

## 2. 解决方案

### 步骤 1：生成可编辑的构建目录
使用 `alien -g -r` 生成 RPM 构建目录和 `.spec` 配置文件，而不立即进行构建。

### 步骤 2：修正 .spec 配置文件
对 `adspower-global-7.12.29-2.spec` 进行了以下关键修改：
1. **补全 Summary：** 添加了 `Summary: AdsPower Global browser package converted from .deb`。
2. **禁用自动依赖检测：** 添加了 `AutoReq: no` 和 `AutoProv: no`。
   - 这确保了安装程序只关注软件包本身，而不会去寻找那些包内自带的、用于其他架构或系统的无关库。

### 步骤 3：手动构建 RPM
使用 `rpmbuild -bb` 命令根据修改后的 `.spec` 文件重新打包，成功生成了纯净的 `adspower-global-7.12.29-2.x86_64.rpm`。

## 3. 结论与建议
通过禁用自动依赖检测，我们成功绕过了跨平台库引起的依赖困境，且未破坏系统的依赖链。

**安装建议：**
执行 `sudo dnf install ./adspower-global-7.12.29-2.x86_64.rpm` 即可正常完成安装。
