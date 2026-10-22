# 上传清单 v2（2026-09-29 重列）

> 本清单完全基于**离线核对**（uv.lock / pip list / uv 本地缓存 / 本地源码），生成时未下载任何东西。
> 上一版 github_deps_20260929.zip 已解压到 `/root/autodl-tmp/uploads/`（lerobot×2、pytorch3d、
> RoboTwin、aloha、LIBERO、openvla-oft×3、flash_attn 2.5.5 cp310、curobo(cca894de)、AgiBot-World、
> s2wrapper 均已收到）。
> 结论先说：**训练环境不缺包；RoboTwin 仿真缺 4 项（都很小）；pi0/pi05 转换环境缺 53 项 / 4.39 GB。**

---

## 一、pi0/pi05 数据转换环境（openpi，uv + py3.11）——缺 53 项，共 4.39 GB

好消息：uv 缓存（`/root/.cache/uv`，1.6G）已覆盖 uv.lock 290 个包中的 **226 个**，所以只需补 53 项。

**已生成两个清单文件（在 `/root/autodl-tmp/uploads/`）：**
- `PI0_ENV_URLS.txt` —— 每行一个**精确 wheel URL**（linux x86_64 / cp311，tsinghua 源），可直接 `wget -i` 批量下
- `PI0_ENV_REQS.txt` —— `name==version` 形式，供 `pip download` 用

**体积大头（前 10）：**

| 包 | 体积 |
|---|---|
| torch==2.6.0 | 767 MB |
| nvidia-cudnn-cu12==9.1.0.70 | 665 MB |
| open3d==0.19.0 | 448 MB |
| nvidia-cublas-cu12==12.4.5.8 | 363 MB |
| triton==3.2.0 | 253 MB |
| nvidia-cufft / cusparse / nccl / cusparselt / cusolver | 依次 211 / 208 / 189 / 150 / 128 MB |
| jax-cuda12-pjrt==0.5.0 + jaxlib==0.5.0 | 103 + 102 MB |
| 其余（sapien、rerun-sdk、opencv×2、mujoco、wandb、numpy、tensorstore、transformers、matplotlib、ruff…） | 均 < 65 MB |

**下载方式（两种任选）：**
```bash
# A) 如果你的下载机是 Linux x86_64 + Python 3.11（最省事）
mkdir -p pi0_wheels && pip download -d pi0_wheels -r PI0_ENV_REQS.txt

# B) 否则直接按 URL 抓（tsinghua 源，国内可直连）
mkdir -p pi0_wheels && wget -i PI0_ENV_URLS.txt -P pi0_wheels/
```

**⚠ av 需单独处理**：lock 里的 `av==14.4.0` 在 PyPI **只有 sdist 且本机 ffmpeg 4.4 编不过**。
已在 `policy/pi0/pyproject.toml` 和 `policy/pi05/pyproject.toml` 中加了
`[tool.uv] override-dependencies = ["av==15.0.0"]`（有预编译 wheel）。
请额外下载：`av==15.0.0` 的 **cp311 manylinux wheel**（例如
`pip download av==15.0.0 --only-binary=:all: --python-version 311 --implementation cp --abi cp311 --platform manylinux2014_x86_64`），
清单里的 av==14.4.0 sdist 可以不下。

**到货后我会做**：把 wheelhouse 挂成本地源，离线完成 `uv sync`（注：pyproject 已改 lerobot→本地路径 +
av override，lock 需要重解析，会用 wheelhouse + 本地缓存离线完成），然后实跑一次转换验证。

---

## 二、RoboTwin 仿真环境（py3.10）——只缺 4 项（都小）

| # | 要下载的 | 精确版本/地址 | 为什么 |
|---|---|---|---|
| 1 | **curobo 源码 v0.7.8** | `https://github.com/NVlabs/curobo/archive/refs/tags/v0.7.8.tar.gz` | 官方 `script/_install.sh:49` 要 v0.7.8；之前上传的 zip 是 DexVLA 用的 `cca894de`，版本不对 |
| 2 | **warp-lang** | `warp-lang==1.12.0`，**cp310 manylinux wheel** | curobo 硬依赖（setup.cfg: `warp-lang>=0.9.0`），官方脚本钉 1.12.0 |
| 3 | **usd-core** | 任意较新版本（py3-none-manylinux wheel） | curobo `setup.cfg:93` 声明的依赖（`from pxr import ...` 在 10 处 / 2 个文件） |
| 4 | **setuptools** | `setuptools==69.5.1`（py3-none-any） | 环境里现在是 83.0.0，`pkg_resources` 已被移除 → `import sapien` 直接报 `No module named 'pkg_resources'` |

其余**全齐**：`script/requirements.txt` 逐条核对 0 不符（torch 2.4.1 / sapien 3.0.0b1 / mplib 0.2.1 /
open3d 0.18.0 / gymnasium 0.29.1 / toppra 0.6.10 / av 17.1.0…），sapien+mplib 官方补丁已打。
pytorch3d 按官方脚本本就跳过（评测有 try/except 兜底），**不需要**。

---

## 三、训练环境 lingbotvla（py3.12）——不缺任何包 ✅

逐条核对 `requirements.txt`：**0 项缺失**，仅有 2 处版本号后缀差异（`torch 2.8.0+cu128`、
`torchvision 0.23.0+cu128`，本地 CUDA 变体，属正确状态）。

本轮已完成的修复（都在本地，无下载）：
1. 恢复被 MoGe 顶掉的 pin：numpy→1.26.4、opencv-python(5.0)→卸载并重装 opencv-python-headless 4.11.0.86；
2. `tools/create_train_env.sh`：MoGe 安装行加 `--no-deps`、`.pth` 改指 `/root/utils3d_src`（原指向仓库里不存在的目录）；
3. `ours/` 补齐缺失的三个目录（`lingbotvla/data`、`MoGe/moge/model`、`lingbot-depth/mdm/model`）；
4. 验证通过：torch 2.8.0+cu128(CUDA True)、flash_attn 2.8.3、lerobot 0.4.2、cv2 4.11、
   utils3d、moge.model、mdm.model、pipeline 全部可导入。

**可选**（只有使用 mdm 的 DINOv2-RGBD 分支才需要）：`xformers==0.0.30`（cp312 manylinux wheel）。

---

## 四、HF 权重（评测/训练要用；本机 hf-mirror 可用，你若直接下好传上来也行）

| 用途 | 仓库 | 文件 | 状态 |
|---|---|---|---|
| 深度模型（训练/评测） | `Robbyant/lingbot-depth-pretrain-vitl-14` | `model.pt` | 缺（代码里 `hf_hub_download(filename="model.pt")`） |
| 深度模型（后训练版） | `Robbyant/lingbot-depth-postrain-dc-vitl14` | `model.pt` | 缺（同上） |
| 评测用 VLA ckpt | `robbyant/lingbot-vla-v2-6b-robotwin` | `checkpoints/global_step_50000/hf_ckpt` | 缺（本地只有基座 `lingbot-vla-v2-6b`） |
| 更多任务原始数据 | `TianxingChen/RoboTwin2.0` | 按任务 | 本地已有 51 个任务，够不够看你训练计划 |

已有、**不用再传**：`lingbot-vla-v2-6b`(24.9G)、`Qwen3-VL-4B-Instruct`、`moge2-vitb-normal.pt`、
`robotwin_assets`(16G)、`robotwin2.0` 原始数据(5.7G)、`processed_data`。

---

## 五、可选 baseline（只有要跑这些策略才需要，暂不展开）

仓库本体上一批都已到货（openvla-oft 三件套、GO-1/AgiBot-World、RDT 的 s2wrapper、DexVLA 用的 curobo）。
每个 baseline 还要各自的独立环境（各自钉 torch 版本），要跑哪个我再单独列依赖。

---

## 六、回答：为什么需要两套 conda 环境？是强制的吗？

**是硬冲突，不是随意拆的：**

| | 训练 lingbotvla | 仿真 RoboTwin |
|---|---|---|
| Python | 3.12 | 3.10（官方） |
| torch | 2.8.0+cu128 | 2.4.1（官方 requirements 钉死） |
| 关键扩展 | flash_attn 2.8.3（按 torch 2.8 ABI 编译的 cp312 wheel） | curobo CUDA 扩展（编译时绑定当前 torch） |
| 其它钉死 | lerobot 0.4.2 / transformers 4.57.3 | sapien 3.0.0b1 / mplib 0.2.1 / open3d 0.18.0 / scipy 1.10.1 |

Python 版本、torch 版本、flash-attn 与 curobo 的 CUDA 扩展 ABI 三重冲突：合并必须推翻一边的全部
pin（把训练降到 2.4.1，或把仿真抬到 2.8），两边都会连带崩。官方 RoboTwin 安装脚本自己也是建独立
py3.10 环境 —— 分开是既定设计。

**另外还有第三套**（pi0/pi05）：它用的 lerobot 是 **0.1.0 旧 API**（`lerobot.common.*`），与训练环境的
lerobot **0.4.2 同包名、API 不兼容**，也不能共存于同一环境 —— 这就是那套 uv 环境存在的原因。

---

## 附：系统盘现状（本轮已处理）

- 系统盘 `/` 从 27G 用满（87%）→ **1.6G（6%）**；代码/环境/缓存实体全部迁到 `/root/autodl-tmp`，
  原路径（`/root/miniconda3`、`/root/Botgame`、`/root/.cache`、`/root/wheels`、`/root/utils3d_src`）
  以软链接保持原样，命令和脚本不用改。
