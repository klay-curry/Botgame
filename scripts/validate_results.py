#!/usr/bin/env python3
"""Validate the shape and counts of a Tianchi results.json submission.

This checks the official template and numeric consistency. It cannot establish
that the numbers match raw evaluation logs; that comparison remains required.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEMPLATE = REPO_ROOT / "docs/灵波2026/初赛评测结果模板_JSON版.json"


def validate(result: object, template: dict, draft: bool = False) -> list[str]:
    errors: list[str] = []
    if not isinstance(result, dict):
        return ["Root must be a JSON object"]
    if set(result) != set(template):
        errors.append(f"Top-level keys must be {sorted(template)}")
    if type(result.get("schema_version")) is not int or result["schema_version"] != template["schema_version"]:
        errors.append(f"schema_version must be {template['schema_version']}")
    team_id = result.get("team_id")
    if not isinstance(team_id, str) or not team_id.strip():
        errors.append("team_id must be a nonempty string")
    elif not draft and team_id == template["team_id"]:
        errors.append("Replace the template team_id before formal submission")

    results = result.get("results")
    if not isinstance(results, dict):
        return errors + ["results must be a JSON object"]
    if set(results) != set(template["results"]):
        errors.append("results must contain exactly clean and randomized")
    for setting, expected in template["results"].items():
        actual = results.get(setting)
        if not isinstance(actual, dict):
            errors.append(f"results.{setting} must be a JSON object")
            continue
        missing = set(expected) - set(actual)
        extra = set(actual) - set(expected)
        if missing:
            errors.append(f"results.{setting} missing tasks: {', '.join(sorted(missing))}")
        if extra:
            errors.append(f"results.{setting} unexpected tasks: {', '.join(sorted(extra))}")
        for task in expected:
            if task not in actual:
                continue
            item = actual[task]
            label = f"results.{setting}.{task}"
            if not isinstance(item, dict) or set(item) != {"attempts", "successes"}:
                errors.append(f"{label} must contain only attempts and successes")
                continue
            attempts, successes = item["attempts"], item["successes"]
            if type(attempts) is not int or type(successes) is not int:
                errors.append(f"{label} attempts and successes must be integers")
                continue
            if attempts < 0 or attempts > 100 or (not draft and attempts != 100):
                errors.append(f"{label}.attempts must be {'0..100' if draft else '100'}")
            if successes < 0 or successes > attempts:
                errors.append(f"{label}.successes must be between 0 and attempts")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("results", type=Path)
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--draft", action="store_true", help="Allow fewer than 100 attempts per task")
    args = parser.parse_args()
    try:
        result = json.loads(args.results.read_text(encoding="utf-8"))
        template = json.loads(args.template.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    errors = validate(result, template, draft=args.draft)
    if errors:
        for error in errors[:20]:
            print(f"ERROR: {error}", file=sys.stderr)
        if len(errors) > 20:
            print(f"... and {len(errors) - 20} more errors", file=sys.stderr)
        return 1
    print(f"Valid {'draft' if args.draft else 'formal'} JSON structure: 50 tasks × 2 settings")
    print("Check attempts/successes against original episode logs before submission.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
