import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from runfile import MARK, RunFileError, build_dd_run, patch_run  # noqa: E402

TEMPLATE = (HERE.parent / "templates" / "scenario.run").read_text()

NZ_LIKE = """\
OPTION PROFILE=1, SOLVEOPT=REPLACE;
option LP=cplex;
*OPTION LP=MyOptimizer;
$SET REDUCE   'YES'
$   BATINCLUDE initsys.mod
$   BATINCLUDE initmty.mod
*$   BATINCLUDE initmty.mod DSC
$BATINCLUDE base.dd
$ BATINCLUDE maindrv.mod mod
"""


class PatchRunTests(unittest.TestCase):
    def test_template_builds_and_patches(self):
        run = build_dd_run(TEMPLATE, ["base", "syssettings.dd"], "example-dd")
        self.assertIn("$BATINCLUDE base.dd\n$BATINCLUDE syssettings.dd\n$BATINCLUDE milestonyr.dd", run)
        self.assertNotIn("output.dd", run)
        patched, rep = patch_run(run)
        self.assertIn("BATINCLUDE initmty.mod TJLREF", patched)
        self.assertIn("execute_unload 'tjl_solveinfo.gdx', TJL_SOLVEINFO;", patched)
        lines = patched.splitlines()
        k = next(i for i, ln in enumerate(lines) if "batinclude maindrv.mod" in ln.lower())
        self.assertTrue(lines[k + 1].startswith(MARK))
        # M1.3 input checkpoint just before maindrv, only with TJL_CHECKPOINTS
        self.assertEqual(lines[k - 1], "$IF SET TJL_CHECKPOINTS execute_unload 'tjl_input.gdx';")
        self.assertTrue(lines[k - 2].startswith(MARK))
        self.assertEqual(rep.input_before, lines[k].strip())

    def test_existing_extension_args_kept(self):
        text = NZ_LIKE.replace("$   BATINCLUDE initmty.mod\n", "$   BATINCLUDE initmty.mod IER\n")
        patched, rep = patch_run(text)
        self.assertIn("initmty.mod IER TJLREF", patched)
        # commented-out include is left alone
        self.assertIn("*$   BATINCLUDE initmty.mod DSC\n", patched)

    def test_override_and_lp_option(self):
        patched, rep = patch_run(NZ_LIKE, {"REDUCE": "NO"})
        lines = patched.splitlines()
        self.assertEqual(rep.overrides, {"REDUCE": "NO"})
        self.assertIn(f"{MARK} overridden: $SET REDUCE   'YES'", lines)
        k = next(i for i, ln in enumerate(lines) if "initsys.mod" in ln)
        self.assertEqual(lines[k - 1], "$SET REDUCE NO")
        self.assertEqual(rep.removed_lp_options, ["option LP=cplex;"])
        self.assertIn("*OPTION LP=MyOptimizer;", lines)  # already a comment
        self.assertFalse(any(ln.strip().lower().startswith("option lp=") for ln in lines))

    def test_idempotent_tag(self):
        once, _ = patch_run(NZ_LIKE)
        # patching an already patched file must not add a second tag
        twice, _ = patch_run(once.replace(MARK, "*x"))
        self.assertEqual(twice.count("TJLREF"), 1)

    def test_errors(self):
        with self.assertRaises(RunFileError):
            patch_run("$BATINCLUDE initsys.mod\n$ BATINCLUDE maindrv.mod mod\n")
        with self.assertRaises(RunFileError):
            build_dd_run("no placeholder here\n", ["base"], "x")

    def test_sensis_presolve_implicit_assign(self):
        # only the pre-solve run (SOLVE_NOW NO) of a run that sets SENSIS YES gets $ONIMPLICITASSIGN, just
        # before maindrv.mod (and before the input checkpoint)
        sensis = NZ_LIKE.replace("$SET REDUCE   'YES'\n", "$SET REDUCE   'YES'\n$   SET SENSIS   YES\n")
        for text, ov, want in ((sensis, {"SOLVE_NOW": "NO"}, True), (sensis, {}, False),
                               (NZ_LIKE, {"SOLVE_NOW": "NO"}, False),
                               (sensis.replace("$   SET SENSIS", "*$   SET SENSIS"), {"SOLVE_NOW": "NO"}, False)):
            patched, rep = patch_run(text, ov)
            lines = patched.splitlines()
            self.assertEqual(rep.implicit_assign, want)
            self.assertEqual("$ONIMPLICITASSIGN" in lines, want)
            if want:
                k = next(i for i, ln in enumerate(lines) if "batinclude maindrv.mod" in ln.lower())
                self.assertEqual(lines[k - 1], "$ONIMPLICITASSIGN")
                self.assertEqual(lines[k - 3], "$IF SET TJL_CHECKPOINTS execute_unload 'tjl_input.gdx';")

    def test_crlf_preserved(self):
        patched, _ = patch_run(NZ_LIKE.replace("\n", "\r\n"))
        self.assertIn("\r\n", patched)


if __name__ == "__main__":
    unittest.main()
