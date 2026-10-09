#!/bin/bash
# 闭环评测一键启动(队列调度,推理服务 + RoboTwin 仿真)
# 用法:
#   MODEL_PATH=<要评的ckpt路径> bash run_eval_smoke.sh        # 单任务冒烟
#   MODEL_PATH=<ckpt> NUM_TASKS=50 bash run_eval_smoke.sh     # 全量 50 任务
set -e
source /root/miniconda3/etc/profile.d/conda.sh

export QWEN3VL_PATH=/root/autodl-tmp/models/Qwen3-VL-4B-Instruct
export EVAL_WORKDIR=/root/autodl-tmp/uploads/sim/RoboTwin
export OUTPUT_BASE=/root/autodl-tmp/output/eval
export CONDA_SH=/root/miniconda3/etc/profile.d/conda.sh
export MODEL_PATH="${MODEL_PATH:-/root/autodl-tmp/lingbot-vla-v2-6b}"   # 默认评 base 权重
NUM_TASKS="${NUM_TASKS:-1}"

mkdir -p "$OUTPUT_BASE"
cd /root/autodl-tmp/uploads/train/ours-20260930
bash experiment/robotwin/start_robotwin_infer_and_eval.sh \
  --eval_workdir "$EVAL_WORKDIR" \
  --num_tasks "$NUM_TASKS" \
  --num_gpus 1 \
  --num_per_gpu 1
