# evaluation 评测基建

> 对应总览表 #1（docs/modules/README.md §1）｜负责人: 梁家诚主建、刘勇泽定格式 ｜状态: 未启动

## 这个模块主要干什么

不涨分，但决定 4 周能做几轮实验——全队的迭代速度杠杆。三块内容：

1. **快筛协议**：固定 10 任务 × 每任务 20 次 × 两 setting（400 episodes），日常迭代只看它，全量评测只留给最终候选；
2. **开环评测调度**：`scripts/open_loop_eval.py` 批量化，所有 checkpoint 的廉价初筛（action 误差排序）；
3. **正式评测支撑**：50 任务 × 100 次 × 2 setting 的排队/断点续跑、吞吐测量、results.json 生成与校验（对齐官方 JSON 模板）。

## 初期可优化方向

1. **定快筛任务名单**：10 个任务覆盖刚性抓取/可形变/双臂协作/工具四类，选定后不再改（否则实验间不可比）；
2. **吞吐测量脚本**：单 episode 耗时 × 并行 slot → 推算全量评测天数。**硬规则：推算 >4.5 天 → 加卡或提前冻结候选**（这条写进总览表备注）；
3. **results.json 生成/校验工具**：从原始日志自动汇总 attempts/successes，带逐任务缺失检查——杜绝手填成绩（CONTRIBUTING 红线）；
4. **开环评测批处理**：一个目录的 checkpoint 全部自动评测 + 汇总排序表，是 training-recipe 模块 checkpoint 扫描的直接依赖（两模块的接口）。

## 涉及文件（负责人补全）

- TODO：`scripts/open_loop_eval.py`；`experiment/robotwin/start_robotwin_infer_and_eval.sh`、`eval_policy_client_lingbotvla.py`；官方 JSON 模板 `docs/灵波2026/初赛评测结果模板_JSON版.json`

## 数据流（负责人补全）

- TODO：checkpoint → 推理服务 → RoboTwin 仿真 → episode 日志 → 汇总表/results.json 的全链路，标注 FP32/BF16 口径在哪一层生效

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
