# demo12_steplin_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_steplin (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP; with the crafted DD
file `objinv.dd` of `reference/dd/demo12_objinv/`, OBJ LIN and TIMESTEP 20) as the reference harness
patches it for the as_run variant (`reference/python/runfile.py` `patch_run`), copied on 15 Nov 2026
from the GAMS 54.6.1 reference run (`raw/tjl_presolve.run`) with line ends made LF. It is the run
of the input dump `../demo12_steplin_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and of
`reference/dd/` and compares the result with `../demo12_steplin_input`. The case's other fixtures are
`../demo12_steplin_ppm`, `../demo12_steplin_equ`, `../demo12_steplin_step<k>` and
`../demo12_steplin_step<k>_matrix` (`test/unit/test_solve_stplin.jl`, M1.5 change 6: the stepped solve
with OBJ LIN).
