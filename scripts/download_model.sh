#!/usr/bin/env bash
# 下载赛事指定模型权重 lingbot-vla-v2-6b（~25GB）
# 用法: bash scripts/download_model.sh            # 默认走 ModelScope（国内快）
#       USE_HF=1 bash scripts/download_model.sh   # 走 HuggingFace（海外或已配代理）
#       国内 HF 加速: export HF_ENDPOINT=https://hf-mirror.com
set -euo pipefail

DEST=${DEST:-model/models/Robbyant--lingbot-vla-v2-6b}
mkdir -p "$DEST"

if [[ "${USE_HF:-0}" == "1" ]]; then
  echo "[download_model] 从 HuggingFace 拉取 Robbyant/lingbot-vla-v2-6b -> $DEST"
  # pip install -U "huggingface_hub[cli]"
  huggingface-cli download Robbyant/lingbot-vla-v2-6b --local-dir "$DEST"
else
  echo "[download_model] 从 ModelScope 拉取 Robbyant/lingbot-vla-v2-6b -> $DEST"
  # pip install modelscope
  modelscope download --model Robbyant/lingbot-vla-v2-6b --local_dir "$DEST"
fi

echo "[download_model] 完成。检查点应包含 6 个 model-*.safetensors 分片 + depth/ + dino_video/"
ls -lh "$DEST"
