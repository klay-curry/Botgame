# data-pipeline 数据管线（含数据审计 + 增强）

> 对应总览表 #3 + #4（docs/modules/README.md §1）｜负责人: 刘勇泽 ｜状态: 单任务审计已跑通，数据增强未启动

## 这个模块主要干什么

数据从 HDF5 到模型输入的整条流水线：50 任务 × 50 条 clean 轨迹 → LeRobot 格式 → 55 维统一动作空间映射 + 3 相机图像 → 归一化 → batch。下面三件事按顺序做，**先审计（最容易，纯统计）再增强（本模块核心价值）**：

1. **数据审计**：2500 条轨迹的长度、关节帧间变化量、夹爪数值分布统计——知道数据长什么样，才知道怎么增强、哪些轨迹可疑；没有帧间时长时，不能把动作差值直接称为物理速度；
2. **数据增强**：规则内扰动（官方 Q18 白名单），直接瞄准"一半分数来自 randomized"的泛化 gap；
3. **归一化与映射核查**：确认 `assets/norm_stats/robotwin.json` 与实际数据一致。

## 初期可优化方向

1. **审计脚本**（放根目录 `scripts/`，不动官方代码）：逐任务统计轨迹帧数、关节动作帧间变化和夹爪数值比例；异常判据先只记录不删除（清洗是否启用等审计结论出来再定）；
2. **颜色/亮度增强**：对相机 RGB 做 brightness/contrast/hue 抖动 + JPEG 压缩噪声——**只动像素，不重渲染场景**（Q18 允许的第 1 条）；挂在 `data/vla_data/transform.py` 管线上，加 yaml 开关（默认关，实验时开）；
3. **状态噪声**：对 14 维关节动作/状态注入小幅高斯噪声（Q18 允许的第 2 条）；幅度从数据统计里定（比如关节速度方差的 5%），不拍脑袋；
4. **增强强度消融**：弱/中/强三档各训一组对比，防止增强过猛把 clean2clean 也拉垮。

**红线提示**：改变光照/桌面外观后重新生成 observation = 重渲染，**禁止**；一切增强必须只作用在已有数据的像素和数值上。

## 已有的只读审计闭环

在仓库根目录运行。只查 ZIP 目录和文件头的清单检查使用 Python 标准库；读取 HDF5 轨迹另需 Python 3.12、`h5py==3.14.0` 和 `numpy==1.26.4`（与 `ours/requirements.txt` 一致）。本机默认 Python 3.14 没装这些依赖，下面用 `uv` 启动临时 Python 3.12 环境。脚本只读 ZIP，不会解压或改动断点：

```bash
python scripts/data_audit.py --root data/robotwin2.0 --output output/data-inventory.json
uv run --no-project --python 3.12 --with h5py==3.14.0 --with numpy==1.26.4 \
  python scripts/data_audit.py --root data/robotwin2.0 --task click_bell --output output/click_bell-audit.json
```

`--root` 可指向任务目录的父目录；脚本也识别下载脚本生成的 `data/robotwin2.0/dataset/` 布局。`ready` 表示 50 个编号齐全且 ZIP 目录可读，或有 50 个带 HDF5 文件头的解压文件；只有 `--task` 才会逐条读取并检查真实内容。正式完成需 50 个任务全为 `ready`，再逐任务审计。

现有 8 个续传分片位于 `data/robotwin2.0/<task>/`。仓库的 `scripts/download_data_ms.sh` 默认写入另一个位置 `data/robotwin2.0/dataset/`，不应把它当作现有分片的续传命令；继续下载时先确认使用原断点流程及目标目录。

2026-09-29 快照：[审计报告](reports/2026-09-29-click_bell.md)。当前 9 个任务有结构完整的 ZIP，8 个任务有未完成分片，33 个任务只有 LFS 指针；目录里看似存在的 2500 个 HDF5 全是指针。`click_bell` ZIP 内 50 条真实轨迹全部可读，长度 75–87 帧，平均 78.1 帧，三路相机帧数与动作对齐，未发现读取错误。关节指标只是相邻帧动作差值；夹爪 `>=0.5` 比例尚未解释成“张开/闭合”。

## 涉及文件与当前代码缺口

- 已有：`scripts/data_audit.py` 负责 ZIP / LFS 完整性和单任务 HDF5 审计；`ours/configs/robot_configs/robotwin.yaml` 负责转换后数据的状态、动作、相机映射；`ours/assets/norm_stats/robotwin.json` 存官方归一化统计。
- 待核对：当前 `ours/` 副本缺少文档所指的 `lingbotvla/data/vla_data/multi_vla_dataset.py`、`transform.py`、`base_dataset.py`，也缺 `configs/vla/robotwin/robotwin.yaml` 和 `experiment/robotwin/`。接入增强前先确认官方版本和缺失代码的来源，不能按不存在的路径修改。

## 数据流（已验证到 HDF5，后续待补）

`click_bell` 的实际路径：`aloha-agilex_clean_50.zip` → `data/episodeN.hdf5`。每条 HDF5 包含 `joint_action/vector`，形状 `(T, 14)`；`observation/head_camera/rgb`、`left_camera/rgb`、`right_camera/rgb` 的第一维均为 `T`。样本还有 `front_camera/rgb`。HDF5 → LeRobot → transform → collator → batch 的代码链和 shape 待上述缺失文件补齐后核对。

## 状态表

| proposal | 状态 | 结论 | 实验记录 |
|---|---|---|---|
| — | — | — | — |
