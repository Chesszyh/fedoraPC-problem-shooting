# Audio Separator 长任务容器自动删除与结果丢失问题报告

生成时间: 2026-04-18T17:21:20+08:00

## 1. Problem Description

在 `/home/chesszyh/Downloads/python-audio-separator` 中用 Docker + NVIDIA RTX 4060 处理两段约 140 分钟的直播音频，目标是提取干净人声供 GPT-SoVITS 工作流使用。

任务运行策略原本为：

- `evil-neuro`: 使用慢速高质量 `vocal_clean` 双模型 ensemble。
- `neuro`: 等 `evil-neuro` 完成后再运行快速单模型方案。

实际结果是：`evil-neuro` 容器在最后 ensemble 阶段被 SIGKILL，Docker 容器因为使用 `--rm` 启动而自动删除。最终输出没有写入宿主机，容器内部 `/tmp` 中的临时 chunk 合并结果也随容器删除而丢失。

这是一次长任务运行策略错误，核心问题不是模型下载、GPU 透传或输入文件损坏，而是长任务容器生命周期和临时文件持久化设计不当。

## 2. Environment and Scope

主机环境：

- Fedora，内核日志显示 `6.19.10-200.fc43.x86_64`
- NVIDIA RTX 4060 Laptop GPU，8GB VRAM
- Docker `29.4.0`
- Docker Compose `v5.1.3`
- NVIDIA driver `580.142`
- 项目路径：`/home/chesszyh/Downloads/python-audio-separator`

相关输入：

- `/home/chesszyh/Downloads/python-audio-separator/data/input/neuro.m4a`
- `/home/chesszyh/Downloads/python-audio-separator/data/input/evil-neuro.m4a`
- `/home/chesszyh/Downloads/python-audio-separator/data/work/source_flac/neuro.flac`
- `/home/chesszyh/Downloads/python-audio-separator/data/work/source_flac/evil-neuro.flac`

相关输出目录：

- `/home/chesszyh/Downloads/python-audio-separator/data/output/vocal_clean/`
- `/home/chesszyh/Downloads/python-audio-separator/data/output/neuro_fast_resurrection/`

相关脚本：

- `/home/chesszyh/Downloads/python-audio-separator/scripts/docker-separate.sh`
- `/home/chesszyh/Downloads/python-audio-separator/scripts/watch-separation-and-notify.sh`
- `/home/chesszyh/Downloads/python-audio-separator/scripts/run-vocal-clean-batch.sh`
- `/home/chesszyh/Downloads/python-audio-separator/data/work/wait-evil-clean-then-neuro-fast.sh`

## 3. Symptoms and Reproduction

用户观察到容器日志最后停在：

```text
2026-04-18 09:10:44.985 - INFO - separator - Chunked processing completed. Output files: ['/tmp/audio-separator-ensemble-zd7_qrj_/evil-neuro_(vocals).flac']
2026-04-18 09:10:45.301 - INFO - separator - Ensembling 2 stems for type: Vocals
```

随后电脑整体卡顿。任务结束后检查：

```bash
docker ps -a --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'
find data/output -maxdepth 4 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' | sort
```

结果：

- `audio-separator` 容器不在 `docker ps -a` 中。
- `data/output/vocal_clean/` 没有最终输出。
- `data/output/neuro_fast_resurrection/` 没有最终输出。
- 只有之前 smoke test 的 `data/output/smoke/mardy20s_(Vocals)_model_bs_roformer_ep_317_sdr_12.flac`。

续跑服务日志显示：

```text
===== wait evil-neuro vocal_clean container START 2026-04-18T16:21:26+08:00 =====
container: 708809fa2b0e
===== evil-neuro vocal_clean container EXIT 137 2026-04-18T17:12:32+08:00 =====
```

`137` 通常表示进程被 `SIGKILL` 终止。由于容器是用 `--rm` 启动，Docker 自动删除了容器和容器私有临时目录。

## 4. Investigation Timeline

1. 构建本地 CUDA Docker 镜像，验证容器内 CUDA 和 ONNX Runtime GPU provider 可用。
2. 用户提供两个 `.m4a` 长音频，分别约 8150 秒和 8475 秒。
3. 首次直接对 `.m4a` 使用 `--chunk_duration` 失败，错误为：

```text
Requested output format 'm4a' is not a suitable output format
```

4. 将 `.m4a` 转为 FLAC 中间文件，规避分块导出 `.m4a` 的 FFmpeg 格式问题。
5. 运行 `evil-neuro` 的 `vocal_clean` 双模型方案。
6. 发现运行很慢，确认 GPU 已经接近满载，且 `vocal_clean` 是两个 RoFormer 模型 ensemble，不适合并行再开第二路。
7. 用户要求完成通知，新增 `watch-separation-and-notify.sh`。
8. 原始外层批处理 shell 被中断后，Docker 容器仍继续运行，但外层批处理不再负责后续 `neuro` 任务。
9. 新增续跑 systemd 用户服务，等待当前 `evil-neuro` 容器完成后再启动 `neuro` 快速单模型方案。
10. `evil-neuro` 容器最后返回 exit code `137`，续跑脚本按失败处理，没有启动 `neuro`。
11. 检查输出目录，确认没有最终人声成品。
12. 根据用户提供的容器日志，定位实际失败阶段为两个完整 stem 的最终 ensemble 阶段，而不是 chunk 推理阶段。
13. 检查 `/tmp`、`/var/tmp` 和项目 `data/`，未发现可抢救的临时 FLAC。
14. `docker inspect 708809fa2b0e` 返回 `no such object`，确认容器已因 `--rm` 被删除。

## 5. Root Cause

根因分两层。

第一层是运行策略错误：`scripts/docker-separate.sh` 使用 `docker run --rm` 启动长任务。`--rm` 使容器退出后立即删除容器对象和容器私有可写层。对于短 smoke test 这很方便，但对于多小时、存在大量容器内临时中间结果的音频分离任务，这是错误选择。

第二层是临时目录未持久化：`audio-separator` 在 ensemble 时使用容器内部 `/tmp/audio-separator-ensemble-*` 保存两个模型的整段临时 vocals。该目录没有 bind mount 到宿主机。容器被 SIGKILL 后，临时目录随容器私有层删除，无法再从宿主机恢复。

直接触发因素是最终 ensemble 阶段内存压力过大。日志显示两个模型的 chunk 输出已经完成并合并到容器内部临时 FLAC，然后进入：

```text
Ensembling 2 stems for type: Vocals
```

该阶段会读取两个约 8150 秒的完整 stem 做合成，比单个 600 秒 chunk 推理阶段内存压力更高。系统卡顿和 exit code `137` 与此一致。

## 6. Changes Made

已修改 `/home/chesszyh/Downloads/python-audio-separator/scripts/docker-separate.sh`：

- 默认不再传 `--rm`。
- 新增 `AUDIO_SEPARATOR_AUTO_REMOVE=1` 才启用自动删除。
- 新增 `AUDIO_SEPARATOR_WORK_TMP`，默认映射到 `/home/chesszyh/Downloads/python-audio-separator/data/work/container_tmp`。
- 启动容器时设置 `TMPDIR=/work_tmp`。
- 默认生成可追踪容器名 `audio-separator-<input>-<timestamp>-<pid>`。
- 输出提示用户验证后手动删除容器。

已修改 `/home/chesszyh/Downloads/python-audio-separator/docs/docker-fedora-rtx4060-tts-vocal-extraction.zh.md`：

- 记录默认保留容器的原因。
- 记录 `data/work/container_tmp` 的用途。
- 记录只有短任务才建议启用 `AUDIO_SEPARATOR_AUTO_REMOVE=1`。
- 记录当前 RTX 4060 设备不建议并行跑多个 RoFormer 分离任务。

已新增或更新：

- `/home/chesszyh/Downloads/python-audio-separator/scripts/watch-separation-and-notify.sh`
- `/home/chesszyh/Downloads/python-audio-separator/scripts/run-vocal-clean-batch.sh`
- `/home/chesszyh/Downloads/python-audio-separator/data/work/wait-evil-clean-then-neuro-fast.sh`
- `/home/chesszyh/Downloads/python-audio-separator/docs/gpt-sovits-vocal-dataset-workflow.zh.md`

## 7. Verification

脚本语法检查：

```bash
bash -n scripts/docker-separate.sh scripts/watch-separation-and-notify.sh scripts/run-vocal-clean-batch.sh
```

验证结果：命令退出码为 `0`。

确认原容器不可恢复：

```bash
docker inspect 708809fa2b0e
```

结果：

```text
[]
error: no such object: 708809fa2b0e
```

确认输出目录没有成品：

```bash
find data/output -maxdepth 4 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' | sort
```

结果只显示 smoke test 文件：

```text
data/output/smoke/mardy20s_(Vocals)_model_bs_roformer_ep_317_sdr_12.flac
```

确认 Docker 只看到其他历史容器：

```bash
docker ps -a --no-trunc --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'
```

未出现 `708809fa2b0e` 或当前 audio-separator 容器。

## 8. Problems Encountered During Debugging

1. 低估了 `vocal_clean` 双模型对长音频最终 ensemble 阶段的内存压力。
2. 将短任务习惯用法 `--rm` 沿用到长任务，导致容器被 kill 后没有恢复窗口。
3. 最初只关注 GPU 是否满载、模型是否可用和 chunk 是否推进，未优先设计中间产物持久化。
4. 外层批处理被中断后，Docker 容器仍在后台继续运行，导致任务状态从“批处理可控”变成“单容器孤立运行”。后续虽然增加了 systemd 等待服务，但仍依赖该容器正常 exit 0。
5. 初版通知脚本用日志关键字粗略判断错误，曾把 `total_failures: 0` 这类正常日志误判为失败风险。后来收紧了匹配规则。
6. 报告前曾尝试查找 `/tmp`、`/var/tmp`、项目 `data/` 和 Docker 容器对象，但由于 `--rm` 已删除容器，普通恢复路径不可用。

## 9. Reuse Notes and Lessons

长任务 Docker 规则：

- 默认不要对多小时任务使用 `--rm`。
- 必须把关键临时目录 bind mount 到宿主机。
- 必须把日志、资源占用和最终输出分开保存。
- 容器名必须可预测，便于 `docker logs`、`docker inspect`、`docker cp` 和 `docker rm`。
- 只有确认输出完整后再删除容器。

音频分离规则：

- `--chunk_duration` 只降低单个模型 chunk 推理的峰值压力，不一定降低最后全长 ensemble 的压力。
- 双模型 ensemble 对长音频可能在最后一次性读入多个完整 stem，引发内存峰值。
- 对 2 小时以上音频，更安全的高质量方案是宿主机预切片，每片独立跑 ensemble，再在宿主机拼接，而不是让一个容器内部完成全长 ensemble。
- 快速产出时优先使用单模型，避免最终双 stem ensemble。

工程流程规则：

- 开始长任务前必须明确失败恢复路径。
- 如果任务预计超过 30 分钟，应默认保留容器、保留中间目录、记录资源曲线。
- 不应仅凭“GPU 正常满载”判断任务安全；CPU 内存、swap、临时目录和最终合成阶段同样关键。
- 对用户承诺“帮我跑完”时，必须优先选择可恢复设计，而不是方便清理的临时运行方式。

## 10. Appendix: Reusable Commands

检查 Docker 容器：

```bash
docker ps -a --no-trunc --format 'table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Names}}'
docker inspect <container_id_or_name>
docker logs -f <container_id_or_name>
```

检查输出文件：

```bash
find data/output -maxdepth 4 -type f -printf '%TY-%Tm-%Td %TH:%TM:%TS %s %p\n' | sort
ffprobe -hide_banner data/output/path/to/file.flac
```

检查资源：

```bash
nvidia-smi --query-gpu=timestamp,utilization.gpu,utilization.memory,memory.used,memory.total,temperature.gpu,power.draw --format=csv
free -h
df -h . data
```

安全运行单模型快速方案：

```bash
AUDIO_SEPARATOR_OUTPUT_DIR="$PWD/data/output/neuro_fast_resurrection" \
AUDIO_SEPARATOR_MODEL_DIR="$PWD/data/models" \
AUDIO_SEPARATOR_WORK_TMP="$PWD/data/work/container_tmp/neuro_fast_resurrection" \
AUDIO_SEPARATOR_CHUNK=600 \
AUDIO_SEPARATOR_CONTAINER_NAME="audio-separator-neuro-fast-$(date +%Y%m%d-%H%M%S)" \
scripts/docker-separate.sh \
  data/work/source_flac/neuro.flac \
  -m bs_roformer_vocals_resurrection_unwa.ckpt \
  --log_level info
```

确认无误后删除保留容器：

```bash
docker ps -a --filter name=audio-separator
docker rm <container_name_or_id>
```
