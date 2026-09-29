#!/usr/bin/env bash
# 从 Team ModelScope 镜像下载 RoboTwin 2.0 Aloha-AgileX 50 个任务的 clean 数据并解压 (~23GB zip)
# 源仓库: https://modelscope.cn/datasets/currytom/robotwin
# （与 scripts/download_data.sh 内容完全相同，只是源不同；HF 慢/不稳时用这个）
# 用法: bash scripts/download_data_ms.sh
set -euo pipefail

ROOT=${ROOT:-data/robotwin2.0}
REPO=currytom/robotwin

echo "[download_data_ms] 从 ModelScope 拉取 $REPO 的 aloha-agilex_clean_50 子集 -> $ROOT"
# pip install -U modelscope
modelscope download \
  --dataset "$REPO" \
  --include "*/*.zip" \
  --local_dir "$ROOT/dataset"

echo "[download_data_ms] 解压..."
cd "$ROOT/dataset"
for d in */; do
  unzip -q -n "${d}aloha-agilex_clean_50.zip" -d "$d"
  echo "  done: $d"
done

n=$(ls -d */ | wc -l)
echo "[download_data_ms] 完成: $n 个任务。校验应输出 2500:"
find . -path "*/aloha-agilex_clean_50/data/*.hdf5" | wc -l
