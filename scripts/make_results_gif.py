#!/usr/bin/env python3
"""把 RoboTwin 评测结果做成动图(GIF)+ 静态图(PNG)。

输入:results.json(官方模板)与逐任务审计 CSV
输出:
  eval_results_animation.gif   逐任务成功率动画(clean vs randomized)
  eval_results_summary.png     静态汇总图(用于 README / 小红书)
"""
import json
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.animation import FuncAnimation, PillowWriter

RESULTS_JSON = sys.argv[1] if len(sys.argv) > 1 else \
    "/root/autodl-tmp/submission/01_评测结果/results.json"
OUT_DIR = sys.argv[2] if len(sys.argv) > 2 else "/root/autodl-tmp/submission/01_评测结果"

CLEAN_C, RAND_C = "#2f6fdb", "#e8833a"
BG = "#0f1218"
FG = "#e8ecf2"
MUTED = "#8b93a3"


def load():
    d = json.load(open(RESULTS_JSON))
    out = {}
    for setting in ("clean", "randomized"):
        tasks = d["results"][setting]
        out[setting] = {k: v["successes"] / v["attempts"] * 100 for k, v in tasks.items()}
    return out


def main():
    data = load()
    clean, rand = data["clean"], data["randomized"]
    # 按 clean 成功率降序,便于展示"从易到难"
    order = sorted(clean.keys(), key=lambda t: -clean[t])
    n = len(order)

    total_clean = sum(clean.values()) / n
    total_rand = sum(rand.values()) / n

    fig = plt.figure(figsize=(11, 6.2), dpi=110, facecolor=BG)
    ax = fig.add_axes([0.30, 0.10, 0.56, 0.80], facecolor=BG)
    ax2 = fig.add_axes([0.875, 0.10, 0.10, 0.80], facecolor=BG)
    ax2.set_axis_off()

    y = list(range(n))[::-1]
    ax.set_xlim(0, 100)
    ax.set_ylim(-1, n)
    ax.set_yticks(y)
    ax.set_yticklabels(order, fontsize=7.5, color=FG)
    ax.set_xlabel("success rate (%)", color=MUTED, fontsize=9)
    ax.tick_params(colors=MUTED, labelsize=8)
    for s in ax.spines.values():
        s.set_color("#2a3040")
    ax.grid(axis="x", color="#1e2430", linewidth=0.8)
    ax.set_axisbelow(True)

    title = fig.text(0.03, 0.955, "RoboTwin 2.0 · Aloha-AgileX", color=FG,
                     fontsize=16, fontweight="bold")
    sub = fig.text(0.03, 0.915, "50 tasks × 100 episodes per task", color=MUTED, fontsize=10)
    legend_c = fig.text(0.03, 0.875, "■ demo_clean", color=CLEAN_C, fontsize=10)
    legend_r = fig.text(0.19, 0.875, "■ demo_randomized", color=RAND_C, fontsize=10)

    bc = ax.barh(y, [0] * n, color=CLEAN_C, height=0.38, zorder=3)
    br = ax.barh([v - 0.21 for v in y], [0] * n, color=RAND_C, height=0.38, zorder=3)

    stat_txt = ax2.text(0, 0.62, "", color=FG, fontsize=11, ha="center", va="center")
    done_txt = fig.text(0.03, 0.045, "", color=MUTED, fontsize=9)

    def frame(k):
        # k+1 个任务已出结果
        m = k + 1
        for i in range(n):
            bc[i].set_width(clean[order[i]] if i < m else 0)
            br[i].set_width(rand[order[i]] if i < m else 0)
        sub_tasks = order[:m]
        c_sum = sum(clean[t] for t in sub_tasks)
        r_sum = sum(rand[t] for t in sub_tasks)
        stat_txt.set_text(f"{m}/{n}\ntasks\n\nclean\n{c_sum/m:.0f}%\n\nrand\n{r_sum/m:.0f}%")
        done_txt.set_text(f"equivalents 10000 steps · LingBot-VLA 2.0 · bf16 inference")
        ax.set_title("")

    anim = FuncAnimation(fig, frame, frames=n, interval=90, blit=False)
    gif = os.path.join(OUT_DIR, "eval_results_animation.gif")
    anim.save(gif, writer=PillowWriter(fps=10))
    print(f"写出动图: {gif}")

    # ---- 静态汇总图 ----
    fig2, axb = plt.subplots(figsize=(11, 6.2), dpi=140, facecolor=BG)
    axb.set_facecolor(BG)
    x = range(n)
    axb.bar([i - 0.2 for i in x], [clean[t] for t in order], width=0.4,
            color=CLEAN_C, label="demo_clean")
    axb.bar([i + 0.2 for i in x], [rand[t] for t in order], width=0.4,
            color=RAND_C, label="demo_randomized")
    axb.set_xticks(list(x))
    axb.set_xticklabels(order, rotation=90, fontsize=6, color=FG)
    axb.set_ylabel("success rate (%)", color=MUTED, fontsize=10)
    axb.set_ylim(0, 100)
    axb.tick_params(colors=MUTED, labelsize=8)
    for s in axb.spines.values():
        s.set_color("#2a3040")
    axb.grid(axis="y", color="#1e2430", linewidth=0.8)
    axb.set_axisbelow(True)
    axb.legend(facecolor=BG, edgecolor="#2a3040", labelcolor=FG, fontsize=10)
    axb.set_title(f"RoboTwin 2.0 Aloha-AgileX · clean {total_clean:.1f}%  |  "
                  f"randomized {total_rand:.1f}%",
                  color=FG, fontsize=14, fontweight="bold", pad=14)
    for t in axb.get_xticklabels():
        t.set_color(FG)
    png = os.path.join(OUT_DIR, "eval_results_summary.png")
    fig2.savefig(png, facecolor=BG, bbox_inches="tight")
    print(f"写出静态图: {png}")


if __name__ == "__main__":
    main()
