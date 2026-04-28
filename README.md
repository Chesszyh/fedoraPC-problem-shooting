# Reports

目前的cli-agents已经很强大（比如codex），足以接管个人电脑的日常维护和问题排查。虽然给full access有风险，但我暂时也选择相信底层基础模型的能力，而且linux环境下，应该比Windows的PowerShell甚至cmd更安全一些，Agents不容易写错命令从而导致文件丢失等问题。

我希望将每次项目部署/电脑配置遇到的问题和解决过程记录下来，形成一个可复用的报告库。因此，我使用`Skill Creator`(似乎是codex自带的skill？)创建了以下`create-problem-reports`技能，见[SKILL.md](SKILL.md)，并产生了这个仓库。

> 其实吧，没什么新鲜的，skill看来也只是可复用的、一定程度上标准化的prompt而已。