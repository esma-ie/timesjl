@echo off
rem Drag a TIMES .run file onto this file (in Windows Explorer) to run it with TIMES.jl, no GAMS:
rem compile the run file and the DD files in its folder, preprocess, build the model and solve it
rem with HiGHS (scripts\run_dd.jl). Julia must be on PATH. The window stays open at the end.
if "%~1"=="" (
  echo Drag a .run file onto run_dd.cmd, or: run_dd.cmd C:\path\to\model\scenario.run
  pause
  exit /b 1
)
cd /d "%~dp0.."
julia --project=test scripts\run_dd.jl "%~1" --solve
pause
