# 2026-09-29 数据清单与 click_bell 审计

## 来源与复现

- 数据：`data/robotwin2.0/`；ModelScope 镜像仓库当前 Git revision `3a94ed97d6b7107b612fc5df58e6875f7a30bcd3`。
- `click_bell/aloha-agilex_clean_50.zip` SHA-256：`4b959d712791792a6dba9a97fa31d81cb4393acd39874470ee19070f8dbeb212`。
- 审计代码：`scripts/data_audit.py`；使用 Python 3.12、h5py 3.14.0、NumPy 1.26.4。命令见 [模块 README](../README.md#已有的只读审计闭环)。
- 审计只读取 ZIP 内的 HDF5，不解压、删除或修改数据文件。

## 50 任务下载状态

| 状态 | 任务数 | 判据 |
|---|---:|---|
| 结构完整 ZIP | 9 | ZIP 目录可读，`episode0`–`episode49` 条目齐全；本次仅对 `click_bell` 逐条读取 |
| 未完成分片 | 8 | 有 `.zip.incomplete`；保留供续传 |
| 仅有 LFS 指针 | 33 | `.zip` 约 134 字节，不能当训练数据 |

结构完整 ZIP 的任务：`lift_pot`、`hanging_mug`、`handover_block`、`click_bell`、`adjust_bottle`、`beat_block_hammer`、`click_alarmclock`、`dump_bin_bigbin`、`grab_roller`。

未完成分片的任务：`blocks_ranking_rgb`、`blocks_ranking_size`、`handover_mic`、`move_can_pot`、`move_pillbottle_pad`、`move_playingcard_away`、`move_stapler_pad`、`open_laptop`。

目录中虽然有 2500 个 `.hdf5` 文件名，检查文件头后确认它们目前全是约 132 字节的 Git LFS 指针。上述 9 个 ZIP 是当前可用的真实数据来源。

## click_bell 单任务结果

| 指标 | 结果 |
|---|---:|
| 实际读取的 HDF5 轨迹 | 50 / 50，错误 0 |
| 帧数 | 最少 75，平均 78.1，中位数 78，最多 87 |
| 左右臂 12 维动作相邻帧绝对差 | 平均 0.006929；P95 0.053019；P99 0.093605 |
| 左夹爪数值 `>=0.5` 的帧比例 | 82.25%；阈值切换 19 次 |
| 右夹爪数值 `>=0.5` 的帧比例 | 71.06%；阈值切换 31 次 |
| 三路相机帧数 | `head`、`left`、`right` 均与动作帧数一致 |

每条轨迹的 `joint_action/vector` 为 `(T, 14)`。相邻帧动作差值不是物理速度，因为此处没有确认帧间时长。夹爪阈值暂不解释为“张开”或“闭合”，要先核对机器人配置和数据转换代码。

## 下一步

1. 继续现有断点下载，先用清单脚本核对是否达到 50 个任务均有真实数据，再对每个任务运行 HDF5 审计。
2. 补齐并核对 `ours/` 缺失的数据转换代码，确认夹爪语义与 55 维映射，再决定增强幅度。
