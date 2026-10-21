#!/bin/bash
# ============================================================================
# 拉取复现所需的全部外部资源(模型 / tokenizer / 数据 / 团队权重)
#
# 用法:
#   bash download_assets.sh              # 全部拉取
#   bash download_assets.sh base         # 只拉官方基座 lingbot-vla-v2-6b
#   bash download_assets.sh tokenizer    # 只拉 Qwen3-VL-4B-Instruct
#   bash download_assets.sh data         # 只拉训练数据(官方 demo_clean → LeRobot v3.0)
#   bash download_assets.sh team         # 只拉团队中间权重(step6600 等)
#
# 可用环境变量:
#   DEST_ROOT     下载根目录(默认:本脚本所在目录的上级,即提交包根)
#   MODELSCOPE_CLI   modelscope 命令(默认自动探测;没有则回退到直链 wget)
#   HF_ENDPOINT      HuggingFace 镜像(可选,设则优先用 HF)
#
# 说明:
#   * 官方基座与 tokenizer 从 ModelScope 官方仓拉取;
#   * 训练数据是"官方 RoboTwin 2.0 demo_clean 转 LeRobot v3.0"版本,
#     50 任务 × 每任务 50 条 = 2500 eps / 549,787 帧,随机化数据不在其中;
#   * 本次提交的最终权重(hf_ckpt_final_equiv10000)已包含在
#     `03_模型权重/checkpoint/` 内,无需下载;team 段用于取等效 6600 步
#     中间权重(若要从头复现训练,用它作为热启动点)。
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_ROOT="${DEST_ROOT:-$(dirname "$SCRIPT_DIR")}"
WHICH="${1:-all}"

MS_BASE="Robbyant/lingbot-vla-v2-6b"
MS_TOKENIZER="Qwen/Qwen3-VL-4B-Instruct"
MS_TEAM="currytom/lingbotvla-robotwin-radeon-ckpt"
MS_DATA="currytom/robotwin-lerobot-official-joint-v30"

# ---- 自动探测 modelscope CLI ----
find_ms_cli() {
    if command -v modelscope >/dev/null 2>&1; then echo "modelscope"; return; fi
    for c in /root/miniconda3/bin/modelscope /opt/conda/bin/modelscope "$HOME"/.local/bin/modelscope; do
        [ -x "$c" ] && { echo "$c"; return; }
    done
    echo ""
}
MS_CLI="$(find_ms_cli)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

# 用 modelscope CLI 下载;不可用时回退到直链(仅适用于模型仓的文件)
ms_pull_model() {   # $1=owner/name  $2=本地目录
    local repo="$1" dest="$2"
    mkdir -p "$dest"
    if [ -n "$MS_CLI" ]; then
        log "  modelscope download $repo -> $dest"
        "$MS_CLI" download --model "$repo" --local_dir "$dest" && return 0
        log "  CLI 下载失败,回退直链"
    fi
    # 直链回退:逐文件 wget(从仓库文件树 API 列举)
    local owner="${repo%%/*}" name="${repo##*/}"
    local listing; listing="$(curl -s --max-time 60 "https://modelscope.cn/api/v1/models/${owner}/${name}/repo/files?Revision=master&Root=")"
    echo "$listing" | python3 -c "
import json,sys
d=json.load(sys.stdin)
for f in d.get('Data',{}).get('Files',[]):
    p=f.get('Path','')
    if p and not p.endswith('/'):
        print(p)
" | while read -r p; do
        [ -z "$p" ] && continue
        mkdir -p "$dest/$(dirname "$p")"
        wget -q --show-progress -c -O "$dest/$p" \
            "https://modelscope.cn/models/${owner}/${name}/resolve/master/${p}" || true
    done
}

ms_pull_dataset() {  # $1=owner/name  $2=本地目录
    local repo="$1" dest="$2"
    mkdir -p "$dest"
    if [ -n "$MS_CLI" ]; then
        log "  modelscope download --dataset $repo -> $dest"
        "$MS_CLI" download --dataset "$repo" --local_dir "$dest" && return 0
        log "  CLI 下载失败,回退直链"
    fi
    local owner="${repo%%/*}" name="${repo##*/}"
    local listing; listing="$(curl -s --max-time 60 "https://modelscope.cn/api/v1/datasets/${owner}/${name}/repo/tree?Revision=master&Root=")"
    echo "$listing" | python3 -c "
import json,sys
d=json.load(sys.stdin)
def walk(files, prefix=''):
    for f in files:
        p=prefix+f.get('Path','')
        if f.get('Type')=='tree':
            walk(f.get('Files',[]), p)
        elif p:
            print(p)
walk(d.get('Data',{}).get('Files',[]))
" | while read -r p; do
        [ -z "$p" ] && continue
        mkdir -p "$dest/$(dirname "$p")"
        wget -q --show-progress -c -O "$dest/$p" \
            "https://modelscope.cn/datasets/${owner}/${name}/resolve/master/${p}" || true
    done
}

case "$WHICH" in
  base)
    log "拉取官方基座: $MS_BASE"
    ms_pull_model "$MS_BASE" "$DEST_ROOT/assets/models/lingbot-vla-v2-6b"
    ;;
  tokenizer)
    log "拉取 tokenizer: $MS_TOKENIZER"
    ms_pull_model "$MS_TOKENIZER" "$DEST_ROOT/assets/models/Qwen3-VL-4B-Instruct"
    ;;
  data)
    log "拉取训练数据: $MS_DATA (官方 demo_clean → LeRobot v3.0)"
    ms_pull_dataset "$MS_DATA" "$DEST_ROOT/assets/data/robotwin_official_joint_v30"
    ;;
  team)
    log "拉取团队中间权重: $MS_TEAM"
    log "  (最终提交权重 hf_ckpt_final_equiv10000 已在 03_模型权重/checkpoint/ 内)"
    ms_pull_model "$MS_TEAM" "$DEST_ROOT/assets/models/radeon_ckpt"
    ;;
  all)
    bash "${BASH_SOURCE[0]}" base
    bash "${BASH_SOURCE[0]}" tokenizer
    bash "${BASH_SOURCE[0]}" data
    bash "${BASH_SOURCE[0]}" team
    ;;
  *)
    echo "未知参数: $WHICH (可选: all | base | tokenizer | data | team)"; exit 1;;
esac

log "完成。下载根目录: $DEST_ROOT"
echo ""
echo "目录约定(train.sh / eval.sh 默认读取这些位置,可用环境变量覆盖):"
echo "  assets/models/lingbot-vla-v2-6b      官方基座"
echo "  assets/models/Qwen3-VL-4B-Instruct   tokenizer"
echo "  assets/data/robotwin_official_joint_v30  训练数据"
echo "  assets/models/radeon_ckpt            团队中间权重(step6600 等)"
