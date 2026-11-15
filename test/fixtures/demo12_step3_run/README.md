# demo12_step3_run

`tjl_presolve.run`: the run file of the crafted case TIMES_Demo-demo12_step3 (`reference/crafted.toml`;
TIMES_Demo demo12, `etsap-TIMES/TIMES_Demo` @ 962db86, CC BY 4.0, IEA-ETSAP; with the crafted DD
files `uc.dd`, `blnd.dd`, `ips.dd`, `refit.dd`, `ls.dd` and `step3.dd` of `reference/dd/`) as the reference
harness patches it for the as_run variant (`reference/python/runfile.py` `patch_run`), copied on
15 Nov 2026 from the GAMS 54.6.1 reference run (`raw/tjl_presolve.run`) with line ends made LF. It
is the run of the input dump `../demo12_step3_input`.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download and of
`reference/dd/` and compares the result with `../demo12_step3_input`. The case's other fixtures are
`../demo12_step3_ppm`, `../demo12_step3_equ`, `../demo12_step3_step<k>` and
`../demo12_step3_step<k>_matrix` (`test/unit/test_solve_stp3.jl`, M1.5 change 7: the stepped solve
with dispatching, unit commitment, blending, storage and retirement).
