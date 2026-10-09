#!/bin/bash
# clean 评测结束后自动启动 randomized 同20任务
LOG=/tmp/chain_randomized.log
RUN=/root/autodl-tmp/output/eval/ckpt_6k_demo_clean_20261008_210621
log(){ echo "$(date '+%F %T') $*" >> $LOG; }
log "chain waiter started; waiting for clean run to finish"
# 等 launcher 退出(每5分钟查,最多30h)
for i in $(seq 1 360); do
  pgrep -f "start_robotwin_infer_and_ev[a]l" > /dev/null || break
  sleep 300
done
sleep 60
log "clean run launcher exited; stats: $(cat $RUN/stats.txt 2>/dev/null | tail -3 | tr '\n' ' ')"
cd /root/autodl-tmp/uploads/train/ours-20260930
QWEN3VL_PATH=/root/autodl-tmp/models/Qwen3-VL-4B-Instruct \
EVAL_WORKDIR=/root/autodl-tmp/uploads/sim/RoboTwin \
OUTPUT_BASE=/root/autodl-tmp/output/eval \
CONDA_SH=/root/miniconda3/etc/profile.d/conda.sh \
MODEL_PATH=/root/autodl-tmp/output/ckpt/checkpoints/global_step_6000/hf_ckpt \
TASK_CONFIG=demo_randomized \
setsid nohup bash experiment/robotwin/start_robotwin_infer_and_eval.sh \
  --eval_workdir /root/autodl-tmp/uploads/sim/RoboTwin \
  --num_tasks 20 --num_gpus 3 --num_per_gpu 2 \
  > /tmp/closed_loop_joint_randomized.log 2>&1 &
log "randomized run launched (pid $!)"
