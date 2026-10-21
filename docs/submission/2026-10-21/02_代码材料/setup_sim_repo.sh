#!/bin/bash
# ============================================================================
# 准备 RoboTwin 仿真仓:克隆官方仓库(指定 commit)+ 叠加本项目增量文件
#
# 用法:
#   bash setup_sim_repo.sh                # 装到 ../src/RoboTwin
#   bash setup_sim_repo.sh <目标目录>      # 装到指定目录
#
# 官方仓:https://github.com/robotwin-Platform/RoboTwin
# 固定 commit:13c3c47(与本次评测所用版本一致)
#
# 叠加内容(src/RoboTwin_overlay/):
#   script/eval_policy_client_lingbotvla.py  评测客户端(websocket 版;test_num=100)
#   script/deploy/{__init__,websocket_client_policy,msgpack_numpy}.py  通信依赖
#   script/update_embodiment_config_path.py   curobo yml 绝对路径重生成(官方文件,随包提供)
#
# 注:官方 assets/objects 资产体积约 16G,由官方仓的 _download_assets.sh 单独下载,
#     不随本提交包分发。
# ============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUBMISSION_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET="${1:-$SUBMISSION_ROOT/src/RoboTwin}"
OVERLAY="$SUBMISSION_ROOT/src/RoboTwin_overlay"
REPO_URL="https://github.com/robotwin-Platform/RoboTwin.git"
COMMIT="13c3c47"

if [ ! -d "$TARGET" ]; then
    echo "克隆官方 RoboTwin → $TARGET"
    git clone "$REPO_URL" "$TARGET"
fi

cd "$TARGET"
if ! git rev-parse --verify "$COMMIT" >/dev/null 2>&1; then
    echo "拉取 commit $COMMIT ..."
    git fetch --depth 1 origin "$COMMIT" || git fetch origin
fi
git checkout "$COMMIT" 2>/dev/null || git checkout -b "eval-$COMMIT" "$COMMIT" || true
echo "RoboTwin 当前版本: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"

echo "叠加本项目增量文件 ..."
mkdir -p "$TARGET/script/deploy"
cp -r "$OVERLAY/." "$TARGET/"

echo ""
echo "完成。仿真仓位置: $TARGET"
echo "下一步:"
echo "  1) cd $TARGET && bash script/_install.sh        # 安装仿真依赖(curobo v0.7.8 等)"
echo "  2) bash script/_download_assets.sh              # 下载官方资产(约 16G)"
echo "  3) 用 eval.sh 评测(会自动重生成 curobo yml 中的 urdf 绝对路径)"
