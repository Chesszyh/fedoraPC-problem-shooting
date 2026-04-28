---
name: creating-problem-reports
description: Use when a debugging session, incident fix, environment issue, or troubleshooting task needs a reusable detailed report in ~/Documents/Reports for later review, handoff, or learning.
---

# Creating Problem Reports

## Overview

Turn one troubleshooting session into a reusable report.

Core principle: record the evidence chain, not just the final fix.

Default language: write the report in Chinese unless the user explicitly asks for another language.

## When to Use

- A bug or environment problem was investigated and fixed
- The user asks for a report, summary, postmortem, incident note, or troubleshooting record
- Future reuse matters more than a short chat recap
- The issue involved false leads, multiple layers, or configuration drift

Do not use for simple one-line answers or routine status updates.

## Quick Reference

Write the report to:

```text
~/Documents/Reports/<topic>-report-YYYY-MM-DD.md
```

If `~/Documents/Reports/mkdocs.yml` exists, treat `~/Documents/Reports` as the MkDocs report repository. Read its `docs_dir` setting and write the report under that docs directory instead of the repository root. For the current repository, this means:

```text
~/Documents/Reports/docs/<topic>-report-YYYY-MM-DD.md
```

Add a fixed header at the top of every report:

```text
生成时间: <output of `date --iso-8601=seconds`>
```

Include these sections in order:

1. Problem Description
2. Environment and Scope
3. Symptoms and Reproduction
4. Investigation Timeline
5. Root Cause
6. Changes Made
7. Verification
8. Problems Encountered During Debugging
9. Reuse Notes and Lessons
10. Appendix: Reusable Commands

## Report Pattern

Each report should capture:

- What was broken
- What evidence was gathered
- Which hypotheses were wrong
- Why the final explanation is correct
- Which files or configs changed
- How to verify the fix later

Prefer concrete commands, paths, process names, and exact error messages.

Before writing the final report, redact sensitive information as needed, including credentials, tokens, private keys, cookies, authorization headers, and live service endpoints that should not be published.

## MkDocs Integration

When writing into the `~/Documents/Reports` MkDocs repository:

1. Read `mkdocs.yml` and follow the current `docs_dir`, `site_dir`, theme, and Markdown extension structure instead of assuming defaults.
2. Add the new report to the Home page at `docs/index.md` using a relative Markdown link from that file.
3. Put the link under the most appropriate existing category. If none fits, add a new category/index section that matches the current Home page structure, including any matching anchor and navigation/card links already used there.
4. Preserve existing Home page layout, wording style, anchors, and link conventions. Do not rewrite unrelated report links or redesign the page during report creation.
5. Run a local MkDocs build from `~/Documents/Reports` before reporting completion:

```bash
mkdocs build --strict
```

If project dependencies are not available in the active environment, use the repository requirements or an equivalent `uvx` invocation that installs the pinned MkDocs dependencies. Fix build errors caused by the new report or Home index update before handing off.

Do not commit or push the report or index change unless the user explicitly asks.

## Implementation

Use a Markdown report with:

- A precise title
- A fixed generation-time header from `date --iso-8601=seconds`
- Absolute file references when local files changed
- Short command blocks for important checks
- A chronological investigation log
- A separate root-cause section that distinguishes symptoms from causes
- An appendix that groups directly reusable commands by purpose

If there were temporary fixes or wrong turns, document them explicitly instead of hiding them.

Unless the user explicitly requests another language, the title, section text, explanations, and summary should all be written in Chinese. Commands, paths, and error messages should remain in their original form.

## Common Mistakes

- Reporting only the final fix and omitting the evidence trail
- Mixing symptoms, hypotheses, and root cause into one paragraph
- Hiding failed assumptions that future debugging would repeat
- Omitting exact files, commands, or validation steps
- Leaving credentials, tokens, private keys, or other sensitive values unredacted
- Writing a report into the MkDocs repository without adding it to `docs/index.md`
- Skipping the local MkDocs build after changing the report or Home index
- Writing a narrative recap without reusable troubleshooting detail
