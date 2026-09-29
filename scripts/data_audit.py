#!/usr/bin/env python3
"""Inventory the competition clean data and audit one available task.

Inventory uses the standard library. ``--task`` additionally needs h5py and
NumPy, which are already pinned by ``ours/requirements.txt``. ZIPs are read in
place; this tool never extracts or changes the dataset.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
from io import BytesIO
import json
from pathlib import Path
import re
from typing import Callable, Iterator
from zipfile import BadZipFile, ZipFile, ZipInfo


REPO_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TEMPLATE = REPO_ROOT / "docs/灵波2026/初赛评测结果模板_JSON版.json"
HDF5_MAGIC = b"\x89HDF\r\n\x1a\n"
LFS_PREFIX = b"version https://git-lfs.github.com/spec/v1"
EPISODE_RE = re.compile(r"(?:^|/)data/episode(\d+)\.hdf5$")
EXPECTED_EPISODES = set(range(50))


def expected_tasks(template: Path) -> list[str]:
    data = json.loads(template.read_text(encoding="utf-8"))
    clean = data["results"]["clean"]
    randomized = data["results"]["randomized"]
    if not isinstance(clean, dict) or set(clean) != set(randomized) or len(clean) != 50:
        raise ValueError("Official template must list the same 50 tasks in both settings")
    return list(clean)


def task_root(root: Path, tasks: list[str]) -> Path:
    """Accept both a direct clone and the download script's dataset/ layout."""
    if any((root / task).is_dir() for task in tasks):
        return root
    if any((root / "dataset" / task).is_dir() for task in tasks):
        return root / "dataset"
    return root


def header(path: Path, size: int = 64) -> bytes:
    with path.open("rb") as stream:
        return stream.read(size)


def archive_episodes(archive: ZipFile) -> dict[int, ZipInfo]:
    found: dict[int, ZipInfo] = {}
    for info in archive.infolist():
        match = EPISODE_RE.search(info.filename)
        if match:
            number = int(match.group(1))
            if number in found:
                raise ValueError(f"Duplicate episode{number}.hdf5 in ZIP")
            found[number] = info
    return found


def inspect_zip(path: Path) -> dict:
    if not path.is_file():
        return {"kind": "missing", "episode_count": 0}
    signature = header(path)
    if signature.startswith(LFS_PREFIX):
        return {"kind": "lfs_pointer", "episode_count": 0}
    if not signature.startswith(b"PK"):
        return {"kind": "invalid", "episode_count": 0, "error": "Not a ZIP header"}
    try:
        with ZipFile(path) as archive:
            episodes = archive_episodes(archive)
    except (BadZipFile, ValueError, OSError) as exc:
        return {"kind": "invalid", "episode_count": 0, "error": str(exc)}
    ids = set(episodes)
    return {
        "kind": "zip",
        "episode_count": len(ids),
        "missing_episode_ids": sorted(EXPECTED_EPISODES - ids),
        "extra_episode_ids": sorted(ids - EXPECTED_EPISODES),
    }


def inspect_task(root: Path, task: str) -> dict:
    directory = root / task
    archive_path = directory / "aloha-agilex_clean_50.zip"
    incomplete_path = directory / "aloha-agilex_clean_50.zip.incomplete"
    data_directory = directory / "aloha-agilex_clean_50" / "data"
    files = list(data_directory.glob("episode*.hdf5"))
    real_ids = set()
    pointers = 0
    for path in files:
        match = re.fullmatch(r"episode(\d+)\.hdf5", path.name)
        if match and header(path, 8) == HDF5_MAGIC:
            real_ids.add(int(match.group(1)))
        elif header(path).startswith(LFS_PREFIX):
            pointers += 1
    zip_info = inspect_zip(archive_path)
    ready_zip = (
        zip_info["kind"] == "zip"
        and zip_info["episode_count"] == 50
        and not zip_info["missing_episode_ids"]
        and not zip_info["extra_episode_ids"]
    )
    ready_extracted = real_ids == EXPECTED_EPISODES
    if ready_extracted or ready_zip:
        status = "ready"
    elif incomplete_path.is_file():
        status = "partial"
    elif zip_info["kind"] == "lfs_pointer" or pointers:
        status = "pointer_only"
    else:
        status = "missing_or_invalid"
    return {
        "status": status,
        "source": "extracted" if ready_extracted else "zip" if ready_zip else None,
        "real_hdf5": len(real_ids),
        "pointer_hdf5": pointers,
        "zip": zip_info,
        "incomplete_bytes": incomplete_path.stat().st_size if incomplete_path.is_file() else 0,
    }


def inventory(root: Path, tasks: list[str]) -> dict:
    actual_root = task_root(root, tasks)
    details = {task: inspect_task(actual_root, task) for task in tasks}
    statuses = {status: sum(item["status"] == status for item in details.values())
                for status in ("ready", "partial", "pointer_only", "missing_or_invalid")}
    return {"data_root": str(actual_root), "total_tasks": len(tasks),
            "status_counts": statuses, "tasks": details}


@contextmanager
def episode_streams(root: Path, task: str, source: str) -> Iterator[Iterator[tuple[int, Callable[[], BytesIO | Path]]]]:
    directory = root / task
    if source == "zip":
        with ZipFile(directory / "aloha-agilex_clean_50.zip") as archive:
            entries = archive_episodes(archive)
            yield ((number, lambda info=entries[number]: BytesIO(archive.read(info)))
                   for number in sorted(entries))
    else:
        data_dir = directory / "aloha-agilex_clean_50" / "data"
        yield ((number, lambda path=data_dir / f"episode{number}.hdf5": path)
               for number in range(50))


def summarize(values, np) -> dict:
    array = np.asarray(values, dtype=np.float64)
    if not array.size:
        return {"count": 0}
    return {"count": int(array.size), "min": float(array.min()),
            "mean": float(array.mean()), "median": float(np.median(array)),
            "p95": float(np.percentile(array, 95)), "p99": float(np.percentile(array, 99)),
            "max": float(array.max())}


def audit_task(root: Path, task: str, source: str) -> dict:
    try:
        import h5py
        import numpy as np
    except ImportError as exc:
        raise RuntimeError("Task audit needs h5py and numpy from ours/requirements.txt") from exc

    episodes = []
    errors = []
    all_deltas = []
    grip_positive = [0, 0]
    grip_transitions = [0, 0]
    grip_frames = 0
    with episode_streams(root, task, source) as streams:
        for number, source_reader in streams:
            try:
                with h5py.File(source_reader(), "r") as h5:
                    actions = np.asarray(h5["joint_action/vector"], dtype=np.float64)
                    if actions.ndim != 2 or actions.shape[1] != 14 or actions.shape[0] == 0:
                        raise ValueError(f"Expected nonempty (frames, 14) actions, got {actions.shape}")
                    if not np.isfinite(actions).all():
                        raise ValueError("Nonfinite joint action")
                    frames = int(actions.shape[0])
                    cameras = {}
                    for camera in ("head_camera", "left_camera", "right_camera"):
                        path = f"observation/{camera}/rgb"
                        cameras[camera] = int(h5[path].shape[0])
                        if cameras[camera] != frames:
                            raise ValueError(f"{path} has {cameras[camera]} frames, expected {frames}")
                    arm = actions[:, list(range(6)) + list(range(7, 13))]
                    delta = np.abs(np.diff(arm, axis=0))
                    if delta.size:
                        all_deltas.append(delta.reshape(-1))
                    grip = actions[:, [6, 13]] >= 0.5
                    grip_positive[0] += int(grip[:, 0].sum())
                    grip_positive[1] += int(grip[:, 1].sum())
                    grip_transitions[0] += int(np.count_nonzero(np.diff(grip[:, 0])))
                    grip_transitions[1] += int(np.count_nonzero(np.diff(grip[:, 1])))
                    grip_frames += frames
                    episodes.append({"id": number, "frames": frames, "camera_frames": cameras,
                                     "left_gripper_ge_0_5_ratio": float(grip[:, 0].mean()),
                                     "right_gripper_ge_0_5_ratio": float(grip[:, 1].mean())})
            except (BadZipFile, OSError, KeyError, ValueError, TypeError) as exc:
                errors.append({"episode": number, "error": str(exc)})

    lengths = [item["frames"] for item in episodes]
    deltas = np.concatenate(all_deltas) if all_deltas else np.asarray([])
    return {
        "task": task, "source": source, "complete": len(episodes) == 50 and not errors,
        "episodes_valid": len(episodes), "episodes_failed": len(errors),
        "frame_count": summarize(lengths, np),
        "arm_absolute_interframe_delta": summarize(deltas, np),
        "gripper": {"left_fraction_ge_0_5": grip_positive[0] / grip_frames if grip_frames else None,
                    "right_fraction_ge_0_5": grip_positive[1] / grip_frames if grip_frames else None,
                    "left_transitions": grip_transitions[0],
                    "right_transitions": grip_transitions[1]},
        "notes": ["Interframe action deltas are not physical speeds; frame duration is unknown.",
                  "Gripper >= 0.5 is a value threshold, not an asserted open/closed label."],
        "episodes": episodes, "errors": errors,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=REPO_ROOT / "data/robotwin2.0")
    parser.add_argument("--template", type=Path, default=DEFAULT_TEMPLATE)
    parser.add_argument("--task", help="Audit one ready task's 50 HDF5 episodes")
    parser.add_argument("--output", type=Path, help="Write JSON report to this path")
    args = parser.parse_args()

    tasks = expected_tasks(args.template)
    report = inventory(args.root, tasks)
    if args.task:
        if args.task not in tasks:
            parser.error(f"Task {args.task!r} is absent from the official template")
        state = report["tasks"][args.task]
        if state["status"] != "ready":
            parser.error(f"Task {args.task!r} is {state['status']}; no complete real data to audit")
        report["audit"] = audit_task(Path(report["data_root"]), args.task, state["source"])

    payload = json.dumps(report, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(payload, encoding="utf-8")
        print(f"Wrote {args.output}; status={report['status_counts']}")
    else:
        print(payload, end="")
    return 0 if not args.task or report["audit"]["complete"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
