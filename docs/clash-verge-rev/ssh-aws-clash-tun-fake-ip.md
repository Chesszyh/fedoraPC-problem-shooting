# Clash Verge Rev TUN 模式下 SSH 连 AWS 被断开的排障记录

## 问题现象

SSH 配置如下：

```sshconfig
Host AWS-SG
    HostName <ec2-hostname>
    User ubuntu
    IdentityFile <private-key-path>
    ProxyCommand none
```

报错：

```text
Connection closed by 198.18.0.45 port 22
```

运行环境：

- Clash Verge Rev
- `tun` 模式开启
- DNS 使用 `fake-ip`

## 根因结论

`198.18.0.0/16` 是 Clash `fake-ip` 网段，不是 AWS EC2 的真实公网地址。

这说明 SSH 连接时拿到的是 Clash 生成的 fake IP，而不是 `<ec2-hostname>` 的真实解析结果。随后该连接又被 TUN/规则链路处理，最终导致连接在 `198.18.0.45:22` 被关闭。

一句话概括：

`SSH -> 域名被 fake-ip 解析 -> 连接落到 198.18.x.x -> 没有正确恢复到真实目标地址 -> 连接被关闭`

## 为什么 `ProxyCommand none` 没解决

`ProxyCommand none` 只表示 OpenSSH 不额外使用命令行代理。

它并不能绕过系统层或 TUN 层的流量接管。只要 Clash TUN 仍在接管本机流量，SSH 进程发出的连接依然可能被 Clash 改写、分流或配合 fake-ip 处理。

## 排查思路

### 1. 先识别 `198.18.0.45` 是什么

看到 `198.18.0.45` 时，首先不要把它当成远端服务器。

关键判断点：

- `198.18.0.0/16` 常见于 Clash fake-ip
- 如果目标域名本应解析到公网 EC2 地址，却出现 `198.18.x.x`
  就几乎可以确认是 fake-ip 介入

### 2. 再看当前 Clash 配置

检查点：

- `dns.enhanced-mode: fake-ip`
- `tun.enable: true`
- 目标域名是否出现在 `dns.fake-ip-filter`
- `ssh` 流量是否存在强制直连规则

本次配置里能确认到：

- 开启了 `tun`
- 开启了 `fake-ip`
- 目标 AWS 域名最初不在 `fake-ip-filter`
- 规则集中还存在 `DOMAIN-SUFFIX,amazonaws.com,🚀节点选择`

最后这一点意味着：

即使不考虑 fake-ip，`amazonaws.com` 默认也会被送进代理组；这对浏览器访问通常没问题，但对基于域名直连的 SSH 更容易引出异常。

## 修复原则

目标是同时解决两类问题：

1. 不要让目标 AWS 域名进入 fake-ip
2. 不要让 SSH 进程继续走代理规则链

因此采用双保险：

- 在 `dns.fake-ip-filter` 中排除该 EC2 域名
- 在规则中给 `ssh` 和该 EC2 域名显式 `DIRECT`

## 本次持久化修改

### 1. Merge 模板

文件：

- `profiles/md3vwVh0HaoX.yaml`

内容：

```yaml
find-process-mode: strict
dns:
  fake-ip-filter:
    - <ec2-hostname>
```

作用：

- 这是订阅关联的 merge 模板
- 改这里比直接改 `clash-verge.yaml` 更稳
- 订阅更新后仍会保留该排除项

### 2. Rules 模板

文件：

- `profiles/ryguEitH4tBd.yaml`

内容：

```yaml
prepend:
  - PROCESS-NAME,cloudflared,DIRECT
  - PROCESS-NAME,ssh,DIRECT
  - DOMAIN,<ec2-hostname>,DIRECT

append: []

delete: []
```

作用：

- `PROCESS-NAME,ssh,DIRECT` 让 OpenSSH 进程直接走直连
- `DOMAIN,...,DIRECT` 给这台 AWS 主机再加一层主机级兜底

## 当前生效配置中的对应结果

在生成后的 `clash-verge.yaml` 中应能看到：

```yaml
dns:
  fake-ip-filter:
    - <ec2-hostname>
```

以及：

```yaml
rules:
  - PROCESS-NAME,ssh,DIRECT
  - DOMAIN,<ec2-hostname>,DIRECT
```

## 操作步骤模板

以后再遇到“开着 TUN 时 SSH 连域名失败、报到 198.18.x.x”的情况，可以按下面流程复用。

### 方案 A：针对单台主机精准修复

1. 找到目标主机域名
2. 将该域名加入订阅关联 merge 模板中的 `dns.fake-ip-filter`
3. 在订阅关联 rules 模板中加入：

```yaml
- PROCESS-NAME,ssh,DIRECT
- DOMAIN,<目标域名>,DIRECT
```

4. 重载 Clash Verge Rev 配置或切换一次 TUN
5. 用下面命令验证：

```bash
ssh -vvv <HostAlias>
```

如果日志里不再出现 `198.18.x.x` 作为目标地址，且连接成功，说明修复生效。

### 方案 B：按域名后缀做更宽松的修复

如果你有很多 AWS 主机都走 SSH，可以考虑把规则扩成：

```yaml
- DOMAIN-SUFFIX,compute.amazonaws.com,DIRECT
```

或者在你确认需求稳定后再把更大的范围直连：

```yaml
- DOMAIN-SUFFIX,amazonaws.com,DIRECT
```

但这个范围更大，会影响其他走代理更合适的 AWS 业务流量，所以默认不建议一步放这么宽。

## 复查命令

### 查看当前生成配置里是否已生效

```bash
rg -n "fake-ip-filter:|<ec2-hostname>|PROCESS-NAME,ssh,DIRECT" clash-verge.yaml profiles/*.yaml
```

### 快速检查 YAML 解析结果

```bash
python - <<'PY'
import yaml
with open('clash-verge.yaml', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
print(data.get('dns', {}).get('fake-ip-filter'))
print(data.get('rules', [])[:5])
PY
```

## 风险与注意点

- 不要把修复只写进 `clash-verge.yaml`
  这是生成文件，可能被重载或订阅更新覆盖
- `profiles.yaml` 常包含订阅 URL、token、选择状态
  不建议纳入 Git
- 远程订阅下发的完整 profile 往往包含大量代理节点和敏感信息
  不建议纳入 Git
- 如果未来 `ssh` 仍异常，要检查是否有别的 SSH 客户端进程名不叫 `ssh`
  例如 GUI 客户端、插件或 wrapper

## 这次修复为什么能成功

因为它同时处理了 DNS 层和路由层：

- DNS 层：避免目标域名被 fake-ip 化
- 路由层：避免 SSH 流量进入代理链

只做其中一半，常常会留下边缘问题；双保险更稳。
