#!/bin/bash
# ============================================================================
# 一键评测:加载 checkpoint,完成 clean / randomized 两个 setting 的
#           50 任务 × 100 局全量评测(队列调度,多卡并发)
#
# ── 用法 ────────────────────────────────────────────────────────────────────
#   模式 A(本地已有资源):显式指定目录
#     bash eval.sh --model <checkpoint 目录> \
#                  --sim <RoboTwin 仿真仓> \
#                  --infer <推理代码仓> \
#                  --tokenizer <Qwen3-VL-4B-Instruct 目录>
#
#   模式 B(本地缺资源):不传参数,脚本自动调用 download_assets.sh 拉取
#     bash eval.sh
#     # 缺 tokenizer 等会自动拉取;checkpoint 默认取 03_模型权重/checkpoint
#
#   常用可选项:
#     --setting demo_clean|demo_randomized   (默认 demo_clean)
#     --tasks 50                              (默认 50)
#     --gpus 6 --per-gpu 2                   (48GB 卡 bf16 每卡 2 副本)
#     --precision bf16|fp32                   (默认 bf16)
#     --video                                 录制每个 episode 的回放视频(较慢)
#
# ── 目录约定(默认值全部相对提交包根目录) ────────────────────────────────────
#   SUBMISSION_ROOT  提交包根(默认:本脚本的上上级)
#   MODEL_PATH       待评权重(默认 $SUBMISSION_ROOT/03_模型权重/checkpoint)
#   EVAL_WORKDIR     RoboTwin 仿真仓(默认 $SUBMISSION_ROOT/src/RoboTwin)
#   INFER_REPO       推理侧代码仓(默认 $SUBMISSION_ROOT/src/infer_repo)
#   ASSETS_ROOT      外部资源根(默认 $SUBMISSION_ROOT/assets)
#   OUTPUT_BASE      评测输出根(默认 $SUBMISSION_ROOT/output/eval)
#
# ⚠️ 注意 1: bf16 与 fp32 不能同时开。推理服务有 assert not (use_bf16 and use_fp32),
#            只开 bf16 而不显式关 fp32 会导致所有推理服务启动即崩溃。
# ⚠️ 注意 2: 48GB 卡 bf16 每副本约 18GB,2 副本安全、3 副本前向时 OOM;
#            24GB 卡只能 bf16 单副本;fp32 单副本约 32GB。
# ⚠️ 注意 3: 推理服务会从模型目录上溯 3 级查找 lingbotvla_cli.yaml,
#            若报 FileNotFoundError,请按 README §4 的说明调整目录布局。
# ⚠️ 注意 4: 启动约需 10 分钟(curobo 首槽 JIT 编译 + 各推理服务加载),非卡死。
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMISSION_ROOT="${SUBMISSION_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
DOWNLOAD_SCRIPT="$SUBMISSION_ROOT/03_模型权重/download_assets.sh"

ASSETS_ROOT="${ASSETS_ROOT:-$SUBMISSION_ROOT/assets}"
EVAL_WORKDIR="${EVAL_WORKDIR:-$SUBMISSION_ROOT/src/RoboTwin}"
INFER_REPO="${INFER_REPO:-$SUBMISSION_ROOT/src/infer_repo}"
OUTPUT_BASE="${OUTPUT_BASE:-$SUBMISSION_ROOT/output/eval}"
export OUTPUT_BASE
MODEL_PATH="${MODEL_PATH:-$SUBMISSION_ROOT/03_模型权重/checkpoint}"
QWEN3VL_PATH="${QWEN3VL_PATH:-$ASSETS_ROOT/models/Qwen3-VL-4B-Instruct}"
export QWEN3VL_PATH

NUM_TASKS="${NUM_TASKS:-50}"
TASK_CONFIG="${TASK_CONFIG:-demo_clean}"
NUM_GPUS="${NUM_GPUS:-6}"
NUM_PER_GPU="${NUM_PER_GPU:-2}"
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
        --out)        OUTPUT_BASE="$2"; shift 2 ;;
        --setting)    TASK_CONFIG="$2"; shift 2 ;;
        --tasks)      NUM_TASKS="$2"; shift 2 ;;
        --gpus)       NUM_GPUS="$2"; shift 2 ;;
        --per-gpu)    NUM_PER_GPU="$2"; shift 2 ;;
        --precision)  PRECISION="$2"; shift 2 ;;
        --video)      VIDEO="true"; shift ;;
        --conda-sh)   CONDA_SH="$2"; shift 2 ;;
        -h|--help)    sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "未知参数: $1(用 --help 查看用法)"; exit 1 ;;
    esac
done

USE_BF16="true"; USE_FP32="false"
if [ "$PRECISION" = "fp32" ]; then USE_BF16="false"; USE_FP32="true"; fi

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
echo " 评测配置"
echo "   model      : $MODEL_PATH"
echo "   sim repo   : $EVAL_WORKDIR"
echo "   infer repo : $INFER_REPO"
echo "   tokenizer  : $QWEN3VL_PATH"
echo "   output     : $OUTPUT_BASE"
echo "   setting    : $TASK_CONFIG   tasks=$NUM_TASKS"
echo "   GPUs=$NUM_GPUS 副本/卡=$NUM_PER_GPU  精度=$PRECISION"
echo "=========================================================="
echo "资源检查:"
ensure "$QWEN3VL_PATH" tokenizer

# 仿真仓缺失 → 自动克隆官方 RoboTwin 并叠加本项目改动
if [ ! -d "$EVAL_WORKDIR" ]; then
    echo "  ✗ 缺失仿真仓: $EVAL_WORKDIR → 自动克隆官方 RoboTwin(commit 13c3c47)"
    bash "$SCRIPT_DIR/setup_sim_repo.sh" "$EVAL_WORKDIR"
fi

for p in "$MODEL_PATH" "$EVAL_WORKDIR" "$INFER_REPO"; do
    if [ ! -e "$p" ]; then
        echo ""
        echo "缺少路径: $p"
        echo "· checkpoint:本次提交权重已随包提供(03_模型权重/checkpoint/),"
        echo "  也可用 --model <目录> 指定其他权重;若评的是官方基座,"
        echo "  先执行: bash ../03_模型权重/download_assets.sh base"
        echo "· 仿真仓 / 推理仓:RoboTwin 官方仓见 https://github.com/robotwin-Platform/RoboTwin,"
        echo "  推理侧代码见 src/ 内本包提供的 launcher 与 deploy/,"
        echo "  也可用 --sim / --infer 指向你本地的对应目录。"
        exit 1
    fi
done
echo "  ✓ 权重 / 仿真仓 / 推理仓 均就位"

source "$CONDA_SH"
export CONDA_SH            # launcher 内部需要该变量(否则回落到占位路径)

mkdir -p "$OUTPUT_BASE"
cd "$INFER_REPO"

bash experiment/robotwin/start_robotwin_infer_and_eval.sh \
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
echo "评测结束。结果位于 $OUTPUT_BASE 下最新的 _${TASK_CONFIG}_<时间戳>/ 目录:"
echo "  - stats.txt          汇总表(逐任务成功率)"
echo "  - eval_logs/         逐 episode 原始日志"
echo "  - inference_logs/    推理服务日志"
echo "可用 python3 src/gen_results_json.py 从原始日志生成官方 results.json。"
