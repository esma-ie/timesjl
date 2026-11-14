*==============================================================================*
* TIMES.jl reference harness hook (not part of TIMES).
* TIMES includes a file of this name at maindrv.mod L50 (v4.9.7) when the
* control variable GAMS_CGI is WWW, and www_out.cgi after every SOLVE
* (solve.mod L44). The harness uses the pair for stepped (myopic) runs only
* (%STEPPED% set, initmty.mod L445-446): there solve.stp solves one model per
* step in a WHILE loop, and each step's model depends on the levels of the
* step before. In every other run, and without --TJL_STEPS, both files do
* nothing. Declarations are here because none is allowed inside the loop.
*   --TJL_STEPS=DUMP  the first solve run: a point file <model>_p<k>.gdx
*                     (levels and marginals) and a dump of every symbol
*                     (tjl_step<k>.gdx, www_out.cgi) after the SOLVE of step k
*   --TJL_STEPS=LOAD  the CONVERT run (www_out.cgi)
*==============================================================================*
$IF NOT SET STEPPED $EXIT
$IF NOT SET TJL_STEPS $EXIT
SCALAR TJL_STEP 'TIMES.jl harness: steps solved so far' / 0 /;
FILE TJL_PUT / 'tjl_steps.txt' /;
$IFI %TJL_STEPS%==DUMP OPTION SAVEPOINT=2;
