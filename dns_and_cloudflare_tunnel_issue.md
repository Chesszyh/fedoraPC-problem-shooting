# DNS 冲突与 Cloudflare Tunnel 启动异常解决报告

## 1. 问题描述
- **现象：** 执行 `cloudflared tunnel` 时报错 `failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel": dial tcp: lookup api.trycloudflare.com on 100.100.100.100:53: server misbehaving`。
- **背景：** 用户曾调试过 Tailscale，系统持续强制使用 `100.100.100.100` (Tailscale MagicDNS) 作为 DNS 服务器，但在当前网络环境下（含 Clash/Meta TUN 代理）该地址响应异常。

## 2. 根本原因分析
1. **DNS 接管冲突：** Tailscale 在启用时将 `/etc/resolv.conf` 修改为了由其管理的静态文件，锁定了 `nameserver 100.100.100.100`。
2. **代理环境干扰：** 系统中运行的 Clash/Meta TUN 模式（地址段 `198.18.0.0/15`）与 Tailscale 的 DNS 路由产生了冲突，导致 `100.100.100.100` 无法正常响应解析请求。
3. **连锁反应：** 由于 DNS 解析失败，`cloudflared` 无法连接到 Cloudflare 控制平面，导致 Tunnel 无法建立。

## 3. 解决步骤
1. **禁用 Tailscale DNS 接受配置：**
   执行 `sudo tailscale set --accept-dns=false`，告知 Tailscale 停止接管系统 DNS。
2. **恢复系统标准 DNS 管理：**
   - 发现 `/etc/resolv.conf` 是静态文件而非软链接，导致配置无法动态更新。
   - 删除过时的静态文件：`sudo rm /etc/resolv.conf`。
   - 恢复 `systemd-resolved` 软链接：`sudo ln -s /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf`。
3. **验证 DNS 路由：**
   - 恢复后，系统自动切换至 `Meta` 链路提供的 DNS (`198.18.0.2`)。
   - 验证 `api.trycloudflare.com` 解析正常，返回代理网段地址。
4. **启动 Cloudflare Tunnel：**
   - 为确保在代理环境下的稳定性，指定协议为 `http2`。
   - 命令：`cloudflared tunnel --url http://localhost:8000 --protocol http2`。

## 4. 当前状态
- **DNS：** 已恢复正常，由 `systemd-resolved` 动态管理，不再被 `100.100.100.100` 锁定。
- **Cloudflare Tunnel：** 已成功在后台启动。
- **访问地址：** `<trycloudflare-url>`
- **日志记录：** 运行日志保存于 `/tmp/cf_tunnel.log`。

---
*报告生成日期：2026-03-10*
