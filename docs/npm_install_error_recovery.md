# NPM 全局安装 ENOTEMPTY 错误恢复报告

## 1. 错误背景
- **触发命令**：`npm install -g <多个包名>`
- **错误代码**：`ENOTEMPTY`
- **错误场景**：由于用户在安装过程中强行中止（Ctrl+C），导致安装状态不一致。

## 2. 问题分析
npm 在执行安装时会先在临时位置解压，随后尝试将旧版本目录重命名/替换为新版本。若上一次操作被中断，目标路径下可能残留文件，导致 `rename` 系统调用失败并抛出 `ENOTEMPTY: directory not empty`。

## 3. 解决方案（标准化步骤）

### 第一步：验证 npm 缓存
清理并验证本地缓存，确保后续下载不受旧缓存干扰。
```bash
npm cache verify
```

### 第二步：识别并清理受损目录
根据报错信息提供的路径，手动删除受损的包目录。
```bash
# 示例：清理特定的全局包目录
rm -rf ~/.npm-global/lib/node_modules/@anthropic-ai/claude-code
# 或者根据需要清理多个
rm -rf ~/.npm-global/lib/node_modules/<package-name>
```

### 第三步：分步重新安装
避免一次性安装过多包，分步执行以确保稳定性并易于排查。
```bash
npm install -g <package-name-1>
npm install -g <package-name-2>
```

### 第四步：最终验证
确认包已正确安装到全局列表。
```bash
npm list -g --depth=0
```

## 4. 预防建议
- 尽量避免在 npm 写入磁盘阶段强行中止任务。
- 若必须中止，建议在下次运行前先手动检查对应包的目录状态。
