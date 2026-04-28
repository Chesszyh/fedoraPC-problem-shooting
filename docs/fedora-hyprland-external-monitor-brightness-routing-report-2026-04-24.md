# Fedora Hyprland 外接显示器亮度路由与卡顿优化报告

生成时间: 2026-04-24T21:54:30+08:00

## 1. Problem Description

在 Fedora Hyprland 环境中，笔记本内置屏幕可以通过 `brightnessctl` 正常调节亮度，但外接显示器无法跟随同一套快捷键工作。用户希望把亮度调节统一到当前使用中的屏幕，而不是为内屏和外屏分别记忆两套快捷键；在功能打通后，又发现外接屏亮度调节明显比内屏卡顿，需要进一步定位并优化。

本次排障目标有两个：

- 让 `xf86MonBrightnessDown` / `xf86MonBrightnessUp` 根据当前焦点屏幕自动路由到内屏或外屏。
- 在不改变使用方式的前提下，减少外接显示器经 `ddcutil` 调节亮度时的等待感。

## 2. Environment and Scope

- 操作系统：Fedora
- 桌面环境：Hyprland
- 主配置目录：`/home/chesszyh/.config/hypr`
- 相关显示器：
  - 内屏：`eDP-1`
  - 外屏：`HDMI-A-1`，`ddcutil detect --brief` 可识别为 `AOC:U27N3R`
- 本次涉及的关键文件：
  - `/home/chesszyh/.config/hypr/UserConfigs/Laptops.conf`
  - `/home/chesszyh/.config/hypr/UserConfigs/UserKeybinds.conf`
  - `/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh`
  - `/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh`
- 关键工具：
  - `hyprctl`
  - `brightnessctl`
  - `ddcutil`
  - `jq`

范围限定在 Hyprland 用户配置与显示器亮度控制链路，不涉及内核驱动、Waybar 模块或显示器 OSD 菜单重配置。

## 3. Symptoms and Reproduction

### 初始现象

- 按笔记本原有亮度键时，只能调节主屏幕亮度。
- 外接显示器亮度不会变化。
- 尝试启用备用的 `Super+Alt+F11/F12` 外屏亮度快捷键后，仍然无效。

### 复现路径

1. 保持 Hyprland 配置中 `xf86MonBrightnessDown` / `xf86MonBrightnessUp` 指向 `Brightness.sh`。
2. 连接外接显示器并把焦点切到外屏。
3. 按亮度键，只会调用 `brightnessctl`，因此只影响支持内核 backlight 的内屏。

### 关键证据

当前 Hyprland 绑定已确认改为：

```text
1014: key: xf86MonBrightnessDown
1019: arg: /home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh --dec
1024: key: xf86MonBrightnessUp
1029: arg: /home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh --inc
```

当前外屏 DDC/CI 探测结果：

```text
Display 1
   I2C bus:          /dev/i2c-9
   DRM connector:    card1-HDMI-A-1
   Monitor:          AOC:U27N3R:1L0R6HA002437

Invalid display
   I2C bus:          /dev/i2c-10
   DRM connector:    card1-eDP-1
   Monitor:          BOE::
```

这说明外屏支持 DDC/CI，而内屏不支持，天然需要两套不同的底层控制方式。

## 4. Investigation Timeline

1. 检查现有 Hyprland 配置后，发现内屏亮度键绑定在 `/home/chesszyh/.config/hypr/UserConfigs/Laptops.conf`，调用的是 `Brightness.sh`，其内部使用 `brightnessctl`。
2. 在同一配置仓库中发现已有 `/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh`，说明外屏亮度本来就计划使用 `ddcutil`。
3. 通过 `ddcutil detect` 和 `ddcutil getvcp 10 --brief` 验证外屏硬件链路可用，确认问题不在显示器是否支持 DDC/CI，而在配置路由与脚本实现。
4. 启用备用外屏快捷键后仍无效，进一步执行 `bash -n /home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh`，发现脚本本身存在 Bash 语法错误，导致外屏路径根本无法执行。
5. 将用户需求从“额外给外屏一套快捷键”调整为“沿用同一组亮度键，根据当前焦点屏幕自动路由”，新增 `/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh` 作为统一入口。
6. 通过 `hyprctl -j activeworkspace` 和 `hyprctl -j monitors` 确认当前活动工作区可映射到具体显示器名称，因此可以在脚本里用焦点屏幕名决定调用 `Brightness.sh` 还是 `ExternalBrightness.sh`。
7. 完成功能后，用户反馈外屏亮度调节比内屏明显卡顿，于是对 `ddcutil` 各子步骤分别计时，确认主要耗时集中在 `ddcutil detect` 和 `ddcutil getvcp`。
8. 继续检查 `ddcutil setvcp --help`，确认支持 `setvcp <feature-code> [+|-] <new-value>` 相对调节，并且可以使用 `--noverify` 关闭写后校验。
9. 在 `/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh` 中加入 connector 到 display id 的缓存、短期亮度缓存，并改用 `--noverify setvcp 10 +/- N` 的相对写法，以减少重复按键时的探测与读取成本。

## 5. Root Cause

### 根因 1：内屏与外屏的亮度控制链路不同

内屏通过 `brightnessctl` 调用内核 backlight 接口；外屏需要通过 `ddcutil` 走 DDC/CI 与显示器固件通信。原始配置把 `xf86MonBrightnessDown` / `xf86MonBrightnessUp` 固定绑定到了 `Brightness.sh`，因此无论焦点在哪个屏幕，都会只走内屏链路。

### 根因 2：外屏脚本原本无法执行

`/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh` 在生成通知图标路径时存在 Bash 语法错误，因此即使绑定到该脚本，外屏亮度快捷键也不会生效。

### 根因 3：外屏卡顿主要来自 DDC/CI 往返和重复探测

外屏亮度调节慢不是 Hyprland 绑定本身的问题，而是外屏控制必须经过 `ddcutil` 与显示器通信。原始外屏脚本在一次按键中需要做：

1. `ddcutil detect --brief`
2. `ddcutil getvcp 10 --brief`
3. `ddcutil setvcp 10 <new>`

实测单项耗时大致为：

```text
detect 0.86
getvcp 0.33
setvcp_noverify 0.36
```

之前还观测到过 `detect ~0.64s`、`getvcp ~0.58s` 的情况，说明 DDC/CI 链路存在一定波动，但结论一致：重复执行 `detect` 与 `getvcp` 会显著放大卡顿感。

## 6. Changes Made

### 已提交变更

Hypr 配置仓库中已提交：

```text
129bd3d Add focused-monitor brightness routing
```

该提交包含：

- 在 `/home/chesszyh/.config/hypr/UserConfigs/Laptops.conf` 中把 `xf86MonBrightnessDown` / `xf86MonBrightnessUp` 改为调用 `BrightnessFocused.sh`
- 新增 `/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh`
- 修复 `/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh` 的语法错误并支持按 connector 路由
- 启用 `/home/chesszyh/.config/hypr/UserConfigs/UserKeybinds.conf` 中原有的外屏备用快捷键

### 报告生成时仍在工作区中的优化变更

`/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh` 进一步加入了以下优化：

- 缓存 `display_connector -> display_id`
- 缓存最近一次亮度值与最大亮度，默认 TTL 为 30 秒
- 调节时改用相对写法：`ddcutil --noverify setvcp 10 +/- N`
- 调节失败时自动清理缓存并重新探测 connector

这些优化的目标是把“每次按键都重新探测和读当前亮度”改成“只在必要时同步一次，然后在热路径上直接写”。

## 7. Verification

### 功能验证

执行过以下检查：

```bash
bash -n /home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh
bash -n /home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh
hyprctl reload
hyprctl binds | rg "xf86MonBrightness(Down|Up)|BrightnessFocused\\.sh"
ddcutil detect --brief
ddcutil --display 1 getvcp 10 --brief
```

关键结果：

- 两个脚本均通过 Bash 语法检查。
- `hyprctl reload` 返回 `ok`。
- `hyprctl binds` 确认亮度键已绑定到 `BrightnessFocused.sh`。
- `ddcutil detect --brief` 能识别 `HDMI-A-1` 对应的外接显示器。
- `ddcutil --display 1 getvcp 10 --brief` 当前返回：

```text
VCP 10 C 50 100
```

### 性能验证

热路径优化后，连续触发外屏亮度调节时，观测到的脚本耗时大致降到了：

```text
warm inc 0.45
warm dec 0.44
```

而冷路径仍会包含首次同步成本，这是预期行为，因为需要重新确认当前 connector 和亮度状态。

## 8. Problems Encountered During Debugging

- 最初容易误判为“Hyprland 不支持外屏亮度键”，但实际是绑定始终指向内屏脚本。
- 启用备用快捷键后没有立刻成功，原因不是快捷键本身，而是 `ExternalBrightness.sh` 语法错误。
- `hyprctl dispatch focusmonitor eDP-1` 的试验结果不稳定，说明把“焦点屏幕”直接建立在 `monitors[].focused` 上并不总是直观；最终优先使用 `activeworkspace.monitor`，再回退到 `monitors[].focused`。
- 外屏性能问题如果只从用户体感出发，很容易停留在“DDC/CI 天生慢”的模糊解释。拆分成 `detect`、`getvcp`、`setvcp` 三段分别计时后，才明确知道优化应该打在“去掉重复探测与读取”上。

## 9. Reuse Notes and Lessons

- Hyprland 多屏亮度控制不要直接假设一套脚本通吃。内屏和外屏底层能力不同，应该先判断是 `brightnessctl` 还是 `ddcutil` 路径。
- 如果外屏完全无响应，优先做三步：
  1. `ddcutil detect --brief`
  2. `ddcutil getvcp 10 --brief`
  3. `bash -n <external script>`
- 对于 `ddcutil` 场景，减少调用次数通常比微调 Bash 逻辑更重要。每一次 `detect`、`getvcp`、`verify` 都是明显的用户可感知延迟来源。
- “按当前焦点屏幕自动路由”比“另外加一套外屏快捷键”更符合日常使用习惯，尤其适合笔记本接外屏场景。
- 如果以后显示器连接器名称变化，例如从 `HDMI-A-1` 换成 `DP-1`，优先检查缓存与 connector 解析，而不是先怀疑 Hyprland 绑定失效。

## 10. Appendix: Reusable Commands

### 检查当前亮度绑定

```bash
hyprctl binds | rg "xf86MonBrightness(Down|Up)|BrightnessFocused\\.sh"
```

### 检查当前焦点屏幕

```bash
hyprctl -j activeworkspace | jq -r '.monitor'
hyprctl -j monitors | jq -r '.[] | select(.focused == true) | .name'
```

### 检查外屏是否支持 DDC/CI

```bash
ddcutil detect --brief
ddcutil --display 1 getvcp 10 --brief
```

### 手动测试统一亮度入口

```bash
/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh --get
/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh --inc
/home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh --dec
```

### 直接测试外屏脚本

```bash
/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh --connector HDMI-A-1 --get
/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh --connector HDMI-A-1 --inc
/home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh --connector HDMI-A-1 --dec
```

### 语法检查与重载

```bash
bash -n /home/chesszyh/.config/hypr/scripts/BrightnessFocused.sh
bash -n /home/chesszyh/.config/hypr/scripts/ExternalBrightness.sh
hyprctl reload
```

### 简单计时

```bash
/usr/bin/time -f '%e' sh -c 'ddcutil detect --brief >/dev/null'
/usr/bin/time -f '%e' sh -c 'ddcutil --display 1 getvcp 10 --brief >/dev/null'
/usr/bin/time -f '%e' sh -c 'ddcutil --display 1 --noverify setvcp 10 + 0 >/dev/null'
```
