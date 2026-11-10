# demo12_off_run

`tjl_presolve.run`: the run file of TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ 962db86,
`model/demo12.run`; CC BY 4.0, IEA-ETSAP) as the reference harness patches it for the reduce_off
variant (`reference/python/runfile.py` `patch_run`), copied from the GAMS 54.6.1 reference run (`raw/tjl_presolve.run`, 31 Oct 2026)
with line ends made LF. The patches set REDUCE and SOLVE_NOW to NO, leave out
`option LP=`, add the TJLREF extension (`reference/gams/*.tjlref`) and the input checkpoint.

`test/unit/test_ddsource.jl` compiles it with the DD files of the pinned TIMES_Demo download
(M1.4 change 2c) and compares the result with `../demo12_off_input`.
