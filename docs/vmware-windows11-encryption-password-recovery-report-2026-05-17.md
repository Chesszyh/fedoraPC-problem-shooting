# VMware Windows 11 虚拟机加密密码找回报告

生成时间: 2026-05-17T15:58:12+08:00

## Problem Description

用户希望通过 `vmcli` 为 VMware Workstation 中的 Windows 11 虚拟机安装最新版 PowerShell、nvm、Node.js 22 和 Codex。执行过程中发现该虚拟机是加密 VM，`vmcli` 和 `vmrun` 在没有 VMware 加密密码时无法执行电源查询、截图、MKS 操作或来宾系统操作。

用户只确认了 Windows 登录界面输入的密码，但忘记了 VMware 加密密码。由于当初创建或打开虚拟机时选择过“记住密码”，需要判断密码是否保存在本机 Linux 桌面密钥环中，并从可验证证据链恢复可用的 VMware 加密密码。

敏感信息处理：本报告不记录恢复出的旧 VMware 加密密码明文，也不记录用户随后修改后的新密码明文。

## Environment and Scope

- Host OS/session: Fedora + Hyprland，当前 shell 为 `zsh`。
- VMware product: VMware Workstation 17.6.4，`vmcli version 0.1 build-24832109`，`vmrun version 1.17.0 build-24832109`。
- VM directory: `/home/chesszyh/vmware/Windows11`
- VMX file: `/home/chesszyh/vmware/Windows11/Windows 11 x64.vmx`
- Guest OS: Windows 11 Pro, 64-bit，VMX 中记录 Build `26200.7623`。
- VMware Tools: 已安装并运行，后续通过 `vmrun checkToolsState` 验证为 `running`。
- Host keyring: `gnome-keyring-daemon` 正在运行，Secret Service 可通过 `secret-tool` / D-Bus 访问。

相关 VMX 证据：

```text
vmx.encryptionType = "partial"
encryptedVM.guid = "10395563108229220110"
guestOS = "windows11-64"
displayName = "Windows 11 x64"
```

## Symptoms and Reproduction

直接用 `vmcli` 查询电源状态时被加密层拦截：

```bash
vmcli "Windows 11 x64.vmx" Power query
```

关键错误：

```text
Encrypted virtual machine password:
vmcli: Missing decryption key for configuration file '/home/chesszyh/vmware/Windows11/Windows 11 x64.vmx'.
```

用用户提供的 Windows 登录密码尝试作为 VMware 加密密码传给 `vmrun -vp`，结果失败：

```bash
vmrun -T ws -vp '<Windows 登录密码，已脱敏>' checkToolsState "Windows 11 x64.vmx"
```

关键错误：

```text
Error: Cannot open VM: /home/chesszyh/vmware/Windows11/Windows 11 x64.vmx, Incorrect password
```

这说明 Windows 登录密码和 VMware 加密密码不是同一个密码。

## Investigation Timeline

1. 确认当前目录和 VM 文件。

   ```bash
   pwd
   rg --files -g '!*{.iso,.vmdk,.nvram,.vmem,.vmss,.vmsn}'
   ```

   发现当前目录为 `/home/chesszyh/vmware/Windows11`，存在 `Windows 11 x64.vmx`。

2. 查询 `vmcli` 能力。

   ```bash
   vmcli --help
   vmcli "Windows 11 x64.vmx" Guest --help
   vmcli "Windows 11 x64.vmx" MKS --help
   ```

   结果显示本机 `vmcli` 支持 `Power`、`Guest`、`MKS` 等模块，其中 `Guest` 操作需要 VMware Tools 和有效 Windows 来宾账号，`MKS` 操作也需要先解开 VM 加密配置。

3. 检查 VMX，确认这不是普通 VM，而是部分加密 VM。

   ```bash
   sed -n '1,180p' "Windows 11 x64.vmx"
   ```

   关键字段为 `vmx.encryptionType = "partial"` 和 `encryptedVM.guid = "10395563108229220110"`。

4. 尝试用 Windows 登录密码作为 VMware 加密密码。

   ```bash
   vmrun -T ws -vp '<Windows 登录密码，已脱敏>' checkToolsState "Windows 11 x64.vmx"
   ```

   返回 `Incorrect password`，排除“两个密码相同”的假设。

5. 检查当前系统是否有密钥环服务。

   ```bash
   command -v secret-tool
   ps -ef | rg -i "gnome-keyring|kwallet|secret-service|vmware" | rg -v rg
   ```

   发现 `secret-tool` 存在，且 `gnome-keyring-daemon --components=secrets` 正在运行。

6. 先用常见属性搜索 VMware 记录，但没有直接命中。

   ```bash
   secret-tool search --all application vmware
   secret-tool search --all service vmware
   secret-tool search --all vmx "/home/chesszyh/vmware/Windows11/Windows 11 x64.vmx"
   ```

   这些查询没有输出，说明 VMware 保存的条目没有使用这些直观属性。

7. 改用 D-Bus 枚举 Secret Service 条目，只查看 label 和 attributes，不读取 secret 明文。

   ```bash
   gdbus call --session \
     --dest org.freedesktop.secrets \
     --object-path /org/freedesktop/secrets \
     --method org.freedesktop.Secret.Service.SearchItems '{}'
   ```

   再逐项读取 `org.freedesktop.Secret.Item` 的 `Label` 和 `Attributes`，找到精确匹配条目：

   ```text
   Label: vm.encryption.password
   Attributes:
     encryptedVM.guid = 10395563108229220110
     xdg:schema = vmware.vm.encryption.password
   ```

8. 用精确属性读取 VMware 保存的 secret，并避免在过程日志中展开明文。

   ```bash
   VM_PASS=$(secret-tool lookup \
     xdg:schema vmware.vm.encryption.password \
     encryptedVM.guid 10395563108229220110)
   printf 'keyring_password_chars=%s\n' "${#VM_PASS}"
   ```

   输出显示该 secret 长度为 20 个字符。明文随后已单独告知用户，但不写入本报告。

9. 验证密钥环密码确实是 VMware 加密密码。

   ```bash
   vmrun -T ws -vp "$VM_PASS" checkToolsState "Windows 11 x64.vmx"
   vmrun -T ws -vp "$VM_PASS" getGuestIPAddress "Windows 11 x64.vmx" -wait
   ```

   关键验证结果：

   ```text
   running
   192.168.1.12
   ```

   这证明从 GNOME Keyring 读取出的 secret 能被 VMware Workstation 接受。

10. 继续检查 guest ops 账号问题。

    截图显示 Windows 内部 PowerShell 提示符为 `C:\Users\chess>`，但 VMware Guest Operations 使用 `-gu chess -gp <Windows 密码>` 仍返回：

    ```text
    Error: Invalid user name or password for the guest OS
    ```

    这属于 Windows 来宾认证问题，可能与 Windows Hello/PIN、Microsoft 账号或本地账号密码状态有关，不影响 VMware 加密密码找回结论。

## Root Cause

根因不是 VMX 文件损坏，也不是 `vmcli` 不支持该虚拟机，而是 VMware Workstation 的虚拟机配置被加密。`vmcli` / `vmrun` 在访问加密 VMX 时需要 VMware 加密密码；用户当时忘记了这个密码。

最终能恢复密码的原因是：用户曾在 VMware Workstation 中选择“记住密码”，VMware 将该加密密码保存到了当前 Linux 用户的 GNOME Keyring 中。当前桌面会话已经解锁 GNOME Keyring，因此可以通过 Secret Service 按 `xdg:schema=vmware.vm.encryption.password` 和 VM 的 `encryptedVM.guid` 精确读取该 secret。

这不是从 `.vmx` 反推出密码；`.vmx` 中没有可直接恢复的密码明文。`.vmx` 只提供了可用于匹配密钥环条目的 `encryptedVM.guid`。

## Changes Made

本次排障过程中没有修改 Windows 虚拟机文件，也没有修改 VMware 配置。

用户在排障后自行将 VMware 加密密码改成了一个更易记的新值。该新密码明文不写入本报告；建议后续仍保存到受保护的密码管理器中，并避免长期使用弱密码。

本报告新增文件：

```text
/home/chesszyh/Documents/Reports/docs/vmware-windows11-encryption-password-recovery-report-2026-05-17.md
```

并将报告链接加入：

```text
/home/chesszyh/Documents/Reports/docs/index.md
```

## Verification

VMware 加密密码恢复是否正确，可以用以下方式验证：

```bash
cd /home/chesszyh/vmware/Windows11
VM_PASS=$(secret-tool lookup \
  xdg:schema vmware.vm.encryption.password \
  encryptedVM.guid 10395563108229220110)
vmrun -T ws -vp "$VM_PASS" checkToolsState "Windows 11 x64.vmx"
```

预期输出包含：

```text
running
```

当虚拟机开机且网络正常时，还可验证来宾 IP：

```bash
vmrun -T ws -vp "$VM_PASS" getGuestIPAddress "Windows 11 x64.vmx" -wait
```

本次实际返回：

```text
192.168.1.12
```

该验证说明 `VM_PASS` 是 VMware Workstation 可接受的 VM 加密密码。

## Problems Encountered During Debugging

- `vmcli` 的帮助命令会提示 `Encrypted virtual machine password:`，但普通命令没有提供明显的 `--password` 参数；直接调用会失败。
- 用户提供的是 Windows 登录密码，不是 VMware 加密密码；将其传给 `vmrun -vp` 返回 `Incorrect password`。
- 常规 `secret-tool search --all application vmware`、`service vmware` 没有命中，因为 VMware 使用的是 `xdg:schema=vmware.vm.encryption.password` 和 `encryptedVM.guid` 作为关键属性。
- Windows guest ops 还需要来宾系统账号认证；即使 VMware 加密密码已恢复，`vmrun -gu chess -gp <Windows 密码>` 仍可能因 Windows Hello/PIN、Microsoft 账号或本地账号密码不一致而失败。
- 在进一步自动化安装软件前，用户中断并关闭虚拟机，因此 PowerShell、nvm、Node.js 22 和 Codex 的安装没有在本轮完成。

## Reuse Notes and Lessons

- VMware 加密 VM 的 `.vmx` 中可以找到 `encryptedVM.guid`，这是查询本机密钥环的关键索引。
- 如果曾在 VMware Workstation 勾选“记住密码”，Linux 桌面环境下优先检查 GNOME Keyring，而不是尝试猜测或从 VMX 反推密码。
- 恢复流程应先枚举 secret 条目的 label/attributes，确认匹配目标 VM 后再读取 secret 明文，降低误读其他凭据的风险。
- 读取出的 secret 应用变量传给 `vmrun -vp` 验证，避免在 shell 历史和日志中留下密码明文。
- 找回密码后建议立即记录到正式密码管理器；如果改成临时易记密码，应尽快换成强密码并保留恢复途径。
- VMware 加密密码和 Windows 登录密码是两层不同认证：前者解开 VM 配置，后者用于 Windows guest ops。

## Appendix: Reusable Commands

### 查询 VMX 加密标识

```bash
cd /home/chesszyh/vmware/Windows11
rg -n 'vmx.encryptionType|encryptedVM.guid|displayName|guestOS' "Windows 11 x64.vmx"
```

### 检查 VMware CLI 版本和 VM 状态

```bash
vmcli --version
vmrun -T ws list
```

### 确认 GNOME Keyring / Secret Service 是否运行

```bash
command -v secret-tool
ps -ef | rg -i "gnome-keyring|secret-service|vmware" | rg -v rg
```

### 枚举 Secret Service 条目路径

```bash
gdbus call --session \
  --dest org.freedesktop.secrets \
  --object-path /org/freedesktop/secrets \
  --method org.freedesktop.Secret.Service.SearchItems '{}'
```

### 按 VM GUID 精确读取 VMware 加密密码

注意：下面命令会读取密码明文。只在本机可信终端执行，不要把输出粘贴到公开报告、日志或聊天记录中。

```bash
secret-tool lookup \
  xdg:schema vmware.vm.encryption.password \
  encryptedVM.guid 10395563108229220110
```

### 不暴露明文地验证密码可用性

```bash
cd /home/chesszyh/vmware/Windows11
VM_PASS=$(secret-tool lookup \
  xdg:schema vmware.vm.encryption.password \
  encryptedVM.guid 10395563108229220110)
vmrun -T ws -vp "$VM_PASS" checkToolsState "Windows 11 x64.vmx"
```

### 获取来宾 IP

```bash
vmrun -T ws -vp "$VM_PASS" getGuestIPAddress "Windows 11 x64.vmx" -wait
```

### 示例：使用已恢复的 VM 加密密码执行 MKS 查询

```bash
printf '%s\n' "$VM_PASS" | vmcli "Windows 11 x64.vmx" MKS query
```
