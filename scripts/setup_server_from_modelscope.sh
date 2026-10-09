#!/usr/bin/env bash
# 服务器一键拉取全部资源 —— 只走 ModelScope 国内源，不依赖 GitHub / HuggingFace。
# 外网只用于 git clone 本仓库；其余（环境包/数据/资产/权重）全部国内 CDN。
#
# 前提:
#   1) 本仓库已经 git clone 到服务器
#   2) pip install -U modelscope        （PyPI/tuna 可达即可）
#
# 用法:
#   bash scripts/setup_server_from_modelscope.sh                  # 全量拉取+解包
#   SKIP_ENV=1 bash ...                                           # 环境包已拉过，跳过
#   WITH_BASELINE=1 bash ...                                      # 附加官方 baseline ckpt（25.5G，currytom/self）
#   WITH_CKPT=1 bash ...                                          # 附加自训 joint-v21 ckpt（默认 step6000，12G）
#   WITH_CKPT=1 WITH_CKPT_STEP=2000 bash ...                      #   换拉别的步数（2000/4000/6000）
#   BASE=/root/autodl-tmp bash ...                                # 自定义根目录（默认 /root/autodl-tmp）
#   ⚠️ AMD(ROCm) 机器: 环境安装段不适用（离线包是 CUDA 版 torch），见 docs/ROCM_SETUP.md
set -euo pipefail

BASE=${BASE:-/root/autodl-tmp}
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- 0. 自举：缺什么装什么（PyPI 走清华源） ---
PY="$(command -v python || command -v python3 || true)"
[ -n "$PY" ] || { echo "没有 python/python3"; exit 1; }
if ! command -v modelscope >/dev/null 2>&1; then
  echo "安装 modelscope CLI..."
  pip install -U modelscope -i https://pypi.tuna.tsinghua.edu.cn/simple \
    || pip3 install -U modelscope -i https://pypi.tuna.tsinghua.edu.cn/simple
fi
command -v unzip >/dev/null 2>&1 || { echo "缺 unzip: sudo apt install -y unzip"; exit 1; }
mkdir -p "$BASE/uploads" "$BASE/robotwin_eef_clean50" "$BASE/robotwin_joint_v21" "$BASE/assets_dl" "$BASE/depth_models"
ms() { modelscope download "$@"; }

echo "== [1/6] 环境离线包 env-kit（~850MB） =="
ENVKIT="$BASE/uploads"
mkdir -p "$ENVKIT"
if [ "${SKIP_ENV:-0}" != "1" ]; then
  ms --dataset currytom/robotwin-env-kit --local_dir "$ENVKIT"
fi
# 2026-10-09 快照优先（含 joint 数据配置 + 闭环评测补件），旧机兼容回退 20260930
OURS_TGZ=$(ls "$ENVKIT"/train/ours-20261009.tar.gz "$ENVKIT"/train/ours-20260930.tar.gz 2>/dev/null | head -1)
RT_TGZ=$(ls "$ENVKIT"/sim/RoboTwin-team-20261009.tar.gz "$ENVKIT"/sim/RoboTwin-team-20260930.tar.gz 2>/dev/null | head -1)
[ -n "$OURS_TGZ" ] || { echo "env-kit 不完整（缺 train/ours-*.tar.gz）"; exit 1; }
[ -n "$RT_TGZ" ]   || { echo "env-kit 不完整（缺 sim/RoboTwin-team-*.tar.gz）"; exit 1; }

echo "== [2/6] 解包训练仓库快照与 RoboTwin 快照 =="
# 注意：tarball 内顶层目录名保持 ours-20260930/（路径兼容，勿改）
[ -d "$ENVKIT/train/ours-20260930/lingbotvla" ] || ( cd "$ENVKIT/train" && tar xzf "$(basename "$OURS_TGZ")" )
[ -d "$ENVKIT/sim/RoboTwin/scripts" ]           || ( cd "$ENVKIT/sim"   && tar xzf "$(basename "$RT_TGZ")" )
RTROOT="$ENVKIT/sim/RoboTwin"
# 闭环评测客户端用相对路径 ../task_config，做软链（旧包没有这条）
[ -e "$RTROOT/task_config" ] || ln -s "$RTROOT/env_cfg/task_config" "$RTROOT/task_config"

echo "== [3/6] 训练数据 LeRobot 官方关节版 joint-v21（14 维关节，2500 eps） =="
# 注意: 必须用 14 维关节版（官方管线口径: config 切片/norm_stats/评测 take_action qpos 全按 14 关节）。
# robbyant 的 eef 版是 16 维末端位姿空间, 与官方管线不兼容, 勿用于训练。
# 数据落盘路径须与 ours/assets/training_data/robotwin_joint.txt 一致: $BASE/robotwin_joint_v21/RoboTwin_lerobot_v21
DS="$BASE/robotwin_joint_v21"
if [ ! -d "$DS/RoboTwin_lerobot_v21/meta" ]; then
  if ms --dataset currytom/robotwin-lerobot-joint-v21 --include "RoboTwin_lerobot_v21_v30.tar.gz" --local_dir "$DS" \
     && [ -f "$DS/RoboTwin_lerobot_v21_v30.tar.gz" ]; then
    echo "  拉到已转好的 v3.0 包，直接解压（免本地转换）"
    tar xzf "$DS/RoboTwin_lerobot_v21_v30.tar.gz" -C "$DS"
  else
    echo "  v3.0 包不可用，回退 v2.1 zip 自行转换"
    ms --dataset currytom/robotwin-lerobot-joint-v21 --include "RoboTwin_lerobot_v21.zip" --local_dir "$DS"
    ( cd "$DS" && unzip -q -n RoboTwin_lerobot_v21.zip )
    echo "  TODO: 装好 lerobot 后执行转换:"
    echo "    HF_LEROBOT_HOME=$DS $PY -m lerobot.datasets.v30.convert_dataset_v21_to_v30 --repo-id RoboTwin_lerobot_v21 --force-conversion"
  fi
fi
n=$(find "$DS/RoboTwin_lerobot_v21/data" -name "*.parquet" 2>/dev/null | wc -l)
echo "  数据集 parquet 数: $n（应为 2500）"
[ "$n" = "2500" ] || { echo "任务数不对，检查下载完整性"; exit 1; }

echo "== [4/6] 仿真资产（~14.8GB）解压到 RoboTwin/assets =="
ASSETS_DL="$BASE/assets_dl"
if [ ! -d "$ASSETS_DL" ] || [ ! -f "$ASSETS_DL/objects.zip" ]; then
  ms --dataset currytom/robotwin-assets --local_dir "$ASSETS_DL"
fi
mkdir -p "$RTROOT/assets"
( cd "$RTROOT/assets"
  [ -d background_texture ] || unzip -q -n "$ASSETS_DL/background_texture.zip"
  [ -d objects ]            || unzip -q -n "$ASSETS_DL/objects.zip"
  [ -d embodiments ]        || unzip -q -n "$ASSETS_DL/embodiments.zip" -x "__MACOSX/*"
)
# MoGe 深度权重（训练配置 moge_path 指向）
cp -n "$ASSETS_DL/moge2-vitb-normal.pt" "$BASE/depth_models/" 2>/dev/null || true
# 官方提供的 embodiment 路径配置脚本
( cd "$RTROOT" && "$PY" scripts/update_embodiment_config_path.py ) \
  || echo "[WARN] update_embodiment_config_path.py 未跑成功，装好环境后手动执行"

echo "== [5/6] 权重（官方 ModelScope 仓库直拉） =="
[ -f "$BASE/lingbot-vla-v2-6b/.download_ok" ] || {
  ms --model robbyant/lingbot-vla-v2-6b --local_dir "$BASE/lingbot-vla-v2-6b" && touch "$BASE/lingbot-vla-v2-6b/.download_ok"
}
[ -f "$BASE/models/Qwen3-VL-4B-Instruct/.download_ok" ] || {
  ms --model Qwen/Qwen3-VL-4B-Instruct --local_dir "$BASE/models/Qwen3-VL-4B-Instruct" && touch "$BASE/models/Qwen3-VL-4B-Instruct/.download_ok"
}

if [ "${WITH_BASELINE:-0}" = "1" ]; then
  echo "== [extra] 官方 robotwin baseline ckpt（25.5G，currytom/self，对照评测用） =="
  ms --dataset currytom/self --include "model-*.safetensors" --local_dir "$BASE/baseline_ckpt"
fi

if [ "${WITH_CKPT:-0}" = "1" ]; then
  echo "== [extra] 自训 joint-v21 ckpt（12G/个，currytom/lingbotvla-joint-v21-ckpt） =="
  # 默认拉 step6000（当前最优，开环 MAE 0.0248）；WITH_CKPT=2000/4000 可拉别的
  STEP=${WITH_CKPT_STEP:-6000}
  ms --model currytom/lingbotvla-joint-v21-ckpt --include "global_step_${STEP}/**" --local_dir "$BASE/joint_ckpt"
fi

echo "== [6/6] 完成。磁盘占用: =="
df -h "$BASE" | tail -1

# 按显卡架构自动决定评测安装是否加 --blackwell（sm_120 及以上需要）
CC="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 | cut -d. -f1 || true)"
BW=""
if [ -n "$CC" ] && [ "$CC" -ge 12 ] 2>/dev/null; then
  BW=" --blackwell"
  echo "检测到 Blackwell 显卡 (compute_cap=$CC)：评测安装将自动追加 --blackwell"
fi

echo
echo "---------- 资源就绪。接下来安装两套环境（逐行复制执行） ----------"
echo "# ⚠️ AMD(ROCm) 机器: 下面离线包装的是 CUDA 版 torch/flash-attn，不可用；"
echo "#    手动装 ROCm 版 torch 并跳过 flash-attn（走 SDPA 回退），步骤见 docs/ROCM_SETUP.md"
echo "conda create -n lingbotvla python=3.12 -y && conda activate lingbotvla"
echo "bash \"$BASE/uploads/train/create_train_env_offline.sh\" --kit \"$BASE/uploads\""
echo
echo "conda create -n RoboTwin python=3.10 -y && conda activate RoboTwin"
echo "bash \"$BASE/uploads/sim/install_sim_offline.sh\" --kit \"$BASE/uploads\" --robotwin \"$BASE/uploads/sim/RoboTwin\"$BW"
echo
echo "# 提示: 评测装完先验证 Vulkan:  vulkaninfo --summary | grep -A2 'GPU id'"
