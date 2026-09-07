生成时间: 2026-09-07T15:18:30+08:00

# Fedora Hyprland 剪贴板停录、文本粘贴失败与截图乱码排障报告

## 1. 问题描述

2026-09-04 至 2026-09-07，同一剪贴板工作流先后出现三类故障：历史记录不再新增；复制文本后不能直接粘贴，必须从历史菜单选择一次；修复文本后，截图直接粘贴被当作文本并产生乱码。

前两轮修改合入配置仓库提交 `b0f0b64`，第三轮格式修复提交为 `4f73848`。截图乱码属于前次修复引入的回归，责任在于桥接实现缺少格式判断、验证只覆盖文本。当前后台验证已通过，但尚无用户在具体粘贴应用中的最终确认，不能把局部验证称为“彻底解决”。

## 2. 环境与范围

系统为 Fedora，桌面使用 Hyprland；XWayland（在 Wayland 桌面运行 X11 应用的兼容层）与原生 Wayland 应用共存。排障时记录的版本为 Hyprland 0.51.1、wl-clipboard 2.2.1、cliphist 0.7.0；这些是当时快照，本报告没有重新核验软件版本。

配置仓库：`/home/chesszyh/.config/hypr`。快捷键包括 `Win+Alt+V` 历史菜单，以及用户报告的 `Win+Shift+PrtSc` 截图并复制。截图脚本使用 `grim` 采集 PNG，经 `wl-copy` 发布。

本次报告生成时重新检查：文本、图片和 X11 三个用户服务均为 `active`，各自 `NRestarts=0`；仓库最新两次提交为上述两个修复提交。未读取或收录用户真实剪贴板正文。

## 3. 症状与复现

| 阶段 | 用户可见症状 | 有效证据 |
| --- | --- | --- |
| 历史停录 | 复制新内容后历史菜单不新增 | 早期排查记录显示历史入库子进程长期阻塞于管道读取 |
| 文本直接粘贴失败 | Ctrl+C 后 Ctrl+V 无内容，历史菜单回车后恢复 | X11 读取可成功，而跨到 Wayland 的读取或粘贴失败；重新发布后可恢复 |
| 截图乱码 | 直接粘贴按文本解码，从历史选择图片则正常 | 旧代码把默认 X11 读取结果统一发布成 text/plain；模拟 PNG 被默认读取返回的回归用例在旧代码上失败 |

第三轮后台首次 PNG 测试保留了图片格式，没有稳定复现用户应用中的乱码。因此这里确认的是代码存在格式破坏路径，以及修复后数据格式验证通过；不是声称已经自动复现并验证所有图形应用中的显示行为。

## 4. 排查时间线

### 2026-09-04：历史记录不再新增

此前排查记录发现 `wl-paste --watch ... cliphist store` 的子进程长期停在 `anon_pipe_read`，约 5.5 小时没有结束。菜单绑定仍指向正确脚本。因为监听器等待入库子进程，单次未结束的传输阻止了后续记录。

引入 `CliphistStore.py` 对输入读取设置起始、空闲和绝对时限，并将文本、图片监听交给用户级 systemd 服务管理。之后发现 XWayland 来源还需要独立的 X11 历史捕获路径。

### 2026-09-04 至 09-05：历史有内容，当前剪贴板仍不可粘贴

用户再次反馈必须打开历史并回车。排查确认“保存进历史”和“为目标应用提供当前数据”是两个不同环节。加入 X11 监听后，仅入库仍不能解决跨后端粘贴，于是增加通过 `wl-copy --foreground --type text/plain` 发布文本的路径。

当时使用默认 X11 读取，没有校验格式，这是随后截图回归的引入点。一次简单发布没有稳定通过，最终实现最多三次发布、每次等待 0.15 秒检查进程是否仍存活。该措施解决了当时隐藏文本源测试，但没有证明底层桥接撤销的全部机制。

期间可见窗口循环测试严重干扰桌面，用户明确指出“一直在弹窗口，疯了？”。停止测试窗口和进程后，改用隐藏源测试。最终记录文本跨后端 10/10 通过、原生文本通过，随后作出了过强的完成声明。

### 2026-09-07：用户报告截图回归

核对代码发现无格式检查的读取结果进入纯文本发布。新增回归用例模拟仅提供 `image/png`、默认读取却返回 PNG 字节的来源；旧实现返回图片字节而不是拒绝，断言失败。

修复为先查询 `TARGETS`（X11 来源声明的可提供格式），仅允许纯文本及必要元数据，再显式请求对应文本格式。含图片、HTML、文件列表的选择不进入文本桥接。

首次严格允许列表阻止了 Tk 测试源的文本桥接。读取真实 `TARGETS` 后发现 `TK_APPLICATION`、`TK_WINDOW` 是元数据，加入识别后，中英文文本跨后端测试通过。

实际截图验证首次使用 `0,0 16x16` 区域失败，错误为 `supplied geometry did not intersect with any outputs`。读取显示器坐标后改为当前输出左上角的小区域，截图发布与读取通过。测试未弹出窗口。

## 5. 根因

### 历史停录：一次传输不结束，阻塞后续监听处理

数据生产者可已写出内容却仍保持管道开启；直接等待输入结束的入库链路因而不能返回。读取时限解决的是这一阻塞，不是图形系统所有剪贴板故障。

### 文本粘贴失败：历史存储不能替代跨后端数据提供

X11 端能读到数据，不代表 Wayland 目标应用能取得数据。历史菜单选择会执行解码和重新发布，因此用户手工操作绕过了当时失效的传递路径。底层为何突然出现桥接问题，并没有定位到具体上游提交、升级或协议错误；此前回答中“首次跨边界或更新改变后端”的解释只是猜测，不应作为已确认根因。

### 截图乱码：文本桥接缺少内容格式边界

旧路径是默认 `xclip -out` 读取后，无条件使用 `text/plain` 发布。只要非文本字节被该读取返回，桥接就会错误声明数据类型。PNG 属于二进制图像，声明成文本会改变接收应用的处理方式。

历史库中的图片条目仍可正确解码发布，所以从历史选择能恢复。该现象与格式破坏相符；实际用户应用中的具体触发时序仍未被后台测试完整捕获。

## 6. 修改内容

| 文件绝对路径 | 最终作用 |
| --- | --- |
| `/home/chesszyh/.config/hypr/scripts/CliphistStore.py` | 限时读取剪贴板输入，避免开放管道永久阻塞历史入库 |
| `/home/chesszyh/.config/hypr/scripts/X11CliphistWatch.py` | 监听 X11 选择变更，查询格式，只将纯文本桥接到 Wayland |
| `/home/chesszyh/.config/hypr/systemd/cliphist-watch@.service` | 分别运行文本和图片历史监听 |
| `/home/chesszyh/.config/hypr/systemd/cliphist-x11.service` | 监督 X11 监听进程 |
| `/home/chesszyh/.config/hypr/UserConfigs/Startup_Apps.conf` | 前两轮的服务启动集成 |
| `/home/chesszyh/.config/hypr/tests/test_cliphist_store.py` | 开放管道和正常结束读取测试 |
| `/home/chesszyh/.config/hypr/tests/test_x11_cliphist_watch.py` | 发布行为、格式拒绝、显式 UTF-8 读取和元数据识别测试 |

最新修复只修改 X11 脚本及其测试。查询格式失败时不再回退到默认读取；优先请求 UTF-8 文本，兼容 `STRING` 的 Latin-1 到 UTF-8 转换；UTF-8 无效的数据不进入桥接。

图片、HTML 和文件列表保持原有来源负责供给。这是防止格式破坏的边界，并未新增这些格式的跨后端桥接能力。

相关提交：

- `b0f0b64 fix(clipboard): bridge XWayland copies into Wayland`：包括历史监听和文本桥接。早期显示过的 `f35d5ad` 在 amend 后由此提交替代。
- `4f73848 fix(clipboard): restrict X11 text bridge to plain-text selections`：格式边界修复，独立提交。

## 7. 验证

| 检查 | 结果与边界 |
| --- | --- |
| 新增图片拒绝用例运行于旧代码 | AssertionError，证明可抓住错误文本路径 |
| 修复后自动测试 | 9 项通过；本机无 pytest，通过 runpy 执行测试函数及断言 |
| Wayland PNG | 图片格式和原始字节保留 |
| X11 PNG | X11 侧声明和读取仍为图片，未被文本桥接覆盖；未据此宣称图片跨后端可用 |
| 隐藏 Tk 中英文文本源 → Wayland | 通过，无可见窗口 |
| 原生 Wayland 中英文文本 | 通过 |
| 实际 grim → wl-copy → image/png | 在发布后约 50ms 和 550ms 两次读取，格式正确、字节一致 |
| git diff --check | 通过 |
| 报告生成时服务状态 | 三个服务 active，NRestarts 均为 0 |

图片传输验证比较实际字节，不以“服务没有报错”代替内容正确。HTML、文件列表目前只有拒绝进入文本桥接的自动测试；没有相应实际应用粘贴验证。用户目标应用的截图显示效果、快速连续复制和重登录后的完整工作流尚未得到本次验证。

## 8. 排障过程中的问题

1. **过早宣布完成。** 文本样例和历史入库通过后宣称彻底修复，实际没有覆盖截图。报告保留这一失误，不把后续回归归因于用户操作。
2. **桌面自动化失控。** 多次创建可见窗口并切换焦点干扰用户；后续应使用隐藏源或后台数据路径，不能重复窗口压力测试。
3. **测试工具错误混入故障判断。** 早期使用 `rtk wait` 代替 shell 内建命令、X11 窗口激活返回 `XGetWindowProperty[_NET_ACTIVE_WINDOW] failed`、向 Wayland 窗口发送 X11 输入，均使部分失败计数无效。
4. **隐藏测试源没有持续处理事件。** Tk 仅调用一次 update 后 sleep，不能稳定响应选择请求；改为 mainloop 后才形成有效输入源。因此早期部分隐藏测试失败不能归因于剪贴板。
5. **运行通过被误当作因果证据。** 发布重试有工程效果，但未抓取底层协议证据；“XWayland 必然撤销第一次所有权”等结论不能提升为已证实事实。
6. **依赖与环境问题。** Python-Xlib 尝试曾出现 `select_selection_input() missing 1 required positional argument: 'mask'` 和 `BadRRCrtcError`，最终使用 ctypes 调用本机 X11/Xfixes 库；pytest 不在系统 Python 中；显示器坐标不能假设从 0,0 开始。
7. **格式验证太浅。** 原测试验证“调用了 wl-copy”却没有验证什么输入允许触发该调用。新增格式边界测试直接覆盖此次故障模式。

## 9. 复用要点与经验

遇到“历史可恢复、直接粘贴失败”，分别检查来源数据、来源声明格式、目标端读取和历史库。四者不能互相替代。

修改剪贴板所有权会影响同一桌面的全部格式。至少需要覆盖纯文本、图片、混合格式拒绝以及中英文文本；对图片应同时断言格式和字节。来源提供 HTML 或文件列表时，只取其中纯文本并覆盖整个选择会丢失功能。

当前实现保留既有发布重试，尚未建立快速连续复制时的过期选择保护验证。后续若再出现旧内容覆盖新内容，应检查这一已存在的时序边界，而不是继续增加固定等待。

有限后台测试可以证明具体路径通过，不能替代用户应用中的最终体验。对首次触发原因不明的底层桥接故障，应保留“不确定”，不要用可能的升级或应用后端变化填补证据空白。

## 10. 附录：可复用命令

### 查看服务与错误日志

```bash
rtk systemctl --user show cliphist-watch@text.service cliphist-watch@image.service cliphist-x11.service -p Id -p ActiveState -p NRestarts
rtk journalctl --user -u cliphist-x11.service -u cliphist-watch@text.service -u cliphist-watch@image.service --since "10 minutes ago" --no-pager
```

### 只检查格式，不输出剪贴板正文

```bash
rtk proxy timeout 2s wl-paste --list-types
rtk proxy timeout 2s xclip -selection clipboard -out -target TARGETS
```

### 执行当前回归测试

```bash
cd /home/chesszyh/.config/hypr
rtk proxy python3 -B - <<'PY'
import runpy

count = 0
for path in (
    "tests/test_cliphist_store.py",
    "tests/test_x11_cliphist_watch.py",
):
    for name, fn in runpy.run_path(path).items():
        if name.startswith("test_") and callable(fn):
            fn()
            count += 1
print("PASS", count, "tests")
PY
```

### 查看最终修改

```bash
rtk git -C /home/chesszyh/.config/hypr show 4f73848 -- scripts/X11CliphistWatch.py tests/test_x11_cliphist_watch.py
rtk git -C /home/chesszyh/.config/hypr show --stat b0f0b64
```

### 修改脚本后重新加载 X11 监听

```bash
rtk systemctl --user restart cliphist-x11.service
```

服务重启会结束其持有的当前剪贴板进程，验证时应重新复制内容。截图区域应从 `hyprctl monitors -j` 的实际 x、y 坐标选择，避免使用不与任何输出相交的固定坐标。

