*==============================================================================*
* TIMES.jl reference harness hook (not part of TIMES); see www_in.cgi.
* Included after every SOLVE (solve.mod L44, v4.9.7), so in a stepped run once
* per step inside the WHILE loop of solve.stp (L109, L291-294), before the next
* step's periods are set (L303-308).
*   DUMP: every symbol as step TJL_STEP left it, to tjl_step<k>.gdx.
*   LOAD: the CONVERT run. CONVERT returns no solution, so the levels and
*         marginals GAMS found at this step in the solve run are loaded from
*         tjl_point<k>.gdx; the next step's model is then the solve run's.
*         The next step reads the option file number k+1 (solve.mod L14), which
*         names that step's own output files. (Number 2 also sets PRIOROPT,
*         solve.mod L15: branching priorities, which an LP does not have.)
* put_utility sets the name of the GDX file at run time; nothing is written to
* the put file itself.
*==============================================================================*
$IF NOT SET STEPPED $EXIT
$IF NOT SET TJL_STEPS $EXIT
TJL_STEP = TJL_STEP + 1;
$IFI %TJL_STEPS%==DUMP put_utility TJL_PUT 'gdxout' / 'tjl_step' TJL_STEP:0:0 '.gdx';
$IFI %TJL_STEPS%==DUMP execute_unload;
$IFI %TJL_STEPS%==LOAD put_utility TJL_PUT 'gdxin' / 'tjl_point' TJL_STEP:0:0 '.gdx';
$IFI %TJL_STEPS%==LOAD execute_loadpoint;
$IFI %TJL_STEPS%==LOAD OPTFILEID = TJL_STEP + 1;
