# 训练/评测流水线脚本（A800×3 实机档案）

这些脚本 2026-09-30 ~ 10-08 在 AutoDL 3×A800-80GB 实机上使用，**路径硬编码 `/root/autodl-tmp/...`**，
换机器需要改路径；保留在此主要作为流水线逻辑的参考实现。

| 脚本 | 作用 | 备注 |
|---|---|---|
| `run_train_joint.sh` | **当前主力**：关节空间14维 joint-v21 数据重训（micro32×3卡=global96, Muon, bf16, 梯度检查点） | 依赖 `configs/vla/robotwin/robotwin.yaml` |
| `run_train_full.sh` | 旧 eef16 数据全量训练（已被 joint 版取代） | |
| `run_train_smoke.sh` | 训练冒烟（几百步验证链路） | |
| `run_eval_smoke.sh` | 闭环评测 20 任务 smoke（MODEL_PATH/NUM_TASKS 环境变量控制） | 依赖 RoboTwin 侧 launcher |
| `run_bench_a..g.sh` | 七组显存/步时基准（micro×检查点扫描），结论见 RESUME.md | |
| `ckpt_cold_manager.sh` | 磁盘守护：非最新 ckpt 搬 autodl-fs 冷存 | AutoDL 专属；**换平台不可用**（无 autodl-fs） |
| `strip_optimizer.sh` | ckpt 瘦身：只留 model/ 清 optimizer/ | |
| `overnight_pipeline.sh` | 夜间流水线：等训练退出 → 开环筛 2000/4000/6000 → 最优自动进闭环 | `/tmp` 易失，已归档 |
| `stop_at_6000.sh` | watcher：step6000 hf_ckpt 落盘后自动停训 | 同上 |
| `chain_randomized.sh` | clean 闭环跑完自动接力 randomized 轮 | 同上 |

## 开环筛选命令（供新机复现）

```bash
python scripts/open_loop_eval.py \
  --model_path output/ckpt/checkpoints/global_step_6000/hf_ckpt \
  --robo_name robotwin \
  --norm_path assets/norm_stats/robotwin_joint.json \
  --data_path <lerobot_v30数据目录> \
  --traj_ids <均匀抽的episode id>
```
