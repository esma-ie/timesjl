"""Checks on reference/suite.toml and the root pre-check in make_reference.py.

No GAMS needed; runs in CI with the other harness tests.
"""

import re
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from make_reference import check_roots, load_suite  # noqa: E402

SUITE = HERE.parent / "suite.toml"
# SPDX ids of licences that allow redistribution and derivative works
# (OSI-approved or Open Definition-conformant). NC and ND licences are not here.
OPEN_LICENCES = {
    "MIT", "BSD-2-Clause", "BSD-3-Clause", "Apache-2.0", "MPL-2.0",
    "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later", "LGPL-3.0-or-later",
    "AGPL-3.0-only", "AGPL-3.0-or-later",
    "CC0-1.0", "CC-BY-4.0", "CC-BY-SA-4.0", "ODbL-1.0", "ODC-By-1.0",
}
# Sources never used (reference/suite.toml header): the esma-cgep archive, the
# unlicensed DemoS and TIMES-GEO DD repositories.
BLOCKED_SOURCES = ("esma-cgep", "esma-cu/", "tim-gams", "demos-dd", "demos-xlsx", "Model_Demo_Adv_Veda",
                   "times-geo")
ROOTS = sorted(set(re.findall(r"\{([a-z_]+)\}", SUITE.read_text())))


class SuiteTests(unittest.TestCase):
    def test_every_model_resolves_with_all_roots(self):
        roots = {r: f"/roots/{r}" for r in ROOTS}
        suite = load_suite(SUITE, roots)
        check_roots(suite, list(suite["models"]))
        for name, model in suite["models"].items():
            filled = suite["fill"](model)
            self.assertIn(filled["kind"], ("dd", "run"), name)
            if filled["kind"] == "run":
                self.assertTrue(filled["run_file"].startswith("/roots/"), name)

    def test_demo12_entry(self):
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        m = suite["fill"](suite["models"]["TIMES_Demo-demo12"])
        self.assertEqual(m["kind"], "run")
        self.assertEqual(m["run_file"], "/roots/times_demo/model/demo12.run")
        # The bundled v4.7.3 source must never be on the include path.
        self.assertEqual(m["idirs"], ["/roots/times_demo/model"])

    def test_missing_root_fails_before_any_run(self):
        roots = {r: f"/roots/{r}" for r in ROOTS if r != "times_demo"}
        suite = load_suite(SUITE, roots)
        with self.assertRaises(SystemExit) as cm:
            check_roots(suite, ["TIMES-NZ-KEA", "TIMES_Demo-demo12"])
        self.assertIn("TIMES_Demo-demo12", str(cm.exception))
        self.assertNotIn("TIMES-NZ-KEA:", str(cm.exception))

    def test_every_model_states_an_open_licence(self):
        # CLAUDE.md "Test-model licences": only models under a clearly stated
        # open-source or open-data licence, unless the entry names an exception;
        # an exception is never redistributed.
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        for name, model in suite["models"].items():
            with self.subTest(model=name):
                self.assertIn("licence", model)
                self.assertIn(model.get("redistribute"), ("public", "summary", "private"))
                if model["licence"] not in OPEN_LICENCES:
                    self.assertIn("exception", model)
                    self.assertEqual(model["redistribute"], "private")
                if model.get("exception"):
                    self.assertEqual(model["redistribute"], "private")

    def test_every_model_states_its_provenance(self):
        # reference/suite.toml header: source_repo, licence_url, licence_checked.
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        for name, model in suite["models"].items():
            with self.subTest(model=name):
                for key in ("source_repo", "licence_url", "licence_checked"):
                    self.assertTrue(model.get(key), key)
                self.assertRegex(model["licence_url"], r"^https://")
                self.assertRegex(model["licence_checked"], r"^\d{4}-\d{2}-\d{2}$")

    def test_every_model_has_a_tier(self):
        # reference/suite.toml header, "Tiers" (James, 30 Oct 2026).
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        for name, model in suite["models"].items():
            with self.subTest(model=name):
                self.assertIn(model.get("tier"), ("core", "milestone"))
        self.assertEqual(suite["models"]["TIMES_Demo-demo12"]["tier"], "core")

    def test_at_most_one_core_case_per_model(self):
        # The core tier is the everyday loop: one baseline case per model, where a
        # model is the source root its run file comes from.
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        core = {}
        for name, model in suite["models"].items():
            if model.get("tier") != "core":
                continue
            root = re.match(r"\{([a-z_]+)\}", model.get("run_file") or model.get("dd_dir", "")).group(1)
            self.assertNotIn(root, core, f"{name} and {core.get(root)} are both core cases of {root}")
            core[root] = name

    def test_solver_lists(self):
        # reference/suite.toml header, "Solvers" (James, 14 Nov 2026): a model may list the GAMS
        # solvers of its solve runs, CPLEX (the reference solver) first; scripts/run_references.ps1
        # reads the line with a regular expression, so it stays on one line.
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        for name, model in suite["models"].items():
            if "solvers" not in model:
                continue
            with self.subTest(model=name):
                self.assertIsInstance(model["solvers"], list)
                self.assertEqual(model["solvers"][0], "CPLEX")
                self.assertLessEqual(set(model["solvers"]), {"CPLEX", "HIGHS"})
                self.assertEqual(len(set(model["solvers"])), len(model["solvers"]))
                line = "solvers = [" + ", ".join(f'"{s}"' for s in model["solvers"]) + "]"
                block = next(b for b in SUITE.read_text().split("[[model]]") if f'name = "{name}"' in b)
                self.assertIn(line, [ln.strip() for ln in block.splitlines()])
        models = suite["models"]
        self.assertEqual(models["OTCGEN-gc_ref"]["solvers"], ["CPLEX", "HIGHS"])
        self.assertEqual(models["OTNYC-s1_nyc_ref"]["solvers"], ["CPLEX", "HIGHS"])
        for name in ("OTUS9r-reference", "OTUS9r-tax1_wo_mou"):
            self.assertEqual(models[name]["solvers"], ["CPLEX"])

    def test_blocked_sources_are_not_used(self):
        # Outside comments, no model, root or path may point at a blocked source.
        text = "\n".join(l for l in SUITE.read_text().splitlines() if not l.lstrip().startswith("#"))
        for blocked in BLOCKED_SOURCES:
            self.assertNotIn(blocked.lower(), text.lower())

    def test_removed_models_stay_out(self):
        names = " ".join(load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})["models"])
        for removed in ("DemoS", "TIMES-GEO", "PROTO", "TIAM"):
            self.assertNotIn(removed, names)
        self.assertNotIn("demos_dd", SUITE.read_text().split("[[model]]", 1)[1])

    def test_unknown_model(self):
        suite = load_suite(SUITE, {r: f"/roots/{r}" for r in ROOTS})
        with self.assertRaises(SystemExit) as cm:
            check_roots(suite, ["NoSuchModel"])
        self.assertIn("unknown model 'NoSuchModel'", str(cm.exception))


CRAFTED = HERE.parent / "crafted.toml"


class CraftedTests(unittest.TestCase):
    """reference/crafted.toml: cases built on an open suite model, with files in reference/dd/."""

    def test_every_crafted_case_extends_an_open_public_model(self):
        roots = {r: f"/roots/{r}" for r in ROOTS}
        suite = load_suite(SUITE, roots)
        public_sources = {m["source_repo"] for m in suite["models"].values() if m["redistribute"] == "public"}
        crafted = load_suite(CRAFTED, roots)
        self.assertTrue(crafted["models"])
        check_roots(crafted, list(crafted["models"]))
        for name, model in crafted["models"].items():
            with self.subTest(model=name):
                self.assertNotIn(name, suite["models"])
                self.assertIn(model["licence"], OPEN_LICENCES)
                self.assertEqual(model["redistribute"], "public")
                self.assertIn(model["source_repo"], public_sources)
                for key in ("licence_url", "licence_checked"):
                    self.assertTrue(model.get(key), key)
                filled = crafted["fill"](model)
                self.assertTrue(Path(filled["run_file"]).is_file(), filled["run_file"])
                for blocked in BLOCKED_SOURCES:
                    self.assertNotIn(blocked.lower(), str(model).lower())


if __name__ == "__main__":
    unittest.main()
