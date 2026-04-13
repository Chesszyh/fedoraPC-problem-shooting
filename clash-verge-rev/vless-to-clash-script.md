# `vless_to_clash.py` 脚本说明

## 作用

`scripts/vless_to_clash.py` 用于把一个纯文本 `vless://` 链接列表批量转换成 Clash Verge Rev 可导入的本地 YAML。

典型输入：

- 一个 `vless.txt`
- 每行一个 `vless://...`
- 允许空行
- 允许以 `#` 开头的注释行

典型输出：

- 一个本地配置文件，例如 `local-vless.yaml`
- 可直接在 Clash Verge Rev 中作为本地配置导入

## 当前支持的链接格式

脚本当前已覆盖这次 AIER 节点使用的主格式：

- `vless://...`
- `security=tls`
- `type=ws`
- `host=...`
- `sni=...`
- `path=...`
- `fp=...`

也支持以下可选参数：

- `flow=...`
- `alpn=...`
- `pbk=...`
- `sid=...`

其中：

- `pbk` / `sid` 会被映射到 `reality-opts`
- `alpn` 会被拆成列表

## 输入示例

```text
vless://<uuid>@<server-host>:<port>?security=tls&type=ws&host=<ws-host>&fp=chrome&sni=<sni-host>&path=%2F&encryption=none#example-1
vless://<uuid>@<server-host>:<port>?security=tls&type=ws&host=<ws-host>&fp=chrome&sni=<sni-host>&path=%2Fws%3Fed%3D2048&encryption=none#example-2
```

## 最常用命令

在当前目录下运行：

```bash
python scripts/vless_to_clash.py vless.txt local-vless.yaml --group AIER
```

含义：

- 输入文件：`vless.txt`
- 输出文件：`local-vless.yaml`
- 生成的代理组名称：`AIER`

成功后会输出类似：

```text
Wrote 50 proxies to local-vless.yaml
```

## 命令参数

脚本支持：

```bash
python scripts/vless_to_clash.py [input] [output] --group <name>
```

参数说明：

- `input`
  输入文件路径，默认是 `vless.txt`
- `output`
  输出 YAML 路径，默认是 `local-vless.yaml`
- `--group`
  输出配置中的代理组名，默认是 `IMPORTED`

例如：

```bash
python scripts/vless_to_clash.py my-links.txt my-aier.yaml --group MY-AIER
```

## 输出 YAML 结构

脚本会生成一个最小可导入 Clash/Mihomo 配置，主要包含：

- `proxies`
- `proxy-groups`
- `rules`

结构大致如下：

```yaml
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
ipv6: true

proxies:
  - name: CF官方优选1
    type: vless
    server: example.com
    port: 443
    uuid: 00000000-0000-0000-0000-000000000000
    network: ws
    udp: true
    tls: true
    servername: example.com
    client-fingerprint: chrome
    ws-opts:
      path: /
      headers:
        Host: example.com

proxy-groups:
  - name: AIER
    type: select
    proxies:
      - CF官方优选1
  - name: SELECT
    type: select
    proxies:
      - AIER
      - DIRECT

rules:
  - MATCH,SELECT
```

## 在 Clash Verge Rev 中导入

生成 YAML 后：

1. 打开 Clash Verge Rev
2. 进入配置文件或 Profiles 页面
3. 选择导入本地文件
4. 选择生成的 `local-vless.yaml`
5. 切换到该本地配置并测试节点

## 推荐验证流程

生成后建议先做三个检查。

### 1. 检查 YAML 是否生成成功

```bash
python scripts/vless_to_clash.py vless.txt local-vless.yaml --group AIER
```

### 2. 检查生成内容是否可解析

```bash
python - <<'PY'
import yaml
with open('local-vless.yaml', 'r', encoding='utf-8') as f:
    data = yaml.safe_load(f)
print('proxies', len(data['proxies']))
print('groups', [g['name'] for g in data['proxy-groups']])
print('rules', data['rules'])
PY
```

### 3. 导入后实际测试

建议至少测试：

- 延迟测试
- `curl ifconfig.me`
- 浏览器访问基础站点

## 脚本行为细节

### 重名节点处理

如果多个链接的 `#节点名` 相同，脚本会自动追加后缀：

- `节点名`
- `节点名-2`
- `节点名-3`

避免 Clash YAML 中代理名冲突。

### 空行与注释

以下内容会自动跳过：

- 空行
- `# 注释`

### 路径解码

URL 中的 `path=%2Fws%3Fed%3D2048` 会被解码成：

```text
/ws?ed=2048
```

## 已知限制

当前脚本是“为这批链接做的最小可用转换器”，不是完整的通用 VLESS 全协议转换器。

目前不保证覆盖所有变体，例如：

- `grpc`
- `httpupgrade`
- `xhttp`
- 更复杂的 `reality` 组合
- 非标准 query 参数

如果后续你引入了新的 VLESS 格式，建议先拿 1 到 2 条样本跑一次；如有缺口，再扩脚本支持。

## 对应文件

- 脚本：
  `scripts/vless_to_clash.py`
- 测试：
  `tests/test_vless_to_clash.py`
- 输入样例：
  `vless.txt`

## 维护建议

- 原始 `vless.txt` 通常包含可用节点凭据，不要纳入 Git
- 把 `local-vless.yaml` 视为生成物，不纳入 Git
- 如果你后续维护多个来源，建议按来源拆分：
  - `vless-provider-a.txt`
  - `vless-provider-b.txt`
  - `local-aier.yaml`
  - `local-foo.yaml`
