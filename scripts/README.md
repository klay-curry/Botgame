# scripts — 复现所需脚本（唯一入口）

这里只保留“从零复现 → 训练 → 评测 → 出图”需要的脚本；开发期的实验流水线
（bench、冷存/瘦身守护、分片 watcher 等）已从当前树移除，仍可在 git 历史中查到
（`git log -- scripts/pipeline`）。

| 脚本 | 作用 |
|---|---|
| `download_model.sh` | 拉第三方权重：官方基座 `lingbot-vla-v2-6b` + Qwen3-VL tokenizer（ModelScope / HF） |
| `download_assets.sh` | 拉全部外部资源：基座、tokenizer、训练数据、团队 6600 步权重（可多选） |
| `setup_sim_repo.sh` | 克隆官方 RoboTwin @ `13c3c47` 到 `RoboTwin/` |
| `train.sh` | 从团队 6600 步权重热启动续训 3400 步（等效 10000 步） |
| `convert_dcp_to_hf.py` | 把训练产出的 DCP 存档转成评测可加载的 HF 权重目录 |
| `eval.sh` | 按官方协议评测 clean / randomized（自动 staging checkpoint） |
| `gen_results_json.py` | 从原始 `eval_logs/` 生成官方模板 `results.json` + 审计 CSV |
| `make_results_gif.py` | 从 `results.json` 生成 dashboard / heatmap / summary / GIF |

## 最短复现路径

```bash
# 1) 权重 + tokenizer + 训练数据 + 团队 6600 步权重
bash scripts/download_assets.sh all

# 2) 官方仿真仓（首次需再跑官方 _install.sh / _download_assets.sh）
bash scripts/setup_sim_repo.sh

# 3) 训练（可选：只在想从 6600 步重训时需要）
bash scripts/train.sh --gpus 4
python scripts/convert_dcp_to_hf.py \
  ours/configs/vla/robotwin/robotwin.yaml \
  output/ckpt/checkpoints/global_step_1000 \
  output/ckpt/hf_ckpt_step1000

# 4) 评测（最终权重解压到 assets/models/hf_ckpt_final_equiv10000）
bash scripts/eval.sh --setting demo_clean --tasks 50 --gpus 6 --per-gpu 2
bash scripts/eval.sh --setting demo_randomized --tasks 50 --gpus 6 --per-gpu 2

# 5) 生成 results.json 与可视化
python scripts/gen_results_json.py --base output/eval
python scripts/make_results_gif.py output/eval/results.json output/eval
```

## 录制回放视频

```bash
bash scripts/eval.sh --model assets/models/hf_ckpt_final_equiv10000 \
  --setting demo_clean --tasks 1 --gpus 1 --per-gpu 1 --video
# 视频在 <output>/_0k_demo_clean_<时间戳>/eval_results/<task>/episodeN_success.mp4
```

仓库内示例素材：`docs/submission/2026-10-21/01_评测结果/videos/`（adjust_bottle 成功回放；
handover_mic clean 成功 vs randomized 失败对照）。

## 资源与路径约定

| 资源 | 默认位置 |
|---|---|
| 官方基座 | `assets/models/lingbot-vla-v2-6b` |
| tokenizer | `assets/models/Qwen3-VL-4B-Instruct` |
| 训练数据 | `assets/data/robotwin_official_joint_v30` |
| 团队中间权重 | `assets/models/radeon_ckpt/hf_ckpt_step6600` |
| 最终提交权重 | `assets/models/hf_ckpt_final_equiv10000`（12G，随提交包提供，不进 git） |
| 评测输出 | `output/eval/` |
| 训练输出 | `output/ckpt/` |

`download_assets.sh team` 默认只拉 `hf_ckpt_step6600/*`（约 13G）；要拉全部 12 个
checkpoint 用 `TEAM_INCLUDE='*' bash scripts/download_assets.sh team`。
