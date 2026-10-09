#!/bin/bash
# 夜间流水线(2026-10-08):等训练→开环筛选→最优ckpt进闭环
LOG=/tmp/overnight_pipeline.log
TRAIN_LOG=/tmp/train_joint.log
CKPT_ROOT=/root/autodl-tmp/output/ckpt/checkpoints
DATA=/root/autodl-tmp/robotwin_joint_v21/RoboTwin_lerobot_v21
OUT=/root/autodl-tmp/output/eval/open_loop_joint
MARKER=/tmp/overnight_pipeline_phase2.marker
log(){ echo "$(date '+%F %T') $*" >> $LOG; }
log "waiter started"

# 1) 等训练退出(每5分钟查,最多20h)
for i in $(seq 1 240); do
  pgrep -f "train_lingbotvl[a]" > /dev/null || break
  sleep 300
done
sleep 90
log "training process exited; checkpoints: $(ls $CKPT_ROOT 2>/dev/null | tr '\n' ' ')"
tail -c 400 $TRAIN_LOG | tr '\r' '\n' | grep -a "INFO - __main__" | tail -1 >> $LOG

# 2) 开环筛选(15个均匀分布的episode,单进程单次加载)
cd /root/autodl-tmp/uploads/train/ours-20260930
source /root/miniconda3/etc/profile.d/conda.sh && conda activate lingbotvla
TRAJIDS="0 167 334 501 668 835 1002 1169 1336 1503 1670 1837 2004 2171 2338"
BEST=""; BEST_MAE=""
for step in 9000 8000 6000 4000 2000; do
  CK=$CKPT_ROOT/global_step_$step/hf_ckpt
  [ -d "$CK" ] || continue
  log "screening global_step_$step"
  CUDA_VISIBLE_DEVICES=0 python scripts/open_loop_eval.py \
    --model_path "$CK" --robo_name robotwin \
    --data_path "$DATA" --traj_ids $TRAJIDS \
    --save_plot_path "$OUT/global_step_$step" > /tmp/open_loop_joint_$step.log 2>&1
  MAE=$(grep -a "Average MAE" /tmp/open_loop_joint_$step.log | tail -1 | grep -oE "[0-9.e-]+$")
  MSE=$(grep -a "Average MSE" /tmp/open_loop_joint_$step.log | tail -1 | grep -oE "[0-9.e-]+$")
  log "RESULT global_step_$step MAE=$MAE MSE=$MSE"
  if [ -n "$MAE" ]; then
    EMPTY=$BEST_MAE
    if [ -z "$BEST" ] || python3 -c "import sys; sys.exit(0 if $MAE < $EMPTY else 1)"; then
      BEST=$CK; BEST_MAE=$MAE
    fi
  fi
done
log "BEST=$BEST MAE=$BEST_MAE"
[ -z "$BEST" ] && { log "no usable checkpoint, abort"; exit 1; }

# 3) 最优ckpt启动20任务闭环(3卡,脱离会话)
touch $MARKER
cd /root/autodl-tmp/uploads/train/ours-20260930
QWEN3VL_PATH=/root/autodl-tmp/models/Qwen3-VL-4B-Instruct \
EVAL_WORKDIR=/root/autodl-tmp/uploads/sim/RoboTwin \
OUTPUT_BASE=/root/autodl-tmp/output/eval \
CONDA_SH=/root/miniconda3/etc/profile.d/conda.sh \
MODEL_PATH=$BEST \
setsid nohup bash experiment/robotwin/start_robotwin_infer_and_eval.sh \
  --eval_workdir /root/autodl-tmp/uploads/sim/RoboTwin \
  --num_tasks 20 --num_gpus 3 --num_per_gpu 1 \
  > /tmp/closed_loop_joint.log 2>&1 &
log "closed-loop launched on $BEST (pid $!)"
