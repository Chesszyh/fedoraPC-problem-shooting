# gcp-sg Clash Verge Rev 订阅增强与远程迁移排障报告

生成时间: 2026-05-08T01:05:06+08:00

## Problem Description

`gcp-sg` 是从 3x-ui 面板生成的 Clash/Mihomo 订阅。原始订阅能导入 Clash Verge Rev，但存在三个可用性问题：

- 节点名称过长，例如 `<protocol remark>-<client email>` 形式。
- 只有一个基础 `PROXY` 组，没有 `AUTO` 自动选择。
- 只有 `MATCH,PROXY`，没有复用“赔钱机场”成熟的分流规则和分流组。

在把本机优化后的 `gcp-sg` 配置迁移到 `ssh MacbookAir` 和 `ssh Macmini` 后，用户反馈两台机器仍然看到旧表现：没有自动选择、短节点名不对、也没有完整分流规则。最终确认这是 Clash Verge Rev 的 profile UID 与增强文件引用机制没有同步迁移导致的配置漂移。

本报告重点记录短节点名、`AUTO` 和完整分流组的本地修改逻辑，以及迁移到远程 Mac 时第一次失败和最终修复的证据链。订阅 ID、节点 UUID、Reality 公钥、Trojan 密码、Hysteria2 密码等敏感值已脱敏。

## Environment and Scope

本机环境：

- OS：Fedora 客户端
- Clash Verge Rev 配置目录：`/home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev`
- 现有成熟订阅：`赔钱机场`
- 优化目标订阅：`gcp-sg`
- 订阅 URL：`https://<panel-domain>:2096/clash/<redacted-sub-id>`

远程迁移目标：

- `ssh MacbookAir`
  - 配置目录：`/Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev`
- `ssh Macmini`
  - 配置目录：`/Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev`

涉及的 Clash Verge Rev 文件类型：

- `profiles.yaml`：profile 注册表，记录当前订阅、远程订阅 UID、增强文件 UID。
- `profiles/<remote>.yaml`：远程订阅拉取后的 YAML。
- `profiles/<merge>.yaml`：merge 增强模板。
- `profiles/<script>.js`：脚本增强模板。
- `profiles/<rules>.yaml`：规则增强模板。
- `profiles/<proxies>.yaml`：代理增强模板。
- `profiles/<groups>.yaml`：代理组增强模板。

## Symptoms and Reproduction

本机直接查看 3x-ui 生成的 `gcp-sg` 原始订阅文件，可以看到它只是最小配置：

```yaml
proxies:
  - name: gcp-sg-vless-reality-vision-gcp-sg-vless-reality
  - name: gcp-sg-trojan-tls-gcp-sg-trojan-tls
  - name: gcp-sg-hysteria2-gcp-sg-hysteria2

proxy-groups:
  - name: PROXY
    type: select

rules:
  - MATCH,PROXY
```

这会导致：

- UI 中节点名很长。
- 没有 `AUTO`/`url-test` 自动测速组。
- 没有 `🚀节点选择`、`🐟漏网之鱼`、`🎬媒体解锁`、`🤖AI网站`、`🛑广告拦截` 等成熟分流组。
- 切换到 `gcp-sg` 后，访问面板和更新该订阅可能走自身代理，形成自引用路径。

第一次迁移到 Mac 后，用户反馈现象仍然存在。后续检查发现远程 Mac 实际使用的 UID 与本机不同：

```text
MacbookAir:
  remote uid/file: RVr80t3PI54U / RVr80t3PI54U.yaml
  merge: mJFkCXbHOmWM
  script: sdxKcHYzYJQI
  rules: r15eX702Kw43
  groups: g4N9Vb0vr9ke

Macmini:
  remote uid/file: Rhe5bfDqBGEN / Rhe5bfDqBGEN.yaml
  merge: mj9TlrPNpx4E
  script: svHnULi27C18
  rules: rAZEd70Jquxu
  groups: g717bBVjtvKr
```

而第一次迁移复制的是本机 UID 相关文件，例如 `R7aNs6qclND5.yaml`、`rCgornSLHpPo.yaml`、`gPBYBqNv9VtW.yaml`。这些文件存在于远端目录里，但没有被远端实际 `gcp-sg` profile 引用，因此 UI 仍显示未增强的订阅。

## Investigation Timeline

1. 对比本机成熟配置与 `gcp-sg` 原始订阅。

   ```bash
   python3 - <<'PY'
   import yaml
   from pathlib import Path
   base = Path.home()/'.local/share/io.github.clash-verge-rev.clash-verge-rev'
   for name in ['clash-verge.yaml', 'profiles/R7aNs6qclND5.yaml']:
       data = yaml.safe_load((base/name).read_text())
       print(name, len(data.get('proxies') or []), [g.get('name') for g in data.get('proxy-groups', [])], len(data.get('rules') or []))
   PY
   ```

   证据：

   ```text
   clash-verge.yaml: proxies 93, groups 9, rules 9272
   profiles/R7aNs6qclND5.yaml: proxies 3, groups ['PROXY'], rules 1
   ```

   结论：3x-ui 订阅只提供节点本身，不带成熟分流体系。

2. 修改 3x-ui 入站名称，减少订阅原始名称长度。

   在服务端把入站 remark 和 client email 缩短：

   ```text
   vless / vless
   trojan / trojan
   hy2 / hy2
   ```

   证据：

   ```text
   ('vless', 'vless', 'vless', '<redacted-sub-id>')
   ('trojan', 'trojan', 'trojan', '<redacted-sub-id>')
   ('hy2', 'hysteria', 'hy2', '<redacted-sub-id>')
   ```

   这一步让 3x-ui 后续生成的原始名称从很长的 `gcp-sg-...` 降低到 `vless-vless`、`trojan-trojan`、`hy2-hy2`，但仍不是最终期望的 `gcp-vless`、`gcp-trojan`、`gcp-hy2`。

3. 本机生成优化后的增强文件。

   本机 `gcp-sg` 原始订阅文件：

   ```text
   /home/chesszyh/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles/R7aNs6qclND5.yaml
   ```

   本机增强文件：

   ```text
   mad6bhgsVym9.yaml
   s32QcY8QcAl9.js
   rCgornSLHpPo.yaml
   p75unFaePhEq.yaml
   gPBYBqNv9VtW.yaml
   ```

   关键结果：

   ```text
   remote proxies: ['gcp-vless', 'gcp-trojan', 'gcp-hy2']
   group enhancement groups: ['AUTO', '🚀节点选择', '♻️自动选择', '🐟漏网之鱼', '🎬媒体解锁', '🤖AI网站', '🛑广告拦截']
   rules prepended: 9148
   current preserved: R0tpI5O8B
   ```

   注：`current` 实际值大小写以文件为准，此处报告只强调未切换当前订阅。

4. 本机合成验证。

   将原始订阅、groups 增强、rules 增强近似合成为完整配置后检查：

   ```text
   raw proxies: ['gcp-vless', 'gcp-trojan', 'gcp-hy2']
   merged groups: ['AUTO', '🚀节点选择', '♻️自动选择', '🐟漏网之鱼', '🎬媒体解锁', '🤖AI网站', '🛑广告拦截', '🇯🇵日本节点', '🇸🇬狮城节点', '🇺🇸美国节点', 'PROXY']
   merged rules: 9150
   proxy duplicates: []
   group duplicates: []
   configuration file /tmp/gcp-sg-approx-merged.yaml test is successful
   ```

5. 第一次迁移到 Mac。

   把本机固定 UID 文件复制到两台 Mac：

   ```text
   R7aNs6qclND5.yaml
   mad6bhgsVym9.yaml
   s32QcY8QcAl9.js
   rCgornSLHpPo.yaml
   p75unFaePhEq.yaml
   gPBYBqNv9VtW.yaml
   ```

   同时尝试更新 `profiles.yaml`，保持 `current` 不变。验证显示文件存在，原始文件语法通过，因此一度误判迁移完成。

6. 用户反馈仍未生效后重新取证。

   MacbookAir 的实际 `profiles.yaml` 显示：

   ```text
   uid: RVr80t3PI54U
   file: RVr80t3PI54U.yaml
   option:
     merge: mJFkCXbHOmWM
     script: sdxKcHYzYJQI
     rules: r15eX702Kw43
     proxies: pzMj3Row0mA4
     groups: g4N9Vb0vr9ke
   ```

   Macmini 的实际 `profiles.yaml` 显示：

   ```text
   uid: Rhe5bfDqBGEN
   file: Rhe5bfDqBGEN.yaml
   option:
     merge: mj9TlrPNpx4E
     script: svHnULi27C18
     rules: rAZEd70Jquxu
     proxies: pzU1DDjMGNBv
     groups: g717bBVjtvKr
   ```

   结论：Clash Verge Rev 给每台机器的导入生成了独立 UID 和独立增强文件 UID。复制本机固定 UID 文件不能保证远端实际 profile 会引用它们。

7. 第二次迁移，写入远端实际引用的文件名。

   MacbookAir 写入：

   ```text
   RVr80t3PI54U.yaml
   mJFkCXbHOmWM.yaml
   sdxKcHYzYJQI.js
   r15eX702Kw43.yaml
   pzMj3Row0mA4.yaml
   g4N9Vb0vr9ke.yaml
   ```

   Macmini 写入：

   ```text
   Rhe5bfDqBGEN.yaml
   mj9TlrPNpx4E.yaml
   svHnULi27C18.js
   rAZEd70Jquxu.yaml
   pzU1DDjMGNBv.yaml
   g717bBVjtvKr.yaml
   ```

   同时把原始订阅文件内的节点名也直接替换为：

   ```text
   gcp-vless
   gcp-trojan
   gcp-hy2
   ```

8. 远端最终验证。

   MacbookAir：

   ```text
   current: RRdWHy3nw17r
   uid: RVr80t3PI54U 1
   name: gcp-sg 1
   merge: mJFkCXbHOmWM 1
   script: sdxKcHYzYJQI 1
   rules: r15eX702Kw43 1
   groups: g4N9Vb0vr9ke 1
   rules file size: 409460
   groups file size: 1353
   script contains rename: True
   ```

   Macmini：

   ```text
   current: R1ruvEdVtFPj
   uid: Rhe5bfDqBGEN 1
   name: gcp-sg 1
   merge: mj9TlrPNpx4E 1
   script: svHnULi27C18 1
   rules: rAZEd70Jquxu 1
   groups: g717bBVjtvKr 1
   rules file size: 409460
   groups file size: 1353
   script contains rename: True
   ```

   近似合成后的最终检查：

   ```text
   proxies: ['gcp-vless', 'gcp-trojan', 'gcp-hy2']
   groups: ['AUTO', '🚀节点选择', '♻️自动选择', '🐟漏网之鱼', '🎬媒体解锁', '🤖AI网站', '🛑广告拦截', '🇯🇵日本节点', '🇸🇬狮城节点', '🇺🇸美国节点', 'PROXY']
   rules: 9148
   has AUTO True
   has mature groups True
   configuration file ... test is successful
   ```

## Root Cause

根因分两层：

第一层是 3x-ui 的 Clash/Mihomo 订阅是最小订阅。它只包含节点、一个 `PROXY` select 组和 `MATCH,PROXY`。它不会自动继承本地已有“赔钱机场”的分流规则、自动选择组或地区/媒体/AI 等分流组。

第二层是 Clash Verge Rev 的 profile 增强文件是按 UID 引用的。每台机器导入同一个订阅 URL 时，会生成不同的 remote UID 和不同的增强文件 UID。只复制本机优化过的固定 UID 文件到远端，不等于远端 `gcp-sg` 会引用这些文件。

因此第一次迁移失败的本质不是 YAML 内容错，而是“写入了未被引用的文件”。UI 仍加载远端实际 UID 对应的空增强文件，所以短节点名、`AUTO` 和完整分流组都没有出现。

## Changes Made

本机优化：

- 服务端 3x-ui 入站名称和 client email 缩短为 `vless`、`trojan`、`hy2`。
- 本机原始订阅节点名规范化为：

  ```text
  gcp-vless
  gcp-trojan
  gcp-hy2
  ```

- 本机脚本增强 `s32QcY8QcAl9.js` 负责在未来订阅更新后把 3x-ui 生成名称重命名为短名称。
- 本机 groups 增强 `gPBYBqNv9VtW.yaml` 添加：

  ```text
  AUTO
  🚀节点选择
  ♻️自动选择
  🐟漏网之鱼
  🎬媒体解锁
  🤖AI网站
  🛑广告拦截
  🇯🇵日本节点
  🇸🇬狮城节点
  🇺🇸美国节点
  ```

- 本机 rules 增强 `rCgornSLHpPo.yaml` 复用成熟规则，并把自管理域名/IP 的 DIRECT 规则放在最前：

  ```text
  DOMAIN,<panel-domain>,DIRECT
  IP-CIDR,<panel-ip>/32,DIRECT,no-resolve
  ```

远程迁移：

- MacbookAir 备份并写入实际引用的 UID 文件：

  ```text
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/RVr80t3PI54U.yaml
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/mJFkCXbHOmWM.yaml
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/sdxKcHYzYJQI.js
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/r15eX702Kw43.yaml
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/pzMj3Row0mA4.yaml
  /Users/chesszyh/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/g4N9Vb0vr9ke.yaml
  ```

- Macmini 备份并写入实际引用的 UID 文件：

  ```text
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/Rhe5bfDqBGEN.yaml
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/mj9TlrPNpx4E.yaml
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/svHnULi27C18.js
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/rAZEd70Jquxu.yaml
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/pzU1DDjMGNBv.yaml
  /Users/chesszyh987/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/g717bBVjtvKr.yaml
  ```

未做的变更：

- 没有切换两台 Mac 的当前订阅。
- 没有 reload 远端运行中的 Clash/Mihomo。

## Verification

本机合成验证：

```bash
verge-mihomo -t -f /tmp/gcp-sg-approx-merged.yaml
```

结果：

```text
configuration file /tmp/gcp-sg-approx-merged.yaml test is successful
```

MacbookAir 原始订阅文件语法验证：

```bash
ssh MacbookAir '"/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" -t -f "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/RVr80t3PI54U.yaml"'
```

结果：

```text
configuration file .../profiles/RVr80t3PI54U.yaml test is successful
```

Macmini 原始订阅文件语法验证：

```bash
ssh Macmini '"/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" -t -f "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/Rhe5bfDqBGEN.yaml"'
```

结果：

```text
configuration file .../profiles/Rhe5bfDqBGEN.yaml test is successful
```

最终合成验证：

```text
MacbookAir-final:
  proxies: ['gcp-vless', 'gcp-trojan', 'gcp-hy2']
  has AUTO True
  has mature groups True
  rules: 9148
  configuration file ... test is successful

Macmini-final:
  proxies: ['gcp-vless', 'gcp-trojan', 'gcp-hy2']
  has AUTO True
  has mature groups True
  rules: 9148
  configuration file ... test is successful
```

当前订阅保持：

```text
MacbookAir current: RRdWHy3nw17r
Macmini current: R1ruvEdVtFPj
```

## Problems Encountered During Debugging

- 第一次迁移只检查“文件存在”和“原始 remote YAML 语法通过”，没有检查远端 `profiles.yaml` 中 `gcp-sg` 实际引用的 UID 文件，导致误判迁移成功。
- macOS 自带 Python 没有 `PyYAML`，直接在远端用 Python 修改 YAML 失败：

  ```text
  ModuleNotFoundError: No module named 'yaml'
  ```

  后续改为把 `profiles.yaml` 拉回本机处理，再传回远端。

- Clash Verge Rev UI 可能自动更新订阅并生成新的 UID 文件。迁移不能假设 UID 跨机器一致。
- 原始订阅文件、脚本增强、groups 增强和 rules 增强分别解决不同层面的问题。只改原始订阅不能获得成熟分流；只改增强文件但没有注册到 `profiles.yaml` 也不会生效。
- 3x-ui 原始订阅会按 `remark-email` 组合生成名称。即使服务端已缩短 remark/email，仍可能得到 `vless-vless` 这类名称，因此仍需要脚本增强或直接改 remote YAML。
- 订阅自更新会覆盖 remote YAML，因此短节点名必须通过 script 增强保持长期生效。

## Reuse Notes and Lessons

- 迁移 Clash Verge Rev profile 时，不要只复制 `profiles/<uid>.yaml`。必须同时检查 `profiles.yaml` 中目标 profile 的 `option.merge/script/rules/proxies/groups` 指向哪些 UID。
- 同一个订阅 URL 在不同机器上可能对应不同 remote UID 和增强文件 UID。迁移脚本应先解析远端 `profiles.yaml`，再把内容写入“实际被引用”的文件。
- 判断增强是否生效，至少要验证三点：

  ```text
  profiles.yaml 中 gcp-sg 的 option 指向非空增强文件
  rules 增强文件大小明显不是空模板
  groups 增强文件包含 AUTO 和成熟分流组
  ```

- 只用 `verge-mihomo -t -f remote.yaml` 只能验证原始订阅语法，不能证明 Clash Verge Rev 的增强项已经合成。需要近似合成 remote + groups + rules 后再测试。
- 自管理域名和面板 IP 必须放在规则最前直连，否则切到自建节点后可能无法访问面板和更新自己的订阅。
- 对可自动更新的远程订阅，短节点名应通过 script 增强持久化，不应只手改 remote YAML。

## Appendix: Reusable Commands

### 查看 Clash Verge Rev profile 实际引用

```bash
BASE="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"
grep -n "gcp-sg\\|vpn.chesszyh.xyz\\|merge:\\|script:\\|rules:\\|groups:" "$BASE/profiles.yaml"
```

### 查看远端实际 UID 和文件大小

```bash
ssh MacbookAir 'BASE="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"; stat -f "%N %z" "$BASE/profiles/RVr80t3PI54U.yaml" "$BASE/profiles/r15eX702Kw43.yaml" "$BASE/profiles/g4N9Vb0vr9ke.yaml" "$BASE/profiles/sdxKcHYzYJQI.js"'
```

```bash
ssh Macmini 'BASE="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"; stat -f "%N %z" "$BASE/profiles/Rhe5bfDqBGEN.yaml" "$BASE/profiles/rAZEd70Jquxu.yaml" "$BASE/profiles/g717bBVjtvKr.yaml" "$BASE/profiles/svHnULi27C18.js"'
```

### 备份远端 profile 文件

```bash
ssh MacbookAir 'BASE="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"; TS=$(date +%Y%m%d-%H%M%S); cp -a "$BASE/profiles.yaml" "$BASE/profiles.yaml.bak.gcp-sg-fix-$TS"'
```

```bash
ssh Macmini 'BASE="$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev"; TS=$(date +%Y%m%d-%H%M%S); cp -a "$BASE/profiles.yaml" "$BASE/profiles.yaml.bak.gcp-sg-fix-$TS"'
```

### 验证远端原始 YAML 语法

```bash
ssh MacbookAir '"/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" -t -f "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/RVr80t3PI54U.yaml"'
```

```bash
ssh Macmini '"/Applications/Clash Verge.app/Contents/MacOS/verge-mihomo" -t -f "$HOME/Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/profiles/Rhe5bfDqBGEN.yaml"'
```

### 合成验证思路

```python
import yaml
from pathlib import Path

raw = yaml.safe_load(Path("remote.yaml").read_text())
groups = yaml.safe_load(Path("groups.yaml").read_text())
rules = yaml.safe_load(Path("rules.yaml").read_text())

merged = dict(raw)
merged["proxy-groups"] = (groups.get("prepend") or []) + (raw.get("proxy-groups") or []) + (groups.get("append") or [])
raw_rules = [r for r in (raw.get("rules") or []) if r not in set(rules.get("delete") or [])]
merged["rules"] = (rules.get("prepend") or []) + raw_rules + (rules.get("append") or [])

Path("merged.yaml").write_text(yaml.safe_dump(merged, allow_unicode=True, sort_keys=False))
```

```bash
verge-mihomo -t -f merged.yaml
```
