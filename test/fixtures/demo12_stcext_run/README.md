# demo12_stcext_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_stcext (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP, with the DD files in
`reference/dd` that the case's entry lists) as the reference harness patches it for the as_run variant
(`reference/python/runfile.py` `patch_run`), copied on 20 Nov 2026 from the GAMS 54.6.1 reference run
(`raw/tjl_presolve.run`) with line ends made LF. It is the run of the input dump `../demo12_stcext_input`.

`test/unit/test_ddsource.jl` compiles it with the case's DD files and compares the result with
`../demo12_stcext_input` (M1.3 change 70: the stochastic extension's declarations and data, initmty.stc).
The case's model fixtures come with M1.3 changes 71-76 (`docs/m13-plan.md`).
