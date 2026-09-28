# training-recipe 训练配方

> 对应总览表 #2（docs/modules/README.md §1）｜负责人: 梁家诚 ｜状态: 未启动

## 这个模块主要干什么

不改模型结构，只调"怎么训"：优化器、学习率、总步数、batch、EMA、LoRA、视觉塔冻结、checkpoint 选择。全部是配置级旋钮（A 级），是全项目性价比最高的模块——2500 条轨迹训 6B 模型，**过拟合是默认结局，"选对 checkpoint + 及时早停"一项就值 5–15 个点**。

## 初期可优化方向（按投入顺序）

1. **checkpoint 扫描**：`save_steps: 10000 → 5000`，训完一次后全部 ckpt 过开环评测，前 3–4 名进快筛闭环。零额外训练成本，最先做；
2. **总步数消融**：官方 `max_steps: 50000` 对照 10k/20k/30k 早停——大概率官方步数远超必要；
3. **学习率**：`lr: 1e-4` 对照 5e-5（注意与 batch 联动，见下一条）；
4. **batch 校准**：官方 global 1024 是 32 卡配置；我们 8 卡时 global 256，用梯度累积对齐 1024 各跑一组，确定 lr 是否要跟着调；
5. **冻结视觉塔**：`freeze_vision_encoder: true`，正则 + 提速，一组对照；
6. **EMA**：`lingbotvla/utils/ema.py` 官方已有现成实现，查配置开关直接开；
7. **Muon vs AdamW**：`optimizer` 字段切换。若 AdamW 不差，后续所有实验迭代提速；
8. **LoRA 正则**：`utils/lora_utils.py` 现成支持，全参过拟合时的替代路线（训完合并回基座，合规）。

## 涉及文件（负责人补全）

- TODO：`lingbotvla/optim/optimizer.py`、`lr_scheduler.py`、`muon.py`；`configs/vla/robotwin/robotwin.yaml` 训练段逐键注释

## 数据流（负责人补全）

- TODO：一个 step 的生命周期（取 batch → forward → loss → optimizer.step → ckpt 落盘路径）

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
