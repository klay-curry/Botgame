#!/bin/bash
# ============================================================================
# 拉取复现所需的全部外部资源（官方基座 / tokenizer / 训练数据 / 团队中间权重）
#
# 用法：
#   bash scripts/download_assets.sh                 # 全部拉取
#   bash scripts/download_assets.sh base tokenizer  # 只拉指定项（可多选）
#   bash scripts/download_assets.sh data            # 官方 demo_clean → LeRobot v3.0
#   bash scripts/download_assets.sh team            # 团队中间权重（默认只拉 step6600）
#
# 可选环境变量：
#   DEST_ROOT      资源根目录（默认：仓库根）
#   TEAM_INCLUDE   团队权重拉取范围（默认 "hf_ckpt_step6600/*"；设 "*" 拉全部）
#   HF_ENDPOINT    HuggingFace 镜像（可选；设置后优先走 HF CLI）
#
# 落地目录（train.sh / eval.sh 默认读取）：
#   assets/models/lingbot-vla-v2-6b          官方基座（约 25G）
#   assets/models/Qwen3-VL-4B-Instruct       tokenizer
#   assets/data/robotwin_official_joint_v30  训练数据（2500 eps / 549,787 帧）
#   assets/models/radeon_ckpt/hf_ckpt_step6600  复现训练的 6600 步热启动点
#
# 注意：最终提交权重 hf_ckpt_final_equiv10000（12G）未上传 ModelScope，
#       随竞赛提交包提供；解压到 assets/models/hf_ckpt_final_equiv10000 即可评测。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEST_ROOT="${DEST_ROOT:-$REPO_ROOT}"
TEAM_INCLUDE="${TEAM_INCLUDE:-hf_ckpt_step6600/*}"

MS_BASE="Robbyant/lingbot-vla-v2-6b"
MS_TOKENIZER="Qwen/Qwen3-VL-4B-Instruct"
MS_TEAM="currytom/lingbotvla-robotwin-radeon-ckpt"
MS_DATA="currytom/robotwin-lerobot-official-joint-v30"

find_ms_cli() {
    if command -v modelscope >/dev/null 2>&1; then echo "modelscope"; return; fi
    for c in /root/miniconda3/bin/modelscope /opt/conda/bin/modelscope "$HOME"/.local/bin/modelscope; do
        if [ -x "$c" ]; then echo "$c"; return; fi
    done
    echo ""
}
MS_CLI="$(find_ms_cli)"
log() { echo "[$(date '+%H:%M:%S')] $*"; }

# 逐文件直链下载（modelscope CLI 不可用时的兜底）
ms_pull_direct() {   # $1=owner/name  $2=dest  $3=model|dataset  $4=include glob
    local repo="$1" dest="$2" kind="$3" include="${4:-*}"
    local owner="${repo%%/*}" name="${repo##*/}"
    local api
    if [ "$kind" = "dataset" ]; then
        api="https://modelscope.cn/api/v1/datasets/${owner}/${name}/repo/tree?Revision=master&Root="
    else
        api="https://modelscope.cn/api/v1/models/${owner}/${name}/repo/files?Revision=master&Root="
    fi
    curl -s --max-time 60 "$api" | python3 -c "
import fnmatch, json, sys
include = sys.argv[1]
d = json.load(sys.stdin)
files = d.get('Data', {}).get('Files', [])
paths = []
def walk(items, prefix=''):
    for f in items:
        p = prefix + f.get('Path', '')
        if f.get('Type') in ('tree', 'dir'):
            walk(f.get('Files', []), p)
        elif p:
            paths.append(p)
walk(files)
for p in paths:
    if include == '*' or fnmatch.fnmatch(p, include):
        print(p)
" "$include" | while read -r p; do
        [ -z "$p" ] && continue
        mkdir -p "$dest/$(dirname "$p")"
        wget -q --show-progress -c -O "$dest/$p" \
            "https://modelscope.cn/${kind}s/${owner}/${name}/resolve/master/${p}" || true
    done
}

ms_pull_model() {   # $1=repo  $2=dest  $3=include glob
    local repo="$1" dest="$2" include="${3:-*}"
    mkdir -p "$dest"
    if [ -n "$MS_CLI" ]; then
        log "  modelscope download --model $repo (include=${include}) -> $dest"
        "$MS_CLI" download --model "$repo" --include "$include" --local_dir "$dest" && return 0
        log "  CLI 下载失败，回退直链"
    fi
    ms_pull_direct "$repo" "$dest" model "$include"
}

ms_pull_dataset() {  # $1=repo  $2=dest
    local repo="$1" dest="$2"
    mkdir -p "$dest"
    if [ -n "$MS_CLI" ]; then
        log "  modelscope download --dataset $repo -> $dest"
        "$MS_CLI" download --dataset "$repo" --local_dir "$dest" && return 0
        log "  CLI 下载失败，回退直链"
    fi
    ms_pull_direct "$repo" "$dest" dataset '*'
}

pull_base() {
    log "拉取官方基座: $MS_BASE"
    ms_pull_model "$MS_BASE" "$DEST_ROOT/assets/models/lingbot-vla-v2-6b" '*'
}

pull_tokenizer() {
    log "拉取 tokenizer: $MS_TOKENIZER"
    ms_pull_model "$MS_TOKENIZER" "$DEST_ROOT/assets/models/Qwen3-VL-4B-Instruct" '*'
}

pull_data() {
    log "拉取训练数据: $MS_DATA（官方 demo_clean → LeRobot v3.0）"
    ms_pull_dataset "$MS_DATA" "$DEST_ROOT/assets/data/robotwin_official_joint_v30"
}

pull_team() {
    log "拉取团队中间权重: $MS_TEAM（include=${TEAM_INCLUDE}）"
    ms_pull_model "$MS_TEAM" "$DEST_ROOT/assets/models/radeon_ckpt" "$TEAM_INCLUDE"
    log "  最终提交权重 hf_ckpt_final_equiv10000 不在 ModelScope，随提交包提供。"
}

WHICH=("$@")
if [ ${#WHICH[@]} -eq 0 ]; then
    WHICH=("all")
fi

for item in "${WHICH[@]}"; do
    case "$item" in
        all)       pull_base; pull_tokenizer; pull_data; pull_team ;;
        base)      pull_base ;;
        tokenizer) pull_tokenizer ;;
        data)      pull_data ;;
        team)      pull_team ;;
        *) echo "未知参数: $item（可选: all | base | tokenizer | data | team）"; exit 1 ;;
    esac
done

log "完成。资源根目录: $DEST_ROOT"
echo ""
echo "目录约定（train.sh / eval.sh 默认读取，可用环境变量覆盖）："
echo "  assets/models/lingbot-vla-v2-6b             官方基座"
echo "  assets/models/Qwen3-VL-4B-Instruct          tokenizer"
echo "  assets/data/robotwin_official_joint_v30     训练数据"
echo "  assets/models/radeon_ckpt/hf_ckpt_step6600  团队 6600 步权重"
echo "  assets/models/hf_ckpt_final_equiv10000      最终权重（从提交包解压，非下载）"
