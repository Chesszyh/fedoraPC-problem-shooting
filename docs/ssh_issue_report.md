# SSH 连接问题分析与解决方案报告

## 1. 问题描述
在使用 **Clash Verge Rev (TUN 模式)** 时，无法通过 SSH 连接到位于 DigitalOcean 的服务器（新加坡 `<do-sg-ip>` 和美国 `<do-us-ip>`）。
SSH 报错信息：`Connection closed by [IP] port 22` 或 `Connection timed out during banner exchange`。

## 2. 问题根源分析
通过 `ssh -v` 调试和网络拓扑分析，确认以下原因：
- **流量拦截**：Clash Verge 的 TUN 模式接管了系统的三层流量。由于默认规则（MATCH）或全局代理模式，SSH 流量被重定向到了代理节点。
- **协议/防火墙冲突**：
    - DigitalOcean 的服务器防火墙检测到 SSH 握手（Banner Exchange）来自已知的代理/VPN 节点，出于安全考虑主动关闭了连接。
    - 代理节点在处理长连接或 SSH 协议头时，可能存在不兼容或网络延迟，导致握手阶段超时。

## 3. 解决方案

### 方案 A：修改 Clash 规则（推荐，应用级）
这是最稳妥的方案，通过调整 Clash 的分流逻辑实现。
在 `clash-verge.yaml` 的 `rules` 列表顶部添加针对服务器 IP 的直连规则：
```yaml
rules:
- IP-CIDR,<do-sg-ip>/32,DIRECT,no-resolve
- IP-CIDR,<do-us-ip>/32,DIRECT,no-resolve
```

### 方案 B：系统级路由绕过（强力方案，内核级）
如果 Clash 规则失效或不想修改配置文件，可以手动在系统路由表中添加静态路由。这种方法优先级最高，流量会跳过 TUN 网卡直接发往物理网关。

**实施命令：**
```bash
# 获取网关 IP (如 192.168.1.1) 和物理网卡名 (如 wlp0s20f3)
# 然后添加静态路由
sudo ip route add <do-sg-ip> via [网关IP] dev [物理网卡]
sudo ip route add <do-us-ip> via [网关IP] dev [物理网卡]
```
*优点：即使 Clash 开启了全局模式或规则错误，也能保证这两个 IP 绝对直连。*
*注意：此设置在重启后或网络断开重新连接后通常会失效，除非将其写入网络管理器的持久化配置中。*

## 4. 验证结果
经过测试（`ssh -v`），连接已能成功看到远程服务器的 OpenSSH 版本号并进行密钥交换，证明**连接已恢复正常**。

## 5. 维护建议
1. **GUI 设置直连**：在 Clash Verge Rev 界面进入 `Settings` -> `TUN Mode` -> `Bypass` 中添加服务器 IP。
2. **持久化路由**：如果经常需要系统级直连，建议将 `ip route` 命令添加到系统启动脚本或网络管理器的 `dispatcher.d` 中。

---
*报告生成日期：2026年3月10日*
