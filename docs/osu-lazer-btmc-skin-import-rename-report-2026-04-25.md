生成时间: 2026-04-25T00:50:03+08:00

# osu! lazer BTMC 皮肤导入后名称过长与重导入修复报告

## 1. Problem Description

在 `osu! lazer` 中部署 BTMC 皮肤后，皮肤本体已经成功导入，但显示名称变成了过长的组合字符串：

`- # BTMC | ⌞Freedom Dive ↓⌝ [- # BTMC ⌞Freedom Dive ↓⌝]`

用户后续提出的目标不是重新换另一套皮肤，而是：

- 保留当前这套已导入 BTMC 皮肤的实际内容
- 把显示名精简成更短、更稳定的名称
- 避免在 `lazer` 里继续残留旧的长名称条目

最终结果是：

- 旧的长名称皮肤条目已从真实 `client.realm` 中删除
- 新皮肤名称为 `BTMC Freedom Dive`
- 当前选择的皮肤 UUID 已切换到新的短名条目

## 2. Environment and Scope

- 系统环境：Fedora 43，Hyprland，Wayland/XWayland 混合桌面
- 游戏版本：`osu! lazer 2026.421.0-lazer`
- 可执行文件：`/home/chesszyh/Applications/osu.AppImage`
- 启动入口：`/usr/local/bin/osu`
- 用户数据目录：`/home/chesszyh/.local/share/osu`
- 关键文件：
  - ` /home/chesszyh/.local/share/osu/game.ini`
  - ` /home/chesszyh/.local/share/osu/client.realm`
  - ` /home/chesszyh/.local/share/osu/logs/1777039749.database.log`
  - ` /home/chesszyh/.local/share/osu/logs/1777039749.runtime.log`

说明：

- `game.ini` 含有账号相关敏感字段，例如 `Token`，本报告只引用与皮肤有关的 `Skin = <uuid>` 行，不粘贴完整文件内容。
- 排障过程中曾意外生成 ` /home/chesszyh/.local/share/osu/client_51.realm`，这是调试写库时触发的 Debug schema 后缀副本，不是 `osu!` 正在使用的真实数据库。

## 3. Symptoms and Reproduction

初始现象：

- 用户提供皮肤目录 `./BTMC`
- 导入后皮肤本体可用，但名称过长
- 用户要求把名称精简，而不是单纯换另一套皮肤

可复现路径：

1. 准备一个 `.osk` 归档，其文件名为 `- # BTMC   ⌞Freedom Dive  ↓⌝.osk`
2. 归档内部 `skin.ini` 的 `Name:` 为 `- # BTMC |  ⌞Freedom Dive  ↓⌝`
3. 在 `osu! lazer` 中导入该归档
4. `lazer` 最终把 `skin.ini` 中的名字和归档文件名组合显示，形成超长条目

关键证据：

```text
/home/chesszyh/.local/share/osu/logs/1777039749.database.log:41
2026-04-24 14:37:30 [verbose]: [?????] Beginning import from - # BTMC   ⌞Freedom Dive  ↓⌝.osk...

/home/chesszyh/.local/share/osu/logs/1777039749.runtime.log:876
2026-04-24 14:37:31 [verbose]: ⚠️ Imported - # BTMC |  ⌞Freedom Dive  ↓⌝ [- # BTMC   ⌞Freedom Dive  ↓⌝] (BTMC / JesusOmega / MyniMyxii / Tofumang / Kazu)! Click to view.
```

## 4. Investigation Timeline

1. 确认 `osu! lazer` 的皮肤不是 stable 那种直接放进 `Skins/` 文件夹的目录模式，而是通过 `client.realm` + `files/` 哈希存储管理；`game.ini` 中的 `Skin` 字段存的是 UUID，不是目录名。

2. 验证官方导入入口。通过：

```bash
/usr/local/bin/osu '/absolute/path/to/skin.osk'
```

把 `.osk` 发送给运行中的 `osu! lazer` 实例，确认这是官方支持的 IPC 导入路径。

3. 克隆 `ppy/osu` 官方源码并检查 `SkinImporter.cs`。定位到名称拼接逻辑：

```text
/tmp/ppy-osu/osu.Game/Skinning/SkinImporter.cs:143-153
```

核心行为是：

- 先取 `skin.ini` 的 `Name`
- 如果归档文件名 `archiveName` 和该名字不同
- 且它又不等于 lazer 导出后的规范文件名
- 就把最终名称改成 `"{skinIniName} [{archiveName}]"`

这直接解释了为什么导入后名称会变长。

4. 第一次错误假设是“直接改数据库里的 `SkinInfo.Name` 就够了”。为此先写了读取/重命名辅助工具，确认能枚举皮肤条目，但真正写入时踩到了两类问题：

- `client.realm` 不是 SQLite，`sqlite3 client.realm` 不能直接读
- 使用 `osu.Game` Debug 构建时，`RealmAccess` 会自动创建 `client_51.realm` 作为 schema-suffixed 调试库

结果是：看起来“删除成功”或“改名成功”的操作其实只影响了 `client_51.realm`，真实运行中的 `client.realm` 没变。

5. 第二次错误假设是“直接用 UI 自动化把名字改掉”。尝试过：

- Hyprland `hyprctl dispatch sendshortcut`
- XWayland/可访问性接口
- 皮肤编辑器与设置页的键盘路径

这些方法能在少数状态下触发切换皮肤，但对“稳定重命名当前皮肤”并不可靠，特别是在游戏界面状态切换、窗口类名变化或应用退出时更容易失效。

6. 之后切换思路，不再尝试原地改名，而是采用更稳的归档级方案：

- 先从当前已导入的长名称皮肤导出 `.osk`
- 修改导出包内 `skin.ini` 的两处 `Name:`
- 将导出包文件名也改成 `BTMC Freedom Dive.osk`
- 重新导入
- 删除旧的长名称条目
- 把 `game.ini` 的当前皮肤 UUID 指向新条目

7. 重新导入成功后，日志出现新的短名称证据：

```text
/home/chesszyh/.local/share/osu/logs/1777039749.database.log:49
2026-04-24 14:56:30 [verbose]: [?????] Beginning import from BTMC Freedom Dive.osk...

/home/chesszyh/.local/share/osu/logs/1777039749.runtime.log:1226
2026-04-24 14:56:30 [verbose]: ⚠️ Imported BTMC Freedom Dive (BTMC / JesusOmega / MyniMyxii / Tofumang / Kazu)! Click to view.
```

8. 最后用 Release 版数据库工具对真实 `client.realm` 删除旧的长名称条目，并把 `game.ini` 的 `Skin` UUID 改到新皮肤：

```text
Skin = efa7776f-35c3-432a-b171-feda9b378c9b
```

## 5. Root Cause

根因不是“导入失败”，而是 `osu! lazer` 的皮肤导入命名策略与该皮肤归档本身的命名不一致。

更准确地说，问题由两个条件共同触发：

1. 归档内部 `skin.ini` 已经定义了一个名字：

```text
Name: - # BTMC |  ⌞Freedom Dive  ↓⌝
```

2. 归档文件名又是另一个不同的名字：

```text
- # BTMC   ⌞Freedom Dive  ↓⌝.osk
```

`SkinImporter.checkSkinIniMetadata()` 在导入时会把这两者合并，最终生成：

```text
<skin.ini 的 Name> [<archiveName>]
```

因此：

- 长名字是官方导入逻辑的结果
- 不是皮肤资源本身损坏
- 也不是 `game.ini` 中当前皮肤 UUID 错乱

调试阶段另外还有一个“次级根因”，导致错误排障结论：

- 使用 Debug 版 `osu.Game` 的 `RealmAccess` 写库时，会创建 `client_51.realm`
- 这让“数据库写入成功”的表象和真实 `client.realm` 状态脱节

## 6. Changes Made

实际生效的变更如下：

- 在真实数据库 ` /home/chesszyh/.local/share/osu/client.realm` 中导入了新的短名称皮肤条目：
  - UUID：`efa7776f-35c3-432a-b171-feda9b378c9b`
  - 名称：`BTMC Freedom Dive`

- 在真实数据库 ` /home/chesszyh/.local/share/osu/client.realm` 中删除了旧的长名称条目：
  - UUID：`80b3b4bb-becd-4f5d-b5d2-fb044e275918`

- 更新了 ` /home/chesszyh/.local/share/osu/game.ini`：
  - 从：`Skin = 80b3b4bb-becd-4f5d-b5d2-fb044e275918`
  - 到：`Skin = efa7776f-35c3-432a-b171-feda9b378c9b`

- 在导出的临时归档中把 `skin.ini` 的所有 `Name:` 改成：

```text
BTMC Freedom Dive
```

- 临时调试产物已清理：
  - `/tmp/BTMC-export.osk`
  - `/tmp/BTMC Freedom Dive.osk`
  - `/tmp/btmc-repack`
  - 各种一次性 C# helper 目录

说明：

- ` /home/chesszyh/.local/share/osu/client_51.realm` 仍然存在，这是调试期间留下的 Debug schema 副本，不参与正常 `osu! lazer` 运行。
- 第一次导入使用的原始 `.osk` 在成功导入后被 `lazer` 自动删除，因此根目录 `BTMC` 中后来只剩 `NEW DESIGN VERSION` 等未导入副本。

## 7. Verification

最终验证点如下：

1. `game.ini` 当前皮肤 UUID 已切到新条目：

```bash
sed -n '1,6p' /home/chesszyh/.local/share/osu/game.ini
```

结果：

```text
Skin = efa7776f-35c3-432a-b171-feda9b378c9b
```

2. 导入日志明确记录新名字：

```bash
rg -n "Imported BTMC Freedom Dive|Beginning import from BTMC Freedom Dive\\.osk" \
  /home/chesszyh/.local/share/osu/logs/1777039749.database.log \
  /home/chesszyh/.local/share/osu/logs/1777039749.runtime.log -S
```

3. 真实皮肤列表中只保留短名条目，不再包含旧长名：

```text
efa7776f-35c3-432a-b171-feda9b378c9b | BTMC Freedom Dive | BTMC / JesusOmega / MyniMyxii / Tofumang / Kazu
```

4. `osu!` 关闭后再次启动，将直接按 `game.ini` 选中短名条目。

## 8. Problems Encountered During Debugging

- `client.realm` 不是 SQLite 数据库，直接用 `sqlite3` 查询会失败。

- 只用本地只读 schema helper 可以安全读皮肤信息，但不适合作为写库方案。

- Debug 版 `osu.Game` 的 `RealmAccess` 会把调试写入落到 `client_51.realm`，这会制造“我已经删掉旧皮肤了”的假象。

- `hyprctl dispatch sendshortcut` 对切换皮肤有时有效，但对稳定完成“打开设置 -> 重命名 -> 保存”并不可靠。

- 从 AppImage 调用导入时会出现噪声警告：

```text
qt.qpa.plugin: Could not find the Qt platform plugin "wayland" in ""
```

但这并没有阻止 IPC 导入成功。

- `osu! lazer` 在导入成功后默认会删除原始 `.osk`，所以后续如果还要修改名字，不能假设原归档仍然留在源目录。

## 9. Reuse Notes and Lessons

- 在 `osu! lazer` 中，皮肤显示名由 `skin.ini` 与归档文件名共同决定；如果两者不一致，`SkinImporter` 可能会自动把两者拼起来。

- 如果目标只是“缩短显示名”，最稳妥的做法不是直接改 Realm，而是：
  1. 导出当前皮肤
  2. 统一修改 `skin.ini` 的 `Name`
  3. 同时把归档文件名改成相同短名
  4. 重新导入
  5. 删除旧条目

- 如果原始 `.osk` 已被 `lazer` 删除，不要急着去找源目录里的旧包；优先从当前已导入皮肤导出，这样能保证内容和当前生效皮肤完全一致。

- 需要真正写 `client.realm` 时，优先使用 Release 版、面向真实数据库路径的官方 `osu.Game` 类型；否则很容易被 `client_51.realm` 这类调试副本误导。

- `Click to view` 是“可切换/可展示”的通知，并不等价于“当前已经自动切到新皮肤”。

## 10. Appendix: Reusable Commands

### A. 查看当前皮肤 UUID

```bash
sed -n '1,6p' /home/chesszyh/.local/share/osu/game.ini
```

### B. 查看皮肤导入日志

```bash
rg -n "Beginning import from .*\\.osk|Imported .*BTMC|Skin import" \
  /home/chesszyh/.local/share/osu/logs/*.database.log \
  /home/chesszyh/.local/share/osu/logs/*.runtime.log -S
```

### C. 向运行中的 osu! lazer 实例发送导入请求

```bash
/usr/local/bin/osu '/absolute/path/to/skin.osk'
```

### D. 修改已导出皮肤包内的名字

```bash
rm -rf /tmp/btmc-repack
mkdir -p /tmp/btmc-repack
unzip -q /tmp/BTMC-export.osk -d /tmp/btmc-repack
perl -0pi -e 's/^(\s*Name:\s*).*$/${1}BTMC Freedom Dive/gm' /tmp/btmc-repack/skin.ini
(cd /tmp/btmc-repack && zip -qr /tmp/BTMC\ Freedom\ Dive.osk .)
```

### E. 验证重打包后的 `skin.ini`

```bash
unzip -p '/tmp/BTMC Freedom Dive.osk' skin.ini | sed -n '1,80p'
```

### F. 官方源码中定位命名拼接逻辑

```bash
nl -ba /tmp/ppy-osu/osu.Game/Skinning/SkinImporter.cs | sed -n '129,153p'
```

### G. 运行中快速切换到上一套皮肤（当窗口仍存在时）

```bash
hyprctl dispatch sendshortcut "CTRL_SHIFT,E,class:^osu!$"
```

### H. 关闭游戏后直接确认目标 UUID

```bash
rg -n '^Skin\\s*=\\s*' /home/chesszyh/.local/share/osu/game.ini
```
