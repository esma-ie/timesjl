# demo12_ashar_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_ashar (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP, with the case's own DD
file in `reference/dd/demo12_ashar`) as the reference harness patches it for the as_run variant
(`reference/python/runfile.py` `patch_run`), copied on 14 Nov 2026 from the GAMS 54.6.1 reference
run (`raw/tjl_presolve.run`) with line ends made LF. It is the run of the input dump
`../demo12_ashar_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and
the case's own, and compares the result with `../demo12_ashar_input` (M1.4 change 6).
