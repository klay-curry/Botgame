#!/usr/bin/env bash
# 下载 RoboTwin 2.0 Aloha-AgileX 50 任务 clean 数据（每任务 50 条，~25GB zip，解压后 ~40GB）
# 注意赛题规则：只允许 clean 数据训练；randomized 仅用于测试，不要下载 randomized 部分参与训练。
# 用法: bash scripts/download_data.sh
# 默认走 hf-mirror 国内加速；海外环境: HF_ENDPOINT= bash scripts/download_data.sh
set -euo pipefail

ROOT=${ROOT:-data/robotwin2.0}
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

echo "[download_data] 拉取 TianxingChen/RoboTwin2.0 的 aloha-agilex_clean_50 子集 -> $ROOT"
# pip install -U "huggingface_hub[cli]"
huggingface-cli download TianxingChen/RoboTwin2.0 \
  --repo-type dataset \
  --include "dataset/*/aloha-agilex_clean_50.zip" \
  --local-dir "$ROOT"

echo "[download_data] 解压..."
cd "$ROOT/dataset"
for d in */; do
  unzip -q -n "${d}aloha-agilex_clean_50.zip" -d "$d"
  echo "  done: $d"
done

n=$(ls -d */ | wc -l)
echo "[download_data] 完成: $n 个任务。校验应输出 2500:"
find . -path "*/aloha-agilex_clean_50/data/*.hdf5" | wc -l
