# LingBotgame — 蚂蚁灵波具身大模型挑战赛

基于 **LingBot-VLA 2.0 (6B)** 在 **RoboTwin 2.0**（Aloha-AgileX，50 任务）上做 post-training 调优。
技术方案、赛程、规则红线见 `docs/plan.md`；赛题规则原文 `docs/work.md`；官方 Q&A `docs/Dingnews.md`。

## 仓库布局

```
├── docs/                  # 方案、赛题规则、学习笔记（入库）
├── scripts/               # 环境复现脚本（入库）
├── src/                   # 我们自己的训练/评测/分析代码（入库）
├── configs/               # 我们自己的实验配置（入库）
├── lingbot-vla-v2/        # 官方仓库（不入库，setup_repos.sh 克隆）
├── RoboTwin/              # 官方仿真仓库（不入库，钉死 commit）
├── data/                  # RoboTwin 数据（不入库，download_data.sh 拉取，~40GB）
└── model/                 # 模型权重（不入库，download_model.sh 拉取，~25GB）
```

> 大文件（数据 / 权重 / checkpoint）一律不进 git，靠 `scripts/` 三个脚本一键复现。实验产物放 `output/`（已 ignore），要分享的结果用表格/截图放进 `docs/experiments/`。

## 新环境快速开始

```bash
# 0) 依赖: git, unzip, python 3.10+, pip install -U "huggingface_hub[cli]" modelscope
bash scripts/setup_repos.sh       # 1) 克隆官方仓库（RoboTwin 钉死指定 commit）
bash scripts/download_model.sh    # 2) 下载 6B 权重（默认 ModelScope，国内快）
bash scripts/download_data.sh     # 3) 下载 50 任务 clean 数据并解压（默认 hf-mirror）
```

Windows 队友用 Git Bash 执行即可。网络不通先开代理或看脚本头部的镜像说明。

## 协作约定

- `main` 保持可复现；实验开分支：`exp/<主题>-<日期>`（如 `exp/lr-scan-0930`）
- 每组实验在 `docs/experiments/` 下留一条记录（配置、成绩、结论），commit message 写清对应实验
- 评测口径：正式成绩用 **FP32** 推理（官方复测口径）；BF16 只用于流程验证
- 赛题红线（违规出局，详见 docs/plan.md）：不用 randomized/外部数据训练、不做 RL/rollout 造数据、不做任务路由/ensemble/多 seed 投票、最终只交一份合并后的全量权重
