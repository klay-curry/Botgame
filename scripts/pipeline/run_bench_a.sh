#!/bin/bash
# 正式训练:3×A800-80GB,冻结视觉塔 + BF16 + Muon(机器实测可跑的配置)
# global_batch 96 = micro 2 × 3卡 × 累积16;总步数由数据量自然决定(~17247)
# 每 5000 步存一次 ckpt;strip_optimizer.sh 负责磁盘守护
set -e
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
source /root/miniconda3/etc/profile.d/conda.sh
conda activate lingbotvla
export PATH=/usr/local/cuda/bin:$PATH

cd /root/autodl-tmp/uploads/train/ours-20260930

bash train.sh tasks/vla/train_lingbotvla.py configs/vla/robotwin/robotwin.yaml \
  --train.micro_batch_size=4 \
  --train.global_batch_size=96 \
  --train.gradient_accumulation_steps=8 \
  --train.enable_gradient_checkpointing=true \
  --train.enable_fp32=false \
  --train.freeze_vision_encoder=true \
  --train.save_steps=100000
