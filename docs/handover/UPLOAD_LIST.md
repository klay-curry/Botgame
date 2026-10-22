# 需要你下载并上传的清单

> 生成于 2026-09-29。前提：本机 **PyPI 通**（pypi.tuna / pypi.org / download.pytorch.org 都是 200），
> **github.com 不通**（`codeload.github.com` 也只是偶尔通，按不通处理）。
> 所以：**PyPI 上的包不用你传，只有 GitHub 上的东西和 HF 上没有的资源需要你传。**

---

## 一、最紧急：数据转换环境（pi0 / pi05 的 uv 环境）

`policy/pi0/generate.sh` 里的 `uv run .../convert_aloha_data_to_lerobot_robotwin.py`，
导入的是 `lerobot.common.*`（**旧 API**），对应 lerobot 版本 **0.1.0**，不是训练环境里的 0.4.2。
`uv sync` 目前卡在两个地方：GitHub 上的 lerobot 拉不到；`av` 源码编译失败。

| # | 要下载的东西 | 精确地址 / 版本 | 为什么 |
|---|---|---|---|
| 1 | **lerobot 源码 @ 指定 commit** | `https://github.com/huggingface/lerobot/archive/a445d9c9da6bea99a8972daa4fe1fdd053d711d2.tar.gz` | 数据转换的 lerobot 本体，`pi0/pyproject.toml:73` 钉死这个 rev（uv.lock 里是 `lerobot 0.1.0`） |
| 2 | （可选）pi0/pi05 的 git 子模块 | `Physical-Intelligence/aloha`、`Lifelong-Robot-Learning/LIBERO` | 只有跑 openpi 的闭环仿真评测才用；**纯数据转换不需要** |

> `av` **不要下载**，见第五节：换成有预编译 wheel 的版本即可，不用编译。

---

## 二、训练环境（lingbotvla，conda py3.12）——已基本装好

现状：torch 2.8.0+cu128、flash_attn 2.8.3、lerobot 0.4.2、transformers 4.57.3、
moge/mdm/utils3d/pipeline 都在。**重建环境时**才需要这些：

| # | 要下载的东西 | 精确地址 / 版本 | 备注 |
|---|---|---|---|
| 3 | lerobot v0.4.2 源码包 | `https://github.com/huggingface/lerobot/archive/refs/tags/v0.4.2.tar.gz` | `tools/create_train_env.sh:132` 用到；当前环境已装好，重建才需要 |
| 4 | flash-attn wheel | 本机已有：`/root/wheels/flash_attn-2.8.3+cu12torch2.8cxx11abiTRUE-cp312-cp312-linux_x86_64.whl` | 传参 `--flash-attn-wheel` 用，省一次长编译 |

`utils3d`（rev `3fab839`）本机已有源码 `/root/utils3d_src`，`pipeline` 已装好 → **不用再传**。

---

## 三、仿真环境（RoboTwin，conda py3.10）——**目前是空的，一个包都没装**

数据采集和闭环评测都在这个环境。它需要两处 GitHub 源码 + 一次 CUDA 编译：

| # | 要下载的东西 | 精确地址 / 版本 | 备注 |
|---|---|---|---|
| 5 | curobo 源码 | `git clone --branch v0.7.8 --depth 1 https://github.com/NVlabs/curobo.git` | `RoboTwin/script/_install.sh:49`；装完要 `pip install -e . --no-build-isolation` 编译 5 个 CUDA 扩展 |
| 6 | pytorch3d 源码 | `git clone https://github.com/facebookresearch/pytorch3d.git`（用 `stable` 分支） | `_install.sh:5`，编译很慢 |
| — | RoboTwin 仓库本体 | `https://github.com/RoboTwin-Platform/RoboTwin.git`，commit `13c3c47ff4312dd62484bcd51be034af55c062d1` | 本机 `/root/Botgame/RoboTwin` 已有，换机器才需要 |

同步需要的系统包：CUDA Toolkit（nvcc，编译 curobo/pytorch3d 用）、cmake、ninja、libGL/EGL。

---

## 四、其它 baseline 策略（只有要跑那些才需要，可以不传）

| 策略 | 需要的东西 | 地址 |
|---|---|---|
| openvla-oft | transformers 分叉 + dlimp | `https://github.com/moojink/transformers-openvla-oft`、`https://github.com/moojink/dlimp_openvla`（`openvla-oft/pyproject.toml:50,55`） |
| openvla-oft | 仓库本体 | `https://github.com/moojink/openvla-oft.git` |
| openvla-oft | flash-attn 2.5.5（py3.10） | 需预编译 wheel，源码编译很慢 |
| DexVLA / TinyVLA | curobo @ `cca894de9ec74e77a0a4071319c81958991a9108` | `policy/DexVLA/Eval_Tiny_DexVLA_requirements.txt:179` |
| GO-1 | AgiBot-World 仓库 | `https://github.com/OpenDriveLab/AgiBot-World` |
| RDT | 可选 s2wrapper | `https://github.com/bfshi/scaling_on_scales.git` |
| ACT / DP / DP3 | 无 GitHub 需求 | 依赖都在 PyPI |

---

## 五、不用上传的（PyPI 能下），但有两个坑要绕开

**坑 1：`av 14.4.0` 在 PyPI 上只有 sdist、没有任何 wheel。**
（pypi.org 的 JSON 显示该版本只有 1 个文件=sdist；本地 uv.lock 也只记录了 sdist。）
所以 uv 只能源码编译，而本机 ffmpeg 是 **4.4.2**，头文件太老，报
`AVCodecParameters has no member named 'ch_layout'`（PyAV 14.4 要求 ffmpeg ≥ 5.1）。

**不要为此上传 av**，两个更省事的办法（任选）：
- 改用**有预编译 wheel 的 av 版本**：`av 15.0.0` 有 cp311/cp312 的 manylinux wheel，
  清华源直接可下（14.0.1/14.1.0/14.2.0/15.0.0/15.1.0/16.x 都有 wheel；**14.3/14.4 没有**）。
  训练环境用的就是 `av==15.0.0`，保持一致最稳。给 pi0/pi05 加一行
  `[tool.uv] override-dependencies = ["av==15.0.0"]` 即可。
- 或者给系统装 ffmpeg ≥ 5 的开发头文件再编译（不推荐，慢且容易连带出问题）。

**坑 2：`xformers` 版本对不上。**
`lingbot-depth/pyproject.toml:20` 钉 `xformers==v0.0.29.post2`，那是配 torch 2.7 的，
本机是 torch 2.8 / cu128；且该版本没有 cp312 wheel。目前它是用 `--no-deps` 装的，
**环境里根本没装 xformers**。如果要用到 `mdm` 的 DINOv2-RGBD 分支（会 import `xformers.ops`），
要装 **`xformers 0.0.30`**（清华源有 cp312 manylinux wheel）。

另外 RoboTwin 的 `script/requirements.txt` **漏了 `toppra`**，但 `envs/robot/planner.py:7` 等 5 处 import 它；
可参照 `policy/DexVLA/Eval_Tiny_DexVLA_requirements.txt` 里的 `toppra==0.6.3` 补上。

---

## 六、HF / ModelScope 资源（本机已有的不用再传）

**已经有了**：
- `/root/autodl-tmp/lingbot-vla-v2-6b`（24.9G，含 `depth/`、`dino_video/`）
- `/root/autodl-tmp/models/Qwen3-VL-4B-Instruct`（8.3G）
- `/root/autodl-tmp/depth_models/moge2-vitb-normal.pt`（400M）
- `/root/autodl-tmp/robotwin2.0` 原始数据（5.7G）、`robotwin_assets` 资产（16G）
- `/root/autodl-tmp/processed_data`（683M，目前只有 `adjust_bottle` 一个任务×50 条）
- `/root/autodl-tmp/lerobot_cache`（uv 缓存 669M）

**如果要做闭环评测 / 更多任务，还缺**（HF 上拿，本机 hf-mirror 可用）：
- `robbyant/lingbot-vla-v2-6b-robotwin` 的 `checkpoints/global_step_50000/hf_ckpt`
- lingbot-depth 预训练权重
- RoboTwin 其它任务的原始数据（`TianxingChen/RoboTwin2.0`）

---

## 七、系统包（apt / 官方源，本机 apt 可用）

`ffmpeg`、`cmake`、`ninja-build`、`build-essential`、`libgl1`/`libegl1`（open3d/moderngl/pyglet）、
CUDA Toolkit 12.8（`/usr/local/cuda-12.8` 已存在，编译 curobo/pytorch3d 要用）。

---

## 八、本地待修的问题（**不需要下载任何东西**）

1. **训练环境被 MoGe 顶掉了版本**：`tools/create_train_env.sh:161` 是
   `pip install -e ".../MoGe"`，**没有 `--no-deps`**，于是 MoGe 里不钉版本的
   `numpy/opencv-python/huggingface_hub/gradio` 把训练 pin 覆盖了。
   实测后果：numpy 变成 **2.2.6**（要求 1.26.4）、`opencv-python-headless` 被换成
   `opencv-python 5.0.0`、还装进了 gradio 6.28。
   修法：给那一行加 `--no-deps`，然后 `pip install -r requirements.txt` 恢复 pin。
2. `create_train_env.sh:151-159` 写的 `.pth` 指向
   `.../morgbd_clean/3rd/utils3d`，该目录**在仓库里不存在**；实际 utils3d 在 `/root/utils3d_src`。
3. `ours/` 是 `lingbot-vla-v2/` 的副本，但**缺 `lingbotvla/data/` 整个包**，以及
   `MoGe/moge/model/`、`lingbot-depth/mdm/model/` 两个子目录 → 直接跑 `ours/scripts/*.py` 会 ImportError。
4. 本机 `RoboTwin` 与 `RoboTwin/data`、`RoboTwin/assets` 是**指向 `/root/autodl-tmp/` 的符号链接**，
   不在仓库里；换机器时这两处要一起搬。

---

## 上传方式建议

传到 `/root/autodl-tmp/uploads/`，文件名保持原样（例如
`lerobot-a445d9c9da6bea99a8972daa4fe1fdd053d711d2.tar.gz`、`curobo-v0.7.8.zip`、`pytorch3d-stable.zip`）。
我会把它们接到本地路径上：把 `pi0/pyproject.toml` 的
`lerobot = { git = "...", rev = "..." }` 改成 `lerobot = { path = "/root/autodl-tmp/uploads/lerobot-..." }`，
再加 `av==15.0.0` 的 override，然后 `uv sync` 就能在不碰 GitHub 的情况下装完。
