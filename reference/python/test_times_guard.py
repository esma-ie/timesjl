"""make_reference.check_same_times: a reference holds the dumps of one TIMES source (harness 0.3.8).

Checked end to end on 26 Nov 2026 with GAMS 54.6.1 in a scratch folder: a demo12 pre-solve
reference made with v4.9.8 @ 7064680 was refused both an --only pass and a full run from
v4.9.7 @ d9a6a25, and the folder was left as it was.
"""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_reference import check_same_times  # noqa: E402

V497 = {"version": "4.9.7", "commit": "d9a6a25ad25ca080202a53d694de816ac3f7324e", "path": "a"}
V498 = {"version": "4.9.8", "commit": "7064680430fe6e42ef3a29a1472ad54a0f8ee68f", "path": "b"}


class TimesGuard(unittest.TestCase):
    def ref(self, times):
        d = Path(tempfile.mkdtemp())
        (d / "manifest.json").write_text(json.dumps({"times": times}))
        return d

    def test_no_reference(self):
        check_same_times(Path(tempfile.mkdtemp()) / "none", V498, "x")

    def test_same_commit(self):
        check_same_times(self.ref(V498), dict(V498, path="elsewhere"), "x")

    def test_other_commit(self):
        with self.assertRaises(SystemExit):
            check_same_times(self.ref(V497), V498, "x")
        with self.assertRaises(SystemExit):
            check_same_times(self.ref(V498), V497, "x")

    def test_no_commit_falls_back_to_version(self):
        check_same_times(self.ref(dict(V498, commit=None)), V498, "x")
        with self.assertRaises(SystemExit):
            check_same_times(self.ref(dict(V497, commit=None)), dict(V498, commit=None), "x")


if __name__ == "__main__":
    unittest.main()
