# 两人 Git 协作规则

本仓库由刘勇泽和梁家诚共同开发。`main` 只保留可复现的代码、配置和文档；实验过程使用独立分支。具体分工与赛程见 [双人开发计划](docs/双人开发计划.md)。

## 1. 分支与合并

1. 开工前确认工作区干净，更新 `main`，再从 `main` 建分支。分支命名：`feat/data-audit`、`feat/eval-runner`、`fix/model-loading`、`docs/team-workflow`、`exp/lr-20261005`。
2. 一条分支只解决一个明确问题。实验分支可以保留验证过的配置和分析；大数据、权重和原始日志不能提交到 Git。
3. 不直接推送或提交到 `main`。通过 Pull Request 合并，由**另一位队员**检查后合并。改动自己负责的文件，也需要对方复核。
4. 两人需要改同一个文件时，先在 Issue/PR 里约定谁先改、谁后改；先合并一人的 PR，另一人再更新分支。不要互相覆盖或重置工作区。
5. 不对共享分支强推，不用 `git add .`，不把账号密钥、下载令牌、云平台地址中的凭据或个人隐私信息提交到仓库。

建议操作：

```bash
git status --short
git switch main
git pull --ff-only
git switch -c feat/data-audit

# 完成一个可验证的小改动后，只暂存本次修改的文件
git add src/data/audit.py configs/data_clean.yaml
git diff --cached --stat
git diff --cached --check
git commit -m "feat(data): validate 50 clean tasks"
git push -u origin feat/data-audit
```

若尚无示例中的文件，应改用本次实际修改的路径。Windows 上编辑 shell 脚本保留 LF 换行；`.gitattributes` 已要求 `*.sh` 使用 LF。正式训练和评测命令在 Linux 云环境运行，Mac/Windows 本机用于开发、审查和远程连接。

## 2. 提交信息

格式：`类型(范围): 本次完成的事`。类型使用 `feat`、`fix`、`docs`、`test`、`chore`；范围优先用 `data`、`train`、`eval`、`infra`、`submit`、`team`。

```text
feat(data): add clean-only dataset manifest check
fix(eval): count only completed policy episodes
docs(team): define two-person ownership and review flow
chore(infra): pin RoboTwin commit
```

一条提交只表达一个意图。纯格式整理和功能修改分开提交；实验配置与对应说明一起提交。不要用“update”“修改”“修好了”这类看不出内容的标题。

## 3. Pull Request 的最小验收

PR 描述写清楚：**目的、修改范围、验证命令与结果、相关实验记录、风险和回退方法**。直接使用仓库的 PR 模板。

合并前双方核对：

- 代码、配置和 README 的运行命令一致；上游 LingBot、RoboTwin 和数据/model revision 已记录。
- 训练改动只读取指定的 50×50 clean 数据；`randomized` 不进入训练清单或归一化统计。
- 评测改动保留原始日志、实际 attempts/successes、checkpoint 哈希及精度/seed/环境设置；不手填成绩。
- 改动至少通过对应的最小验证。文档改动检查链接和 `git diff --cached --check`；代码改动给出实际运行日志或说明尚不能运行的原因。
- 仅暂存本次文件；`git status --short` 没有意外的大文件、权重、数据或密钥。

Reviewer 给出“通过”或具体修改意见；作者处理意见后再合并。若是紧急修复，也先在 PR 中写明原因与验证，再由另一人确认。合并后作者删除已完成分支，双方更新 `main`。

## 4. 实验与文档记录

每次有意义的训练或闭环评测，按 [实验记录模板](docs/experiments/TEMPLATE.md) 在 `docs/experiments/YYYY-MM-DD-主题.md` 留一条简短记录：目标、代码 commit、数据/模型 revision、配置、GPU/耗时、checkpoint 哈希、clean/randomized 的 attempts 与 successes、结论和下一步。原始日志与 checkpoint 放在云端持久目录，文档只记录定位方式和哈希。

规则冲突时以天池赛题及官方模板为准，官方仓库文档用于实现细节；`docs/Dingnews.md` 是赛事群答复的转述，涉及合规边界时核对最新原始答复。修改已有结论时保留原实验记录，新建记录说明为何推翻它。

每晚用三句话同步：**今天完成什么（附 PR/日志）→ 当前阻塞是什么 → 明天谁接手什么**。影响次日训练或评测排期的阻塞，发现后立即同步。
