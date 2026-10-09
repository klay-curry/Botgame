#!/bin/bash
# checkpoint 磁盘守护:只保留最新一份 checkpoint 的 optimizer/,旧的只留 model/
# 用法: nohup bash strip_optimizer.sh > /tmp/strip_optimizer.log 2>&1 &
CKPT_ROOT=/root/autodl-tmp/output/ckpt/checkpoints
while true; do
  if [ -d "$CKPT_ROOT" ]; then
    newest=$(ls -t "$CKPT_ROOT" 2>/dev/null | head -1)
    if [ -n "$newest" ]; then
      for d in "$CKPT_ROOT"/*/; do
        name=$(basename "$d")
        if [ "$name" != "$newest" ] && [ -d "$d/optimizer" ]; then
          rm -rf "$d/optimizer" "$d/ema" "$d/extra_state"
          echo "$(date '+%F %T') stripped optimizer: $name (kept model only)"
        fi
      done
    fi
  fi
  sleep 120
done
