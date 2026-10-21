#!/usr/bin/env python3
"""从原始评测日志生成官方模板格式的 results.json。
只读取 logs,不手填成绩:每任务取其所属 run 的最后一轮(重试后)attempts/successes。
"""
import json, os, re, glob, hashlib, subprocess

BASE = "/root/autodl-tmp/output/eval"
TEMPLATE = "/root/autodl-tmp/Botgame/docs/灵波2026/初赛评测结果模板_JSON版.json"
OUT = "/root/autodl-tmp/submission/01_评测结果/results.json"

# 已知的两个废弃 run(失败的 C5 尝试,无有效数据)
DEAD = {"_0k_demo_randomized_20261020_231422", "_0k_demo_randomized_20261020_231751"}

# setting -> run 目录
RUNS = {
    "clean": ["_0k_demo_clean_20261020_113351"],
    "randomized": [
        "_0k_demo_randomized_20261020_170237",   # A 组:36 任务
        "_0k_demo_randomized_20261020_202926",   # B 组:9 任务
        "_0k_demo_randomized_20261020_224329",   # C1
        "_0k_demo_randomized_20261020_231259",   # C2
        "_0k_demo_randomized_20261020_231319",   # C3
        "_0k_demo_randomized_20261020_231339",   # C4
        "_0k_demo_randomized_20261020_235803",   # C5
    ],
}

ANSI = re.compile(r"\x1b\[[0-9;]*m")
RATE = re.compile(r"Success rate:\s*(\d+)/(\d+)\s*=>\s*([\d.]+)%")


def parse_task(logfile):
    """日志格式: 'Success rate: <successes>/<attempts> => <pct>%'
    返回 (attempts, successes, rate_pct, n_rate_lines)"""
    last = None
    n = 0
    with open(logfile, errors="ignore") as f:
        for line in f:
            m = RATE.search(ANSI.sub("", line))
            if m:
                successes = int(m.group(1))
                attempts = int(m.group(2))
                last = (attempts, successes, float(m.group(3)))
                n += 1
    return (last[0], last[1], last[2], n) if last else None


def main():
    tpl = json.load(open(TEMPLATE))
    out = {"schema_version": tpl["schema_version"], "team_id": tpl["team_id"], "results": {}}
    audit = {}
    problems = []

    for setting, run_dirs in RUNS.items():
        res = {}
        for task in tpl["results"]["clean"].keys():
            found = None
            for rd in run_dirs:
                lg = os.path.join(BASE, rd, "eval_logs", f"{task}.log")
                if not os.path.exists(lg):
                    continue
                p = parse_task(lg)
                if p:
                    found = (p, rd)
                    break
            if found is None:
                problems.append(f"{setting}/{task}: 无日志")
                res[task] = {"attempts": 0, "successes": 0}
                continue
            (att, suc, rate, n), rd = found
            res[task] = {"attempts": att, "successes": suc}
            audit[f"{setting}/{task}"] = {"run": rd, "attempts": att, "successes": suc,
                                          "rate": rate, "rate_lines": n}
            if att != 100:
                problems.append(f"{setting}/{task}: attempts={att} (非100)")
            if suc > att:
                problems.append(f"{setting}/{task}: successes>suspects")
        out["results"][setting] = res

    # 任务名与官方模板完全一致
    for setting in out["results"]:
        assert list(out["results"][setting].keys()) == list(tpl["results"]["clean"].keys()), setting

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        json.dump(out, f, indent=2, ensure_ascii=False)

    # 汇总
    for setting in ("clean", "randomized"):
        a = sum(v["attempts"] for v in out["results"][setting].values())
        s = sum(v["successes"] for v in out["results"][setting].values())
        print(f"{setting}: tasks={len(out['results'][setting])} attempts={a} successes={s} rate={s/a*100:.1f}%")

    with open(os.path.join(os.path.dirname(OUT), "audit_attempts_successes.csv"), "w") as f:
        f.write("setting,task,attempts,successes,rate_pct,run_dir\n")
        for k, v in sorted(audit.items()):
            setting, task = k.split("/", 1)
            f.write(f"{setting},{task},{v['attempts']},{v['successes']},{v['rate']},{v['run']}\n")

    print("\n=== 异常 ===")
    if problems:
        for p in problems:
            print("  ⚠", p)
    else:
        print("  无:全部 100 attempts,任务名与官方模板一致")
    print(f"\n写出: {OUT}")


if __name__ == "__main__":
    main()
