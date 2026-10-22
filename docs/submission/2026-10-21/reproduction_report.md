# 复现与调优说明

> **仓库路径说明**：本文中的 `02_代码材料/`、`03_模型权重/` 是竞赛提交包的目录布局。
> 对应到 GitHub 仓库：训练/推理代码在 `ours/`，复现脚本在根目录 `scripts/`，
> 最终权重放在 `assets/models/hf_ckpt_final_equiv10000`。映射见 [README.md](README.md)。

## 1. 基础信息

- **团队名称**：【请替换为实际团队名称】
- **使用模型版本**：LingBot-VLA 2.0(`robbyant/lingbot-vla-v2-6b`,Hugging Face / ModelScope 官方发布版)
- **代码版本 / Commit**：
  - 训练仓 `klay-curry/Botgame` @ `18c5592`(`feat(train): switch to official RoboTwin joint_v30 data (549,787 frames) — resume Radeon 6.6k ckpt`)
  - 仿真仓 `robotwin-Platform/RoboTwin` @ `13c3c47`(官方仓,仅做 §4 所列修复)
  - 官方基座 `robbyant/lingbot-vla-v2-6b`(本轮未改动模型结构,主干自该权重初始化)
- **提交 checkpoint 名称**：`hf_ckpt_final_equiv10000`(目录 `03_模型权重/checkpoint/`)
  - 语义:自官方基座起累计等效 **10000 步**训练后的全量权重(AMD 侧 6600 步 + 本机续训 3400 步 + 收尾 400 步)
  - 权重 SHA-256:
    | 文件 | SHA-256 |
    |---|---|
    | `model-00001-of-00003.safetensors` | `7efc2403f4eee1e89d420c137f8d9db8cd46b44d1076b7ea29790962bcb53ffe` |
    | `model-00002-of-00003.safetensors` | `161085bf7fc1b4f68ca3fc770abae058017199654ba81ed24b368ee9c8ca12b6` |
    | `model-00003-of-00003.safetensors` | `f12af100084f826e26d54e086a7c09fcd6f6b9e4463c30c1f68256ba68b00335` |
    | `config.json` | `10fc3fe280792bc58661e5f9c6df88a7b4022d4fedaab80e74854e32ca7e4d47` |
  - 权重大小 12G,14 个文件;HF 目录可直接被 `transformers`/`lingbotvla` 加载,无需 merge。

## 2. 训练复现

- **使用数据集**:RoboTwin 2.0 Aloha-AgileX **demo_clean** 官方数据,经 `lerobot` v3.0 格式转换为 LeRobot 数据集
  - 来源:官方 `robotwin2-demo-clean-official` → 转换包 `robotwin-lerobot-official-joint-v30`
  - **审计结果:50 个任务 × 每任务 50 条 = 2500 episodes / 549,787 frames(每任务均恰好 50 条,无缺失)**
  - 动作空间:**14 维关节空间**(每臂 7 维 = 6 关节 + 1 夹爪),由官方 hdf5 的 14 维关节轨迹直接转换;相机 `camera_top` / `camera_wrist_left` / `camera_wrist_right`
  - 归一化统计:`configs/robotwin_joint_v30.json`(count=549787),由本数据集重算,`bounds_99_woclip` 口径
  - 训练清单:`configs/training_data/robotwin_joint_v30.txt`(50 行)
- **是否使用 randomized 数据训练**:**否**。训练数据仅含 clean;randomized 仅用于最终评测,未参与训练、未参与归一化统计。
- **一键训练脚本**:`02_代码材料/train.sh`(**两种模式**:本地已有资源时用参数显式指定目录;缺失时脚本自动调用 `03_模型权重/download_assets.sh` 拉取)
  ```bash
  # 模式 A:本地已有
  bash train.sh --base-ckpt <6600步权重> --base-config <基座> --tokenizer <tokenizer> \
                --data <robotwin_official_joint_v30> --repo <训练仓> --out <输出目录>
  # 模式 B:本地缺失 → 自动拉取
  bash train.sh
  ```
- **训练配置文件**:`02_代码材料/configs/vla/robotwin/robotwin.yaml`(模型/MoE/数据管线),命令行覆盖如下超参
- **robot config**:`02_代码材料/configs/robot_configs/robotwin.yaml`
  - `arm.position: 14`、`end.position: 14`、`effector.position: 2`
  - `norm_type: bounds_99_woclip`
- **路径约定**:`train.sh` / `eval.sh` / `download_assets.sh` 的所有默认路径均相对**提交包根目录**(`SUBMISSION_ROOT`)推导,不依赖任何特定机器的目录布局;每个资源也可用同名环境变量或命令行参数覆盖

### 训练配方(等效 10000 步 = 6600 步官方配方 + 本机续训 3400 步 + 收尾 400 步)

| 项 | 取值 |
|---|---|
| 起点 | `lingbot-vla-v2-6b` → 官方 AdamW 配方(global 256、双教师 full、image_augment)训至 6600 步 → 本机续训 |
| 优化器 | **AdamW**(非 Muon) |
| 学习率 | `5e-5` **恒定**(lr_min=5e-5,无 cosine 衰减),warmup_ratio=0.03 |
| 精度 | BF16(`enable_fp32=false`) |
| 梯度检查点 | 开启(`enable_gradient_checkpointing=true`) |
| micro / global batch | micro 24 × 4 卡 = **global 96** |
| 视觉塔 | 解冻(`freeze_vision_encoder=false`) |
| 图像增强 | **开启**(`image_augment=true`) |
| 步数 | 续训 3400 步(计数器从 0 起,因热启动无优化器状态),最后 400 步由 step3000 权重续训补齐 → **等效 10000 步** |
| 实测吞吐 | 3.09 s/步(4 卡),3400 步约 3 小时 |
| 数据加载 | `num_workers=8`,`prefetch_factor=8`(4 卡护栏,见 §5 已知问题) |

## 3. 评测复现

- **一键评测脚本**:`02_代码材料/eval.sh`(**两种模式**:本地已有资源时用参数显式指定目录;缺失时脚本自动调用 `03_模型权重/download_assets.sh` 拉取、并自动克隆官方 RoboTwin)
  ```bash
  # 模式 A:本地已有
  bash eval.sh --model <checkpoint 目录> --sim <RoboTwin 仿真仓> --infer <推理代码仓> --tokenizer <tokenizer 目录>
  # 模式 B:本地缺失 → 自动拉取/克隆
  bash eval.sh
  ```
- **资源拉取脚本**:`03_模型权重/download_assets.sh`(官方基座 `Robbyant/lingbot-vla-v2-6b`、tokenizer `Qwen/Qwen3-VL-4B-Instruct`、训练数据集 `currytom/robotwin-lerobot-official-joint-v30`、团队中间权重 `currytom/lingbotvla-robotwin-radeon-ckpt`);仿真仓由 `02_代码材料/setup_sim_repo.sh` 克隆官方 `robotwin-Platform/RoboTwin@13c3c47` 并叠加本项目增量文件
- **checkpoint 加载方式**:推理服务以 **完整 HF 目录** 加载(`--model <checkpoint 目录>`),权重为全量微调结果,**不需要 merge**。
  - ⚠️ 推理服务会从模型目录上溯 3 级查找 `lingbotvla_cli.yaml`;若直接指向 `03_模型权重/checkpoint/` 报 FileNotFoundError,请复制一份 `lingbotvla_cli.yaml` 到其上溯 3 级目录,或参照 `ol_staging/equiv10000/m/a/b/ckpt` 的目录布局放置 checkpoint。
- **clean setting 评测命令**:
  ```bash
  bash eval.sh --setting demo_clean --tasks 50
  ```
- **randomized setting 评测命令**:
  ```bash
  bash eval.sh --setting demo_randomized --tasks 50
  ```
- **评测环境**(务必与官方复测对齐):
  | 项 | 取值 |
  |---|---|
  | GPU | 6 × NVIDIA RTX 4090(48GB),驱动 595.71.05 / CUDA 13.2 |
  | 推理环境 | conda `lingbotvla`(Python 3.12),torch 2.8.0+cu128 |
  | 仿真环境 | conda `RoboTwin`(Python 3.10.21),torch 2.4.1 / sapien 3.0.0b1 / mplib 0.2.1 / numpy 1.26.4 |
  | 运动规划 | curobo v0.7.8(edit 安装于 `RoboTwin/envs/curobo/src`) |
  | **推理精度** | **BF16**(`--use_bf16 true --use_fp32 false`,`use_compile=true`) |
  | 并发槽位 | 6 卡 × 2 副本/卡 = 12 槽(48GB 卡 bf16 每副本约 18GB,3 副本会 OOM) |
  | seed | 评测客户端按 `100000 + episode 序号` 生成,单 setting 内每个任务 100 局互不重复 |
  | 每任务次数 | **100 次**(`script/eval_policy_client_lingbotvla.py` 中 `test_num = 100`) |
  | 视频 | 全量评测关闭(`--no_video`)；示例回放已用 `--video` 单独录制，见 `../01_评测结果/videos/` |
  | 实测吞吐 | clean 5000 局 8.9 小时;randomized 5000 局 7.3 小时(约 11-13 局/分) |

  > **精度口径说明**:本次自测成绩为 **BF16 推理**。开环 MAE 上 BF16 与 FP32 的差异为 1.9%(0.03565 vs 0.0350,在噪声内),但闭环成功率的 BF16/FP32 差异本次未单独测量;若官方复测采用 FP32,成功率可能与自测值存在差异,特此声明以便评委复现时对齐口径。

### 评测结果

| setting | 任务数 | attempts | successes | 成功率 |
|---|---|---|---|---|
| demo_clean | 50 | 5000 | 2829 | **56.6%** |
| demo_randomized | 50 | 5000 | 1655 | **33.1%** |

逐任务 attempts/successes 见 `../01_评测结果/results.json`;原始逐 episode 日志位置见 §6。

可视化与回放（均在同一目录）：

| 素材 | 文件 |
|---|---|
| 总览面板（总分 / 逐任务 / 退化分析） | `../01_评测结果/eval_results_dashboard.png` |
| 50 任务 × 2 setting 热力图 | `../01_评测结果/eval_results_heatmap.png` |
| 逐任务柱状图 | `../01_评测结果/eval_results_summary.png` |
| 逐任务展开动画 | `../01_评测结果/eval_results_animation.gif` |
| 评测实拍回放（adjust_bottle，3 局并排） | `../01_评测结果/videos/adjust_bottle_success_montage.gif` |
| 单局回放（MP4 / GIF） | `../01_评测结果/videos/adjust_bottle_episode0.{mp4,gif}` |

## 4. 代码改动说明

> 本节列出的改动均为**评测链路适配与并行调度**，不涉及模型结构、损失函数或训练算法；
> 本项目没有对官方模型/代码做算法层面的改进，最终提交的是按官方配方微调的全量权重。

- **是否修改 LingBot-VLA 2.0 官方代码**:**否**(模型结构、损失、优化器实现均未改;仅通过命令行覆盖训练超参)。`deploy/lingbot_vla_v2_policy.py` 为官方推理脚本,本次仅改变调用精度参数。
- **是否修改 RoboTwin 官方评测代码**:**是**,均为不改变评测语义的适配与修复,逐条如下:
  1. `script/eval_policy_client_lingbotvla.py`:**`test_num` 由 30 恢复为 100**(官方 `script/eval_policy_client.py` 即为 100)。此前为内部筛选期临时值,不符合提交协议,已还原。**这是本次提交前修复的关键问题**。
  2. `script/eval_policy_client_lingbotvla.py`:本文件整体为官方客户端的 websocket 适配版(官方为 HTTP);观测/动作序列化沿用官方 `script/deploy/websocket_client_policy.py`。
  3. `script/deploy/{__init__,websocket_client_policy,msgpack_numpy}.py`:由训练仓 `deploy/` 复制,供客户端 import。
  4. `script/update_embodiment_config_path.py`:官方仓自带,被 launcher 调用于重生成 curobo yml 中写死的 urdf 绝对路径(换机器必需)。
  5. 仿真仓资产修复:此前 `envs/`、`policy/LingBot-VLA-v2`、`assets/objects/objaverse/list.json`、`envs/curobo/src` 曾缺失,已按官方仓 `robotwin-Platform/robotwin` 逐一补齐并校验;修复内容为**原文件还原**,未改动任何任务逻辑。
  6. 评测 launcher `start_robotwin_infer_and_eval.sh`:队列调度版并行实现(见 `02_代码材料/README.md` §5.3),**不改变 episode 判定、seed 生成与任务执行顺序语义**,仅把官方逐任务串行改为多槽并发。
- **对应文件位置**:全部见 `02_代码材料/src/`(逐文件可对照)。

## 5. 已知问题与踩坑(供复现者避坑)

1. **BF16 与 FP32 不能同时开**:推理服务有 `assert not (use_bf16 and use_fp32)`,launcher 默认 `use_fp32=True`,若只传 `--use_bf16 true` 会导致**全部推理服务启动即崩溃**(历史批次曾因此空跑)。必须显式 `--use_fp32 false`。
2. **48GB 卡 bf16 只能放 2 个推理副本**(约 18GB/副本)。3 副本在权重加载阶段看似可行(44-48GB),但前向激活叠加后 OOM。48GB 卡用 fp32 时单副本约 32GB,只能 1 副本/卡。
3. **curobo 首槽 JIT 编译 + N 个推理服务加载,启动约需 10 分钟**,属正常现象,不是卡死;日志中的 `JIT compiling` 正常。
4. **4 卡训练必须加内存护栏**:`--data.num_workers=8` + `TORCHINDUCTOR_COMPILE_THREADS=8`。否则 96 个 dataloader 进程 + 各 rank 默认 64 个 inductor 线程会顶爆容器内存限额,出现**无 Python 报错的 SIGKILL**(cgroup oom_kill 计数为 0,极难定位)。
5. **DCP 存档峰值约 84G**(DCP 72G + HF 12G),单次存档期间本地盘必须留出余量;长训建议 `OUTPUT_DIR` 放持久盘,或 `save_steps ≥ 2000`。
6. **清理进程时不要用宽泛的 pkill pattern**(如 `lingbot_vla_v2_policy`),会误杀其他并行 run 的服务;`pkill -f` 还会匹配到自己所在的命令行。
7. 评测吞吐瓶颈在仿真侧(物理步进 + 3 相机渲染),不在 GPU 推理(单次推理 0.2-0.3 s);提高并发只能靠增加"槽位 × 任务并行",单任务内部无法多卡加速。

## 6. 原始日志与结果文件位置

| 内容 | 位置 |
|---|---|
| 官方模板评测结果 | `01_评测结果/results.json` |
| attempts/successes 逐任务审计表(由日志自动生成) | `01_评测结果/audit_attempts_successes.csv` |
| demo_clean 原始逐 episode 日志 | `<持久盘>/output/eval/_0k_demo_clean_20261020_113351/eval_logs/<task>.log` |
| demo_clean 汇总表 | 同上 `stats.txt` |
| demo_randomized 原始日志(分 A/B/C1-C5 五个 run) | `<持久盘>/output/eval/_0k_demo_randomized_20261020_{170237,202926,224329,231259,231319,231339,235803}/eval_logs/<task>.log` |
| demo_randomized 合并汇总表 | `<持久盘>/output/eval/randomized_merged_stats.txt` |
| clean + randomized 双口径汇总 | `<持久盘>/output/eval/FINAL_SUMMARY.txt` |
| 推理服务日志 | 各 run 目录下 `inference_logs/qwenpi_slot*.log` |
| 训练日志与 ckpt 存档 | `<持久盘>/output/ckpt_radeon_cont/`;最终权重转换脚本 `02_代码材料/src/convert_dcp_to_hf.py` |

> 说明:raw 日志体量较大,按团队约定存于云端持久目录,提交包内仅保留定位方式与由其自动生成的汇总/审计文件。

## 7. 调优说明

- **训练参数调整**:
  - 优化器由默认 **Muon 改为 AdamW**,lr 恒定 5e-5(warmup 3%),与前一版基线配方对齐(见 §2 表格);
  - global batch 96(4 卡 × micro 24),BF16 + 梯度检查点开启,视觉塔解冻;
  - 步数从 6600 增到等效 10000 步。
- **数据处理方式**:
  - 统一使用 **官方 joint_v30**(14 维关节空间)数据,而非早期版本 —— 早期版本存在"从就位姿态起步、缺少零位形起步段"的问题,导致闭环从零位形起步时全 OOD、成功率为 0;官方 joint 数据包含零位形起步段,与评测环境初始状态一致,该修复是闭环成功率从 0 提升到 50%+ 的根本原因之一;
  - 归一化统计随数据集重算(不跨数据集混用)。
- **模型结构改动**:**无**。未使用 LoRA/DoRA 等低秩方法,未外挂任何 vision/depth/segmentation 预训练模块,未修改 MoE 结构。因此提交的是**一份可直接加载的全量权重**。
- **推理策略**:**无任何推理期增强**。单权重、单 seed、无多 seed 投票、无 temporal ensemble、无 action smoothing、无 replanning、无按 task ID 路由。每步单次前向,chunk length 50,`use_compile=true`。
- **主要提升点**:
  1. **数据语义对齐(最大贡献)**:改用官方 14 维关节空间数据并保证零位形起步段 → 闭环成功率从 **0%** 量级恢复到 **50%+**;
  2. **步数与配方对齐官方基线**:等效 10000 步 + AdamW/5e-5 恒定 LR + image_augment;
  3. **评测链路完整修复**:BF16/FP32 断言崩溃、48GB 卡副本数 OOM、`test_num` 被改成 30 三处问题修复后,才得到符合协议的完整数据(否则 10-18 批次"50 任务评测"实为空跑)。
  4. **评测吞吐优化**:队列调度 + 12 槽并发 + 分片并行,单机 5000 局从"预计 3.5 天"压到 7-9 小时,为"先做 20 任务对比、再决定全量"争取到了决策窗口。

### 7.1 失败任务与已知限制

- **两个 setting 均低分的任务**(clean → randomized):`stack_blocks_three` 4%→2%、`lift_pot` 48%→6%、`stamp_seal` 29%→6%、`place_mouse_pad` 21%→7%、`put_bottles_dustbin` 19%→8%、`move_can_pot` 11%→9%。
- **randomized 相对 clean 的降幅分布**(整体 56.6%→33.1%):
  - 抓取/倾倒类任务降幅小(adjust_bottle −9、stack_bowls_two −8、shake_bottle −15),说明**动作回归精度不是瓶颈**;
  - 依赖视觉定位/物体辨认的任务降幅大(rotate_qrcode 69%→12% −57、scan_object 71%→29% −42、stack_blocks_two 73%→33% −40、click_alarmclock 67%→35% −32),说明**当前瓶颈在视觉鲁棒性**。
  - 结论:下一轮改进应优先投入视觉侧(更强图像增强、视觉塔针对性增强、目标辨识类数据配比),而非继续堆动作侧训练步数。
- **未完成项**:真机创新可选任务(`05_真机创新可选任务/`)未提供;BF16 与 FP32 的闭环成功率差异未单独测量(见 §3 精度口径说明)。
