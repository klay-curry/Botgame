# action-head 动作头（MoE + 流匹配）

> 对应总览表 #5（docs/modules/README.md §1）｜负责人: 梁家诚 ｜状态: 未启动

## 这个模块主要干什么

模型的"手"：动作专家是一层 FFN 换成 32 个小网络（专家），每个 token 经路由只走其中 4 个（top-4）；动作不是一次算出，而是流匹配——从纯噪声迭代去噪（默认 10 步）得到动作序列。**这是理解"模型怎么输出动作"的核心入口**，可改点以 A 级为主，收益小而稳。

## 初期可优化方向（按投入顺序）

1. **推理去噪步数**：默认 10 步，试 5/20——纯推理侧实验，不训练就能验证，本模块最便宜的实验；步数少可能掉点但评测提速（吞吐预算直接受益）；
2. **`token_top_k` 路由数**：4 → 2/6/8。注意：**只动路由行为，不动专家权重形状**，预训练权重兼容（这是 MoE 上唯一安全的主力旋钮）；
3. **loss 类型**：`loss_type: L1_fm` 对照 smooth L1 / L2（`lingbotvla/ops/loss.py`），一次训练一组；
4. **路由辅助损失系数**：`sequence_wise_loss_coeff: 1e-3`、`router_z_loss_coeff: 1e-4`，影响专家负载均衡，微调观察 `moe_monitor_interval` 输出的负载统计。

**死路声明**：改专家数量（`token_num_experts`）、专家维度（`token_moe_intermediate_size`）、层数——全部破坏预训练权重对齐，禁止。若训练日志显示某几个专家长期闲置/过载，正确反应是调路由损失，而不是改结构。

## 涉及文件（负责人补全）

- TODO：`lingbotvla/models/vla/lingbot_vla/qwen2_action_expert.py`、`moe_load_balance.py`；`lingbotvla/ops/fused_moe.py`、`moe_loss.py`；`lingbotvla/schedulers/flow_match.py`

## 数据流（负责人补全）

- TODO：从 VLM 主干输出 → 路由 → 专家 → 流匹配去噪 → 55 维动作的完整张量流，标 shape

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
