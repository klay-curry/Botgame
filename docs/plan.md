# 蚂蚁灵波具身大模型挑战赛 — 技术方案

> 状态：初版（2026-09-28）。提交截止：**2026-10-26 24:00**，约 4 周。

## 0. 赛题本质（一句话）

在 **RoboTwin 2.0** 仿真基准（Aloha-AgileX 双臂机器人，50 个任务）上，基于官方指定 **LingBot-VLA 2.0 (6B)** 预训练模型做 post-training，50 个任务 co-train 出**一份权重**，在 `clean2clean`（seen 指令）和 `clean2random`（unseen 指令）两个 setting 下各测 100 次闭环仿真，拼成功率。

胜负手不在"造模型"，而在三件事：

1. **把官方 pipeline 完整跑通**（数据准备 → 训练 → 闭环评测），这是大多数队伍的第一道坎；
2. **在规则允许范围内把训练配方和 checkpoint 选择做到位**（数据只有 50 任务 × 50 条 = 2500 条轨迹，过拟合 vs 欠拟合的平衡是核心矛盾）；
3. **评测算力排期**：50 任务 × 100 次 × 2 setting 的闭环仿真非常耗时，测不满就吃亏（官方复测为准），要倒排时间。

## 1. 资源盘点

| 资源 | 状态 |
|---|---|
| 指定模型权重 lingbot-vla-v2-6b | ✅ 已下载 `model/models/Robbyant--lingbot-vla-v2-6b/`（含 depth、dino_video 辅助模块） |
| 官方代码 | https://github.com/robbyant/lingbot-vla-v2 （训练 + 开环评测 + RoboTwin 闭环评测全家桶，基于 VeOmni） |
| 训练数据 | HF `TianxingChen/RoboTwin2.0`，只需下 `aloha-agilex_clean_50` 子集（勿下全量 1.53TB） |
| 赛题规则 / 群 Q&A | `docs/work.md` / `docs/Dingnews.md` |
| 官方代码 | ✅ 已克隆：`lingbot-vla-v2/`（训练+评测）、`RoboTwin/`（仿真环境） |
| 训练数据 | ✅ 已下载并解压到 `data/robotwin2.0/dataset/<task>/aloha-agilex_clean_50/`，50 任务 × 50 条 = 2500 条 hdf5 齐全 |
| 本机 | RTX 4060 Laptop 8GB → 只够代码开发、数据转换调度、远程管理；**训练与评测全部上云** |
| 云算力 | 选项 A：赛事官方 AMD 算力（免费，ROCm + MPLib 评测链路，成绩合法）；选项 B：租 NVIDIA 卡（AutoDL 等，4090/A100/H20/H100）。官方训练配方基于单节点 8×H20 |

## 2. 分阶段计划（4 周）

### 阶段 0：先跑通评测流水线（第 1 周，最优先）

> 为什么评测优先：评测是最大瓶颈，且"能测"才有迭代闭环。训练反而相对简单（官方配置现成）。

1. clone 官方仓库，`bash tools/create_train_env.sh` 建 Python 3.12 + PyTorch 2.8 + flash-attn 环境
2. 搭 RoboTwin 仿真环境（sapien / mplib / cuRobo / open3d，numpy 钉在 1.26.x，RoboTwin 仓库 checkout 到官方指定 commit `13c3c47f...`）
3. 数据准备（按 `experiment/robotwin/README.md`）：
   - 下载 `aloha-agilex_clean_50`（国内建议 hf-mirror）
   - `process_data_pi0.sh <task> aloha-agilex_clean_50 50` → `generate.sh` 转 LeRobot v2.1
   - robot config（`configs/robot_configs/robotwin.yaml`）和归一化统计（`assets/norm_stats/robotwin.json`）官方已给，不用自己算
4. **Smoke test**：用未微调的 base 模型跑 1 个任务 × 10 次闭环，验证推理服务与仿真对接
5. 产出：流水线通了 + 一张基线成功率表

### 阶段 1：基线训练复现（第 1–2 周）

1. 用官方 `configs/vla/robotwin/robotwin.yaml` 做 50 任务 co-train 全量微调
   - 先用 5% 数据 + 少步数验证训练循环能收敛，再上全量
2. 优化器先 AdamW 跑通；再对比官方推荐的 Muon / Distributed Muon（官方称更好但更慢）
3. 训练中每 ~500 步存 checkpoint
4. `scripts/open_loop_eval.py` 开环评测（action error）快速筛 checkpoint，选 2–3 个候选
5. 闭环小规模评测（每任务 20 次）确认方向
6. 产出：基线 ckpt + clean2clean 全量成绩

### 阶段 2：调优冲刺（第 2–4 周，可多组实验并行）

按性价比排序：

1. **训练步数 / 学习率扫描**：2500 条数据极易过拟合，早停和 checkpoint 选择是最大增益点
2. **checkpoint 挑选**：开环指标粗筛 + 闭环验证细筛
3. **规则内数据增强**：颜色/亮度噪声、机器人状态扰动（diffusion 训练加噪天然允许）
4. 优化器 / 调度器 / batch 消融
5. （进阶，有余力再上）模型结构改动：MoE 配置、外挂公开 vision/depth encoder（须在 README 注明来源）；LoRA 合并回基座也允许

**红线自查**（违规直接出局，来自官方 Q&A）：
- ❌ RL、仿真 rollout、重渲染观测、reward 筛选等任何"造新数据"手段
- ❌ randomized 数据参与训练；❌ 任何外部数据
- ❌ 按 task ID / instruction 路由、多模型 ensemble、多 seed 投票、replanning 类确定性增强
- ❌ 起点必须是 lingbot-vla-v2-6b，最终**只能提交一份合并后的全量权重**
- ✅ 允许：视觉/状态增强、模型结构大改（基于该模型初始化）、公开预训练模块（需声明）

### 阶段 3：正式评测与提交（截止前 1 周启动）

1. **FP32 推理**出正式成绩（官方复测口径就是 FP32；BF16 成功率会明显不同，自测口径必须与 README 声明一致）
2. 50 任务 × 100 次 × 2 setting，队列调度多卡并行，**预算 3–5 天纯评测**
3. 提交包（按官方目录模板）：
   - `01_评测结果/results.json`（官方模板）
   - `02_代码材料/`（README、train.sh、eval.sh、configs、src）
   - `03_模型权重/checkpoint/`
   - `04_复现与调优说明/reproduction_report.md`
   - `05_真机创新可选任务/`（可选，不占分值但作筛选参考；视余力决定）

## 3. 资源与时间预算

- **磁盘**：数据子集（数百 GB）+ LeRobot 缓存 + 多个 6B checkpoint（单个 ~12GB×多版本），云主机准备 ≥2TB
- **训练**：官方配方单节点 8×H20；8×A100-80G 可跑（调 per-GPU batch + 梯度累积）；显存紧张可走 LoRA→合并路线
- **评测**：FP32 推理服务单 slot 约 32GB 显存（24GB 卡只能 BF16）；示例用 4–8 卡并行；先测单任务吞吐再倒排开始日期
- **里程碑**：W1 末评测通 + 数据齐 → W2 末基线成绩 → W3 调优实验高峰 → W4 前半正式评测，W4 后半整理提交（10-26 截止）

## 4. 学习路径（第一次做具身/VLA，按顺序）

论文已下载到 `G:\document\papers\Embodied AI\`（论文名命名，每篇配同名导读笔记，笔记内含 arXiv 链接）：

1. `Vision-Language-Action Models Survey` — 快读，建立全局地图（两大动作范式、VLA 结构分类）
2. `RoboTwin 2.0 - Scalable Bimanual Manipulation Benchmark` — 精读评测协议：50 任务、clean/randomized 差异、success 判定、seen/unseen 指令
3. `LingBot-VLA 2.0 - From Foundation to Application` — 精读：MoE action expert、双查询蒸馏、55 维动作空间（对着官方仓库配置看）
4. `RoboTwin Dual-Arm Collaboration Challenge at CVPR 2025` — 各名次队伍方案总结，直接借鉴调优套路
5. `pi0 - ...Flow Model...` + `RDT-1B - Diffusion Foundation Model...` — 连续动作（flow/diffusion）路线两篇代表作，重点读微调章节
6. 背景补充（选读）：`OpenVLA`（离散 token 路线）、`ALOHA-ACT`（双臂+action chunking 源头）、`RoboTwin 1.0`、`LingBot-VLA 1`
7. 本赛官方 Q&A：已整理在 `docs/Dingnews.md`
8. 官方仓库：README → `configs/vla/Training_Config.md` → `lingbotvla/data/vla_data/README.md`（55 维统一动作空间、数据格式）

## 5. 风险清单

| 风险 | 对策 |
|---|---|
| 评测算力不足、测不满 100 次 | 阶段 0 就实测单任务耗时；评测排期倒推；不足时如实记录，官方复测为准 |
| FP32/BF16 成绩差异大 | 自测与提交声明口径统一为 FP32 |
| 2500 条数据过拟合 | 早停、checkpoint 筛选、适度增强，宁可欠拟合保泛化（clean2random 是 unseen 指令） |
| 数据下载慢/失败 | hf-mirror，只下 aloha-agilex_clean_50 子集 |
| 环境兼容性（cuRobo/numpy/驱动） | 严格按官方 commit + 版本钉死；AMD 链路用 MPLib 替代 cuRobo |
| 时间不够 | 调优项按性价比砍，优先保正式评测完整 |
