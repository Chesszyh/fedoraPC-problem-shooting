<section class="report-hero" markdown>
<div class="report-eyebrow">Personal Troubleshooting Archive</div>

# Chesszyh Reports

Fedora Hyprland、网络代理、开发工具和系统排障记录。每篇报告保留问题现象、证据链、根因、验证方式和可复用命令。

<p class="report-lede">适合在下次遇到同类问题时快速回到上下文，也适合把 Codex、Gemini CLI、Claude Code 的排障过程沉淀成可检索的个人知识库。</p>

<div class="report-actions">
<a class="report-action" href="#fedora">Fedora 与桌面环境</a>
<a class="report-action" href="#network">网络与代理</a>
<a class="report-action" href="#tools">开发工具与应用</a>
<a class="report-action" href="#macmini">Mac mini</a>
<a class="report-action" href="#notes">其他记录</a>
</div>
</section>

<div class="report-grid">
<a class="report-card" href="#fedora">
  <strong>Fedora 与桌面环境</strong>
  <span>Hyprland、SDDM、akmods、字体、键盘、系统清理。</span>
</a>
<a class="report-card" href="#network">
  <strong>网络与代理</strong>
  <span>Cloudflare Tunnel、Tailscale、Clash Verge Rev、SSH、s-ui。</span>
</a>
<a class="report-card" href="#tools">
  <strong>开发工具与应用</strong>
  <span>Codex 代理、Discord handler、Conda 污染、npm、IDE hooks。</span>
</a>
<a class="report-card" href="#macmini">
  <strong>Mac mini</strong>
  <span>本地网络、远程开发、Playwright 浏览器缓存和外接磁盘迁移。</span>
</a>
<a class="report-card" href="#notes">
  <strong>其他记录</strong>
  <span>DNF、Tongji、自动化注册探索和零散排障素材。</span>
</a>
</div>

<p class="report-note">报告默认按主题归档；遇到明确凭据、token、私钥、授权头和不应公开的服务端点时应先脱敏再发布。</p>

## Fedora 与桌面环境 { #fedora }

<div class="report-list" markdown>

- [Hyprland 登录黑屏问题报告](Hyprland_登录黑屏问题报告_2026-03-03.md)
- [Fedora Hyprland SDDM 黑屏与 akmods 报告](fedora-hyprland-sddm-black-screen-akmods-2026-03-15.md)
- [Fedora Hyprland SDDM 黑屏快速检查清单](fedora-hyprland-sddm-black-screen-akmods-quick-checklist-2026-03-15.md)
- [Fedora Legion Y9000P 键盘突然失效报告](fedora-legion-y9000p-keyboard-sudden-failure-report-2026-04-07.md)
- [Fedora Hyprland 外接显示器亮度路由与卡顿优化报告](fedora-hyprland-external-monitor-brightness-routing-report-2026-04-24.md)
- [Fedora 格式化 exFAT U 盘后 macOS 提示无法读取修复报告](fedora-exfat-usb-macos-unreadable-report-2026-04-27.md)
- [DaVinci Resolve 20.3.1 Fedora 43 安装报告](INSTALL_REPORT_DAVINCI_RESOLVE_20.3.1_FEDORA43.md)
- [Chrome 字体事件报告](chrome_font_incident_report_2026-02-12.md)
- [系统清理报告](system_cleanup_report_20260312.md)

</div>

## 网络与代理 { #network }

<div class="report-list" markdown>

- [DNS 与 Cloudflare Tunnel 问题](dns_and_cloudflare_tunnel_issue.md)
- [Tailscale 登录卡死问题](tailscale_issue_report.md)
- [SSH 连接问题分析与解决方案](ssh_issue_report.md)
- [Kitty SSH 配置说明](kitty-ssh-conf.md)
- [Clash Verge Rev: SSH AWS fake-ip 排障](clash-verge-rev/ssh-aws-clash-tun-fake-ip.md)
- [Clash Verge Rev: Hyprland Tailscale WebUI 502 排障](clash-verge-rev/hyprland-tailscale-webui-502-proxy-report-2026-04-21.md)
- [Clash Verge Rev: GCP x-ui 面板 ERR_CONNECTION_CLOSED 排障](clash-verge-rev/gcp-x-ui-panel-clash-tun-err-connection-closed-report-2026-05-07.md)
- [Clash Verge Rev: gcp-sg 订阅增强与远程迁移排障](clash-verge-rev/gcp-sg-clash-verge-profile-enhancement-migration-report-2026-05-08.md)
- [Clash Verge Rev: VLESS 转换脚本说明](clash-verge-rev/vless-to-clash-script.md)
- [CPA 8317 通过 Cloudflare Tunnel 有限公网暴露排障报告](cpa-cloudflare-tunnel-8317-public-api-report-2026-05-15.md)
- [Mihomo Headless 部署、UI 后端连接与多订阅切换排障报告](mihomo-headless-ui-subscription-switch-report-2026-04-28.md)
- [s-ui 数据库端口查询说明](s-ui-db-restore-guide.md)

</div>

## 开发工具与应用 { #tools }

<div class="report-list" markdown>

- [osu! lazer BTMC 皮肤导入后名称过长与重导入修复报告](osu-lazer-btmc-skin-import-rename-report-2026-04-25.md)
- [Neuro 桌宠在 macOS 上的 Java 8、启动器与菜单排障报告](neurolings-macos-java8-launcher-report-2026-05-02.md)
- [context-mode 项目暂缓采用复查记录](context-mode-deferred-evaluation-report-2026-04-27.md)
- [cliproxyapi Codex 非流式 content null 报告](cliproxyapi-codex-nonstream-content-null-report-2026-04-14.md)
- [Codex 切换 provider 后旧会话无法 Resume 排障报告](codex-provider-resume-session-report-2026-05-12.md)
- [Discord URL handler 报告](discord-url-handler-report-2026-04-14.md)
- [Kitty Conda 污染报告](kitty-conda-pollution-report-2026-04-12.md)
- [Audio Separator 长任务容器自动删除与结果丢失问题报告](audio-separator-long-task-container-rm-report-2026-04-18.md)
- [npm install 错误恢复](npm_install_error_recovery.md)
- [peon-ping 多 IDE 配置报告](peon-ping-multi-ide-config-report-2026-03-09.md)
- [AdsPower RPM 转换报告](AdsPower_RPM_Conversion_Report.md)
- [tldr 自定义页面指南](tldr_custom_pages_guide.md)
- [tmux 中文字体不显示](tmux-中文字体不显示.md)

</div>

## Mac mini { #macmini }

<div class="report-list" markdown>

- [Mac mini 排障报告索引](macmini-reports/index.md)
- [tmux 远程开发配置与持久化问题报告](macmini-reports/tmux-remote-dev-config-report-2026-04-14.md)
- [Hermes Codex API Timeout 代理与 DNS 排障报告](macmini-reports/hermes-codex-proxy-tun-dns-report-2026-04-17.md)
- [Playwright Chromium 安装卡住问题报告](macmini-reports/playwright-chromium-install-stuck-report-2026-04-17.md)
- [Mac mini 外接 NTFS 磁盘不可写与局域网传输速度分析报告](macmini-reports/macmini-ntfs-lan-transfer-report-2026-04-28.md)

</div>

## 其他记录 { #notes }

<div class="report-list" markdown>

- [DNF 403 错误报告](dnf-403-error-report.md)
- [Tongji 分析报告](TONGJI_ANALYSIS_REPORT.md)
- [项目探索笔记](项目探索笔记.md)

</div>
