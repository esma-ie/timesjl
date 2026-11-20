"""Write the small dump in test/fixtures/tiny_dump used by the Julia tests.

It goes through the same writer functions as gdx2arrow.py, so the Julia tests
pin the file format shared by the Python harness and OpenTIMES.Reference without
needing GAMS. Run from the repository root:

    python reference/python/make_test_fixture.py
"""

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from gdx2arrow import write_manifest, write_symbol_table  # noqa: E402

INF = float("inf")


def main():
    out = HERE.parent.parent / "test" / "fixtures" / "tiny_dump"
    out.mkdir(parents=True, exist_ok=True)
    for f in out.glob("*"):
        f.unlink()
    symbols = []

    def add(name, kind, domain, dvals, values, typ="", desc=""):
        fname = f"{name}.arrow"
        n = write_symbol_table(out / fname, dvals, values)
        symbols.append({"name": name, "kind": kind, "type": typ, "dimension": len(domain), "domain": domain,
                        "description": desc, "records": n, "file": fname})

    # Ordered 1-D set: GAMS order is REG2 before REG1 here on purpose.
    add("REG", "set", ["*"], [["REG2", "REG1"]], {"element_text": ["second", "first"]}, desc="regions")
    add("TOP", "set", ["R", "P", "C", "IO"],
        [["REG1", "REG1", "REG2"], ["ELC01", "ELC01", "ELC01"], ["COA", "ELC", "ELC"], ["IN", "OUT", "OUT"]],
        {"element_text": ["", "", ""]})
    add("NCAP_COST", "parameter", ["R", "ALLYEAR", "P", "CUR"],
        [["REG1", "REG1", "REG2", "REG2"], ["2020", "2030", "2020", "2030"], ["ELC01"] * 4, ["EUR"] * 4],
        {"value": [1200.5, -0.0, INF, 1e-12]})
    add("G_DYEAR", "parameter", [], [], {"value": [2005.0]}, desc="discount base year")
    add("VAR_ACT", "variable", ["R", "ALLYEAR", "ALLYEAR", "P", "S"],
        [["REG1"], ["2020"], ["2020"], ["ELC01"], ["ANNUAL"]],
        {"level": [3.25], "marginal": [-0.0], "lower": [0.0], "upper": [INF], "scale": [1.0]}, typ="positive")
    add("EQE_COMBAL", "equation", ["R", "ALLYEAR", "C", "S"],
        [["REG1"], ["2020"], ["ELC"], ["ANNUAL"]],
        {"level": [10.0], "marginal": [0.05], "lower": [10.0], "upper": [10.0], "scale": [1.0]}, typ="eq")
    symbols.append({"name": "EMPTYPAR", "kind": "parameter", "type": "", "dimension": 2, "domain": ["R", "P"],
                    "description": "no records", "records": 0, "file": None})
    symbols.append({"name": "ALL_R", "kind": "alias", "alias_with": "REG", "dimension": 1, "domain": ["*"],
                    "description": "", "records": 0, "file": None})
    write_manifest(out, "make_test_fixture.py", symbols,
                   ["REG2", "REG1", "ELC01", "COA", "ELC", "IN", "OUT", "2020", "2030", "EUR", "ANNUAL"])
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
