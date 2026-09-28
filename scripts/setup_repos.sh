#!/usr/bin/env bash
# 克隆赛事官方依赖仓库并钉死版本（团队所有人环境一致）
# GitHub 直连失败时（国内网络）：HTTPS_PROXY=http://127.0.0.1:7890 bash scripts/setup_repos.sh
# 或改用镜像前缀: https://ghfast.top/https://github.com/...
set -euo pipefail

ROBOTWIN_COMMIT=13c3c47ff4312dd62484bcd51be034af55c062d1

if [ ! -d lingbot-vla-v2 ]; then
  echo "[setup_repos] clone lingbot-vla-v2（训练 + 评测代码）"
  git clone https://github.com/robbyant/lingbot-vla-v2.git
else
  echo "[setup_repos] lingbot-vla-v2 已存在，跳过"
fi

if [ ! -d RoboTwin ]; then
  echo "[setup_repos] clone RoboTwin（仿真环境）"
  git clone https://github.com/robotwin-Platform/RoboTwin.git
else
  echo "[setup_repos] RoboTwin 已存在，跳过"
fi

echo "[setup_repos] RoboTwin checkout 到 lingbot-vla-v2 官方指定的 commit"
git -C RoboTwin checkout "$ROBOTWIN_COMMIT"

echo "[setup_repos] 完成。当前 RoboTwin commit:"
git -C RoboTwin rev-parse HEAD
