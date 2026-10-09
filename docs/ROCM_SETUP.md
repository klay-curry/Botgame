# AMD (ROCm) 机器搭建指引

> 背景：项目原在 3×A800-80GB（CUDA 12.8）上训练/评测；换到 AMD 显卡（ROCm）时，
> **代码本身基本不用改**（PyTorch ROCm 版保留 `torch.cuda.*` API 别名），
> 要换的是环境。本文按"要装什么 / 什么装不上 / 装不上怎么降级"组织。
> 环境版本基准：torch 2.8.0 + transformers 4.57.3 + lerobot 0.4.2（conda py3.12）。

## 1. 训练环境（lingbotvla）

```bash
conda create -n lingbotvla python=3.12 -y && conda activate lingbotvla
# ROCm 版 torch（按机器 ROCm 版本选 index，6.4 为 torch 2.8 官方支持线）
pip install torch==2.8.0 torchvision==0.23.0 torchaudio==2.8.0 \
  --index-url https://repo.download.pytorch.org/whl/rocm6.4
# 其余依赖直接用仓库 requirements（去掉 torch 四件套和 flash-attn）
grep -vE '^(torch|triton)' requirements.txt | pip install -r /dev/stdin
```

| 组件 | NVIDIA 侧 | AMD 侧处理 |
|---|---|---|
| torch 2.8.0 | cu128 wheel | **rocm6.x wheel**（`torch.cuda` API 同名可用，`PYTORCH_CUDA_ALLOC_CONF` 不用改） |
| flash-attn 2.8.3 | cu12 wheel | **不装**。代码无硬 import，transformers 自动回退 SDPA；首跑对比几十步 loss 确认 |
| triton 3.4.0 | NVIDIA wheel | 随 torch-rocm 自带 `pytorch-triton-rocm`；MoE group_gemm 内核理论可用，**先冒烟** |
| curobo | 可装（CUDA-only） | **装不上**，仅影响 RoboTwin 部分任务初始化（见下） |
| bitsandbytes | QLoRA 用 | ROCm 支持仍是实验性，QLoRA 消融先缓 |

## 2. 已知风险点（换卡必测）

1. **MoE triton 内核**：`lingbotvla/ops/group_gemm`、`triton_moe_loss`、`robby_moe`。先跑 20 步训练冒烟，
   报错再定位（可能是 autotune 配置 NVIDIA 专属）。
2. **注意力回退**：A800 上实际未走 FA3（Hopper 专属路径有 try/except）；不装 flash-attn 后
   transformers 走 SDPA，训练前几百步 loss 曲线应与 A800 基线（VLA_Loss 0.32→0.037@2045步）同量级。
3. **单卡训练形态**：原 global 96 = micro 32 × 3 卡。单卡改为 `micro 32 × 累积 3`；
   显存不够（<80GB）先降 micro（16/8）再加累积，梯度检查点保持开。
   `NPROC_PER_NODE` 改 1。

## 3. 评测环境（RoboTwin）

```bash
conda create -n RoboTwin python=3.10 -y && conda activate RoboTwin
```

- **渲染**：SAPIEN 走 Vulkan。NVIDIA 装的是 GRID 驱动那套；AMD 要装
  `vulkan-radeon`（RADV）或 AMDVLK：`apt install vulkan-tools mesa-vulkan-drivers`，
  验证：`vulkaninfo --summary | grep -A2 "GPU id"`。
- **curobo 装不上（CUDA-only）**：`envs/robot/planner.py` 是 try/except 可选导入，
  底层规划走 mplib（CPU）；但**依赖 CuroboPlanner 初始化的任务**会退化或失败，
  闭环冒烟时逐任务确认，必要时把任务列表裁剪到 mplib 可跑的子集。
- 评测启动器：`ours/experiment/robotwin/start_robotwin_infer_and_eval.sh`
  （内部会自动补 `script/`、`policy/ACT/deploy_policy.yml`、`task_config` 软链）。

## 4. 推荐上机顺序

1. 装 ROCm torch + 冒烟：`python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"`
2. SDPA 前向冒烟：加载 step6000 hf_ckpt 跑一次 open_loop 单轨迹
3. 20 步训练冒烟（MoE 内核、Muon、梯度检查点全链路）
4. RoboTwin 闭环 3 任务 smoke（确认 curobo 缺失影响面）
5. 全量流程
