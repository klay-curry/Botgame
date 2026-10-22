#!/usr/bin/env python3
"""从原始评测日志生成官方模板格式的 results.json。

只读取日志，不手填成绩：每个任务取最新一次有效评测（重试取最后一轮）的
attempts / successes。支持把一次评测拆成多个 run 目录（分片）后合并。

用法：
  python3 scripts/gen_results_json.py --base output/eval --out output/eval/results.json
  python3 scripts/gen_results_json.py --base output/eval \
      --clean-run _0k_demo_clean_20261020_113351 \
      --randomized-run _0k_demo_randomized_20261020_170237 \
      --randomized-run _0k_demo_randomized_20261020_235803

默认自动发现 $BASE 下所有包含 eval_logs/ 的 *_demo_clean_* / *_demo_randomized_* 目录。
"""
import argparse
import csv
import json
import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;]*m")
RATE = re.compile(r"Success rate:\s*(\d+)/(\d+)\s*=>\s*([\d.]+)%")


def parse_task(logfile: Path):
    """返回 (attempts, successes, rate_pct, n_rate_lines)，取日志中最后一轮。"""
    last = None
    n = 0
    with open(logfile, errors="ignore") as f:
        for line in f:
            m = RATE.search(ANSI.sub("", line))
            if m:
                last = (int(m.group(2)), int(m.group(1)), float(m.group(3)))
                n += 1
    if last is None:
        return None
    attempts, successes, rate = last
    return attempts, successes, rate, n


def discover(base: Path, setting: str):
    dirs = []
    for d in base.iterdir() if base.is_dir() else []:
        if not d.is_dir() or f"demo_{setting}" not in d.name:
            continue
        if (d / "eval_logs").is_dir():
            dirs.append(d)
    # 最新的 run 优先；同一任务在多个分片中只取最新
    dirs.sort(key=lambda p: p.stat().st_mtime, reverse=True)
    return dirs


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--base", default=str(Path(__file__).resolve().parents[1] / "output/eval"),
                    help="评测输出根目录（默认 output/eval）")
    ap.add_argument("--template",
                    default=str(Path(__file__).resolve().parents[1] /
                                "docs/灵波2026/初赛评测结果模板_JSON版.json"),
                    help="官方 results.json 模板（用于任务顺序与 schema）")
    ap.add_argument("--out", default="", help="输出 results.json（默认 <base>/results.json）")
    ap.add_argument("--team-id", default=None, help="覆盖模板中的团队 ID")
    ap.add_argument("--clean-run", action="append", default=[],
                    help="指定 clean run 目录名或路径（可重复）")
    ap.add_argument("--randomized-run", action="append", default=[],
                    help="指定 randomized run 目录名或路径（可重复）")
    args = ap.parse_args()

    base = Path(args.base).resolve()
    template = json.load(open(args.template))
    out_path = Path(args.out) if args.out else base / "results.json"
    audit_path = out_path.parent / "audit_attempts_successes.csv"
    out_path.parent.mkdir(parents=True, exist_ok=True)

    tasks = list(template["results"]["clean"].keys())
    out = {"schema_version": template.get("schema_version", 1),
           "team_id": args.team_id or template.get("team_id", ""),
           "results": {}}
    audit = []
    problems = []

    explicit = {"clean": args.clean_run, "randomized": args.randomized_run}
    for setting in ("clean", "randomized"):
        if explicit[setting]:
            runs = []
            for r in explicit[setting]:
                p = Path(r)
                runs.append(p if p.is_absolute() else base / p)
        else:
            runs = discover(base, setting)
        if not runs:
            problems.append(f"{setting}: 未找到任何 run 目录")

        res = {}
        for task in tasks:
            found = None
            for run in runs:
                log = run / "eval_logs" / f"{task}.log"
                if not log.exists():
                    continue
                p = parse_task(log)
                if p and p[0] > 0:
                    found = (p, run)
                    break
            if found is None:
                problems.append(f"{setting}/{task}: 无有效日志")
                res[task] = {"attempts": 0, "successes": 0}
                continue
            (att, suc, rate, n), run = found
            res[task] = {"attempts": att, "successes": suc}
            audit.append({
                "setting": setting, "task": task, "attempts": att,
                "successes": suc, "rate_pct": f"{rate:.1f}", "run_dir": run.name,
                "rate_lines": n,
            })
            if att != 100:
                problems.append(f"{setting}/{task}: attempts={att}（非 100）")
            if suc > att:
                problems.append(f"{setting}/{task}: successes>attempts")
        out["results"][setting] = res

    with open(out_path, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)
    with open(audit_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["setting", "task", "attempts", "successes",
                                          "rate_pct", "run_dir", "rate_lines"])
        w.writeheader()
        w.writerows(audit)

    for setting in ("clean", "randomized"):
        a = sum(v["attempts"] for v in out["results"][setting].values())
        s = sum(v["successes"] for v in out["results"][setting].values())
        rate = s / a * 100 if a else 0.0
        print(f"{setting}: tasks={len(tasks)} attempts={a} successes={s} rate={rate:.1f}%")

    print(f"\n写出: {out_path}")
    print(f"审计: {audit_path}")
    if problems:
        print("\n=== 需要检查 ===")
        for p in problems:
            print("  ⚠", p)
    else:
        print("\n全部任务 100 attempts，无异常。")
    return 1 if any("未找到" in p for p in problems) else 0


if __name__ == "__main__":
    sys.exit(main())
