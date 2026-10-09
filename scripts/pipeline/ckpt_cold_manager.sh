#!/bin/bash
# ckpt 冷存管理器(2026-10-02):
#   1) 新 ckpt 落盘稳定后,rsync 其 hf_ckpt(12GB)到 autodl-fs 冷存并校验
#   2) 校验通过后清理本地 model//optimizer/(~50GB,断点续训用;盘不够,放弃续训能力)
#   3) 非最新的 ckpt 连本地 hf_ckpt 也删(fs 已有冷存备份),最新一份保留在本地供评测快速加载
CKPT_ROOT=/root/autodl-tmp/output/ckpt/checkpoints
COLD=/autodl-fs/data/ckpt_cold
mkdir -p "$COLD"
while true; do
  if [ -d "$CKPT_ROOT" ]; then
    newest=$(ls -t "$CKPT_ROOT" 2>/dev/null | head -1)
    for d in "$CKPT_ROOT"/*/; do
      name=$(basename "$d")
      [ -d "$d/hf_ckpt" ] || continue
      # 跳过仍在写入的目录(4 分钟内有文件更新)
      last=$(find "$d" -type f -newermt "-240 seconds" 2>/dev/null | head -1)
      [ -n "$last" ] && continue
      # 1) 冷存
      if [ ! -f "$COLD/$name/.done" ]; then
        if rsync -a "$d/hf_ckpt" "$COLD/$name/" 2>/dev/null; then
          n1=$(find "$d/hf_ckpt" -type f | wc -l)
          n2=$(find "$COLD/$name/hf_ckpt" -type f | wc -l)
          if [ "$n1" = "$n2" ] && [ "$n1" -gt 0 ]; then
            touch "$COLD/$name/.done"
            echo "$(date '+%F %T') cold stored: $name ($n1 files)"
          fi
        fi
      fi
      # 2) 清理本地 dcp
      if [ -f "$COLD/$name/.done" ]; then
        if [ -d "$d/optimizer" ] || [ -d "$d/model" ]; then
          rm -rf "$d/optimizer" "$d/model" "$d/extra_state"
          echo "$(date '+%F %T') stripped dcp: $name"
        fi
        # 3) 非最新:本地 hf_ckpt 也删
        if [ "$name" != "$newest" ] && [ -d "$d/hf_ckpt" ]; then
          rm -rf "$d/hf_ckpt"
          echo "$(date '+%F %T') removed local hf_ckpt (cold exists): $name"
        fi
      fi
    done
  fi
  sleep 120
done
