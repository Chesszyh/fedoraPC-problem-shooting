# DaVinci Resolve 20.3.1 安装复盘报告（Fedora 43 + Hyprland）

日期：2026-02-26  
安装包：`DaVinci_Resolve_20.3.1.run`

## 1. 初始安装器无法直接运行（FUSE 权限）

- 现象：
  - 运行 `.run` 时出现 `Cannot mount AppImage`、`failed to open /dev/fuse: Permission denied`
- 根因：
  - 安装包是 AppImage 封装，当前环境下 FUSE 挂载不可用。
- 解决：
  - 先解包安装器再运行：
  ```bash
  ./DaVinci_Resolve_20.3.1.run --appimage-extract
  ```
- 结果：
  - 成功得到 `squashfs-root/`，可继续执行内部安装器。

## 2. 依赖检查报缺 `zlib`

- 现象：
  - 安装器提示 `Missing or outdated system packages`，缺少 `zlib`。
- 根因：
  - Fedora 43 实际提供的是 `zlib-ng-compat`，而 Resolve 安装器用 `rpm -q zlib` 硬编码检查包名，导致误报。
- 解决：
  - 使用安装器提供的跳过检查开关：
  ```bash
  SKIP_PACKAGE_CHECK=1
  ```
- 结果：
  - 可绕过包名误判，继续安装流程。

## 3. GUI 安装在 Hyprland 环境下授权失败

- 现象：
  - 通过 `sudo ... AppRun -i` 时出现 `Authorization required, but no authorization protocol specified`，并触发安装器崩溃。
- 根因：
  - root 图形授权/显示会话在该环境下不可用。
- 解决：
  - 改为文本模式安装，并指定最小 Qt 平台：
  ```bash
  sudo QT_QPA_PLATFORM=minimal SKIP_PACKAGE_CHECK=1 \
    ./squashfs-root/installer ./squashfs-root --install --noconfirm
  ```
- 结果：
  - 安装完成，日志出现：
  - `DaVinci Resolve installed to /opt/resolve`
  - `Done`

## 4. 首次启动缺库：`libcrypt.so.1`

- 现象：
  - `/opt/resolve/bin/resolve` 报错：
  - `error while loading shared libraries: libcrypt.so.1: cannot open shared object file`
- 根因：
  - Fedora 43 默认未提供旧 ABI 的 `libcrypt.so.1` 兼容层。
- 解决：
  ```bash
  sudo dnf install -y libxcrypt-compat
  ```
- 结果：
  - `ldd /opt/resolve/bin/resolve` 不再出现 `not found`。

## 5. 启动期符号冲突：`libpango` / `glib` 版本不兼容

- 现象：
  - 启动报错：
  - `symbol lookup error: /lib64/libpango-1.0.so.0: undefined symbol: g_once_init_leave_pointer`
- 根因：
  - Resolve 自带较旧 `glib`（位于 `/opt/resolve/libs`）覆盖了系统 `glib`，与 Fedora 43 的 `pango` 符号版本不匹配。
- 解决：
  - 禁用 Resolve 自带 `glib` 系列库，让程序使用系统库：
  ```bash
  sudo mkdir -p /opt/resolve/libs/_disabled_by_codex_20260226
  sudo mv /opt/resolve/libs/lib{gio,glib,gmodule,gobject}-2.0.so* \
          /opt/resolve/libs/_disabled_by_codex_20260226/
  ```
- 结果：
  - 该符号错误消失，程序进入后续初始化阶段。

## 6. 启动目录初始化失败（应用支持目录）

- 现象：
  - 日志出现 `Failed to create application support directories`。
- 根因：
  - 首次启动前，用户侧 Blackmagic/Resolve 目录未创建（加之受限环境测试下目录写入受限）。
- 解决：
  ```bash
  mkdir -p "$HOME/.local/share/DaVinciResolve" \
           "$HOME/.config/Blackmagic Design" \
           "$HOME/.cache/BlackmagicDesign"
  ```
- 结果：
  - 启动日志不再出现上述目录创建失败报错。

## 最终状态

- 安装路径：`/opt/resolve`
- 启动器：`/usr/share/applications/com.blackmagicdesign.resolve.desktop`
- 可执行文件：`/opt/resolve/bin/resolve`
- 本次已完成安装与主要运行时兼容修复，用户确认“已安装成功”。

## 可复用的关键命令（汇总）

```bash
# 1) 解包 AppImage 安装器
./DaVinci_Resolve_20.3.1.run --appimage-extract

# 2) 文本模式安装（规避 GUI 授权问题 + 依赖包名误报）
sudo QT_QPA_PLATFORM=minimal SKIP_PACKAGE_CHECK=1 \
  ./squashfs-root/installer ./squashfs-root --install --noconfirm

# 3) 修复 libcrypt.so.1
sudo dnf install -y libxcrypt-compat

# 4) 修复 glib/pango 符号冲突
sudo mkdir -p /opt/resolve/libs/_disabled_by_codex_20260226
sudo mv /opt/resolve/libs/lib{gio,glib,gmodule,gobject}-2.0.so* \
        /opt/resolve/libs/_disabled_by_codex_20260226/

# 5) 预建用户支持目录
mkdir -p "$HOME/.local/share/DaVinciResolve" \
         "$HOME/.config/Blackmagic Design" \
         "$HOME/.cache/BlackmagicDesign"
```
