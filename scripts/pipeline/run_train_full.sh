#!/bin/bash
# 正式训练(最终配置,2026-10-02 七组基准实测选定):
#   3×A800-80GB,micro 32 × 3卡 × 累积1 = global 96
#   解冻视觉塔(官方语义)+ BF16 混合精度 + Muon + 梯度检查点 + workers24 + prefetch8
#   实测 5.5s/步 → 5749 步约 8.8 小时;显存 73.6GB/卡(安全余量 ~5GB)
#   每 2000 步存 ckpt(2000/4000/5749 三个候选);strip_optimizer.sh 守护磁盘
set -e
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
source /root/miniconda3/etc/profile.d/conda.sh
conda activate lingbotvla
export PATH=/usr/local/cuda/bin:$PATH

cd /root/autodl-tmp/uploads/train/ours-20260930

bash train.sh tasks/vla/train_lingbotvla.py configs/vla/robotwin/robotwin.yaml \
  --train.micro_batch_size=32 \
  --train.global_batch_size=96 \
  --train.gradient_accumulation_steps=1 \
  --train.enable_gradient_checkpointing=true \
  --train.enable_fp32=false \
  --train.freeze_vision_encoder=false \
  --train.save_steps=2000 \
  --data.prefetch_factor=8
