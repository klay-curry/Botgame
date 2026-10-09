# 训练进行中状态(2026-10-02 16:07 启动) → ✅ 训练已完成,评测诊断见下方 10-08 节

## 🟢 2026-10-08 14:50 更新:重训=baseline,夜间流水线已自动化(队友离线,当前由 ZCode+用户推进)
- **定位**:本次 9000 步重训 = **消融基线 baseline**(用户确认,不必训到完美,接近收敛即可横向对比)
- **进度**:Step 2045/9000 @14:46,VLA_Loss 0.32→0.037,5.68s/步;日志 `/tmp/train_joint.log`
- **⚠️ 计划变更(15:04)**:改为 **6000 步停训 ≈ 1.05 epoch**(用户要求"先训 1 epoch";1 epoch=5717 步但存档点只在 2000/4000/6000,6000 是最近的完整存档)。watcher `/tmp/stop_at_6000.sh` 在 step6000 hf_ckpt 完整落盘后自动 kill 训练(预计 ~21:05),夜间流水线自动接手筛 2000/4000/6000(=0.35/0.7/1.05 epoch 曲线)→ 最优进闭环。代价:无 8000/9000 点;停后 optimizer 被守护清掉,如需延长只能从 hf_ckpt 权重重启(非严格续训)
- **夜间流水线**(`/tmp/overnight_pipeline.sh`,日志 `/tmp/overnight_pipeline.log`,waiter 已 setsid):
  等训练退出 → 对 2000/4000/6000 ckpt 开环筛选(新 joint 数据集上 15 个均匀 episode,单进程一次加载,~4min/ckpt)→ 按 MAE 选最优 → 自动启动 20任务闭环(3卡,`/tmp/closed_loop_joint.log`),预计今晚 ~21:45 启动闭环
- **✅ 21:25 夜间流水线全部按计划执行**:6000 步自动停训(21:01)→ 开环筛 step6000(21:06)→ 闭环已启动(21:06,run 目录 `ckpt_6k_demo_clean_20261008_210621`)
- **步数消融曲线(开环 MAE,新joint数据 15 均匀episode)**:2000步=0.0501 / 4000步=0.0323 / 6000步=0.0248 —— 4000→6000 仍 -23%,未完全平台;若明天闭环不理想可考虑基线延到 2epoch
- **闭环早期成功率(step6000,21:25 时点)**:lift_pot 6/18=33%、hanging_mug 2/10=20%、stack_bowls_three 5/10=50%(合计 ~34%)——**对比旧模型同三任务 0/62,数据修复完全生效**;完整 20任务×100ep 明天中午-傍晚出
- ⚠️ 流程教训:磁盘守护把非最新 ckpt 本地副本删了导致流水线只筛到 6000;已停守护、从 fs 拉回 2000/4000 补筛;守护暂停中,**下次开训前记得重启**(并注意同名 .done 问题已通过腾空目录解决)
- **免费消融**:本次 2000→9000 五个存档点 = 训练步数消融曲线;若 6000 步 MAE≈9000 步,后续消融可统一用 6000 步预算(~10h/条)省 1/3 时间
- **消融路线图建议**(每次只动一个变量,开环快筛→胜者进闭环):
  1. 步数曲线(本次免费获得) 2. LR/调度(warmup+cosine vs 恒定) 3. LoRA vs 全参 4. EMA 5. 数据增强(旧 eef 包的 aug 版思路)
  ⚠️ 开环只是快筛(自洽性指标),一切结论以闭环成功率为准(20任务 smoke,~11-21h)
- **LoRA 变体清单(2026-10-08 补,环境已确认: peft 0.15.2 可用;QLoRA 需另装 bitsandbytes)**:
  统一口径:同预算(6000 步 ≈1.05epoch @global96)、同数据同 norm;评测前必须 **merge 回底座**(开环/闭环都按完整 HF 目录加载,merge 脚本待写);开跑前先 20min 速测定 LoRA 实际步时/显存(方法同七组基准)
  - 第一梯队(低成本、高概率有效):
    1. **标准 LoRA 基线**: r=32, alpha=64, target=attn(q,k,v,o)+MLP, LR 1e-4 —— 先跑通 merge→评测链路
    2. **DoRA**: 权重分解为幅值+方向,同 rank 通常优于 LoRA;peft `use_dora=True` 一行开关
    3. **LoRA+**: B 矩阵 LR×16(A/B 分组学习率),改动极小,小数据常有收益
    4. **rsLoRA**: alpha 按 √r 缩放;配合 rank 扫描 {16,32,64} 一起做(高 rank 更稳)
  - 第二梯队:
    5. **混合策略(VLA 针对性最强)**: VLM 底座 LoRA + **动作专家全参**(action expert 36层/hidden768,任务特定部件) —— 若 2-4 无明显差异,优先试这个
    6. **PiSSA**: 用权重主成分 SVD 初始化 A/B,小数据收敛更快
    7. **QLoRA(NF4 4bit 底座)**: 显存大降→可关梯度检查点/加大 batch;⚠️ 动作回归对量化精度敏感,须与标准 LoRA 对比确认无损
  - 网格建议: rank {16,32,64} × target {attn, attn+MLP};vision tower(解冻/LoRA/冻结)单独做一组消融
- **时间预算**:全量 50任务×100条×2setting ≈ 3.5 天(3卡),10/26 截止,baseline 闭环明天出数后即可排
- **两个 setting 已排满(21:30)**:RoboTwin 协议 = demo_clean(无随机化)+ demo_randomized(随机背景/光照/桌面/杂物),launcher 用 `TASK_CONFIG=demo_randomized` 切换。当前 clean 20任务预计明天 ~13:00 完成(按 34% 成功率精算 15-16h)→ 接力 watcher `/tmp/chain_randomized.sh` 自动启动 randomized 同 20 任务(日志 `/tmp/closed_loop_joint_randomized.log`)→ 后天出 clean+randomized 基线对
- **测评慢的原因与加速(21:34)**:瓶颈 97% 在仿真侧(物理步进+3相机观测+专家规划),GPU 推理仅 ~2.3s/条;机器 128核/1TB 内存大量闲置。randomized 轮已改 **--num_per_gpu 2(6槽,~2×加速,~7-8h)**;后续全量可上 bf16 服务(显存减半→12-15槽,4-5×,3.5天→<1天,需先 A/B bf16 不掉点)
- **明早看三处**:`/tmp/overnight_pipeline.log`(夜间流水线)、`output/eval/ckpt_6k_demo_clean_20261008_210621/stats.txt`(clean 完整成功率)、`/tmp/chain_randomized.log`(randomized 是否已接力)
- 旧 eef 包 16 维之谜已解:每臂 [xyz3+四元数4+夹爪1]=8,双臂16;+2 维=旋转用四元数表示。旧训练=把位姿当关节角学,自洽但语义错位 → 闭环 0% 的第二个原因(与零位形失配叠加)

## 🟢 2026-10-08 下午:修复数据已就绪,重训已启动(当前进行中)
- **新数据**:ModelScope `currytom/robotwin-lerobot-joint-v21`(2.4GB zip,团队自制包)→ 解压并转 v3.0:`/root/autodl-tmp/robotwin_joint_v21/RoboTwin_lerobot_v21`(2500 eps / 548,893 帧 / fps15 / **14维关节空间**)
- **关键验证全部通过**:ep0 第一帧 = [0,0,0,0,0,0, 1, 0,0,0,0,0,0, 1] 与评测环境初始状态完全一致;action[t]==state[t+1](max err 0);含零位形起步的完整接近段 → 根因修复
- **维度问题定论**:旧 eef 包 16 维是 EEF 位姿空间的槽位约定(README 明确警告勿用 robbyant eef 版),训练配置只切 0-13 维所以未出错;新包是干净的官方 14 维
- **管线**:HF_LEROBOT_HOME=... python .../lerobot/datasets/v30/convert_dataset_v21_to_v30.py --repo-id RoboTwin_lerobot_v21 --force-conversion(旧版存为 *_old);norm stats 重算 → `assets/norm_stats/robotwin_joint.json`(count=548893),robot 配置已切换指向;专用无 model 段配置 `configs/vla/robotwin/robotwin_norm.yaml`
- **重训已启动(setsid 脱离会话)**:脚本 `/root/autodl-tmp/run_train_joint.sh`,日志 `/tmp/train_joint.log`;配置沿用七组基准最优 **micro 32×3卡=global 96**(实测 ~5.9s/步,三卡 74GB/100%);max_steps=9000(新数据 5717 步/epoch,约 1.6 epoch)、save_steps=2000;**预计 ~15h,今晚完成**
- 旧 eef ckpt 本地已删(36GB,autodl-fs 备份改名为 `ckpt_cold_eef16_old` 保留,**新模型首次冷存成功后可删**);冷存目录已腾空重建,避免管理器误判同名 .done
- 训练后流程:开环筛选(`--data_path` 指向旧 eef 数据或新数据均可,但 norm 用新 json)→ step6000 进闭环(20任务×100ep,3卡,~11-21h,协议已修通)
- 闭环 launcher 的 4 处修复 + probe 验证结论见下节,直接复用

## 🔴 2026-10-08 评测日:闭环 0% 的根因已定位(数据-评测初始状态失配)
### 已完成
- 训练确认跑完:实际跑到 ~step 6097(超 5749 预估),step_6000 ckpt 完整落盘;2000/4000 冷存于 autodl-fs 且已拉回本地(`output/ckpt/checkpoints/global_step_{2000,4000,6000}/hf_ckpt`,各 12GB)
- **开环筛选(5任务×3轨迹,fp32,均值 MSE)**:step2000=0.00263 / step4000=0.00107 / **step6000=0.00086(胜出)**;吞吐 0.77s/次前向,单 ckpt 全程 ~8.5 分钟;结果图 `output/eval/open_loop/`
- **闭环链路修通**(此前从未真正跑通,修了 4 处):① 启动脚本 CRLF→LF;② RoboTwin/script 目录缺失→launcher 加 mkdir;③ client 依赖的 `policy/ACT/deploy_policy.yml` 与可导入的 `ACT` 模块缺失→已补(RoboTwin/policy/ACT/deploy_policy.yml + RoboTwin/script/ACT.py stub);④ `task_config/` 软链到 `env_cfg/task_config/`
- 闭环实测吞吐:单次推理 0.28s;失败 episode 打满 400 步 ≈ 110s/条;3 卡 3 并发槽
### 🔴 根因(证据链完整)
1. **评测环境**机器人初始关节 = homestate 全零(亲测复现 episode:INIT state=[0,0,0,0,0,0,1,0,...]);**原始 RoboTwin hdf5** 第一帧同样是零位形(已验证)→ 基准协议就是零位形起步
2. **训练数据**(ModelScope currytom/robotwin aloha-agilex_clean_50)所有 episode 从"就位抓取姿态"起步:第一帧恒为 [-0.298,-0.314,0.942,0.700,...](50 episode std=0),**从未包含零位形起步段**
3. 模型本身没问题:把数据集帧经同款 websocket 通路喂给模型,pred[i]↔gt[i] 全维匹配 MAE 0.008~0.03(注意:要按数据集原始 0-13 维对齐,不能按 robotwin.yaml 的 arm/effector 重排对齐——robot 配置的切片恰好等于原始布局,不涉及重排)
4. 后果:闭环从零位形起步全 OOD → lift_pot 0/30、hanging_mug 0/18、stack_bowls_three 0/14
### 下一步(团队决策)
- **正解**:换含零位形起步段的数据重训(官方 RoboTwin 2.0 数据或本地重新采集;ModelScope 源现无权访问);重训 ~9.5h(吞吐实测 5.5s/步)+ 开环 0.5h + 闭环 smoke 一晚
- **快速自检(可选)**:把评测初始关节摆到训练数据第一帧姿态跑几条 episode,验证模型在匹配分布下的成功率
- 开环筛选的 MSE 只反映"从就位姿态续段"的能力,排序结论(6000>4000>2000)不受影响,但绝对值与闭环成功率无关联
### 全量评测排期参考(修复数据后)
- 闭环单条 episode:成功 ~40-60s(数据 demo ≈140 步)/ 失败 110s(400 步封顶);单任务 100 条 ≈ 1.5-3h
- 20 任务 smoke(3 卡)≈ 11-21h;全量 50 任务×100 条×2 setting ≈ 10000 条 ÷ 3 槽 ≈ **83h ≈ 3.5 天**(10/26 截止,够但别浪费)


## 🔴 当前正在跑:正式训练(3×A800-80GB)
- 配置:micro 32 × 3卡 × 累积1 = global 96;解冻视觉塔 + BF16 + Muon + 梯度检查点 + workers 24 + prefetch 8
- 实测:5.84s/步 → 5749 步 ≈ 9.5 小时(预计 10/3 凌晨 1:30-2:00 完成)
- 显存:73.5GB/卡(三卡均匀,余量 ~5GB)
- ckpt:第 2000 / 4000 / 5749 步各存一个(三个候选);每存一个立即过开环评测筛选
- **机器不能关机**;进程挂在 nohup,日志 /tmp/train_full.log
- 磁盘守护 strip_optimizer.sh 在跑:旧 ckpt 只留 model/,清 optimizer/ 省空间
- 脚本:/root/autodl-tmp/run_train_full.sh

## 七组基准测试结果(全记录,供团队复用)
| 配置 | 步时 | 显存 | 结论 |
|---|---|---|---|
| micro 2 + 冻结 + ckpt on(首试) | 19s | 46.7GB | 太慢(30h) |
| micro 4 + 冻结 + workers16 | 10.3s | 46.9GB | |
| micro 8 + 解冻 | 7.5s | 52.4GB | 解冻仅 +3GB |
| micro 16 + 解冻 | 6.05s | 63GB | |
| micro 16 + 解冻 + **关检查点** | 7.2s↑ | **79GB 临界** | ❌ 更慢且顶显存 |
| **micro 32 + 解冻 + ckpt on** | **5.5s** | 73.6GB | ✅ **最优,采用** |
| micro 40 + 解冻 + ckpt on | 7.4s↑ | 79.2GB(GPU1/2 临界) | ❌ 更慢 |
- 关键发现:关梯度检查点在 micro≥16 时无收益且显存触顶;**OOM 临界在 micro 40 / 关检查点配置**;workers 24 + prefetch 8 已使 GPU 利用率 87-99%
- 提速:19s → 5.84s(3.2×);总时长 30h → 9.5h

## 待办(训练完成后)
1. 三个 ckpt 过 `scripts/open_loop_eval.py` 开环评分(action error)
2. 前 2-3 名进闭环小规模评测:`MODEL_PATH=<ckpt> NUM_TASKS=20 bash /root/autodl-tmp/run_eval_smoke.sh`
3. 与团队确认:LR/步数消融、LoRA 对比、EMA 等(team training-recipe 模块)
4. 评测吞吐实测 + 50 任务×100 次×2 setting 排期(截止 10/26)

## 路径速查(不变)
| 内容 | 路径 |
|---|---|
| 训练工作目录 | /root/autodl-tmp/uploads/train/ours-20260930 |
| RoboTwin 仿真 | /root/autodl-tmp/uploads/sim/RoboTwin |
| 6B 权重 | /root/autodl-tmp/lingbot-vla-v2-6b |
| Qwen tokenizer | /root/autodl-tmp/models/Qwen3-VL-4B-Instruct |
| 训练数据(v3.0,50 任务) | /root/autodl-tmp/robotwin_eef_clean50/lerobot_robotwin_eef_clean_50 |
| ckpt 输出 | /root/autodl-tmp/output/ckpt |
| conda 环境 | lingbotvla(训练)/ RoboTwin(仿真);miniconda 已迁 /root/autodl-tmp/miniconda3(软链 /root/miniconda3) |

## 今日已完成
- 数据 v2.1→v3.0 转换 50/50(latents 完整);系统盘治理(95%→5%);缓存重定向数据盘
- 模型/数据/评测链路全部实测;磁盘守护;七组性能基准
- 注意:模型是 3 卡(之前 1 卡),torchrun 自动识别 NPROC_PER_NODE=3
