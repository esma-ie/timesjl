# demo12_uc_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_uc (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP, with the case's own DD
file in `reference/dd/demo12_uc`) as the reference harness patches it for the as_run variant
(`reference/python/runfile.py` `patch_run`), copied on 10 Nov 2026 from the GAMS 54.6.1 reference
run (`raw/tjl_presolve.run`) with line ends made LF. It is the run of the input dump
`../demo12_uc_input`.

`test/unit/test_m13_chain.jl` compiles it with the DD files of the pinned TIMES_Demo download and
the case's own, compares the result with `../demo12_uc_input`, and goes on to the model, which it
compares with `../demo12_uc_matrix` and `../demo12_uc_solution.json` (M1.4 change 6; the model from
M1.3 change 40, when the unit commitment by start-up type was translated).
