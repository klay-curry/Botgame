#!/usr/bin/env python3
"""把 RoboTwin 评测结果做成动图/静态图，供 README 与提交材料使用。

输入：官方模板 results.json（逐任务 attempts/successes）
输出（同目录）：
  eval_results_animation.gif   逐任务展开的成功率动画（clean vs randomized）
  eval_results_summary.png     双 setting 逐任务柱状图
  eval_results_dashboard.png   总览面板：总成绩 / 逐任务 / 退化分析
  eval_results_heatmap.png     50 任务 × 2 setting 成功率热力图

仅依赖 matplotlib，不需要 GPU：
  python3 scripts/make_results_gif.py [results.json] [输出目录]
"""
import json
import os
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.animation import FuncAnimation, PillowWriter
from matplotlib.colors import LinearSegmentedColormap

REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RESULTS = REPO_ROOT / "docs/submission/2026-10-21/01_评测结果/results.json"
RESULTS_JSON = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_RESULTS
OUT_DIR = Path(sys.argv[2]) if len(sys.argv) > 2 else RESULTS_JSON.parent

CLEAN_C, RAND_C = "#2f6fdb", "#e8833a"
BG = "#0f1218"
PANEL = "#151a23"
FG = "#e8ecf2"
MUTED = "#8b93a3"
GRID = "#252c3a"
WIN_C = "#3fb950"
LOSS_C = "#f85149"


def load():
    d = json.load(open(RESULTS_JSON))
    out = {}
    for setting in ("clean", "randomized"):
        tasks = d["results"][setting]
        out[setting] = {
            k: {
                "rate": v["successes"] / v["attempts"] * 100,
                "succ": v["successes"],
                "att": v["attempts"],
            }
            for k, v in tasks.items()
        }
    return out


def style_ax(ax, title=None):
    ax.set_facecolor(PANEL)
    for s in ax.spines.values():
        s.set_color(GRID)
    ax.tick_params(colors=MUTED, labelsize=8)
    ax.grid(color=GRID, linewidth=0.7, alpha=0.7)
    ax.set_axisbelow(True)
    if title:
        ax.set_title(title, color=FG, fontsize=11, fontweight="bold", loc="left")


def overall_bars(ax, clean, rand):
    totals = [
        ("demo_clean", sum(v["succ"] for v in clean.values()),
         sum(v["att"] for v in clean.values()), CLEAN_C),
        ("demo_randomized", sum(v["succ"] for v in rand.values()),
         sum(v["att"] for v in rand.values()), RAND_C),
    ]
    labels = [t[0] for t in totals]
    rates = [t[1] / t[2] * 100 for t in totals]
    bars = ax.bar(labels, rates, color=[t[3] for t in totals], width=0.55, zorder=3)
    ax.set_ylim(0, 100)
    ax.set_ylabel("success rate (%)", color=MUTED, fontsize=9)
    style_ax(ax, "Overall success rate · 50 tasks × 100 episodes")
    for b, (_, s, a, _), r in zip(bars, totals, rates):
        ax.text(b.get_x() + b.get_width() / 2, r + 1.5,
                f"{r:.1f}%\n{s:,}/{a:,}", ha="center", va="bottom",
                color=FG, fontsize=10, fontweight="bold")


def scatter_clean_vs_rand(ax, order, clean, rand):
    xs = np.array([clean[t]["rate"] for t in order])
    ys = np.array([rand[t]["rate"] for t in order])
    deltas = xs - ys
    sc = ax.scatter(xs, ys, c=deltas, cmap="RdYlGn_r", vmin=-5, vmax=60,
                    s=46, edgecolor=BG, linewidth=0.6, zorder=4)
    ax.plot([0, 100], [0, 100], color=MUTED, lw=1, ls="--", zorder=2)
    ax.set_xlim(-2, 102)
    ax.set_ylim(-2, 102)
    ax.set_xlabel("demo_clean success rate (%)", color=MUTED, fontsize=9)
    ax.set_ylabel("demo_randomized success rate (%)", color=MUTED, fontsize=9)
    style_ax(ax, "Per-task clean vs randomized (below the diagonal = domain gap)")
    # 标注退化最大的 6 个任务
    for i in np.argsort(-deltas)[:6]:
        ax.annotate(order[i], (xs[i], ys[i]), xytext=(4, -9),
                    textcoords="offset points", color=FG, fontsize=6.5)
    cb = plt.colorbar(sc, ax=ax, fraction=0.045, pad=0.02)
    cb.set_label("clean − randomized (pt)", color=MUTED, fontsize=8)
    cb.ax.tick_params(colors=MUTED, labelsize=7)
    cb.outline.set_edgecolor(GRID)
    # 平均值参考线
    ax.axhline(ys.mean(), color=RAND_C, lw=1, ls=":", alpha=0.8)
    ax.axvline(xs.mean(), color=CLEAN_C, lw=1, ls=":", alpha=0.8)


def delta_hist(ax, order, clean, rand):
    deltas = np.array([clean[t]["rate"] - rand[t]["rate"] for t in order])
    ax.hist(deltas, bins=np.arange(-15, 66, 5), color="#6e7fa8",
            edgecolor=BG, zorder=3)
    ax.axvline(deltas.mean(), color=LOSS_C, lw=1.6, zorder=4,
               label=f"mean {deltas.mean():.1f} pt")
    ax.axvline(0, color=FG, lw=0.8, ls="--", alpha=0.5)
    ax.set_xlabel("success-rate drop, clean − randomized (pt)", color=MUTED, fontsize=9)
    ax.set_ylabel("tasks", color=MUTED, fontsize=9)
    style_ax(ax, "Domain-gap distribution")
    ax.legend(facecolor=PANEL, edgecolor=GRID, labelcolor=FG, fontsize=8)

    worst = sorted(order, key=lambda t: -(clean[t]["rate"] - rand[t]["rate"]))[:3]
    txt = "largest drops:\n" + "\n".join(
        f"{t}  −{clean[t]['rate'] - rand[t]['rate']:.0f} pt" for t in worst)
    ax.set_ylim(0, ax.get_ylim()[1] * 1.55)
    ax.text(0.98, 0.97, txt, transform=ax.transAxes, va="top", ha="right",
            color=MUTED, fontsize=6.5)


def task_bars(ax, order, clean, rand):
    n = len(order)
    y = np.arange(n)
    ax.barh(y - 0.2, [clean[t]["rate"] for t in order], height=0.38,
            color=CLEAN_C, label="demo_clean", zorder=3)
    ax.barh(y + 0.2, [rand[t]["rate"] for t in order], height=0.38,
            color=RAND_C, label="demo_randomized", zorder=3)
    ax.set_yticks(y)
    ax.set_yticklabels(order, fontsize=6.5, color=FG)
    ax.invert_yaxis()
    ax.set_xlim(0, 100)
    ax.set_xlabel("success rate (%)", color=MUTED, fontsize=9)
    style_ax(ax, "Per-task success rate · sorted by demo_clean")
    ax.legend(facecolor=PANEL, edgecolor=GRID, labelcolor=FG, fontsize=9,
              loc="lower right")
    ax.grid(axis="x")
    ax.grid(axis="y", visible=False)


def dashboard(data):
    clean, rand = data["clean"], data["randomized"]
    order = sorted(clean, key=lambda t: -clean[t]["rate"])

    fig = plt.figure(figsize=(17, 11), dpi=140, facecolor=BG)
    gs = fig.add_gridspec(1, 2, width_ratios=[1.0, 1.45], wspace=0.26,
                          left=0.05, right=0.98, top=0.90, bottom=0.06)
    left = gs[0, 0].subgridspec(3, 1, hspace=0.42)
    ax1 = fig.add_subplot(left[0])
    ax2 = fig.add_subplot(left[1])
    ax3 = fig.add_subplot(left[2])
    ax4 = fig.add_subplot(gs[0, 1])

    overall_bars(ax1, clean, rand)
    scatter_clean_vs_rand(ax2, order, clean, rand)
    delta_hist(ax3, order, clean, rand)
    task_bars(ax4, order, clean, rand)

    total_c = sum(v["succ"] for v in clean.values()) / sum(v["att"] for v in clean.values()) * 100
    total_r = sum(v["succ"] for v in rand.values()) / sum(v["att"] for v in rand.values()) * 100
    fig.suptitle("RoboTwin 2.0 Aloha-AgileX · LingBot-VLA 2.0 (equiv. 10000 steps)",
                 color=FG, fontsize=18, fontweight="bold", x=0.05, ha="left")
    fig.text(0.05, 0.935,
             f"final checkpoint · bf16 inference · demo_clean {total_c:.1f}%  |  "
             f"demo_randomized {total_r:.1f}%  ·  50 tasks × 100 episodes, 0 skipped",
             color=MUTED, fontsize=10)
    out = OUT_DIR / "eval_results_dashboard.png"
    fig.savefig(out, facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    print(f"写出总览面板: {out}")


def heatmap(data):
    clean, rand = data["clean"], data["randomized"]
    order = sorted(clean, key=lambda t: -(clean[t]["rate"] + rand[t]["rate"]))
    m = np.array([[clean[t]["rate"], rand[t]["rate"]] for t in order])

    fig, ax = plt.subplots(figsize=(8.8, 13.5), dpi=140, facecolor=BG)
    fig.subplots_adjust(left=0.32, right=0.93, top=0.94, bottom=0.03)
    ax.set_facecolor(PANEL)
    cmap = LinearSegmentedColormap.from_list("rate", ["#2b1520", "#7a2f2f", "#c98b2e", "#3f8f4f", "#2f9e44"])
    im = ax.imshow(m, aspect="auto", cmap=cmap, vmin=0, vmax=100)
    ax.set_xticks([0, 1], ["demo_clean", "demo_randomized"], color=FG, fontsize=10)
    ax.set_yticks(range(len(order)), order, fontsize=6.5, color=FG)
    ax.tick_params(colors=MUTED, length=0)
    for i in range(len(order)):
        for j in range(2):
            v = m[i, j]
            ax.text(j, i, f"{v:.0f}", ha="center", va="center",
                    color="#0b0d12" if v > 55 else FG, fontsize=6)
    cb = plt.colorbar(im, ax=ax, fraction=0.035, pad=0.03)
    cb.set_label("success rate (%)", color=MUTED, fontsize=8)
    cb.ax.tick_params(colors=MUTED, labelsize=7)
    cb.outline.set_edgecolor(GRID)
    ax.set_title("Per-task success rate heatmap\n(sorted by mean of two settings)",
                 color=FG, fontsize=11, fontweight="bold", pad=16)
    for s in ax.spines.values():
        s.set_color(GRID)
    out = OUT_DIR / "eval_results_heatmap.png"
    fig.savefig(out, facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    print(f"写出热力图: {out}")


def animation(data):
    clean = {k: v["rate"] for k, v in data["clean"].items()}
    rand = {k: v["rate"] for k, v in data["randomized"].items()}
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
        s.set_color(GRID)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)

    fig.text(0.03, 0.955, "RoboTwin 2.0 · Aloha-AgileX", color=FG,
             fontsize=16, fontweight="bold")
    fig.text(0.03, 0.915, "50 tasks × 100 episodes per task", color=MUTED, fontsize=10)
    fig.text(0.03, 0.875, "■ demo_clean", color=CLEAN_C, fontsize=10)
    fig.text(0.19, 0.875, "■ demo_randomized", color=RAND_C, fontsize=10)

    bc = ax.barh(y, [0] * n, color=CLEAN_C, height=0.38, zorder=3)
    br = ax.barh([v - 0.21 for v in y], [0] * n, color=RAND_C, height=0.38, zorder=3)

    stat_txt = ax2.text(0, 0.62, "", color=FG, fontsize=11, ha="center", va="center")
    done_txt = fig.text(0.03, 0.045,
                        "equivalent 10000 steps · LingBot-VLA 2.0 · bf16 inference",
                        color=MUTED, fontsize=9)

    def frame(k):
        m = k + 1
        for i in range(n):
            bc[i].set_width(clean[order[i]] if i < m else 0)
            br[i].set_width(rand[order[i]] if i < m else 0)
        sub_tasks = order[:m]
        c_sum = sum(clean[t] for t in sub_tasks)
        r_sum = sum(rand[t] for t in sub_tasks)
        stat_txt.set_text(f"{m}/{n}\ntasks\n\nclean\n{c_sum/m:.0f}%\n\nrand\n{r_sum/m:.0f}%")
        done_txt.set_text("equivalent 10000 steps · LingBot-VLA 2.0 · bf16 inference")

    anim = FuncAnimation(fig, frame, frames=n, interval=90, blit=False)
    gif = OUT_DIR / "eval_results_animation.gif"
    anim.save(gif, writer=PillowWriter(fps=10))
    plt.close(fig)
    print(f"写出动图: {gif}")


def summary(data):
    clean = {k: v["rate"] for k, v in data["clean"].items()}
    rand = {k: v["rate"] for k, v in data["randomized"].items()}
    order = sorted(clean, key=lambda t: -clean[t])
    n = len(order)
    total_clean = sum(clean.values()) / n
    total_rand = sum(rand.values()) / n

    fig, axb = plt.subplots(figsize=(11, 6.2), dpi=140, facecolor=BG)
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
        s.set_color(GRID)
    axb.grid(axis="y", color=GRID, linewidth=0.8)
    axb.set_axisbelow(True)
    axb.legend(facecolor=BG, edgecolor=GRID, labelcolor=FG, fontsize=10)
    axb.set_title(f"RoboTwin 2.0 Aloha-AgileX · clean {total_clean:.1f}%  |  "
                  f"randomized {total_rand:.1f}%",
                  color=FG, fontsize=14, fontweight="bold", pad=14)
    for t in axb.get_xticklabels():
        t.set_color(FG)
    png = OUT_DIR / "eval_results_summary.png"
    fig.savefig(png, facecolor=BG, bbox_inches="tight")
    plt.close(fig)
    print(f"写出静态图: {png}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    data = load()
    animation(data)
    summary(data)
    dashboard(data)
    heatmap(data)


if __name__ == "__main__":
    main()
