# data-pipeline 数据管线（含数据审计 + 增强）

> 对应总览表 #3 + #4（docs/modules/README.md §1）｜负责人: 刘勇泽 ｜状态: 未启动

## 这个模块主要干什么

数据从 HDF5 到模型输入的整条流水线：50 任务 × 50 条 clean 轨迹 → LeRobot 格式 → 55 维统一动作空间映射 + 3 相机图像 → 归一化 → batch。下面三件事按顺序做，**先审计（最容易，纯统计）再增强（本模块核心价值）**：

1. **数据审计**：2500 条轨迹的长度/速度/夹爪开合分布统计——知道数据长什么样，才知道怎么增强、哪些轨迹可疑；
2. **数据增强**：规则内扰动（官方 Q18 白名单），直接瞄准"一半分数来自 randomized"的泛化 gap；
3. **归一化与映射核查**：确认 `assets/norm_stats/robotwin.json` 与实际数据一致。

## 初期可优化方向

1. **审计脚本**（放根目录 `scripts/`，不动官方代码）：逐任务统计轨迹帧数分布、关节速度分布、夹爪开合比例，画箱线图；异常判据先只记录不删除（清洗是否启用等审计结论出来再定）；
2. **颜色/亮度增强**：对相机 RGB 做 brightness/contrast/hue 抖动 + JPEG 压缩噪声——**只动像素，不重渲染场景**（Q18 允许的第 1 条）；挂在 `data/vla_data/transform.py` 管线上，加 yaml 开关（默认关，实验时开）；
3. **状态噪声**：对 14 维关节动作/状态注入小幅高斯噪声（Q18 允许的第 2 条）；幅度从数据统计里定（比如关节速度方差的 5%），不拍脑袋；
4. **增强强度消融**：弱/中/强三档各训一组对比，防止增强过猛把 clean2clean 也拉垮。

**红线提示**：改变光照/桌面外观后重新生成 observation = 重渲染，**禁止**；一切增强必须只作用在已有数据的像素和数值上。

## 涉及文件（负责人补全）

- TODO：`lingbotvla/data/vla_data/multi_vla_dataset.py`、`transform.py`、`base_dataset.py`；`configs/robot_configs/robotwin.yaml`（55 维映射）；`assets/norm_stats/robotwin.json`

## 数据流（负责人补全）

- TODO：HDF5 → LeRobot → transform → collator → batch 的全链路，标注每步的 shape 和字段

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
