# vision-encoder 视觉编码器（含蒸馏旁路）

> 对应总览表 #6 + #7（docs/modules/README.md §1）｜负责人: 刘勇泽（调研为主，P2） ｜状态: 未启动

## 这个模块主要干什么

模型的"眼睛"和两位"辅导老师"：Qwen3-VL 自带 ViT 把 3 路相机图像编码成视觉 token；蒸馏旁路是 V2 的特色——LingBot-Depth（几何）和 DINO-Video（时序）两个老师网络不直接输出动作，只给中间层当监督信号。**本模块当前只做调研和 A 级旋钮**，写代码（外挂特征）是 P2、GPU 富余才启动。

## 初期可优化方向

1. **蒸馏损失权重**（A 级）：`depth_loss_weight / future_depth_loss_weight / future_video_loss_weight`（现均 0.004）、`cosine_loss_weight: 0.2`——官方调优过，预期收益小，但 `visual_steps: 5000`（视觉损失只在前 5000 步？）值得先搞清语义再决定动不动；
2. **`use_future_image` 开关**（A 级）：未来帧预测与 randomized 泛化有理论关联（预测场景演化 ⇒ 对外观变化更鲁棒），一组对照实验；
3. **外挂公开特征**（B 级，仅调研）：并联 DINOv2/DINOv3 特征 token 拼进视觉序列——先在 `refs/` 写清三件事：维度怎么对齐、token 预算增加多少、公开权重来源怎么在 README 声明（官方 Q7 义务）。**调研通过评审前不写代码**。

**死路声明**：替换原 ViT、改它的层数/维度——破坏预训练权重对齐，禁止。

## 涉及文件（负责人补全）

- TODO：`lingbotvla/models/vla/lingbot_vla/qwen3vl_in_vla.py`；`models/vla/vision_models/align_heads/`（depth_head、resampler）；`dino_video/teacher.py`

## 数据流（负责人补全）

- TODO：图像 → ViT → 视觉 token；两位老师 → 查询 → 蒸馏损失的完整路径

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
