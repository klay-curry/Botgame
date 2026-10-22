# Git 提交与仓库维护规则

本仓库为个人项目，由一名维护者完成全部训练、评测与文档工作。`main` 只保留可复现的
代码、配置和文档；大改动建议开分支，验证后再合并。整体方向见 [plan.md](docs/plan.md)，
实验结论见 [docs/experiments/](docs/experiments/)。

## 1. 分支与提交

1. 大改动（训练配方、评测 launcher、依赖升级）从 `main` 开分支；小的文档/图表修正可直接提交 `main`。
2. 一条分支只解决一个明确问题。大数据、模型权重、checkpoint、原始日志不进入 Git。
3. 不提交账号密钥、下载令牌、云平台凭据或个人隐私信息。
4. 提交前自查：

```bash
git status --short
git diff --cached --stat
git diff --cached --check
```

只暂存本次相关的文件，避免误带数据、权重或无关产物。

## 2. 提交信息

格式：`类型(范围): 本次完成的事`。类型使用 `feat`、`fix`、`docs`、`test`、`chore`；
范围优先用 `data`、`train`、`eval`、`infra`、`submit`、`docs`。

```text
feat(eval): add queue-scheduled launcher
fix(eval): restore 100 episodes per task
docs(final): record final clean/randomized results
chore(infra): pin RoboTwin commit
```

一条提交只表达一个意图。纯格式整理和功能修改分开提交；实验配置与对应说明一起提交。

## 3. 提交前的最小验收

- 代码、配置和 README 里的运行命令一致；LingBot / RoboTwin / 数据 revision 已记录。
- 训练只读取 50 任务 × 50 条 clean 数据；`randomized` 不进入训练清单或归一化统计。
- 评测保留原始日志、实际 attempts/successes、checkpoint 哈希及精度/seed/环境设置；
  成绩由日志脚本生成，不手填。
- 脚本改动至少通过 `bash -n`（或 `python -m py_compile`）；评测改动给出实际运行日志。
- 文档改动检查链接和 `git diff --cached --check`。

## 4. 实验与文档记录

每次有意义的训练或闭环评测，按 [实验记录模板](docs/experiments/TEMPLATE.md) 在
`docs/experiments/YYYY-MM-DD-主题.md` 留一条简短记录：目标、代码 commit、数据/模型
revision、配置、GPU/耗时、checkpoint 哈希、clean/randomized 的 attempts 与 successes、
结论和下一步。原始日志与 checkpoint 放在云端持久目录，文档只记录定位方式和哈希。

规则冲突时以天池赛题及官方模板为准；`docs/Dingnews.md` 是赛事群答复的转述，涉及合规
边界时核对最新原始答复。修改已有结论时保留原实验记录，新建记录说明为何推翻它。
