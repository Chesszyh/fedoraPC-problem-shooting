# Fedora 格式化 exFAT U 盘后 macOS 提示无法读取修复报告

生成时间: 2026-04-27T23:54:37+08:00

## 1. Problem Description（问题描述）

一只此前被做成 Ubuntu Server 启动盘的 `Lenovo 128GB thinkplus` U 盘，需要恢复为普通存储盘，并支持 Fedora 与 macOS 之间互传文件。

在 Fedora 上重新分区并格式化为 `exFAT` 后，本机可以正常挂载和读写；但插到 macOS 上时，系统提示“此电脑不能读取你连接的磁盘”。

本次排障目标有两个：

- 在不碰主机内置系统盘的前提下，只操作目标 U 盘。
- 让该 U 盘同时被 Fedora 和 macOS 正常识别，并保留盘内已有文件。

## 2. Environment and Scope（环境与范围）

- 主机操作系统：Fedora
- 主机内置盘：`/dev/nvme0n1`，`SAMSUNG MZVL21T0HCLR-00BL2`，953.9G
- 目标外接盘：`Lenovo 128GB thinkplus`
- 目标外接盘序列号：`FC093C9F2E655`
- 目标外接盘在不同阶段的设备名：
  - 初始阶段：`/dev/sda`
  - 最终复查阶段：`/dev/sdb`
- 目标挂载点：`/run/media/chesszyh/SHAREUSB`
- 目标文件系统：`exFAT`
- 调查中涉及的本机文件：
  - `/home/chesszyh/twitter-bookmarks.json.usb-backup`
  - `/home/chesszyh/Documents/Reports/docs/fedora-exfat-usb-macos-unreadable-report-2026-04-27.md`
  - `/home/chesszyh/Documents/Reports/docs/index.md`

范围限定在 Fedora 侧对 U 盘的识别、分区、文件系统和跨平台兼容性元数据，不涉及主机内置盘分区、不涉及 macOS 上的磁盘工具手工修复。

## 3. Symptoms and Reproduction（现象与复现）

### 初始现象

- U 盘最开始仍保留 Ubuntu Server 启动盘布局，存在 `iso9660`、`ESP` 和 `writable` 分区。
- 第一次尝试清除分区签名和重建分区表时，U 盘在写入扇区 0 后掉线。
- 重新插拔并最终格式化为 `exFAT` 后，Fedora 可正常挂载、写入和卸载。
- 插到 macOS 后，系统提示无法读取该磁盘。

### Fedora 侧关键证据

最开始识别到的启动盘布局：

```text
sda    117.2G
├─sda1  2.1G iso9660 Ubuntu-Server 25.10 amd64
├─sda2    5M vfat    ESP
├─sda3  300K
└─sda4 115.1G ext4    writable
```

U 盘掉线时的内核日志：

```text
sd 0:0:0:0: [sda] tag#0 Add. Sense: Medium not present
I/O error, dev sda, sector 0 op 0x1:(WRITE)
sda: detected capacity change from 245760000 to 0
usb usb2-port8: unable to enumerate USB device
```

在 Fedora 侧能正常读写 `exFAT` 的证据：

```text
/dev/sdb1 /run/media/chesszyh/SHAREUSB exfat rw,...
```

盘内已有文件：

```text
/run/media/chesszyh/SHAREUSB/twitter-bookmarks.json
```

### 触发 macOS 报错的复现路径

1. 在 Fedora 上把该 U 盘恢复为 `GPT + exFAT`。
2. 将 U 盘安全卸载后插入 macOS。
3. macOS 报“此电脑不能读取你连接的磁盘”。

## 4. Investigation Timeline（调查时间线）

1. 先通过 `lsblk` 确认主机内置盘是 `nvme0n1`，目标 U 盘是可移动 USB 盘 `Lenovo 128GB thinkplus`，避免误操作主机磁盘。
2. 识别到 U 盘仍是 Ubuntu Server 启动盘布局，包含 `iso9660`、`ESP` 和 `writable` 分区，说明需要重建分区表。
3. 第一次执行 `wipefs` 和后续写盘动作时，设备在写扇区 0 后返回 `Medium not present`，容量一度变为 `0B`，因此先暂停并转向根因调查，而不是继续强写。
4. 检查 `dmesg` 后确认，掉线发生在对目标 U 盘 `/dev/sda` 的首扇区写入阶段，主机内置盘未参与任何写操作。
5. 重新插拔 U 盘，重新按 `MODEL + TRAN + RM + SERIAL` 校验目标身份，确保后续操作只会命中 `Lenovo 128GB thinkplus / FC093C9F2E655`。
6. 先用最小写入测试验证设备是否仍然“一写就掉线”。`dd if=/dev/zero of=/dev/sda bs=512 count=1` 成功，说明设备恢复到可写状态。
7. 分步执行重建流程：先写 `GPT`，再创建单分区，最后执行 `mkfs.exfat -n SHAREUSB`，避免把多个潜在失败点捆在一起。
8. 在 Fedora 上完成挂载、写入、卸载验证，确认 `exFAT` 文件系统本身是可用的。
9. 用户反馈 macOS 无法读取后，重新把 U 盘插回 Fedora，读取分区和文件系统元数据。
10. `fdisk -l /dev/sdb` 显示该盘虽然是 `exFAT`，但 GPT 分区类型被标记为 `Linux filesystem`，这与跨平台预期不符。
11. 使用 `fsck.exfat -n /dev/sdb1` 验证文件系统本身是干净的，因此问题不在 `exFAT` 损坏，而在 GPT 分区类型元数据。
12. 在修改前先把盘内文件备份到 `/home/chesszyh/twitter-bookmarks.json.usb-backup`，避免元数据调整过程中出现意外。
13. 卸载 U 盘后，仅使用 `sfdisk --part-type /dev/sdb 1 EBD0A0A2-B9E5-4433-87C0-68B6B72699C7` 将分区类型改为 `Microsoft basic data`，不重格式化、不改动文件系统内容。
14. 重新挂载并核对 `blkid`、`fsck.exfat -n` 和挂载目录内容，确认 `twitter-bookmarks.json` 仍在，文件系统仍干净。
15. 最后安全卸载并断电，用户回报插到 macOS 后识别成功。

## 5. Root Cause（根因）

### 直接根因

U 盘的文件系统是 `exFAT`，但 GPT 分区类型被建成了 `Linux filesystem`，而不是跨平台常用的 `Microsoft basic data`。

Fedora 在识别文件系统时更宽松，只要分区里的 `exFAT` 元数据正确，就可以正常挂载；macOS 对可移动存储介质会更重视 GPT 分区类型，因此在分区类型不匹配时直接报“不能读取该磁盘”。

### 为什么会出现这个错误类型

在 Fedora 上执行：

```bash
parted -s /dev/sda mkpart primary 1MiB 100%
```

后，虽然单分区本身创建成功，但默认分区类型被标成了 `Linux filesystem`。随后又执行了 `mkfs.exfat`，于是形成了“文件系统是 `exFAT`，GPT 类型却是 Linux”的混合状态。

### 非根因但会误导调查的现象

本次会话前半段还出现过 U 盘写入时掉线、`Medium not present`、USB 重新枚举失败等现象。这些现象说明该 U 盘或接口存在一定不稳定性，但它们不是 macOS 最终拒绝识别的根因。真正导致 macOS 报错的是 GPT 分区类型不正确。

## 6. Changes Made（已做变更）

### 对目标 U 盘做的变更

- 清除原 Ubuntu Server 启动盘分区布局。
- 重建为单分区 `GPT + exFAT`。
- 将卷标设置为 `SHAREUSB`。
- 将分区类型从 `Linux filesystem` 改为 `Microsoft basic data`。

### 本机落盘的辅助文件

- 为避免误操作后丢失现有内容，先备份了：

```text
/home/chesszyh/twitter-bookmarks.json.usb-backup
```

- 新增本报告并更新 Reports 首页索引：

```text
/home/chesszyh/Documents/Reports/docs/fedora-exfat-usb-macos-unreadable-report-2026-04-27.md
/home/chesszyh/Documents/Reports/docs/index.md
```

### 未做的事

- 没有对 `/dev/nvme0n1` 做任何写操作。
- 没有重新格式化修复阶段的 `exFAT` 分区。
- 没有修改盘内 `twitter-bookmarks.json` 内容。

## 7. Verification（验证）

### Fedora 侧验证

分区类型修复后的 `fdisk` 结果：

```text
Device     Start       End   Sectors   Size Type
/dev/sdb1   2048 245757951 245755904 117.2G Microsoft basic data
```

文件系统识别结果：

```text
/dev/sdb1: LABEL="SHAREUSB" UUID="EFEF-B505" BLOCK_SIZE="512" TYPE="exfat"
```

文件系统一致性检查：

```text
exfatprogs version : 1.3.2
/dev/sdb1: clean. directories 1, files 1
```

盘内文件复查结果：

```text
/run/media/chesszyh/SHAREUSB/twitter-bookmarks.json
```

### macOS 侧验证

用户在修正 GPT 分区类型后反馈“成功了”，说明该 U 盘已经可以被 macOS 识别。

### 安全移除验证

Fedora 侧执行了：

```bash
udisksctl unmount -b /dev/sdb1
udisksctl power-off -b /dev/sdb
```

之后 `lsblk` 中只剩主机内置盘 `nvme0n1`，说明该 U 盘已从 Fedora 侧干净移除。

## 8. Problems Encountered During Debugging（调试中遇到的问题）

- 最早的写盘失败容易让人误判为“格式化命令不对”或“分区表残留太脏”，但 `dmesg` 明确显示是设备写入时掉线。
- 在第一次成功做出 `exFAT` 后，Fedora 本机可用，容易让人过早认为任务已经完成；如果没有继续检查 macOS 侧兼容性，会漏掉 GPT 分区类型问题。
- `parted` 默认创建的 GPT 分区类型在这个场景下不适合跨平台 U 盘，这是这次最容易重复踩坑的点。
- 调试过程中 U 盘的设备名从 `/dev/sda` 变成 `/dev/sdb`，如果后续脚本仍写死旧设备名，会有误操作风险，因此每一步都重新做了 `MODEL / TRAN / RM / SERIAL` 校验。

## 9. Reuse Notes and Lessons（复用笔记与经验）

- 要做 Fedora 与 macOS 互传的 U 盘，不要只验证“Fedora 能挂载 `exFAT`”，还要验证 GPT 分区类型是否是 `Microsoft basic data`。
- 对可移动介质做危险操作前，优先通过以下组合确认目标身份：
  - `MODEL`
  - `TRAN`
  - `RM`
  - `SERIAL`
- 如果看到 `Medium not present`、`capacity change to 0`、`unable to enumerate USB device`，先停下来检查硬件链路，不要连续强写。
- 当 `exFAT` 文件系统本身是干净的，但 macOS 仍提示无法读取时，优先检查 `fdisk -l` 中的 GPT `Type`，不要一上来就重格式化。
- 修改 GPT 分区类型前，先备份盘内已有文件；像本次这样只改分区类型 GUID，通常比重做文件系统更保守。

## 10. Appendix: Reusable Commands（附录：可复用命令）

### 识别目标 U 盘并避免碰到主机内置盘

```bash
lsblk -o NAME,MODEL,SIZE,FSTYPE,LABEL,MOUNTPOINTS,RM,RO,TYPE,TRAN,SERIAL
lsblk -S -o NAME,MODEL,SIZE,TRAN,RM,VENDOR,SERIAL,HOTPLUG
```

### 检查 U 盘在 Fedora 上的挂载来源

```bash
findmnt -T /run/media/chesszyh/SHAREUSB -o SOURCE,TARGET,FSTYPE,OPTIONS -n
ls -la /run/media/chesszyh/SHAREUSB
```

### 检查分区类型与文件系统是否一致

```bash
sudo fdisk -l /dev/sdb
sudo blkid /dev/sdb1
sudo fsck.exfat -n /dev/sdb1
```

### 仅修复 GPT 分区类型，不重格式化

```bash
sudo umount /dev/sdb1
sudo sfdisk --part-type /dev/sdb 1 EBD0A0A2-B9E5-4433-87C0-68B6B72699C7
sudo partprobe /dev/sdb
sudo udevadm settle
```

### 重新挂载并确认内容还在

```bash
udisksctl mount -b /dev/sdb1
ls -la /run/media/chesszyh/SHAREUSB
sudo fsck.exfat -n /dev/sdb1
```

### 安全移除 U 盘

```bash
sudo udisksctl unmount -b /dev/sdb1
sudo udisksctl power-off -b /dev/sdb
```
