#!/bin/bash
# A800-80GB 单卡 smoke 训练:50 步,验证训练循环能跑通、能存 ckpt
# 正式训练去掉最后的 --train.* 覆盖参数即可
set -e
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
source /root/miniconda3/etc/profile.d/conda.sh
conda activate lingbotvla
export PATH=/usr/local/cuda/bin:$PATH

cd /root/autodl-tmp/uploads/train/ours-20260930

# 单卡 80GB 保守参数:micro_batch 8 + 梯度检查点;50 步只验证链路
bash train.sh tasks/vla/train_lingbotvla.py configs/vla/robotwin/robotwin.yaml \
  --train.max_steps=50 \
  --train.save_steps=50 \
  --train.micro_batch_size=1 \
  --train.global_batch_size=32 \
  --train.gradient_accumulation_steps=32 \
  --train.enable_gradient_checkpointing=true \
  --train.enable_fp32=false \
  --train.freeze_vision_encoder=true
