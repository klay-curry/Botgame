#!/bin/bash
# ============================================================================
# 准备 RoboTwin 2.0 仿真仓：克隆官方仓库并钉死 commit
#
#   bash scripts/setup_sim_repo.sh                # 安装到 <repo>/RoboTwin
#   bash scripts/setup_sim_repo.sh /path/RoboTwin # 安装到指定目录
#
# 官方仓：https://github.com/robotwin-Platform/RoboTwin
# 固定 commit：13c3c47（与本次评测所用版本一致）
#
# 说明：
#   * 本仓库不修改 RoboTwin 的任务定义 / 成功判定 / 随机化 / seed 逻辑。
#   * 评测客户端与 websocket 通信依赖由 eval.sh 调用的 launcher 自动复制到
#     RoboTwin/script/，无需手工叠加。
#   * 官方 assets（objects 等，约 16G）不进入 git，需执行官方下载脚本。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-$REPO_ROOT/RoboTwin}"
REPO_URL="https://github.com/robotwin-Platform/RoboTwin.git"
COMMIT="13c3c47"

if [ ! -d "$TARGET/.git" ]; then
    echo "克隆官方 RoboTwin -> $TARGET"
    git clone "$REPO_URL" "$TARGET"
else
    echo "已存在仿真仓：$TARGET（跳过 clone）"
fi

cd "$TARGET"
if ! git rev-parse --verify --quiet "$COMMIT" >/dev/null; then
    echo "拉取 commit $COMMIT ..."
    git fetch --depth 1 origin "$COMMIT" || git fetch origin
fi
git checkout "$COMMIT" 2>/dev/null || git checkout -b "eval-$COMMIT" "$COMMIT"
echo "RoboTwin 当前版本：$(git rev-parse --short HEAD)"

echo ""
echo "完成。后续步骤（首次安装）："
echo "  1) cd $TARGET && bash script/_install.sh          # 安装 sapien/curobo 等仿真依赖"
echo "  2) bash script/_download_assets.sh                # 下载官方资产（约 16G）"
echo "  3) 回到仓库根目录运行 bash scripts/eval.sh        # 评测（自动接推理服务）"
