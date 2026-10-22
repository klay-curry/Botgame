#!/bin/bash
# ============================================================================
# 一键训练：从官方基座/团队 6600 步权重热启动，续训 3400 步（等效 10000 步）
#
# 训练数据：RoboTwin 2.0 Aloha-AgileX 50 任务 clean，每任务 50 条（2500 eps）
#           绝不使用 randomized 数据
#
# 用法：
#   bash scripts/train.sh                    # 自动拉取缺失资源后开训
#   bash scripts/train.sh --gpus 4 --max-steps 3400
#   bash scripts/train.sh \
#     --base-ckpt  assets/models/radeon_ckpt/hf_ckpt_step6600 \
#     --base-config assets/models/lingbot-vla-v2-6b \
#     --tokenizer  assets/models/Qwen3-VL-4B-Instruct \
#     --data       assets/data/robotwin_official_joint_v30 \
#     --repo       ours --out output/ckpt
#
# 说明：
#   * 4 卡及以上必须保留 num_workers=8 与 TORCHINDUCTOR_COMPILE_THREADS=8，
#     否则容器内存会被顶爆并出现无 Python 报错的 SIGKILL。
#   * 训练存档为 DCP；评测前用 scripts/convert_dcp_to_hf.py 转成 HF 目录。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_SCRIPT="$SCRIPT_DIR/download_assets.sh"

ASSETS_ROOT="${ASSETS_ROOT:-$REPO_ROOT/assets}"
TRAIN_REPO="${TRAIN_REPO:-$REPO_ROOT/ours}"
OUTPUT_DIR="${OUTPUT_DIR:-$REPO_ROOT/output/ckpt}"
NUM_GPUS="${NUM_GPUS:-4}"
MICRO_BS="${MICRO_BS:-24}"
MAX_STEPS="${MAX_STEPS:-3400}"
SAVE_STEPS="${SAVE_STEPS:-1000}"
CONDA_SH="${CONDA_SH:-/root/miniconda3/etc/profile.d/conda.sh}"
TRAIN_ENV="${TRAIN_ENV:-lingbotvla}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

BASE_CKPT="${BASE_CKPT:-$ASSETS_ROOT/models/radeon_ckpt/hf_ckpt_step6600}"
BASE_CONFIG="${BASE_CONFIG:-$ASSETS_ROOT/models/lingbot-vla-v2-6b}"
TOKENIZER="${TOKENIZER:-$ASSETS_ROOT/models/Qwen3-VL-4B-Instruct}"
DATA_ROOT="${DATA_ROOT:-$ASSETS_ROOT/data/robotwin_official_joint_v30}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-ckpt)   BASE_CKPT="$2"; shift 2 ;;
        --base-config) BASE_CONFIG="$2"; shift 2 ;;
        --tokenizer)   TOKENIZER="$2"; shift 2 ;;
        --data)        DATA_ROOT="$2"; shift 2 ;;
        --repo)        TRAIN_REPO="$2"; shift 2 ;;
        --out)         OUTPUT_DIR="$2"; shift 2 ;;
        --gpus)        NUM_GPUS="$2"; shift 2 ;;
        --micro-bs)    MICRO_BS="$2"; shift 2 ;;
        --max-steps)   MAX_STEPS="$2"; shift 2 ;;
        --save-steps)  SAVE_STEPS="$2"; shift 2 ;;
        --conda-sh)    CONDA_SH="$2"; shift 2 ;;
        --train-env)   TRAIN_ENV="$2"; shift 2 ;;
        -h|--help)     sed -n '2,27p' "$0"; exit 0 ;;
        *) echo "未知参数: $1（用 --help 查看用法）"; exit 1 ;;
    esac
done

GLOBAL_BS=$(( MICRO_BS * NUM_GPUS ))

ensure() {   # $1=路径 $2=下载项
    if [ -e "$1" ]; then
        echo "  ✓ 已存在: $1"
        return 0
    fi
    echo "  ✗ 缺失: $1 -> 自动拉取 [$2]"
    bash "$DOWNLOAD_SCRIPT" "$2"
    [ -e "$1" ] || { echo "拉取后仍未找到: $1"; exit 1; }
}

echo "=========================================================="
echo " 训练配置"
echo "   repo root   : $REPO_ROOT"
echo "   assets root : $ASSETS_ROOT"
echo "   train repo  : $TRAIN_REPO"
echo "   base ckpt   : $BASE_CKPT"
echo "   base config : $BASE_CONFIG"
echo "   tokenizer   : $TOKENIZER"
echo "   data root   : $DATA_ROOT"
echo "   output      : $OUTPUT_DIR"
echo "   GPUs=$NUM_GPUS  micro=$MICRO_BS  global=$GLOBAL_BS  max_steps=$MAX_STEPS"
echo "=========================================================="
echo "资源检查:"
ensure "$BASE_CONFIG" base
ensure "$TOKENIZER"  tokenizer
ensure "$BASE_CKPT"  team
ensure "$DATA_ROOT"  data

if [ ! -d "$TRAIN_REPO" ]; then
    echo "缺少训练代码仓: $TRAIN_REPO"
    echo "本仓库自带训练实现（ours/），一般无需手动指定 --repo。"
    exit 1
fi
echo "  ✓ 训练仓: $TRAIN_REPO"

# 数据清单：从实际 DATA_ROOT 生成，避免机器相关的绝对路径写死
mkdir -p "$OUTPUT_DIR"
DATA_MANIFEST="$OUTPUT_DIR/train_manifest_robotwin_joint_v30.txt"
: > "$DATA_MANIFEST"
for d in "$DATA_ROOT"/lerobot/*_joint_v30; do
    if [ -d "$d" ]; then
        echo "robotwin $d" >> "$DATA_MANIFEST"
    fi
done
N_TASKS=$(wc -l < "$DATA_MANIFEST")
if [ "$N_TASKS" -ne 50 ]; then
    echo "⚠️  数据清单任务数为 $N_TASKS（预期 50），请检查 $DATA_ROOT/lerobot"
fi
echo "  ✓ 数据清单: $DATA_MANIFEST（$N_TASKS 个任务）"

export TORCHINDUCTOR_COMPILE_THREADS="${TORCHINDUCTOR_COMPILE_THREADS:-8}"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export PATH=/usr/local/cuda/bin:$PATH

source "$CONDA_SH"
conda activate "$TRAIN_ENV"
cd "$TRAIN_REPO"

bash train.sh tasks/vla/train_lingbotvla.py configs/vla/robotwin/robotwin.yaml \
  --train.micro_batch_size="$MICRO_BS" \
  --train.global_batch_size="$GLOBAL_BS" \
  --train.gradient_accumulation_steps=1 \
  --train.max_steps="$MAX_STEPS" \
  --train.save_steps="$SAVE_STEPS" \
  --train.enable_gradient_checkpointing=true \
  --train.enable_fp32=false \
  --train.freeze_vision_encoder=false \
  --train.optimizer=adamw \
  --train.lr=5e-5 \
  --train.lr_min=5e-5 \
  --train.lr_warmup_ratio=0.03 \
  --train.enable_resume=false \
  --train.output_dir="$OUTPUT_DIR" \
  --model.model_path="$BASE_CKPT" \
  --model.config_path="$BASE_CONFIG" \
  --model.tokenizer_path="$TOKENIZER" \
  --data.train_path="$DATA_MANIFEST" \
  --data.image_augment=true \
  --data.num_workers=8 \
  --data.prefetch_factor=8 \
  $EXTRA_ARGS

echo ""
echo "训练完成。把 DCP 存档转成 HF 目录后再评测："
echo "  python scripts/convert_dcp_to_hf.py ours/configs/vla/robotwin/robotwin.yaml \\"
echo "      $OUTPUT_DIR/checkpoints/global_step_XXXX $OUTPUT_DIR/hf_ckpt_stepXXXX \\"
echo "      --train.output_dir=$OUTPUT_DIR"
