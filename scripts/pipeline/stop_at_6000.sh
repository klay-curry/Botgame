#!/bin/bash
# 到 6000 步自动停训:hf_ckpt 完整落盘且稳定后 kill 训练进程组
LOG=/tmp/stop_at_6000.log
CK=/root/autodl-tmp/output/ckpt/checkpoints/global_step_6000/hf_ckpt
log(){ echo "$(date '+%F %T') $*" >> $LOG; }
log "watcher started"
while true; do
  if [ -f "$CK/model.safetensors.index.json" ]; then
    n=$(find "$CK" -name "*.safetensors" | wc -l)
    if [ "$n" -ge 3 ]; then
      s1=$(du -sb "$CK" | cut -f1); sleep 90; s2=$(du -sb "$CK" | cut -f1)
      if [ "$s1" = "$s2" ] && [ "$s1" -gt 11000000000 ]; then
        log "step6000 hf_ckpt complete ($s1 bytes), stopping training"
        pkill -f "train_lingbotvl[a]"
        sleep 10
        pkill -9 -f "train_lingbotvl[a]" 2>/dev/null
        log "training stopped; overnight pipeline will take over"
        exit 0
      fi
    fi
  fi
  sleep 60
done
