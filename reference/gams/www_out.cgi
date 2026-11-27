*==============================================================================*
* TIMES.jl reference harness hook (not part of TIMES); see www_in.cgi.
* Included after every SOLVE (solve.mod L44, v4.9.8), so in a stepped run once
* per step inside the WHILE loop of solve.stp (L109, L291-294), before the next
* step's periods are set (L303-308).
*
* Part 1, the solution before the reports (harness 0.3.10, M1.6): with
* --TJL_POSTSOLVE=1 (the first solve run) every symbol goes to
* tjl_postsolve.gdx. In a run with one SOLVE from maindrv.mod L113 this point
* (solve.mod L44) is after the SOLVE (L37) and its status check (L41), and no
* statement runs between it and the report driver (maindrv.mod L114 is a
* compile-time $GOTO, L120 is rptmain.mod), so the dump holds the levels and
* marginals as the solver returned them and every set and parameter as the
* report code finds it. Not written, with the reason in tjl_postsolve_skip.txt:
*   stepped  %STEPPED% set (TIMESTEP or FIXBOH): solve.stp changes levels and
*            marginals after its last SOLVE (L299-301, L325-330), so this is
*            not the state the reports read
*   stages   %STAGES% YES (stochastic, SENSIS, SPINES): solve.stc has several
*            SOLVEs, and SENSIS reports after each one (L56, L86)
*   macro    %MACRO% YES: its reports are rptmain.tm's
*
* Part 2, the steps of a stepped run (--TJL_STEPS):
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
$IF NOT SET TJL_POSTSOLVE $GOTO TJL_STEPS_PART
$IF SET STEPPED $ECHO stepped > tjl_postsolve_skip.txt
$IF SET STEPPED $GOTO TJL_STEPS_PART
$IFI %STAGES%==YES $ECHO stages > tjl_postsolve_skip.txt
$IFI %STAGES%==YES $GOTO TJL_STEPS_PART
$IFI %MACRO%==YES $ECHO macro > tjl_postsolve_skip.txt
$IFI %MACRO%==YES $GOTO TJL_STEPS_PART
execute_unload 'tjl_postsolve.gdx';
$LABEL TJL_STEPS_PART
$IF NOT SET STEPPED $EXIT
$IF NOT SET TJL_STEPS $EXIT
TJL_STEP = TJL_STEP + 1;
$IFI %TJL_STEPS%==DUMP put_utility TJL_PUT 'gdxout' / 'tjl_step' TJL_STEP:0:0 '.gdx';
$IFI %TJL_STEPS%==DUMP execute_unload;
$IFI %TJL_STEPS%==LOAD put_utility TJL_PUT 'gdxin' / 'tjl_point' TJL_STEP:0:0 '.gdx';
$IFI %TJL_STEPS%==LOAD execute_loadpoint;
$IFI %TJL_STEPS%==LOAD OPTFILEID = TJL_STEP + 1;
