# Tailscale 登录卡死问题分析与解决报告

## 1. 问题描述
- **现象：** 在终端执行 `sudo tailscale login` 时没有任何输出，程序呈卡死状态，最终因超时失败。Tailscale 状态显示为离线（Offline）。
- **环境：** Fedora Linux 43，系统中运行有代理服务（Clash/Meta），监听端口为 7897。

## 2. 分析过程
1.  **服务状态检查：** 使用 `systemctl status tailscaled` 查看，发现守护进程（Daemon）虽在运行，但状态为 "Needs login"（需要登录）。
2.  **日志排查：** 通过 `journalctl -u tailscaled` 发现大量报错信息：
    - `context deadline exceeded`（上下文截止日期已过）。
    - 报错发生在尝试向 `https://controlplane.tailscale.com/machine/register` 发送 POST 请求时。
    - 同时还可见 `tailscaled` 在访问 `log.tailscale.com:443` 时，实际拨号目标变成了 `198.18.0.91:443`。
    - 这表明后台守护进程 `tailscaled` 无法正常连接到 Tailscale 的控制平面，且其流量已被 Clash/Meta 的 TUN 虚拟网段（`198.18.0.0/15`）接管。
3.  **环境变量检查：** `env | grep proxy` 显示当前用户会话有代理配置，但 Linux 系统服务（Systemd Service）默认不会继承用户会话的环境变量。
4.  **网络连通性验证：** 使用 `curl` 进行测试，证实必须通过代理才能成功访问 Tailscale 的注册接口。

## 3. 根本原因
`tailscaled` 守护进程作为 Systemd 服务运行，没有自动继承当前用户会话中的代理环境变量；与此同时，系统中启用了 Clash/Meta 的 TUN 模式，默认出站流量会被接管到 `198.18.0.0/15` 虚拟网段。在该环境下，`tailscaled` 既不能稳定直连 Tailscale 服务器，又没有显式通过本地代理（`127.0.0.1:7897`）出站，最终导致连接控制平面超时。由于 `tailscale login` 命令只是与本地后台进程通信的客户端，后台进程连不上网，客户端就会一直处于等待响应的状态，表现为命令行没有任何输出。

## 4. 解决方案
1.  **注入代理配置：** 在 Tailscale 的环境配置文件 `/etc/default/tailscaled` 中手动添加了代理设置：
    - `HTTP_PROXY="http://127.0.0.1:7897"`
    - `HTTPS_PROXY="http://127.0.0.1:7897"`
    - `ALL_PROXY="http://127.0.0.1:7897"`
2.  **重启服务：** 执行 `systemctl restart tailscaled` 使配置生效。
3.  **重新认证：** 再次执行 `sudo tailscale login`。此时后台进程可以通过代理联网，成功返回了身份验证 URL，用户点击链接后完成登录。

## 5. 当前状态
- **状态：** 已在线并成功认证（Online & Authenticated）。
- **连通性：** 已能成功 Ping 通 Tailscale 网络中的其他节点（如 macOS 节点）。
- **备注：** 由于 Clash/Meta TUN 使用 `198.18.0.x` 虚拟地址段，可能与 Tailscale 的部分 DNS 或路由健康检查产生轻微冲突，导致出现 DNS 相关警告，但基础网络连接功能已恢复正常。

---
*报告生成日期：2026-03-09*
