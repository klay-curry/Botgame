# 2026-10-21 竞赛提交包快照

> 这是初赛提交材料的仓库内快照。提交包原本的 4 个子目录为
> 01_评测结果 / 02_代码材料 / 03_模型权重 / 04_复现与调优说明；
> 为了控制仓库体积，最终权重（12G）没有放进 git（03 不在此处），
> 复现说明直接放在本目录的 `reproduction_report.md`（对应原 04），
> RoboTwin 官方资产也没有放进 git。在 GitHub 仓库里运行时请用根目录的 `scripts/`。

## GitHub 仓库 ↔ 提交包路径对照

| 提交包内路径 | GitHub 仓库中的位置 |
|---|---|
| `02_代码材料/src/train_repo/` | `ours/` |
| `02_代码材料/src/experiment/robotwin/` | `ours/experiment/robotwin/` |
| `02_代码材料/configs/` | `ours/configs/` |
| `03_模型权重/checkpoint/` | `assets/models/hf_ckpt_final_equiv10000`（从提交包解压，不入库） |
| `03_模型权重/download_assets.sh` | `scripts/download_assets.sh` |
| `02_代码材料/train.sh` / `eval.sh` | `scripts/train.sh` / `scripts/eval.sh` |
| `02_代码材料/setup_sim_repo.sh` | `scripts/setup_sim_repo.sh` |
| `02_代码材料/src/gen_results_json.py` | `scripts/gen_results_json.py` |
| 结果图 / 动图 | `01_评测结果/`（本目录）与根目录 `scripts/make_results_gif.py` |

## 目录内容

| 目录 | 内容 |
|---|---|
| `01_评测结果/` | `results.json`、逐任务审计 CSV、汇总 txt、dashboard / heatmap / summary / GIF、`videos/` 回放（含 clean 成功与 randomized 失败对照） |
| `02_代码材料/` | 提交包代码说明、一键 train/eval、仿真仓准备脚本 |
| `scripts/` | 提交包内使用的资源拉取 / 结果生成 / 作图脚本 |
| `reproduction_report.md` | 复现与调优说明（原 `04_复现与调优说明/` 的内容） |

完整成绩与结论见仓库根目录 [README](../../../README.md) 与
[最终提交评测记录](../../experiments/2026-10-21-最终提交评测.md)。
