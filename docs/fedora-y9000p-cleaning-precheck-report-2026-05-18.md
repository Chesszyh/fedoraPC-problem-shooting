# Fedora Legion Y9000P 清灰前硬件与性能快照报告

生成时间: 2026-05-18T22:17:41+08:00

## Problem Description

本机是联想拯救者 Y9000P 2023，运行 Fedora 43 / Hyprland。机器已使用约 3 年，两侧风扇有明显积灰，游戏时偶发发烫。清灰前需要保留可复跑脚本和原始输出，作为清灰后的性能、温控和硬件身份对比基线。

## Environment and Scope

- 主机路径: `/home/chesszyh`
- 证据目录: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18`
- 清灰前运行目录: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913`
- 原始采集脚本: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh`
- 后续对比脚本: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh`
- 系统: Fedora Linux 43，kernel `7.0.4-100.fc43.x86_64`
- CPU: `13th Gen Intel(R) Core(TM) i9-13900HX`，32 线程
- GPU: `NVIDIA GeForce RTX 4060 Laptop GPU`

## Symptoms and Reproduction

用户主观症状是积灰明显、游戏时发烫。本次没有复现具体游戏场景，而是建立一套清灰前/清灰后可重复的机器体检流程：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18 \
  pre-clean
```

脚本执行约 6 分钟，包含硬件身份采集、SMART/电池/日志采集、60 秒空闲监控、180 秒 CPU 压力测试和 90 秒短内存压力测试。所有命令输出保存在 `raw/` 和 `monitor/` 下，`command-index.tsv` 记录每条命令状态，`SHA256SUMS` 固化证据文件哈希。

## Investigation Timeline

1. 先检查本机可用工具，确认已有 `inxi`、`dmidecode`、`sensors`、`stress-ng`、`glxinfo`、`nvidia-smi`、`nvme`、`smartctl`、`tlp-stat`、`turbostat`。
2. 编写 `y9000p_health_snapshot.sh`，使用免密 `sudo -n` 采集 DMI、NVMe SMART、PCI 详细信息、dmesg、turbostat。
3. 执行清灰前基线，运行目录为 `runs/pre-clean-20260518-220913`。
4. 检查 `command-index.tsv`，只有 `hwmon_sysfs` 因部分 glob/权限返回非零；该文件仍写入了可读的 hwmon 内容，不影响主体证据。
5. 编写 `compare_y9000p_runs.sh`，用于清灰后把两个 run 目录做身份和性能差异比较。

## Root Cause

本次目标是清灰前建档，不是已经定位某个单一故障。基于当前快照：

- CPU 压力测试 180 秒通过，未看到测试失败。
- `turbostat` 摘要显示 CPU 压力段 `PkgTmp` 约 72 C，传感器监控峰值 Package 约 73 C。
- NVIDIA 当前/结束状态没有硬件热降频激活，`HW Thermal Slowdown` 为 `Not Active`，计数为 0。
- NVMe SMART `critical_warning=0`，`media_errors=0`，`num_err_log_entries=0`。
- 当前环境中 `stress-ng --vm-bytes 70%` 只识别到约 400 MB available memory，因此内存压力段仅作为脚本执行证明，不作为整机内存压力基准。

## Changes Made

新增文件：

- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh`
- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh`
- `/home/chesszyh/Documents/Reports/docs/fedora-y9000p-cleaning-precheck-report-2026-05-18.md`

生成证据：

- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/raw/`
- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/monitor/`
- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/command-index.tsv`
- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/SHA256SUMS`

## Verification

关键清灰前身份锚点已经记录在原始输出中：

- 整机: LENOVO `82WK` / `Legion Y9000P IRX8`
- BIOS: `KWCN36WW`，Release Date `04/28/2023`，BIOS Revision `1.36`
- 主板: LENOVO `LNVNB161216`
- 内存: 两条 SK Hynix 8 GB DDR5-5600 SODIMM，Part Number `HMCG66AGBSA092N`
- NVMe: Samsung `SAMSUNG MZVL21T0HCLR-00BL2`，1.02 TB，Firmware `CL1QGXA7`
- NVIDIA: RTX 4060 Laptop GPU，VBIOS `95.07.16.80.6D`，Device ID `0x28E010DE`，Subsystem ID `0x3B5317AA`
- 电池: COSMX `L22X4PC0`，设计容量 80 Wh，当前 full 70.53 Wh，健康约 88.16%

关键清灰前性能/温控锚点：

- CPU 压力段: `stress-ng` CPU bogo ops `3790784`，约 `21059.65` bogo ops/s real time。
- `turbostat` 压力段摘要: `Avg_MHz=1761`，`Busy%=98.91`，`Bzy_MHz=1781`，`PkgTmp=72`，`PkgWatt=42.50`。
- 传感器监控峰值: CPU Package 约 73 C，CPU Core 约 73 C，NVMe Composite 约 52.9 C，GPU 约 56 C。
- 空闲监控范围: CPU Package 约 61-65 C，NVMe 约 51.9-52.9 C，GPU 约 48-50 C。

## Problems Encountered During Debugging

- `hwmon_sysfs` 命令返回状态 2，原因是某些 `hwmon` glob 不存在或不可读；脚本仍保留了可读取的 `hwmon` 内容。
- `sensors` 对部分 `temp1_max_alarm` 子项提示 `Can't read`，属于传感器驱动暴露字段不可读，不影响温度主体值。
- 没有安装 `glmark2`、`vulkaninfo`、`fio`，因此本次没有加入图形跑分和磁盘写入压力测试。清灰对磁盘写入性能意义较小，避免无必要写盘。
- 内存压力段受当前运行环境可见内存影响，只使用约 280 MB，总结时不应把它当作全内存压力基准。

## Reuse Notes and Lessons

清灰后建议在相同电源模式、同样外接电源、同样室温附近、关闭大型后台任务后运行：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18 \
  post-clean
```

然后找出最新的 `post-clean-*` 目录，与本次 `pre-clean-20260518-220913` 对比：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913 \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-YYYYMMDD-HHMMSS
```

清灰后重点看：

- 硬件身份是否一致: DMI、内存条序列号/Part Number、NVMe 序列号、NVIDIA UUID/VBIOS/subsystem id。
- 同样压力下 CPU Package 峰值是否下降，或者同温度下 `Avg_MHz` / `Bzy_MHz` 是否更高。
- NVIDIA 是否出现新的 `HW Thermal Slowdown` 或异常功耗限制。
- NVMe SMART 是否出现新的 media error、error log、critical warning。
- 电池型号、serial、full capacity 是否异常跳变。

## Appendix: Reusable Commands

查看清灰前命令状态：

```bash
awk -F'\t' 'NR==1 || $2 != 0 {print}' \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/command-index.tsv
```

查看清灰前文件哈希：

```bash
sha256sum -c \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/SHA256SUMS
```

快速抽取温度峰值：

```bash
awk '
/Package id 0:/ {gsub(/[+°C]/,"",$4); if($4>pkg) pkg=$4}
/Core [0-9]+:/ {gsub(/[+°C]/,"",$3); if($3>core) core=$3}
/Composite:/ {gsub(/[+°C]/,"",$2); if($2>nvme) nvme=$2}
/^[0-9]{4}\// {split($0,a,","); gsub(/^ +| +$/,"",a[5]); if(a[5]>gpu) gpu=a[5]}
END {printf "package_max=%s\ncore_max=%s\nnvme_max=%s\ngpu_max=%s\n",pkg,core,nvme,gpu}
' /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913/monitor/*.log
```
