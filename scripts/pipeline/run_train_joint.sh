#!/bin/bash
# 重训(修复数据:关节空间+含零位形起步段, 2026-10-08):
#   数据: /root/autodl-tmp/robotwin_joint_v21/RoboTwin_lerobot_v21 (2500 eps, 548k帧, fps15, 14维joint)
#   配置: 沿用七组基准最优 micro 32 × 3卡 × 累积1 = global 96 (5.5s/步, 73.6GB/卡)
#   步数: max_steps 9000(约3epoch), save_steps 2000 → 预计 ~13.5h
#   norm: assets/norm_stats/robotwin_joint.json (对新数据重算)
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
  --train.max_steps=9000 \
  --train.save_steps=2000 \
  --train.enable_gradient_checkpointing=true \
  --train.enable_fp32=false \
  --train.freeze_vision_encoder=false \
  --data.train_path=assets/training_data/robotwin_joint.txt --train.enable_resume=false \
  --data.prefetch_factor=8
