# Mac mini 外接 NTFS 磁盘不可写与局域网传输速度分析报告

生成时间: 2026-04-28T00:38:40+08:00

## 1. 问题描述

本次问题由磁盘清理需求触发。目标是将 `~/Music` 下约 `12G` 的音频目录迁移到外接移动硬盘，以释放 Mac mini 本地空间。

实际遇到的两个问题是：

1. 外接移动硬盘虽然已经被 macOS 识别，但文件系统为 `NTFS`，在当前环境下只能只读挂载，无法直接写入。
2. 临时改走局域网，将目录传到局域网内 Fedora 主机时，实际传输速度只有大约 `13–16 MB/s`，用户希望确认这是否走了 `Clash Verge Rev (TUN)` 代理，以及为什么“局域网传输”没有跑满预期带宽。

最终采用的方案是：

- 不在当前 Mac 上安装 `NTFS` 写入驱动
- 先将目录传到 Fedora 主机的 `/home/chesszyh/Music`
- 后续由 Fedora 侧负责写入外接 `NTFS` 磁盘

## 2. 环境与范围

- 主机：Mac mini
- CPU 架构：Apple Silicon (`Apple M4`)
- 系统：`macOS 15.7.3`
- 外接磁盘：`Seagate Expansion Drive`
- 外接磁盘文件系统：`NTFS`
- Clash 客户端：`Clash Verge Rev`，启用 `TUN`
- 局域网目标主机：Fedora，使用私网地址 `<fedora-ip>`（原会话中为 `192.168.1.x` 网段）
- Mac mini 当前网络：`Wi‑Fi` (`en1`)
- Fedora 当前网络：`Wi‑Fi` (`wlp0s20f3`)

本次迁移涉及的主要目录：

```text
~/Music/neuro
~/Music/evil-neuro
```

会话中测得体积：

```text
6.0G ~/Music/neuro
5.9G ~/Music/evil-neuro
```

## 3. 症状与复现

### 3.1 外接 NTFS 磁盘不可写

外接盘挂载后可见于：

```text
/Volumes/Seagate Expansion Drive
```

写入测试失败：

```bash
touch '/Volumes/Seagate Expansion Drive/.codex_write_test'
```

错误：

```text
touch: /Volumes/Seagate Expansion Drive/.codex_write_test: Read-only file system
```

挂载状态显示为只读：

```bash
mount | rg 'Seagate Expansion Drive|ntfs'
```

结果中包含：

```text
(ntfs, local, nodev, nosuid, read-only, noowners, noatime, fskit)
```

### 3.2 局域网传输速度低于主观预期

使用 `rsync` 通过 `SSH` 将目录传输到 Fedora：

```bash
rsync -avhP --stats ~/Music/neuro ~/Music/evil-neuro chesszyh@<fedora-ip>:/home/chesszyh/Music/
```

会话中持续观察到的速率大致为：

```text
9–19 MB/s 波动
常见区间约 13–16 MB/s
```

用户的直觉疑问是：

- 是否经过了 `Clash` 代理
- 是否是 `rsync/SSH` 本身太慢
- 为什么“局域网”没有跑满预期带宽

## 4. 排查时间线

1. 先确认外接盘是否已经正常挂载。
   使用 `ls -la /Volumes` 和 `diskutil list external physical`，确认当前只有一个外接卷，名称为 `Seagate Expansion Drive`，容量约 `1TB`，文件系统为 `Windows_NTFS`。

2. 再确认问题是否是空间不足而不是写权限不足。
   使用 `df -h '/Volumes/Seagate Expansion Drive'`，确认磁盘空余空间约 `693Gi`，空间不是问题。

3. 对外接盘做最小写入测试。
   `touch` 失败并返回 `Read-only file system`，说明问题不是路径拼写或 Finder 权限，而是挂载层面只读。

4. 检查挂载参数。
   `mount` 输出中明确出现 `ntfs` 和 `read-only`，确认 macOS 当前使用的是系统只读 `NTFS` 挂载能力。

5. 讨论 `NTFS` 可写方案。
   排查方向曾转向 `Paragon NTFS for Mac`。进一步核实后发现，在 `Apple Silicon + macOS 15` 场景下，稳定可写通常需要安装第三方驱动，并进入 Recovery 调整到 `Reduced Security`，这超出了用户可接受的系统改动范围。

6. 于是改成“先传到 Fedora，再由 Fedora 写盘”的中转方案。
   先验证局域网 Fedora 主机上的 `SSH` 免密可用，并创建目标目录：

   ```bash
   ssh -o BatchMode=yes -o ConnectTimeout=5 chesszyh@<fedora-ip> 'echo connected && mkdir -p /home/chesszyh/Music'
   ```

7. 排查“这条流量会不会走 Clash 代理”。
   使用：

   ```bash
   route -n get <fedora-ip>
   ```

   结果显示目标地址走 `en1`，不是远端代理出口。

8. 继续检查 `Clash Verge Rev` 配置是否显式绕过局域网。
   在 `~/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml` 中检索到以下规则：

   ```text
   allow-lan: true
   tun.enable: true
   tun.auto-route: true
   IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
   IP-CIDR,172.16.0.0/12,DIRECT,no-resolve
   IP-CIDR,192.168.0.0/16,DIRECT,no-resolve
   ```

   这一步推翻了“局域网传输可能走代理流量”的怀疑。

9. 再排查“是不是 rsync/SSH 自身太慢”。
   观察 `rsync` 进程资源占用：

   ```bash
   ps -o pid,%cpu,%mem,command -p <rsync-pid>
   ```

   会话中 `CPU` 仅约 `5%`，没有出现 CPU 打满或加密明显成为瓶颈的迹象。

10. 检查无线链路质量。
    通过 `system_profiler SPAirPortDataType` 获取当前 Wi‑Fi 状态，看到：

    ```text
    PHY Mode: 802.11ax
    Channel: 153 (5GHz, 80MHz)
    Signal / Noise: -57 dBm / -92 dBm
    Transmit Rate: 288
    ```

    同时在 Fedora 侧确认目标主机接口为 `wlp0s20f3`，也是 Wi‑Fi，不是有线。

11. 由此得出最终解释：
    当前路径不是“本机直连文件系统”，而是：

    ```text
    Mac mini -> Wi‑Fi -> AP/路由器 -> Wi‑Fi -> Fedora
    ```

    这是双无线客户端经同一个 AP 中转的场景，同一份数据会占用两次无线空口时间，因此 `13–16 MB/s` 的吞吐与链路状态是吻合的。

12. 继续执行 `rsync`，用户后续确认传输完成。

## 5. 根因

### 5.1 外接盘不可写的根因

根因不是磁盘空间不足，也不是 Finder/Unix 权限问题，而是：

- 外接盘文件系统为 `NTFS`
- 当前 `macOS 15.7.3` 在本机上以系统自带 `NTFS` 只读能力挂载该卷
- 未安装第三方 `NTFS` 写入驱动，也未修改系统安全策略去支持此类驱动

因此该卷在当前 Mac 上天然不可写。

### 5.2 局域网传输速度不高的根因

根因不是 `Clash` 代理，也不是 `rsync/SSH` 的 CPU 开销，而是无线拓扑本身：

- Mac mini 与 Fedora 都走 Wi‑Fi
- 目标路径是“无线客户端 A -> AP -> 无线客户端 B”
- Wi‑Fi 有 PHY 速率与真实吞吐之间的协议损耗
- 同一份数据经过 AP 中转时，会占用两次无线空口时间

因此虽然流量没有出局域网，也没有经过代理出口，但吞吐依然会明显低于用户对“局域网带宽”的直觉预期。

## 6. 已做变更

本次没有对 macOS 的系统安全策略、Recovery 配置或第三方文件系统驱动做任何修改。

实际做过的变更只有：

1. 在 Fedora 端创建目标目录：

   ```text
   /home/chesszyh/Music
   ```

2. 将以下目录从 Mac mini 传输到 Fedora：

   ```text
   ~/Music/neuro
   ~/Music/evil-neuro
   ```

3. 生成本次排障报告：
   [macmini-ntfs-lan-transfer-report-2026-04-28.md](macmini-ntfs-lan-transfer-report-2026-04-28.md)

## 7. 验证

### 7.1 NTFS 只读状态验证

已验证：

- `diskutil list external physical` 可识别外接卷
- `df -h` 显示空间充足
- `touch` 写测试失败
- `mount` 显示 `read-only`

这些证据足以确认：当前 Mac 上无法直接向该外接 NTFS 卷写入。

### 7.2 代理绕过验证

已验证：

- `route -n get <fedora-ip>` 指向本地 `en1`
- Clash 规则里对 `192.168.0.0/16` 明确走 `DIRECT`

这些证据足以确认：本次 Fedora 传输没有经过 Clash 的远端代理出口。

### 7.3 传输链路验证

已验证：

- Mac mini 当前走 `Wi‑Fi`
- Fedora 当前走 `Wi‑Fi`
- `rsync` CPU 不高
- 实际吞吐稳定在 `13–16 MB/s` 附近

这些证据支持“瓶颈在双无线局域网链路而非 CPU/代理”的结论。

### 7.4 未做的验证

以下验证本次未执行：

- 对传输前后目录做 `checksum` 级别校验
- 在 Fedora 侧再次用 `du -sh` 或 `find` 核对文件数与总字节数
- 使用 `iperf3` 单独测量 Mac mini 与 Fedora 的裸网络吞吐上限

如果后续需要更严格的完整性保证，建议补做。

## 8. 排障过程中遇到的问题

1. `Paragon NTFS for Mac` 虽然能解决写盘问题，但在当前平台上需要较重的系统改动，和用户的接受边界冲突。

2. macOS 自带 `rsync` 版本较旧，不支持：

   ```text
   --info=progress2
   ```

   因此中途改用：

   ```bash
   rsync -avhP --stats ...
   ```

   来观察当前文件进度与速度。

3. 由于两个端点都在 Wi‑Fi 上，哪怕协议层换成 `LocalSend`、`SMB` 或 `NFS`，也很难出现数量级上的吞吐提升，因此不能把“换传输工具”误认为“解决链路瓶颈”。

## 9. 复用说明与经验

1. 看到外接盘是 `NTFS` 时，先不要直接假设 Mac 可以写。先用 `mount` 和 `touch` 做最小验证。

2. 对于“局域网会不会走代理”的问题，优先看两层：
   - 系统路由：`route -n get <target>`
   - 代理规则：是否对私网段做了 `DIRECT`

3. 传输慢时，不要先怪 `rsync` 或 `SSH`。先看：
   - 两端是否都是 Wi‑Fi
   - PHY 速率是多少
   - 进程 CPU 是否真的打满

4. 双无线客户端经同一 AP 中转时，文件吞吐往往远低于“想象中的局域网带宽”。如果要显著提速，最有效的是至少让一端改为有线，更理想是两端都走有线。

5. 如果只是一次性中转写盘，而不想在 Apple Silicon Mac 上改 `Reduced Security`，优先考虑：
   - 先传到 Linux/Windows 主机
   - 再由该主机写入 `NTFS`

## 10. 附录：可复用命令

### 10.1 查看外接盘与挂载状态

```bash
ls -la /Volumes
diskutil list external physical
df -h '/Volumes/<volume-name>'
mount | rg '<volume-name>|ntfs'
```

### 10.2 验证外接盘是否可写

```bash
touch '/Volumes/<volume-name>/.write_test' && rm '/Volumes/<volume-name>/.write_test'
```

### 10.3 检查局域网目标是否走本地直连

```bash
route -n get <fedora-ip>
```

### 10.4 检查 Clash/Mihomo 是否绕过私网

```bash
rg -n 'DIRECT|192\\.168\\.|10\\.|172\\.(1[6-9]|2[0-9]|3[0-1])\\.' \
  ~/Library/Application\ Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml
```

### 10.5 查看当前 Wi‑Fi 链路质量

```bash
system_profiler SPAirPortDataType | sed -n '/Current Network Information:/,/Auto Unlock:/p'
```

重点看：

- `PHY Mode`
- `Channel`
- `Signal / Noise`
- `Transmit Rate`

### 10.6 通过 SSH/rsync 中转到 Fedora

```bash
ssh -o BatchMode=yes chesszyh@<fedora-ip> 'mkdir -p /home/chesszyh/Music'
rsync -avhP --stats ~/Music/neuro ~/Music/evil-neuro chesszyh@<fedora-ip>:/home/chesszyh/Music/
```

### 10.7 在 Fedora 侧查看网络接口与是否具备带宽测试工具

```bash
ip -brief addr
command -v iperf3
command -v nload
command -v bmon
```

### 10.8 在传输时观察 rsync CPU 占用

```bash
ps -o pid,%cpu,%mem,command -p <rsync-pid>
```
