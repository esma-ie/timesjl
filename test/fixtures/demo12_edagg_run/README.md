# demo12_edagg_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_edagg (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP, with
its own DD file in `reference/dd/demo12_edagg` (`agg.dd`) and the base prices of
`reference/dd/demo12_ed/com_bprice/`, found on the include path) as the reference harness patches it for the as_run variant
(`reference/python/runfile.py` `patch_run`), copied on 19 Nov 2026 from the GAMS 54.6.1 reference
run (`raw/tjl_presolve.run`) with line ends made LF. It is the run of the input dump
`../demo12_edagg_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and
the case's own, and compares the result with `../demo12_edagg_input`.
`test/unit/test_m13_chain.jl` goes on from the DD files to the model, which it compares with
`../demo12_edagg_matrix` and `../demo12_edagg_solution.json`.
