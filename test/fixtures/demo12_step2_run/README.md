# demo12_step2_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_step2 (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP; with the crafted DD
files `ucdyn.dd`, `ucrt.dd`, `cumc.dd` and `step2.dd` of `reference/dd/`) as the reference harness
patches it for the as_run variant (`reference/python/runfile.py` `patch_run`), copied on 15 Nov 2026
from the GAMS 54.6.1 reference run (`raw/tjl_presolve.run`) with line ends made LF. It is the run
of the input dump `../demo12_step2_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and of
`reference/dd/` and compares the result with `../demo12_step2_input`. The case's other fixtures are
`../demo12_step2_ppm`, `../demo12_step2_equ`, `../demo12_step2_step<k>` and
`../demo12_step2_step<k>_matrix` (`test/unit/test_solve_stp2.jl`, M1.5 change 5: the stepped solve
on a second case).
