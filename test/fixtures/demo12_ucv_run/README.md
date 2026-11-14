# demo12_ucv_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_ucv (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP, with the case's own DD
file in `reference/dd/demo12_ucv`) as the reference harness patches it for the as_run variant
(`reference/python/runfile.py` `patch_run`), copied on 14 Nov 2026 from the GAMS 54.6.1 reference
run (`raw/tjl_presolve.run`) with line ends made LF. It is the run of the input dump
`../demo12_ucv_input`.

`test/unit/test_m13_chain.jl` compiles it with the DD files of the pinned TIMES_Demo download and
the case's own, compares the result with `../demo12_ucv_input`, and goes on to the model, which it
compares with `../demo12_ucv_matrix` and `../demo12_ucv_solution.json` (M1.4 change 9).
