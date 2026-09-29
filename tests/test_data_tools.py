"""Focused checks for real-data detection and submission count validation."""

from copy import deepcopy
from io import BytesIO
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import data_audit  # noqa: E402
import validate_results  # noqa: E402


class DataAuditTests(unittest.TestCase):
    def test_lfs_pointers_and_partial_archive_are_not_complete_data(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            task = root / "click_bell"
            data_dir = task / "aloha-agilex_clean_50" / "data"
            data_dir.mkdir(parents=True)
            pointer = b"version https://git-lfs.github.com/spec/v1\noid sha256:abc\n"
            for index in range(50):
                (data_dir / f"episode{index}.hdf5").write_bytes(pointer)
            (task / "aloha-agilex_clean_50.zip").write_bytes(pointer)
            self.assertEqual(data_audit.inspect_task(root, "click_bell")["status"], "pointer_only")
            (task / "aloha-agilex_clean_50.zip.incomplete").write_bytes(b"PK\x03\x04")
            self.assertEqual(data_audit.inspect_task(root, "click_bell")["status"], "partial")

    def test_wrong_episode_numbers_are_not_a_complete_extract(self):
        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            data_dir = root / "click_bell" / "aloha-agilex_clean_50" / "data"
            data_dir.mkdir(parents=True)
            for index in range(50, 100):
                (data_dir / f"episode{index}.hdf5").write_bytes(data_audit.HDF5_MAGIC)
            self.assertEqual(data_audit.inspect_task(root, "click_bell")["status"], "missing_or_invalid")

    def test_audit_reads_hdf5_members_from_zip_without_extraction(self):
        try:
            import h5py
            import numpy as np
        except ImportError:
            self.skipTest("h5py and numpy are required for HDF5 auditing")

        with TemporaryDirectory() as temporary:
            root = Path(temporary)
            task_dir = root / "click_bell"
            task_dir.mkdir()
            memory = BytesIO()
            with h5py.File(memory, "w") as h5:
                actions = np.zeros((2, 14), dtype=np.float64)
                actions[1, 0] = 0.25
                actions[1, 6] = 1.0
                actions[:, 13] = 1.0
                h5.create_dataset("joint_action/vector", data=actions)
                for camera in ("head_camera", "left_camera", "right_camera"):
                    h5.create_dataset(f"observation/{camera}/rgb", data=np.zeros((2, 1)))
            with ZipFile(task_dir / "aloha-agilex_clean_50.zip", "w") as archive:
                for index in range(50):
                    archive.writestr(f"aloha-agilex_clean_50/data/episode{index}.hdf5", memory.getvalue())
            state = data_audit.inspect_task(root, "click_bell")
            self.assertEqual(state["status"], "ready")
            report = data_audit.audit_task(root, "click_bell", state["source"])
            self.assertTrue(report["complete"])
            self.assertEqual(report["frame_count"]["min"], 2)
            self.assertEqual(report["gripper"]["left_transitions"], 50)


class ResultValidationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = json.loads(data_audit.DEFAULT_TEMPLATE.read_text(encoding="utf-8"))

    def test_formal_results_require_one_hundred_attempts_per_task(self):
        result = deepcopy(self.template)
        result["team_id"] = "example-team"
        for setting in result["results"].values():
            for item in setting.values():
                item.update(attempts=100, successes=50)
        self.assertEqual(validate_results.validate(result, self.template), [])
        first = next(iter(result["results"]["clean"].values()))
        first["attempts"] = 99
        self.assertTrue(any("attempts must be 100" in error
                            for error in validate_results.validate(result, self.template)))

    def test_invalid_counts_and_boolean_are_rejected(self):
        result = deepcopy(self.template)
        first = next(iter(result["results"]["clean"].values()))
        first.update(attempts=True, successes=0)
        errors = validate_results.validate(result, self.template, draft=True)
        self.assertTrue(any("must be integers" in error for error in errors))
        first.update(attempts=2, successes=3)
        errors = validate_results.validate(result, self.template, draft=True)
        self.assertTrue(any("between 0 and attempts" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
