"""Checks on the per-step reference of stepped (myopic) runs (harness 0.3.4).

No GAMS needed; runs in CI with the other harness tests.
"""

import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from make_reference import (STEP_DUMP_FLAGS, STEP_LOAD_FLAGS, finish, keep_steps, numbered_files,  # noqa: E402
                            optfile_name, parse_solves, step_convert_opt)

GAMS = HERE.parent / "gams"

LISTING = """\
MODEL STATISTICS

BLOCKS OF EQUATIONS         104     SINGLE EQUATIONS        5,921
BLOCKS OF VARIABLES          27     SINGLE VARIABLES        6,717
NON ZERO ELEMENTS        20,736

               S O L V E      S U M M A R Y

     MODEL   TIMES               OBJECTIVE  OBJZ
**** SOLVER STATUS     1 Normal Completion
**** MODEL STATUS      1 Optimal
**** OBJECTIVE VALUE         12397965.9863

MODEL STATISTICS

BLOCKS OF EQUATIONS         104     SINGLE EQUATIONS        1,380
BLOCKS OF VARIABLES          27     SINGLE VARIABLES        3,179
NON ZERO ELEMENTS         6,930

**** SOLVER STATUS     1 Normal Completion
**** MODEL STATUS      14 No Solution Returned
**** OBJECTIVE VALUE                0.0000

MODEL STATISTICS

BLOCKS OF EQUATIONS         104     SINGLE EQUATIONS        1,149
BLOCKS OF VARIABLES          27     SINGLE VARIABLES        2,523  2 projected
NON ZERO ELEMENTS         8,348

**** SOLVER STATUS     1 Normal Completion
**** MODEL STATUS      1 Optimal
**** OBJECTIVE VALUE         80873281.9743
"""


class StepTests(unittest.TestCase):
    def test_option_file_names(self):
        # GAMS: <model>.optfile = k reads solver.opt, .op2 ... .op9, .o10 ... .o99, .100 ... .999
        self.assertEqual([optfile_name("CONVERT", k) for k in (1, 2, 9, 10, 99, 100, 999)],
                         ["convert.opt", "convert.op2", "convert.op9", "convert.o10", "convert.o99",
                          "convert.100", "convert.999"])
        for k in (0, 1000):
            with self.assertRaises(ValueError):
                optfile_name("convert", k)

    def test_step_option_file_renames_every_output(self):
        base = (GAMS / "convert.opt").read_text()
        opt = step_convert_opt(base, 3)
        for name in ("tjl_matrix_step3.gdx", "tjl_dictmap_step3.gdx", "tjl_dict_step3.txt", "tjl_model_step3.mps"):
            self.assertIn(name, opt)
        for name in ("tjl_matrix.gdx", "tjl_dictmap.gdx", "tjl_dict.txt", "tjl_model.mps"):
            self.assertIn(name, base)
            self.assertNotIn(name, opt)
        # nothing else changes
        self.assertEqual(opt.replace("_step3", ""), base)

    def test_numbered_files_stop_at_a_gap(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            for n in ("tjl_step1.gdx", "tjl_step2.gdx", "tjl_step4.gdx", "times_p1.gdx", "TIMES_p2.gdx",
                      "tjl_point1.gdx", "demo12~data_261114_093855.gdx"):
                (d / n).write_text("")
            self.assertEqual([f.name for f in numbered_files(d, r"tjl_step(\d+)\.gdx")],
                             ["tjl_step1.gdx", "tjl_step2.gdx"])
            # GAMS's point files <model>_p<k>.gdx, in any case; never the harness's own files
            self.assertEqual([f.name.lower() for f in numbered_files(d, r"(?!tjl_).+_p(\d+)\.gdx")],
                             ["times_p1.gdx", "times_p2.gdx"])
            self.assertEqual(numbered_files(d / "none", r"tjl_step(\d+)\.gdx"), [])

    def test_parse_solves(self):
        with tempfile.TemporaryDirectory() as d:
            lst = Path(d) / "x.lst"
            lst.write_text(LISTING)
            self.assertEqual(parse_solves(lst), [
                {"step": 1, "rows": 5921, "columns": 6717, "nonzeros": 20736, "solver_status": 1, "model_status": 1,
                 "objective": 12397965.9863},
                {"step": 2, "rows": 1380, "columns": 3179, "nonzeros": 6930, "solver_status": 1, "model_status": 14,
                 "objective": 0.0},
                # "N projected" after the number of single variables (harness 0.3.5)
                {"step": 3, "rows": 1149, "columns": 2523, "nonzeros": 8348, "solver_status": 1, "model_status": 1,
                 "objective": 80873281.9743}])
            self.assertEqual(parse_solves(Path(d) / "none.lst"), [])

    def test_a_run_that_is_not_stepped_keeps_no_steps(self):
        with tempfile.TemporaryDirectory() as d:
            manifest = {"runs": {"solve_cplex": {}}, "dumps": {}}
            self.assertEqual(keep_steps(Path(d), Path(d) / "out", manifest, "solve_cplex", None), 0)
            self.assertEqual(manifest, {"runs": {"solve_cplex": {}}, "dumps": {}})

    def test_hooks_act_only_in_stepped_runs(self):
        # TIMES includes the two files when GAMS_CGI is WWW (maindrv.mod L50, solve.mod L44); the
        # first solve run of every model gets the flag, so both must leave a run that is not stepped
        # (no %STEPPED%) before their first statement.
        self.assertIn("--GAMS_CGI=WWW", STEP_DUMP_FLAGS)
        self.assertIn("--GAMS_CGI=WWW", STEP_LOAD_FLAGS)
        for name in ("www_in.cgi", "www_out.cgi"):
            code = [ln.strip() for ln in (GAMS / name).read_text().splitlines() if ln.strip() and not ln.startswith("*")]
            self.assertEqual(code[:2], ["$IF NOT SET STEPPED $EXIT", "$IF NOT SET TJL_STEPS $EXIT"], name)

    def test_steps_of_another_size_than_the_solve_run_need_a_check(self):
        with tempfile.TemporaryDirectory() as d:
            runs = {"solve_cplex": {"returncode": 0}, "convert": {"returncode": 0, "steps_match_solve": True}}
            self.assertEqual(finish(Path(d), {"runs": runs, "dumps": {"final": {}}}, "m", "v"), "OK")
            runs["convert"]["steps_match_solve"] = False
            self.assertEqual(finish(Path(d), {"runs": runs, "dumps": {"final": {}}}, "m", "v"), "CHECK")


if __name__ == "__main__":
    unittest.main()
