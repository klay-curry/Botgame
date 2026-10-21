#!/bin/bash
# ============================================================================
# 一键训练:从官方 lingbot-vla-v2-6b 的 6600 步产物热启动,续训 3400 步
#           (等效 10000 步),得到提交权重 hf_ckpt_final_equiv10000
#
# 训练数据:RoboTwin 2.0 Aloha-AgileX 50 任务 clean,每任务 50 条(2500 eps)
#           绝不使用 randomized 数据
#
# ── 用法 ────────────────────────────────────────────────────────────────────
#   模式 A(本地已有资源):显式指定目录
#     bash train.sh \
#       --base-ckpt  <6600步权重目录> \
#       --base-config <lingbot-vla-v2-6b 目录> \
#       --tokenizer  <Qwen3-VL-4B-Instruct 目录> \
#       --data       <robotwin_official_joint_v30 目录> \
#       --repo       <LingBot-VLA 2.0 训练仓> \
#       --out        <输出目录>
#
#   模式 B(本地缺资源):不传参数,脚本自动调用 download_assets.sh 拉取
#     bash train.sh
#     # 缺失项会逐个提示并自动拉取(基座 / tokenizer / 训练数据 / 中间权重)
#
#   其余可调项:--gpus 4 --micro-bs 24 --max-steps 3400 --conda-sh <path> --train-env lingbotvla
#
# ── 目录约定(默认值全部相对提交包根目录) ────────────────────────────────────
#   SUBMISSION_ROOT  提交包根(默认:本脚本的上上级)
#   ASSETS_ROOT      外部资源根(默认 $SUBMISSION_ROOT/assets)
#   TRAIN_REPO       训练代码仓(默认 $SUBMISSION_ROOT/src/train_repo)
#   OUTPUT_DIR       输出目录(默认 $SUBMISSION_ROOT/output/ckpt)
#
# 注:4 卡及以上必须保留 num_workers=8 与 TORCHINDUCTOR_COMPILE_THREADS=8,
#     否则容器内存会被顶爆并出现无 Python 报错的 SIGKILL(详见复现报告 §5)。
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMISSION_ROOT="${SUBMISSION_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DOWNLOAD_SCRIPT="$SUBMISSION_ROOT/03_模型权重/download_assets.sh"

ASSETS_ROOT="${ASSETS_ROOT:-$SUBMISSION_ROOT/assets}"
TRAIN_REPO="${TRAIN_REPO:-$SUBMISSION_ROOT/src/train_repo}"
OUTPUT_DIR="${OUTPUT_DIR:-$SUBMISSION_ROOT/output/ckpt}"
NUM_GPUS="${NUM_GPUS:-4}"
MICRO_BS="${MICRO_BS:-24}"
MAX_STEPS="${MAX_STEPS:-3400}"
CONDA_SH="${CONDA_SH:-/root/miniconda3/etc/profile.d/conda.sh}"
TRAIN_ENV="${TRAIN_ENV:-lingbotvla}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

BASE_CKPT="${BASE_CKPT:-$ASSETS_ROOT/models/radeon_ckpt/hf_ckpt_step6600}"
BASE_CONFIG="${BASE_CONFIG:-$ASSETS_ROOT/models/lingbot-vla-v2-6b}"
TOKENIZER="${TOKENIZER:-$ASSETS_ROOT/models/Qwen3-VL-4B-Instruct}"
DATA_ROOT="${DATA_ROOT:-$ASSETS_ROOT/data/robotwin_official_joint_v30}"

# ---------- 命令行参数 ----------
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
        --conda-sh)    CONDA_SH="$2"; shift 2 ;;
        --train-env)   TRAIN_ENV="$2"; shift 2 ;;
        -h|--help)     sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "未知参数: $1(用 --help 查看用法)"; exit 1 ;;
    esac
done

GLOBAL_BS=$(( MICRO_BS * NUM_GPUS ))

# ---------- 资源自检:缺什么拉什么 ----------
ensure() {   # $1=路径 $2=下载目标(base|tokenizer|data|team)
    if [ -e "$1" ]; then
        echo "  ✓ 已存在: $1"
        return 0
    fi
    echo "  ✗ 缺失: $1 → 自动拉取 [$2]"
    bash "$DOWNLOAD_SCRIPT" "$2"
    [ -e "$1" ] || { echo "拉取后仍未找到: $1"; exit 1; }
}

echo "=========================================================="
echo " 训练配置"
echo "   submission root : $SUBMISSION_ROOT"
echo "   assets root     : $ASSETS_ROOT"
echo "   train repo      : $TRAIN_REPO"
echo "   base ckpt       : $BASE_CKPT"
echo "   base config     : $BASE_CONFIG"
echo "   tokenizer       : $TOKENIZER"
echo "   data root       : $DATA_ROOT"
echo "   output          : $OUTPUT_DIR"
echo "   GPUs=$NUM_GPUS  micro=$MICRO_BS  global=$GLOBAL_BS  max_steps=$MAX_STEPS"
echo "=========================================================="
echo "资源检查:"
ensure "$BASE_CONFIG" base
ensure "$TOKENIZER"  tokenizer
ensure "$BASE_CKPT"  team
ensure "$DATA_ROOT"  data

if [ ! -d "$TRAIN_REPO" ]; then
    echo ""
    echo "缺少训练代码仓: $TRAIN_REPO"
    echo "该仓为 LingBot-VLA 2.0 训练代码(含 train.sh / tasks/ / configs/ / assets/),"
    echo "请用 --repo <路径> 指定,或将其放到 $SUBMISSION_ROOT/src/train_repo。"
    exit 1
fi
echo "  ✓ 训练仓: $TRAIN_REPO"

export TORCHINDUCTOR_COMPILE_THREADS="${TORCHINDUCTOR_COMPILE_THREADS:-8}"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export PATH=/usr/local/cuda/bin:$PATH

source "$CONDA_SH"
conda activate "$TRAIN_ENV"

cd "$TRAIN_REPO"

# 数据清单:优先用训练仓内的,否则用提交包内的(50 行,<任务名> <数据目录>)
DATA_MANIFEST="assets/training_data/robotwin_joint_v30.txt"
if [ ! -f "$DATA_MANIFEST" ]; then
    DATA_MANIFEST="$SUBMISSION_ROOT/configs/training_data/robotwin_joint_v30.txt"
    echo "使用提交包内数据清单: $DATA_MANIFEST"
fi

bash train.sh tasks/vla/train_lingbotvla.py configs/vla/robotwin/robotwin.yaml \
  --train.micro_batch_size="$MICRO_BS" \
  --train.global_batch_size="$GLOBAL_BS" \
  --train.gradient_accumulation_steps=1 \
  --train.max_steps="$MAX_STEPS" \
  --train.save_steps=1000 \
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
echo "训练完成。请用 src/convert_dcp_to_hf.py 将 DCP 存档转换为 HF 目录后再评测。"
