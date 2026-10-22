#!/bin/bash
# 拉取第三方权重：赛事官方基座 lingbot-vla-v2-6b + Qwen3-VL tokenizer
#
#   bash scripts/download_model.sh              # 默认走 ModelScope（国内快）
#   USE_HF=1 bash scripts/download_model.sh     # 走 HuggingFace（海外或已配代理）
#   DEST_ROOT=/path bash scripts/download_model.sh
#
# 落地目录：
#   assets/models/lingbot-vla-v2-6b
#   assets/models/Qwen3-VL-4B-Instruct
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="${DEST_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
export DEST_ROOT

if [ "${USE_HF:-0}" = "1" ]; then
    echo "[download_model] 从 HuggingFace 拉取基座 -> $DEST_ROOT/assets/models/lingbot-vla-v2-6b"
    huggingface-cli download Robbyant/lingbot-vla-v2-6b \
        --local-dir "$DEST_ROOT/assets/models/lingbot-vla-v2-6b"
    echo "[download_model] 从 HuggingFace 拉取 tokenizer"
    huggingface-cli download Qwen/Qwen3-VL-4B-Instruct \
        --local-dir "$DEST_ROOT/assets/models/Qwen3-VL-4B-Instruct"
else
    bash "$SCRIPT_DIR/download_assets.sh" base tokenizer
fi

echo "[download_model] 完成。基座目录应包含 model-0000x-of-00006.safetensors + depth/ + dino_video/"
ls -lh "$DEST_ROOT/assets/models/lingbot-vla-v2-6b" | head
