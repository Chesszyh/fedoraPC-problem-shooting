# Fedora Legion Y9000P 拆机清灰换硅脂前后体检对比报告

生成时间: 2026-05-26T21:36:49+08:00

## Problem Description

联想拯救者 Y9000P 2023 在深度拆机清灰并更换硅脂后，需要与清灰前保存的体检快照对比，判断：

- 机器性能是否提升；
- 散热状态是否改善；
- 内存、SSD、GPU、主板等硬件身份是否被更换或异常；
- 清灰后是否出现新的 SMART、NVIDIA、系统日志层面的明显问题。

## Environment and Scope

- 主机: `/home/chesszyh`
- 系统: Fedora 43 / Hyprland
- 证据根目录: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18`
- 清灰前 run: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913`
- 清灰后 run: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610`
- 体检脚本: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh`
- 对比脚本: `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh`

本报告只总结已经完成的两次本机脚本采集，不重新改动系统配置。

## Symptoms and Reproduction

清灰前用户观察到两侧风扇明显积灰、游戏时发烫。清灰前先建立了包含 DMI、NVMe SMART、NVIDIA、传感器、`turbostat`、`stress-ng` 的完整快照。清灰换硅脂后使用同一脚本复跑：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18 \
  post-clean
```

对比命令：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913 \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610
```

## Investigation Timeline

1. 清灰前在 `2026-05-18` 保存基线：`pre-clean-20260518-220913`。
2. 深度拆机清灰并更换硅脂后，在 `2026-05-26` 复跑同一脚本：`post-clean-20260526-171610`。
3. 复查 `command-index.tsv`，清灰后仍只有 `hwmon_sysfs` 返回非零，原因是部分 hwmon glob 不存在或不可读；主体传感器、DMI、SMART、NVIDIA、压力测试均完成。
4. 运行对比脚本，重点检查硬件身份、NVMe SMART、NVIDIA 热降频、CPU 压力性能和传感器峰值。

## Root Cause

清灰前性能偏保守的主要原因不是硬件故障，而是散热/电源状态下 CPU 没有释放高功耗。清灰后 CPU 能在压力测试中拉到更高功耗和频率，性能提升明显。

关键结论：

- 没有看到硬件被调包的证据。
- NVMe、GPU、内存、整机 DMI 等关键身份锚点一致。
- 清灰后 CPU 压力性能显著提高。
- 清灰后 SSD/GPU 温度更低。
- CPU 监控日志出现过 `99 C` 瞬时峰值，但 `turbostat` 压力段摘要为 `PkgTmp=77 C`，更像高功耗释放时的瞬时峰值，不是持续过热证据。

## Changes Made

本次对系统未做配置修改。新增的是清灰后证据 run：

- `/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610`

本报告新增：

- `/home/chesszyh/Documents/Reports/docs/fedora-y9000p-cleaning-postcheck-comparison-report-2026-05-26.md`

## Verification

硬件身份检查：

- 整机: LENOVO `82WK` / `Legion Y9000P IRX8`，与清灰前一致。
- BIOS: `KWCN36WW` / `1.36`，与清灰前一致。
- 主板: `LNVNB161216`，与清灰前一致。
- 内存: 两条 SK Hynix 8 GB DDR5-5600，Part Number `HMCG66AGBSA092N`，与清灰前一致。
- NVMe: Samsung `SAMSUNG MZVL21T0HCLR-00BL2`，Firmware `CL1QGXA7`，与清灰前一致。
- GPU: RTX 4060 Laptop GPU，UUID `GPU-5011cbcd-7033-6444-66e7-e485ade01645`，VBIOS `95.07.16.80.6D`，Subsystem `0x3B5317AA`，与清灰前一致。
- 电池: COSMX `L22X4PC0`，容量信息与清灰前一致。

性能和温度对比：

| 指标 | 清灰前 | 清灰后 | 结论 |
| --- | ---: | ---: | --- |
| CPU stress-ng bogo ops/s | `21059.65` | `42730.46` | 明显提升，约 2 倍 |
| CPU stress-ng bogo ops | `3790784` | `7691520` | 明显提升 |
| `turbostat Avg_MHz` | `1761` | `3388` | 频率释放明显 |
| `turbostat Bzy_MHz` | `1781` | `3448` | 频率释放明显 |
| `turbostat PkgWatt` | `42.50 W` | `119.53 W` | CPU 功耗释放明显 |
| `turbostat PkgTmp` | `72 C` | `77 C` | 高功耗下仍可接受 |
| 监控 CPU Package 峰值 | `73 C` | `99 C` | 清灰后瞬时峰值更高，因功耗大幅释放 |
| NVMe SMART 温度 | `52 C` | `38 C` | 明显更低 |
| 监控 NVMe 峰值 | `52.9 C` | `43.9 C` | 明显更低 |
| NVIDIA 当前温度 | `52 C` | `41 C` | 更低 |
| 监控 GPU 峰值 | `56 C` | `50 C` | 更低 |

健康检查：

- NVMe `critical_warning=0`，`media_errors=0`，`num_err_log_entries=0`。
- NVIDIA `HW Thermal Slowdown=0`，状态为 `Not Active`。
- 清灰后 CPU 压力测试和短内存压力测试均通过。

## Problems Encountered During Debugging

- 用户中途询问测试耗时并中断了等待输出，但后台脚本继续执行并完成。
- `hwmon_sysfs` 返回状态 2，与清灰前一致；该项不影响 `sensors`、`turbostat` 和核心温度结论。
- 清灰前与清灰后的电源/性能状态不完全相同：清灰前 `stress-ng` 明确提示 turbo disabled 和 powersave governor；清灰后没有该提示。因此 CPU 提升同时包含散热维护和当时电源/性能状态变化的影响，不能把全部 2 倍提升都归因于硅脂。

## Reuse Notes and Lessons

- 判断拆机后是否调包，应优先看硬件身份锚点，而不是只看温度或体感。
- 清灰后 CPU 可能因为散热/功耗释放而跑得更快，温度峰值反而更高；要同时看频率、功耗、测试成绩和是否持续热降频。
- 本次最有价值的对比是：硬件身份一致、CPU 成绩大幅上升、NVMe/GPU 温度下降、无 SMART 和 NVIDIA 硬件热降频告警。

## Appendix: Reusable Commands

复跑清灰后体检：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/y9000p_health_snapshot.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18 \
  post-clean
```

对比两个 run：

```bash
/home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/scripts/compare_y9000p_runs.sh \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/pre-clean-20260518-220913 \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610
```

查看清灰后异常命令状态：

```bash
awk -F'\t' 'NR==1 || $2 != 0 {print}' \
  /home/chesszyh/Documents/Reports/evidence/y9000p-cleaning-baseline-2026-05-18/runs/post-clean-20260526-171610/command-index.tsv
```
