# 同济大学 (tongji.edu.cn) 在 SWOT 项目中的状态分析报告

## 1. 核心发现 (Findings)

经过对 `swot` 项目源代码、提交历史及 GitHub PR 的深度分析，得出以下结论：

### 1.1 封禁现状与矛盾
*   **物理存在**：`lib/domains/cn/edu/tongji.txt` 文件在项目中一直存在，包含校名 "Tongji University"。
*   **逻辑失效**：同济大学主域名 `tongji.edu.cn` 被列入了 `lib/domains/stoplist.txt`（黑名单）。
*   **生效机制**：根据 `src/main/kotlin/swot/Swot.kt` 中的 `isAcademic` 函数逻辑，任何出现在 `stoplist.txt` 中的域名都会被直接判定为 **无效学术域名**。

### 1.2 封禁原因：校友邮箱政策
*   JetBrains 封禁域名的主要标准是：该域名是否提供**终身校友邮箱**。
*   **同济被封原因**：2020 年左右，因发现校友仍能使用 `tongji.edu.cn` 后缀邮箱，维护者 Philip Torchinsky 将其列入黑名单。
*   **与交大 (SJTU) 的对比**：交大很早就区分了 `alumni.sjtu.edu.cn` (校友域) 和 `sjtu.edu.cn` (在校生域)。JetBrains 仅封禁了交大的校友域，因此交大主域依然有效。
*   **政策变动**：同济大学现已执行“毕业即收回主域邮箱，校友申请 `alumni.` 域”的政策，理论上已符合解封标准。

### 1.3 历史遗留问题 (PR #21206)
*   2024 年 6 月，曾有用户提交 **PR #21206** 试图解封同济并精准封禁校友域。
*   该 PR 因文件命名不规范（`malformatted`）且恰逢维护者假期，最终被无视并关闭，导致同济一直躺在黑名单中。

---

## 2. 本地修复操作 (Modifications)

为了恢复同济大学邮箱的有效性，我已在你的本地仓库中完成了以下修改：

### 2.1 修改域名文件
**文件：** `lib/domains/cn/edu/tongji.txt`
**变更：** 按照项目规范添加了中文校名，确保识别。
```text
+ 同济大学
  Tongji University
```

### 2.2 调整黑名单 (精确封禁)
**文件：** `lib/domains/stoplist.txt`
**变更：** 
1.  **解封主域**：移除了 `tongji.edu.cn`。
2.  **封禁校友域**：添加了 `alumni.tongji.edu.cn`（按字母顺序排列在 `alumni.stu.edu.cn` 之后）。
*这将允许正常的 `student@tongji.edu.cn` 通过验证，同时拦截校友邮箱。*

### 2.3 添加逻辑测试
**文件：** `src/test/kotlin/swot/SwotTest.kt`
**变更：** 增加了针对同济大学的自动化测试用例。
```kotlin
// Tongji University
assertEquals(true, isAcademic("student@tongji.edu.cn"))
assertEquals(false, isAcademic("alumni@alumni.tongji.edu.cn"))
```

---

## 3. 结论与建议

*   **本地状态**：同济大学现在你的本地仓库中已处于**有效**状态。
*   **官方状态**：若要彻底解决此问题，需向 JetBrains 官方仓库提交一个格式正确的 PR（参考我的修改内容）。
*   **技术备注**：目前浙大 (ZJU)、华科 (HUST)、北航 (BUAA) 等多所 985 高校均面临与同济类似的“误伤”封禁，其根源多为历史上的校友邮箱管理政策。

---
*报告生成日期：2026年3月14日*
