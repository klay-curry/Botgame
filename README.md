# LingBotgame — 蚂蚁灵波具身大模型挑战赛

基于 **LingBot-VLA 2.0 (6B)** 在 **RoboTwin 2.0**（Aloha-AgileX，50 任务）上做 post-training 调优。
技术方案、赛程、规则红线见 `docs/plan.md`；赛题规则原文 `docs/work.md`；赛事群答复整理见 `docs/Dingnews.md`。
两人协作先看 [整体方向与节奏](docs/plan.md)、[模块分工](docs/modules/README.md) 和 [Git 协作规则](CONTRIBUTING.md)。

## 仓库布局

```
├── docs/                  # 方案、赛题规则、学习笔记（入库）
├── scripts/               # 环境复现脚本 + 我们的原创工具（入库）
├── ours/                  # 官方代码可修改副本（入库，开发都在这里进行；对照 lingbot-vla-v2/）
├── configs/               # 我们自己的实验配置（入库）
├── docs/modules/          # 模块化技术方案与分工（规则见 docs/modules/README.md）
├── lingbot-vla-v2/        # 官方原始参照（不入库，保持 clone 原状，改坏了用来对照）
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
# HF 拉数据慢/失败时，改用团队 ModelScope 镜像（内容相同）:
bash scripts/download_data_ms.sh
```

梁家诚可在 Windows 上用 Git Bash 执行。网络不通先开代理或看脚本头部的镜像说明。

## 协作约定

- `main` 保持可复现；实验开分支并通过 PR 由另一位队员复核，提交格式见 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 模块化推进：技术方案按模块存放于 `docs/modules/<模块>/`（方案、参考文献、状态），分工与规则见 [docs/modules/README.md](docs/modules/README.md)。
- 每组有意义的实验在 `docs/experiments/` 下留记录（配置、成绩、结论）。
- 评测口径和赛题红线以天池赛题、官方模板及最新赛事答复为准；关键参数写入实验记录和最终 README。
