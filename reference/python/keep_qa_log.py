"""Copy the QA log of earlier reference runs into their raw/ folders.

Harness 0.3.2 (9 Nov 2026) keeps each pre-solve run's QA_CHECK.LOG as
``raw/tjl_presolve_qa_check.log``. For references made before, the log is
still in the harness's work folder (``<out>/_work/<model>/<variant>/presolve``)
as long as no later run of that model and variant replaced it. This copies it
when the work folder's listing ``tjl_presolve.lst`` is byte for byte the one
in ``raw/``, so the log comes from the very run the reference's dumps do;
otherwise the reference is left as it is (rerun the pre-solve run:
``make_reference.py --only presolve``).

    python reference/python/keep_qa_log.py --out ../timesjl-reference [<model> ...]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_reference import keep_qa_log  # noqa: E402


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--out", type=Path, required=True, help="the reference folder (make_reference.py --out)")
    p.add_argument("--work", type=Path, default=None, help="the harness's work folder (default <out>/_work)")
    p.add_argument("models", nargs="*", help="<model> folder names (default: every folder with a pre-solve listing)")
    a = p.parse_args()
    work_root = a.work or a.out / "_work"
    models = a.models or sorted(d.name for d in a.out.iterdir() if d.is_dir() and not d.name.startswith("_"))
    for m in models:
        for vdir in sorted((a.out / m).glob("*/raw")):
            variant = vdir.parent.name
            dest = vdir / "tjl_presolve_qa_check.log"
            lst, wlst = vdir / "tjl_presolve.lst", work_root / m / variant / "presolve" / "tjl_presolve.lst"
            if dest.exists():
                print(f"{m}/{variant}: kept already")
            elif not (lst.exists() and wlst.exists()):
                print(f"{m}/{variant}: no pre-solve listing here or in the work folder")
            elif lst.read_bytes() != wlst.read_bytes():
                print(f"{m}/{variant}: the work folder holds another run; rerun --only presolve")
            elif keep_qa_log(wlst.parent, dest):
                print(f"{m}/{variant}: copied")
            else:
                print(f"{m}/{variant}: the run wrote no QA log")
    return 0


if __name__ == "__main__":
    sys.exit(main())
