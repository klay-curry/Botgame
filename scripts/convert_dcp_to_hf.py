#!/usr/bin/env python
"""把 trainer 的 model-only DCP 存档离线转换为 HF 权重目录。

评测服务直接加载 HF 目录（完整权重，无需 merge），所以训练结束后需要这一步。

用法：
  python scripts/convert_dcp_to_hf.py <config.yaml> <dcp_dir> <out_dir> [额外覆盖参数...]

示例：
  python scripts/convert_dcp_to_hf.py \
    ours/configs/vla/robotwin/robotwin.yaml \
    output/ckpt/checkpoints/global_step_3000 \
    output/ckpt/hf_ckpt_step3000 \
    --train.output_dir=output/ckpt
"""
import argparse
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "ours"))

import torch  # noqa: E402,F401

from lingbotvla.checkpoint import ckpt_to_state_dict  # noqa: E402
from lingbotvla.models import build_processor, save_model_weights  # noqa: E402
from lingbotvla.models.config_registry import get_config_registry  # noqa: E402
from lingbotvla.utils.arguments import parse_args  # noqa: E402
from tasks.vla.train_lingbotvla import Arguments  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("config", help="训练配置 yaml（如 ours/configs/vla/robotwin/robotwin.yaml）")
    parser.add_argument("dcp_dir", help="DCP 存档目录（.../checkpoints/global_step_XXXX）")
    parser.add_argument("out_dir", help="输出 HF 权重目录")
    parser.add_argument("extra", nargs=argparse.REMAINDER,
                        help="额外的 train 覆盖参数，如 --train.output_dir=/path")
    cli = parser.parse_args()

    os.environ["DCP_DIR"] = cli.dcp_dir
    os.environ["OUT_DIR"] = cli.out_dir
    sys.argv = [sys.argv[0], cli.config, *cli.extra]

    ns = parse_args(Arguments)
    config_kwargs = {**vars(ns.model), **vars(ns.train)}
    registry = get_config_registry()
    config_cls = registry.get_config_cls_from_config_key(ns.model.config_key)(**config_kwargs)

    ckpt_dir = os.environ["DCP_DIR"]
    out_dir = os.environ["OUT_DIR"]

    print(f"[1/3] loading DCP state dict from {ckpt_dir} ...", flush=True)
    state_dict = ckpt_to_state_dict(
        save_checkpoint_path=ckpt_dir,
        output_dir=ns.train.output_dir,
        ckpt_manager="dcp",
    )

    print(f"[2/3] building processor from {ns.model.tokenizer_path} ...", flush=True)
    processor = build_processor(ns.model.tokenizer_path)

    print(f"[3/3] saving HF weights to {out_dir} ...", flush=True)
    save_model_weights(out_dir, state_dict, model_assets=[config_cls, processor])
    print("done.", flush=True)


if __name__ == "__main__":
    main()
