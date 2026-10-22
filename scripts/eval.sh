#!/bin/bash
# ============================================================================
# 一键评测：加载 checkpoint，按官方协议跑 clean / randomized 50 任务 × 100 局
#
# 用法：
#   bash scripts/eval.sh                                  # 默认 1 卡 1 槽
#   bash scripts/eval.sh --setting demo_randomized --tasks 50
#   bash scripts/eval.sh --gpus 6 --per-gpu 2             # 全量评测推荐
#   bash scripts/eval.sh --model /path/to/hf_ckpt --video # 录制 rollout 视频
#
# 目录约定（均可用参数/环境变量覆盖）：
#   MODEL_PATH     assets/models/hf_ckpt_final_equiv10000
#   EVAL_WORKDIR   RoboTwin（缺失时自动克隆 @13c3c47）
#   INFER_REPO     ours
#   QWEN3VL_PATH   assets/models/Qwen3-VL-4B-Instruct（缺失时自动拉取）
#   OUTPUT_BASE    output/eval
#
# 注意：
#   1) bf16 与 fp32 不能同时开；本脚本会根据 --precision 显式二选一。
#   2) 48G 卡 bf16 每副本约 18G，2 副本安全；fp32 单副本约 32G。
#   3) 推理服务会从模型目录上溯 3 级查找 lingbotvla_cli.yaml；本脚本会自动
#      创建 staging 目录并生成该配置，无需手工摆放。
#   4) 启动约需 10 分钟（curobo JIT + 模型加载），不是卡死。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_SCRIPT="$SCRIPT_DIR/download_assets.sh"
INFER_CONFIG_TEMPLATE="$REPO_ROOT/ours/configs/vla/robotwin/inference_robotwin.yaml"

ASSETS_ROOT="${ASSETS_ROOT:-$REPO_ROOT/assets}"
EVAL_WORKDIR="${EVAL_WORKDIR:-$REPO_ROOT/RoboTwin}"
INFER_REPO="${INFER_REPO:-$REPO_ROOT/ours}"
OUTPUT_BASE="${OUTPUT_BASE:-$REPO_ROOT/output/eval}"
MODEL_PATH="${MODEL_PATH:-$ASSETS_ROOT/models/hf_ckpt_final_equiv10000}"
BASE_MODEL="${BASE_MODEL:-$ASSETS_ROOT/models/lingbot-vla-v2-6b}"
MOGE_PATH="${MOGE_PATH:-$ASSETS_ROOT/models/moge2-vitb-normal.pt}"
QWEN3VL_PATH="${QWEN3VL_PATH:-$ASSETS_ROOT/models/Qwen3-VL-4B-Instruct}"
export QWEN3VL_PATH
export OUTPUT_BASE

NUM_TASKS="${NUM_TASKS:-50}"
TASK_CONFIG="${TASK_CONFIG:-demo_clean}"
NUM_GPUS="${NUM_GPUS:-1}"
NUM_PER_GPU="${NUM_PER_GPU:-1}"
VIDEO="${VIDEO:-false}"
PRECISION="${PRECISION:-bf16}"
CONDA_SH="${CONDA_SH:-/root/miniconda3/etc/profile.d/conda.sh}"
INFERENCE_ENV="${INFERENCE_ENV:-lingbotvla}"
SIM_ENV="${SIM_ENV:-RoboTwin}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --model)      MODEL_PATH="$2"; shift 2 ;;
        --sim)        EVAL_WORKDIR="$2"; shift 2 ;;
        --infer)      INFER_REPO="$2"; shift 2 ;;
        --tokenizer)  QWEN3VL_PATH="$2"; export QWEN3VL_PATH; shift 2 ;;
        --out)        OUTPUT_BASE="$2"; export OUTPUT_BASE; shift 2 ;;
        --setting)    TASK_CONFIG="$2"; shift 2 ;;
        --tasks)      NUM_TASKS="$2"; shift 2 ;;
        --gpus)       NUM_GPUS="$2"; shift 2 ;;
        --per-gpu)    NUM_PER_GPU="$2"; shift 2 ;;
        --precision)  PRECISION="$2"; shift 2 ;;
        --video)      VIDEO="true"; shift ;;
        --conda-sh)   CONDA_SH="$2"; shift 2 ;;
        -h|--help)    sed -n '2,31p' "$0"; exit 0 ;;
        *) echo "未知参数: $1（用 --help 查看用法）"; exit 1 ;;
    esac
done

USE_BF16="true"; USE_FP32="false"
if [ "$PRECISION" = "fp32" ]; then USE_BF16="false"; USE_FP32="true"; fi

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
echo " 评测配置"
echo "   model      : $MODEL_PATH"
echo "   sim repo   : $EVAL_WORKDIR"
echo "   infer repo : $INFER_REPO"
echo "   tokenizer  : $QWEN3VL_PATH"
echo "   output     : $OUTPUT_BASE"
echo "   setting    : $TASK_CONFIG   tasks=$NUM_TASKS"
echo "   GPUs=$NUM_GPUS 副本/卡=$NUM_PER_GPU  精度=$PRECISION  video=$VIDEO"
echo "=========================================================="
echo "资源检查:"
ensure "$QWEN3VL_PATH" tokenizer

if [ ! -d "$EVAL_WORKDIR" ]; then
    echo "  ✗ 缺失仿真仓: $EVAL_WORKDIR -> 自动克隆官方 RoboTwin@13c3c47"
    bash "$SCRIPT_DIR/setup_sim_repo.sh" "$EVAL_WORKDIR"
fi

if [ ! -d "$MODEL_PATH" ]; then
    echo ""
    echo "缺少 checkpoint: $MODEL_PATH"
    echo "· 最终权重 hf_ckpt_final_equiv10000（12G）随竞赛提交包提供，"
    echo "  解压到 $ASSETS_ROOT/models/hf_ckpt_final_equiv10000 即可；"
    echo "· 或评测官方基座 / 其他权重：bash scripts/eval.sh --model <HF 权重目录>"
    exit 1
fi
for p in "$EVAL_WORKDIR" "$INFER_REPO" "$INFER_CONFIG_TEMPLATE"; do
    if [ ! -e "$p" ]; then
        echo "缺少路径: $p"
        exit 1
    fi
done
echo "  ✓ 权重 / 仿真仓 / 推理仓 / 推理配置 均就位"

# ---------- staging：把任意位置的 HF ckpt 摆成推理服务期望的目录布局 ----------
STAGE_ROOT="$OUTPUT_BASE/.staging/$(basename "$MODEL_PATH")"
mkdir -p "$STAGE_ROOT/m/a/b"
ln -sfn "$(cd "$MODEL_PATH" && pwd -P)" "$STAGE_ROOT/m/a/b/ckpt"
sed -e "s|__BASE_MODEL__|$BASE_MODEL|g" \
    -e "s|__TOKENIZER__|$QWEN3VL_PATH|g" \
    -e "s|__MOGE_PATH__|$MOGE_PATH|g" \
    -e "s|__OUTPUT_DIR__|$OUTPUT_BASE|g" \
    "$INFER_CONFIG_TEMPLATE" > "$STAGE_ROOT/m/lingbotvla_cli.yaml"
STAGED_MODEL="$STAGE_ROOT/m/a/b/ckpt"
echo "  ✓ 已生成推理 staging: $STAGED_MODEL"
echo "     配置: $STAGE_ROOT/m/lingbotvla_cli.yaml"

source "$CONDA_SH"
export CONDA_SH            # launcher 内部需要该变量（否则回落到占位路径）

mkdir -p "$OUTPUT_BASE"
cd "$INFER_REPO"

bash experiment/robotwin/start_robotwin_infer_and_eval.sh \
  --model_path "$STAGED_MODEL" \
  --eval_workdir "$EVAL_WORKDIR" \
  --num_tasks "$NUM_TASKS" \
  --task_config "$TASK_CONFIG" \
  --output_base "$OUTPUT_BASE" \
  --conda_sh "$CONDA_SH" \
  --inference_env "$INFERENCE_ENV" \
  --sim_env "$SIM_ENV" \
  --num_gpus "$NUM_GPUS" --num_per_gpu "$NUM_PER_GPU" \
  --use_bf16 "$USE_BF16" --use_fp32 "$USE_FP32" \
  $([ "$VIDEO" = "true" ] && echo "--video")

echo ""
echo "评测结束。结果位于 $OUTPUT_BASE 下最新的 _${TASK_CONFIG}_<时间戳>/："
echo "  - stats.txt          汇总表（逐任务成功率）"
echo "  - eval_logs/         逐 episode 原始日志"
echo "  - eval_results/      逐 episode 视频（开启 --video 时）"
echo "  - inference_logs/    推理服务日志"
echo "用 python scripts/gen_results_json.py --base $OUTPUT_BASE --out results.json 生成官方模板。"
