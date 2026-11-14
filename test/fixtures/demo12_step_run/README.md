# demo12_step_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_step (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP; the case has no DD
file of its own, only its run file in `reference/dd/demo12_step`) as the reference harness patches it
for the as_run variant (`reference/python/runfile.py` `patch_run`), copied on 14 Nov 2026 from
the GAMS 54.6.1 reference run (`raw/tjl_presolve.run`) with line ends made LF. It is the run of
the input dump `../demo12_step_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and
compares the result with `../demo12_step_input` (M1.4 change 7: the stepped-run controls,
initmty.mod L442-444). The case's other fixtures are `../demo12_step_ppm` and `../demo12_step_equ`
(`test/unit/test_stepped.jl`, M1.3 change 30); the stepped solve is M1.5.
