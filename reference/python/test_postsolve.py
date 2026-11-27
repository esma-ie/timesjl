"""The solution before the reports (postsolve/) and gdx2veda's files (vd/): harness 0.3.10, M1.6.

No GAMS needed; runs in CI with the other harness tests. Checked end to end on 27 Nov 2026 with
GAMS 54.6.1 and TIMES v4.9.8 on TIMES_Demo demo12, both variants, in a scratch folder
(reference/README.md, "The solution before the reports").
"""

import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from make_reference import (POSTSOLVE_FLAG, POSTSOLVE_SKIPS, STEP_DUMP_FLAGS, VD_SKIPS, finish,  # noqa: E402
                            keep_postsolve, keep_vd, vd_records)

GAMS = HERE.parent / "gams"
NO_POOL = {"pool": 0}


def hook_code() -> list[str]:
    return [ln.strip() for ln in (GAMS / "www_out.cgi").read_text().splitlines() if ln.strip() and not ln.startswith("*")]


def fake_gdx2veda(folder: Path, fail: bool = False) -> None:
    """A stand-in for gdx2veda in ``folder``: writes <run>.vd, .vde and .vds for the run name it is given."""
    if os.name == "nt":
        (folder / "gdx2veda.cmd").write_text(
            "@echo off\r\n" + ("exit /b 3\r\n" if fail else "") +
            # the redirection first: a digit just before > would be taken for a handle
            "> %3.vd echo *         ValueDim- PV\r\n>> %3.vd echo.\r\n"
            '>> %3.vd echo "VAR_Act","-",1.5\r\n>> %3.vd echo "VAR_Act","+",2\r\n'
            '> %3.vde echo "Attribute","-","VAR_act","Process Activity"\r\n'
            '> %3.vds echo "Commodity","REG1","ELC+","ELC"\r\n')
    else:
        exe = folder / "gdx2veda"
        exe.write_text("#!/bin/sh\n" + ("exit 3\n" if fail else "") +
                       "printf '*         ValueDim- PV\\n\\n\"VAR_Act\",\"-\",1.5\\n\"VAR_Act\",\"+\",2\\n' > \"$3.vd\"\n"
                       "printf '\"Attribute\",\"-\",\"VAR_act\",\"Process Activity\"\\n' > \"$3.vde\"\n"
                       "printf '\"Commodity\",\"REG1\",\"ELC+\",\"ELC\"\\n' > \"$3.vds\"\n")
        exe.chmod(0o755)


class Hook(unittest.TestCase):
    def test_only_the_first_solve_run_asks_for_the_dump(self):
        # www_out.cgi is included when GAMS_CGI is WWW (solve.mod L44), which the first solve run and
        # the CONVERT run of a stepped reference pass; the dump has its own flag, so only the first does
        self.assertEqual(POSTSOLVE_FLAG, "--TJL_POSTSOLVE=1")
        self.assertNotIn(POSTSOLVE_FLAG, STEP_DUMP_FLAGS)
        self.assertEqual(hook_code()[0], "$IF NOT SET TJL_POSTSOLVE $GOTO TJL_STEPS_PART")

    def test_skips_come_before_the_dump_and_name_their_reason(self):
        code = hook_code()
        dump = code.index("execute_unload 'tjl_postsolve.gdx';")
        self.assertEqual(code[dump + 1], "$LABEL TJL_STEPS_PART")
        head = code[1:dump]
        # pairs: a condition that writes the reason, then the same condition leaving
        self.assertEqual(len(head) % 2, 0)
        reasons = []
        for note, leave in zip(head[::2], head[1::2]):
            cond, _, rest = note.partition(" $ECHO ")
            reason, _, target = rest.partition(" > ")
            self.assertEqual(target, "tjl_postsolve_skip.txt")
            self.assertEqual(leave, f"{cond} $GOTO TJL_STEPS_PART")
            reasons.append(reason)
        # every reason has its text in POSTSOLVE_SKIPS (MACRO has a line for each of its four values)
        self.assertEqual(list(dict.fromkeys(reasons)), list(POSTSOLVE_SKIPS))
        self.assertEqual(reasons.count("macro"), 4)
        self.assertEqual(head[0].split(" $ECHO ")[0], "$IF SET STEPPED")
        self.assertEqual(head[2].split(" $ECHO ")[0], "$IFI %STAGES%==YES")   # SENSIS sets STAGES to Yes (maindrv.mod L34)
        self.assertTrue(set(VD_SKIPS) < set(POSTSOLVE_SKIPS))
        self.assertNotIn("stepped", VD_SKIPS)

    def test_the_dump_statement_is_the_only_new_one(self):
        # one execute_unload with a file name: nothing is declared or assigned, so every other dump
        # of the run holds what it held before
        code = hook_code()
        label = code.index("$LABEL TJL_STEPS_PART")
        statements = [ln for ln in code[:label] if not ln.startswith("$")]
        self.assertEqual(statements, ["execute_unload 'tjl_postsolve.gdx';"])


class KeepPostsolve(unittest.TestCase):
    def test_a_skipped_run_gets_a_note_and_no_dump(self):
        for reason in POSTSOLVE_SKIPS:
            with tempfile.TemporaryDirectory() as d:
                d = Path(d)
                (d / "tjl_postsolve_skip.txt").write_text(reason + "\n")
                manifest = {"runs": {"solve_cplex": {"returncode": 0}}, "dumps": {"final": {}}}
                self.assertEqual(keep_postsolve(d, d / "out", manifest, None), reason)
                self.assertEqual(manifest["postsolve_skipped"], {"reason": reason, "why": POSTSOLVE_SKIPS[reason]})
                self.assertNotIn("postsolve", manifest["dumps"])
                self.assertFalse((d / "out" / "postsolve").exists())
                # a note is not a missing dump
                self.assertEqual(finish(d, manifest, "m", "v"), "OK")

    def test_a_run_with_neither_dump_nor_note_needs_a_check(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            manifest = {"runs": {"solve_cplex": {"returncode": 0}}, "dumps": {"final": {}}}
            self.assertIsNone(keep_postsolve(d, d / "out", manifest, None))
            self.assertIn("postsolve", manifest["dumps"])
            self.assertIsNone(manifest["dumps"]["postsolve"])
            self.assertNotIn("postsolve_skipped", manifest)
            self.assertEqual(finish(d, manifest, "m", "v"), "CHECK")


class KeepVd(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        d = Path(self.tmp.name)
        self.sysdir, self.work, self.out = d / "sys", d / "work" / "m" / "v" / "solve_cplex", d / "out"
        for p in (self.sysdir, self.work, self.out):
            p.mkdir(parents=True)
        self.vdd = d / "times2veda.vdd"
        self.vdd.write_text("[DataBaseName]\n TIMES\n")
        self.manifest = {"runs": {"solve_cplex": {"returncode": 0}}, "dumps": {"final": {}}}

    def tearDown(self):
        self.tmp.cleanup()

    def keep(self, name="vd"):
        return keep_vd(str(self.sysdir), self.work, self.out, self.manifest, name, self.vdd, "demo run", NO_POOL)

    def test_files_are_kept_and_recorded(self):
        fake_gdx2veda(self.sysdir)
        (self.work / "tjl_final.gdx").write_text("")
        rec = self.keep()
        self.assertEqual(rec["returncode"], 0)
        self.assertEqual(rec["command"][1:], [str(self.work / "tjl_final.gdx"), str(self.vdd), "demo run"])
        self.assertEqual(sorted(rec["files"]), ["demo run.vd", "demo run.vde", "demo run.vds"])
        self.assertEqual([rec["files"][f]["records"] for f in sorted(rec["files"])], [2, 1, 1])
        self.assertEqual(sorted(f.name for f in (self.out / "vd").iterdir()), sorted(rec["files"]))
        self.assertEqual(len(rec["vdd_sha256"]), 64)
        self.assertIs(self.manifest["vd"]["vd"], rec)
        self.assertEqual(finish(self.out, self.manifest, "m", "v"), "OK")
        # a second solver's files go beside the first's
        self.keep("vd_highs")
        self.assertEqual(sorted(self.manifest["vd"]), ["vd", "vd_highs"])
        self.assertTrue((self.out / "vd_highs" / "demo run.vd").exists())

    def test_no_final_gdx_needs_a_check(self):
        fake_gdx2veda(self.sysdir)
        rec = self.keep()
        self.assertEqual((rec["returncode"], rec["files"], rec["error"]), (None, {}, "no tjl_final.gdx"))
        self.assertEqual(finish(self.out, self.manifest, "m", "v"), "CHECK")

    def test_a_failed_gdx2veda_needs_a_check(self):
        fake_gdx2veda(self.sysdir, fail=True)
        (self.work / "tjl_final.gdx").write_text("")
        self.assertEqual(self.keep()["returncode"], 3)
        self.assertEqual(finish(self.out, self.manifest, "m", "v"), "CHECK")

    def test_no_gdx2veda_needs_a_check(self):
        (self.work / "tjl_final.gdx").write_text("")
        self.assertEqual(self.keep()["error"], "gdx2veda not found")
        self.assertEqual(finish(self.out, self.manifest, "m", "v"), "CHECK")

    def test_stochastic_and_macro_runs_have_no_vd(self):
        fake_gdx2veda(self.sysdir)
        (self.work / "tjl_final.gdx").write_text("")
        for reason in VD_SKIPS:
            self.manifest = {"runs": {"solve_cplex": {"returncode": 0}}, "dumps": {"final": {}},
                             "postsolve_skipped": {"reason": reason}}
            self.assertIsNone(self.keep())
            self.assertEqual(self.manifest["vd_skipped"]["reason"], reason)
            self.assertNotIn("vd", self.manifest)
            self.assertEqual(finish(self.out, self.manifest, "m", "v"), "OK")
        # a stepped run has no postsolve/ but its end-of-run GDX gives the Veda files as usual
        self.manifest = {"runs": {"solve_cplex": {"returncode": 0}}, "dumps": {"final": {}},
                         "postsolve_skipped": {"reason": "stepped"}}
        self.assertEqual(self.keep()["returncode"], 0)
        self.assertNotIn("vd_skipped", self.manifest)

    def test_records_leave_out_header_and_empty_lines(self):
        f = Path(self.tmp.name) / "x.vd"
        f.write_text('*  ImportID- Scenario:x\n*   FieldSeparator- ,\n\n"A","-",1\n"B","-",2\n\n')
        self.assertEqual(vd_records(f), 2)


if __name__ == "__main__":
    unittest.main()
