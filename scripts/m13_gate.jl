# The M1.3 gate (docs/m13-plan.md "Gate"): the whole preprocessing chain from
# the input dump, TIMES.jl's own state carried from one segment to the next,
# compared with GAMS at every checkpoint (init, prep, prelv, ppm), then on
# through the M1.2 coefficient stage (coef) and the coef -> pre-solve step
# (presolve, M1.3 change 25), on every set and parameter at 1e-9.
#
#   julia --project=test scripts/m13_gate.jl <reference dir> [--root name=path ...] [<model> ...]
#   julia --project=test scripts/m13_gate.jl <reference dir> --from-dd <timesjl-sources> [--solve] [--local] [<model> ...]
#
# --from-dd (M1.4 change 5): no GAMS state at all. The input is compiled from the model's own run and
# DD files (src/dd/compile.jl, the TIMES source from times_source()) and written as a dump
# (write_dump), checked against GAMS's input dump, then the chain runs on TIMES.jl's state alone: no
# checkpoint dump is read into it (no carry), they are only compared. Past pre-solve the model is
# generated and compared with GAMS's CONVERT matrix (layer 2); with --solve, HiGHS solves it and the
# objective is compared with GAMS/CPLEX's (layer 3, 1e-6). The DD folders are the suite's (scripts/m14_models.jl);
# TIM and JRC-EU-TIMES need --local (James's workstation only, logs kept there).
#
# scripts/m13_probe.jl starts each segment from GAMS's own state; here only
# the input dump comes from GAMS. At a checkpoint the state goes on in a
# TimesModel of that checkpoint's dump, so that the symbols the GAMS code
# declares after the previous checkpoint exist with their declared data; every
# symbol TIMES.jl read or wrote so far keeps TIMES.jl's value (the dump's
# value is never used for it). A symbol that neither TIMES.jl nor the
# segment's check touched is the same in both dumps (the segment ends compare
# every symbol of their start dump). Compared at each checkpoint: every set
# and parameter of the segment's start dump, less the harness's
# TJL_SOLVEINFO. The QA log TIMES.jl wrote is compared with GAMS's
# (raw/tjl_presolve_qa_check.log, harness 0.3.2 or
# reference/python/keep_qa_log.py): at ppm as the start of GAMS's, which goes
# on with pp_qack.mod's groups, and at presolve whole (M1.3 change 25b). The
# run's compilation warnings (ppmain.mod L35) are read from the pre-solve
# listing. Both variants. A path TIMES.jl does not translate yet
# (UnportedError) ends the chain there; the checkpoints before it still count.
#
# A stepped (myopic) run (TIMESTEP; M1.3 change 30) has one more checkpoint, equ (harness 0.3.3:
# after eqmain.mod and the extensions' equ_ext, maindrv.mod L79-80), compared on every symbol. Its
# pre-solve dump is not a pre-solve state: with SOLVE_NOW=NO the run still goes through the loop of
# solve.stp, every step without a solve, so the dump holds the state after the last step. It is
# compared less the symbols that loop assigns (STEPPED_LOOP_SYMBOLS). A stepped run has no single
# model: with the per-step reference (harness 0.3.4, steps/<k>/) the run is solved step by step to
# its end (M1.5 change 4, `solve_stepped!`, HiGHS), twice. First with GAMS's levels loaded between
# the steps: each step's sets and parameters against GAMS's dump after its SOLVE (layer 1), its LP
# against the LP GAMS solved (layer 2, 1e-9), and its objective against GAMS/CPLEX's, each optimum
# evaluated in the other LP (layer 3, 1e-6). Then on TIMES.jl's own levels: each step's objective
# against GAMS/CPLEX's and the last against GAMS/HiGHS's (1e-6).
# compared less the symbols that loop assigns (STEPPED_LOOP_SYMBOLS). No model: the stepped solve
# is M1.5.
#
# The wall timer (James, 14 Nov 2026; dashboard slide 12): run as a script, each (model, variant) ends
# with a line "whole run <seconds> s": the wall time from the end of the run before it to its own end,
# so with everything the run does, the comparisons with GAMS included. The first run's time starts
# where this file starts, so it also holds the loading and compilation of TIMES.jl (not Julia's own
# start, a fraction of a second). scripts/run_timing.jl reads the line.

const GATE_T0 = time()
include(joinpath(@__DIR__, "m13_probe.jl"))      # M13_STEPS, M13_SEGMENTS, run_switches, runfile_of, suite_switches
include(joinpath(@__DIR__, "m14_models.jl"))     # REFGAMS, dd_model_dirs, take_local!
import HiGHS, JuMP
using OpenTIMES: compile_run, write_dump, generate!
using OpenTIMES.Reference: load_dump, compare_dumps, canonical_from_jump, canonical_from_dump, compare_lp
using OpenTIMES: coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, qa_warnings!, gams_warnings,
             qa_carry!, qa_text, qa_compare

"The M1.2 coefficient stage, ppm -> coef: coefmain.mod in order, then coef_ext.vda (maindrv.mod L62-73)."
const M12_COEF = Tuple(f for (a, _, f) in OpenTIMES.PRESOLVE_STEPS if a == "ppm")   # src/run.jl

"The gate's segments: M1.3's preprocessing, the M1.2 coefficient stage, then the coef -> pre-solve step."
const GATE_SEGMENTS = [filter(s -> s[1] != "coef", M13_SEGMENTS)..., ("ppm", "coef"), ("coef", "presolve")]
"The coef -> pre-solve steps up to the equ checkpoint of a stepped run (mod_vars.mod, eqmain.mod, equ_ext.vda)."
const EQU_STEPS = ("prepret_decl", "eqobjinv_prep", "eqobjfix_prep", "eqobsalv_prep", "eqmain_prep")

"The steps of the segment `a` -> `b`."
function gate_steps(a, b="presolve")
    a == "ppm" && return collect(M12_COEF)
    a == "equ" && return [s[3] for s in M13_STEPS if s[1] == "coef" && !(s[2] in EQU_STEPS)]
    b == "equ" && return [s[3] for s in M13_STEPS if s[1] == "coef" && s[2] in EQU_STEPS]
    return [s[3] for s in M13_STEPS if s[1] == a]
end

"The segments of one run: a stepped run with an equ checkpoint (harness 0.3.3) goes coef -> equ -> presolve."
gate_segments(tm, dir) = OpenTIMES.stepped(tm) && isdir(joinpath(dir, "equ")) ?
                         [GATE_SEGMENTS[1:end-1]..., ("coef", "equ"), ("equ", "presolve")] : GATE_SEGMENTS

"""
The sets and parameters the loop of solve.stp (v4.9.7) assigns and does not restore, in a stepped
run's pre-solve dump (the state after the last step, each step without a solve):
- L43-57, L111-114, L303-308, the partition into steps: YR_V1, YR_VL, MY_FYEAR, G_OVERLAP, F, Z, SUBT,
  BACKWARD, RT_PP, NO_RT, and RTC_NET, RTC_PRD (L53);
- clearsol.stp L9 (L60): RVT;
- L78-94, UC_RN and R_UC; L97, RTP_CAPYR; L101-103, STP_UCT; L132-134, UNCD1; L155-161, UC_BND; L217, NO_RVP;
  L225, FIL; L295, PRESOL;
- L124, coef_alt.lin STP: L160 clears YK1 (eqflomrk.mod left it set);
- L127, eqobsalv.mod STP EXIT (L26-82 for the last step): OBJ_SUMS, SALV_INV, OBJSCC, OBJ_DCEOH;
- reached by demo12_step2: L69 and L190-191, CAP_BND; L70-75 and L176-181, UC_RHS, UC_RHSR, UC_RHST,
  UC_RHSTS, UC_RHSRT, UC_RHSRTS; L76 and L183-185, PRC_DYNUC; L96, RTP_VARP; L132-136, RXX and
  UC_T_SUM; L140-151, UC_T, UC_T_EACH, UC_T_SUCC; L195, UC_RTSUC; L196, REG_CUMCST; L186-189 and
  L227 (bnd_cum.mod in every step), COM_CUM, FLO_CUM, RC_CUMCOM.
Every one of them is compared after each step instead (`stepped_check`, steps/<k>/final).
"""
const STEPPED_LOOP_SYMBOLS = ("YR_V1", "YR_VL", "MY_FYEAR", "G_OVERLAP", "F", "Z", "SUBT", "BACKWARD", "RT_PP", "NO_RT",
                              "RTC_NET", "RTC_PRD", "RVT", "UC_RN", "R_UC", "RTP_CAPYR", "STP_UCT", "UNCD1", "UC_BND",
                              "NO_RVP", "FIL", "PRESOL", "YK1", "OBJ_SUMS", "SALV_INV", "OBJSCC", "OBJ_DCEOH",
                              "CAP_BND", "UC_RHS", "UC_RHSR", "UC_RHST", "UC_RHSTS", "UC_RHSRT", "UC_RHSRTS", "PRC_DYNUC",
                              "RTP_VARP", "RXX", "UC_T_SUM", "UC_T", "UC_T_EACH", "UC_T_SUCC", "UC_RTSUC", "REG_CUMCST",
                              "COM_CUM", "FLO_CUM", "RC_CUMCOM",
                              # under LINFLO (coef_alt.lin L137-157) and with decommissioning costs (the objective's
                              # preparation runs in every step)
                              "RTP_CAPVL", "STP_DIV", "OBJ_DIVI", "OBJ_DIVIV", "OBJ_DIVIII", "FIL2", "MY_F",
                              "COR_SALVD", "OBJ_CRFD", "OBJ_SUMS3", "SALV_DEC")

"Carry `tm`'s state (every symbol read or written, and the switches) into a TimesModel of `dir`."
function carry(tm, dir)
    nt = TimesModel(dir; switches=tm.switches)
    merge!(nt.switches, tm.switches)
    merge!(nt.data.sets, tm.data.sets)
    merge!(nt.data.params, tm.data.params)
    return qa_carry!(nt, tm)
end

"Every set and parameter of the dump `d`, less the harness's own (and the QA-log scalars unless `qa`)."
gate_symbols(d; qa=true) = sort([i.name for i in values(d.dump.symbols) if i.kind in (:set, :parameter) && i.name != "TJL_SOLVEINFO" &&
                                 (qa || !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV")))])

"""
    dd_input(dir, model, variant, sources, sw) -> (TimesModel, ok)

M1.4: compile the run's own run file (raw/tjl_presolve.run, the harness's patched copy) and DD files
without GAMS, write the result as a dump, and compare it with GAMS's input dump: every set and
parameter at 1e-9, and the label list.
"""
function dd_input(dir, model, variant, sources, sw)
    run = joinpath(dir, "raw", "tjl_presolve.run")
    out = mktempdir()
    t = @elapsed g = compile_run(run; dirs=[dd_model_dirs(sources, model); REFGAMS], globals=Dict("RUN_NAME" => model))
    tw = @elapsed write_dump(g, out; source="$model $variant: compiled from its DD files by TIMES.jl")
    mine, theirs = load_dump(out), load_dump(joinpath(dir, "input"))
    r = compare_dumps(mine, theirs)
    bad = filter(!ispass, r.symbols)
    ok = isempty(bad) && isempty(r.only_left) && isempty(r.only_right) && mine.uels == theirs.uels
    println("== ", model, "/", variant, " DD files -> input: ", ok ? "PASS" : "FAIL", " (", length(r.symbols),
            " sets and parameters, ", length(mine.uels), " labels; compiled in ", round(t; digits=1), " s, written in ",
            round(tw; digits=1), " s, ", g.warnings, " compile warnings)")
    foreach(d -> println("     ", d), first(bad, 10))
    isempty(r.only_left) || println("     reader only: ", first(r.only_left, 10))
    isempty(r.only_right) || println("     GAMS only: ", first(r.only_right, 10))
    mine.uels == theirs.uels || println("     the label lists differ")
    # REDUCE YES generates the reduced model (cal_red.red), as scripts/m13_cross_eval.jl sets it
    tm = TimesModel(out; switches=sw, reduce=uppercase(get(sw, "REDUCE", "NO")) == "YES")
    qa_warnings!(tm, g.warnings)            # $IF WARNINGS (ppmain.mod L35) from the reader's own count
    return tm, ok
end

"""
The time limit of the layer-3 HiGHS solve, in seconds: 24 hours for every model (James, 19 Nov
2026; an hour until then, which HiGHS rarely met on TIMES-NZ shift with REDUCE off).
"""
const HIGHS_TIME_LIMIT = 86400.0

"""
    model_check(tm, dir, model, variant; solve) -> Bool

Layer 2: the model generated from TIMES.jl's state against GAMS's CONVERT matrix (1e-9). Layer 3
with `solve`: HiGHS (TIMESJL_THREADS threads, 24 hours at most, HIGHS_TIME_LIMIT) against
GAMS/CPLEX's objective (1e-6).
"""
function model_check(tm, dir, model, variant; solve=false)
    ok = true
    t = @elapsed generate!(tm)
    mine = canonical_from_jump(tm.model)
    if isdir(joinpath(dir, "matrix")) && isdir(joinpath(dir, "matrix_dictmap"))
        cmp = compare_lp(mine, canonical_from_dump(joinpath(dir, "matrix"), joinpath(dir, "matrix_dictmap")))
        ok &= ispass(cmp)
        println("== ", model, "/", variant, " model vs GAMS's matrix: ", ispass(cmp) ? "PASS" : "FAIL", " (",
                length(mine.rows), " rows, ", length(mine.cols), " columns, ", length(mine.coefs), " nonzeros; generated in ",
                round(t; digits=1), " s)")
        ispass(cmp) || foreach(e -> println("     ", e), first(cmp.examples, 10))
    else
        println("== ", model, "/", variant, " model: generated in ", round(t; digits=1), " s; no CONVERT matrix to compare")
    end
    solve || return ok
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    si = get(get(get(m, "runs", Dict()), "solve_cplex", Dict()), "solveinfo", Dict())
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer)
    JuMP.set_silent(tm.model)
    JuMP.set_attribute(tm.model, "threads", parse(Int, get(ENV, "TIMESJL_THREADS", "12")))
    JuMP.set_time_limit_sec(tm.model, HIGHS_TIME_LIMIT)
    ts = @elapsed JuMP.optimize!(tm.model)
    st = JuMP.termination_status(tm.model)
    if st != JuMP.OPTIMAL
        println("== ", model, "/", variant, " HiGHS solve: FAIL (", st, " after ", round(ts; digits=1), " s)")
        return false
    end
    obj = JuMP.objective_value(tm.model)
    gobj = get(si, "objval", nothing)
    if gobj === nothing
        println("== ", model, "/", variant, " HiGHS solve: optimal, objective ", obj, " in ", round(ts; digits=1),
                " s; no GAMS/CPLEX objective to compare")
        return ok
    end
    rel = abs(obj - gobj) / max(1.0, abs(gobj))
    ok &= rel <= 1e-6
    println("== ", model, "/", variant, " HiGHS solve vs GAMS/CPLEX: ", rel <= 1e-6 ? "PASS" : "FAIL", " (objective ",
            obj, " vs ", gobj, ", relative difference ", round(rel; sigdigits=2), "; solved in ", round(ts; digits=1), " s)")
    return ok
end

"""
    stepped_state(snap) -> TimesModel

The state of a stepped run before solve.stp, from a snapshot `snap` taken at the equ checkpoint:
a copy of its data with the rest of maindrv.mod L81-108 run on it (the steps of equ -> presolve
less `pp_clean!`, which solve.mod L12 runs inside each step). The run's REDUCE switch selects the
reduced model, as scripts/m11_probe.jl sets it.
"""
function stepped_state(snap)
    sw = snap.switches
    nt = qa_carry!(TimesModel(deepcopy(snap.data); reduce=strip(get(sw, "REDUCE", "")) == "YES", switches=sw), snap)
    foreach(f -> f(nt), filter(f -> f !== OpenTIMES.pp_clean!, gate_steps("equ", "presolve")))
    return nt
end

"""
    stepped_check(snap, dir, model, variant) -> Bool

M1.5 change 4 (docs/m15-plan.md): a stepped (myopic) run solved to its end by `solve_stepped!` with
HiGHS (TIMESJL_THREADS threads), against the per-step reference `steps/<k>/` (harness 0.3.4), twice:

- with GAMS's levels loaded after each step, so that a difference in one step cannot hide in the
  next: the sets and parameters of the step against GAMS's dump after its SOLVE (layer 1, 1e-9), its
  LP against the LP GAMS solved (layer 2, 1e-9), its objective against GAMS/CPLEX's of that step,
  GAMS's optimum evaluated in TIMES.jl's LP and HiGHS's optimum in GAMS's LP (layer 3, 1e-6);
- on TIMES.jl's own levels (the run as a user makes it): the objective of each step against
  GAMS/CPLEX's, and of the last step against GAMS/HiGHS's (1e-6). The LPs of the later steps are
  not compared there: where a step has more than one optimum, HiGHS and CPLEX may fix the periods
  solved at different levels.
"""
function stepped_check(snap, dir, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    runs = get(m, "runs", Dict())
    gsteps = get(get(runs, "solve_cplex", Dict()), "steps", Any[])
    hfinal = get(get(get(runs, "solve_highs", Dict()), "solveinfo", Dict()), "objval", nothing)
    threads = parse(Int, get(ENV, "TIMESJL_THREADS", "12"))
    rel(a, b) = abs(a - b) / max(1.0, abs(b))
    ok = true
    for own in (false, true)
        tag = string("== ", model, "/", variant, " stepped run on ", own ? "TIMES.jl's own" : "GAMS's", " levels")
        tm = stepped_state(snap)
        allok = true
        hook = function (tm, st, info)
            k = info.step
            d = joinpath(dir, "steps", string(k))
            parts, good = String[], true
            if !own
                ref = DumpData(joinpath(d, "final"))
                names = sort!([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) &&
                               !startswith(i.name, "TJL_") && i.name != "Z" &&       # Z: err_stat.mod L56-63 after the SOLVE
                               (haskey(tm.data.dump.symbols, i.name) || haskey(tm.data.sets, i.name) || haskey(tm.data.params, i.name))])
                r = layer1(tm, ref, names)
                bad = filter(!ispass, r)
                good &= isempty(bad)
                push!(parts, string("layer 1 ", isempty(bad) ? "PASS" : "FAIL", " (", length(r), " symbols)"))
                foreach(x -> println("     ", x, " ", x.examples), first(bad, 10))
                mine = canonical_from_jump(st.model)
                theirs = canonical_from_dump(joinpath(d, "matrix"), joinpath(d, "matrix_dictmap"))
                cmp = compare_lp(mine, theirs)
                good &= ispass(cmp)
                push!(parts, string("layer 2 ", ispass(cmp) ? "PASS" : "FAIL", " (", length(mine.rows), " rows, ", length(mine.cols),
                                    " columns, ", length(mine.coefs), " nonzeros)"))
                ispass(cmp) || foreach(e -> println("     ", e), first(cmp.examples, 10))
                # each optimum in the other LP
                g = evaluate_point(mine, solution_levels(joinpath(d, "final"); columns=keys(mine.cols)); nworst=typemax(Int))
                gref = g.feasible ? g : evaluate_point(theirs, solution_levels(joinpath(d, "final"); columns=keys(theirs.cols)); nworst=typemax(Int))
                e = evaluate_point(theirs, Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(st.model)))
                cross = as_feasible_as(g, gref) && e.feasible && isempty(e.missing_columns) && isempty(g.missing_columns) &&
                        rel(e.objective, info.objective) <= 1e-6
                good &= cross
                push!(parts, string("each optimum in the other LP ", cross ? "PASS" : "FAIL", " (GAMS's here: objective ", g.objective,
                                    ", largest row violation ", round(g.max_row_violation; sigdigits=2), "; HiGHS's in GAMS's LP: ",
                                    round(e.max_row_violation; sigdigits=2), ")"))
            end
            gobj = k <= length(gsteps) ? get(gsteps[k], "objective", nothing) : nothing
            if gobj === nothing
                good = false
                push!(parts, string("objective ", info.objective, "; no GAMS/CPLEX objective of this step"))
            else
                same = rel(info.objective, gobj) <= 1e-6
                good &= same
                push!(parts, string("objective vs GAMS/CPLEX ", same ? "PASS" : "FAIL", " (", info.objective, " vs ", gobj,
                                    ", relative difference ", round(rel(info.objective, gobj); sigdigits=2), ")"))
            end
            allok &= good
            println(tag, ", step ", k, " (periods ", join(info.periods, ", "), "): ", good ? "PASS" : "FAIL", "; ", join(parts, "; "),
                    "; prepared, generated, solved in ", round(info.prepare_s; digits=2), ", ", round(info.generate_s; digits=2), ", ",
                    round(info.solve_s; digits=2), " s")
            own || OpenTIMES.stp_load_point!(tm, DumpData(joinpath(d, "final")))
        end
        steps = try
            OpenTIMES.solve_stepped!(tm, HiGHS.Optimizer; attributes=("threads" => threads,), step_hook=hook)
        catch e
            e isa ErrorException || rethrow()
            println(tag, ": FAIL (", sprint(showerror, e), ")")
            ok = false
            continue
        end
        allok &= length(steps) == length(gsteps)
        note = string(length(steps), " steps, GAMS ", length(gsteps))
        if own && hfinal !== nothing && !isempty(steps)
            same = rel(steps[end].objective, hfinal) <= 1e-6
            allok &= same
            note *= string("; last objective vs GAMS/HiGHS ", same ? "PASS" : "FAIL", " (", steps[end].objective, " vs ", hfinal, ")")
        end
        ok &= allok
        println(tag, ": ", allok ? "PASS" : "FAIL", " (", note, ")")
    end
    return ok
end

"""
    gate13(refdir, model; roots, variant, from_dd=nothing, solve=false) -> Bool

The chain input -> init -> prep -> prelv -> ppm -> coef -> presolve on one
reference run, as far as TIMES.jl translates it; true when every checkpoint
reached matches GAMS and the chain reaches ppm at least.
"""
function gate13(refdir, model; roots=Dict{String,String}(), variant="reduce_off", from_dd=nothing, solve=false)
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || (println("== ", model, "/", variant, ": no reference"); return false)
    missing_cp = filter(c -> !isdir(joinpath(dir, c)), ["input", "init", "prep", "prelv", "ppm"])
    isempty(missing_cp) || (println("== ", model, "/", variant, ": no checkpoint dump ", join(missing_cp, ", ")); return false)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    ok, t_all, reached = true, 0.0, "input"
    if from_dd === nothing
        tm = TimesModel(joinpath(dir, "input"); switches=sw)
        qa_warnings!(tm, gams_warnings(joinpath(dir, "raw", "tjl_presolve.lst")))   # $IF WARNINGS, ppmain.mod L35
    else
        tm, ok = dd_input(dir, model, variant, from_dd, sw)
    end
    stp = OpenTIMES.stepped(tm)
    snap = nothing          # a stepped run: TIMES.jl's state at the equ checkpoint, for the steps
    for (a, b) in gate_segments(tm, dir)
        isdir(joinpath(dir, b)) || (println("== ", model, "/", variant, ": no ", b, " dump; the chain ends at ", a); break)
        stp && a == "equ" && isdir(joinpath(dir, "steps")) &&
            (snap = qa_carry!(TimesModel(deepcopy(tm.data); switches=tm.switches), tm))
        names = gate_symbols(tm.data)                 # the segment's start dump
        # a stepped run's pre-solve dump is the state after the loop of solve.stp (STEPPED_LOOP_SYMBOLS)
        stp && b == "presolve" && filter!(n -> !(n in STEPPED_LOOP_SYMBOLS), names)
        t = try
            @elapsed foreach(f -> f(tm), gate_steps(a, b))
        catch e
            e isa OpenTIMES.UnportedError || rethrow()
            # Before ppm a refusal fails the gate ("not translated", as run_overnight.ps1 counts it); past
            # ppm it only ends the chain, worded so that run_overnight.ps1 does not count it as a failure
            past_gate = reached in ("ppm", "coef", "equ")
            println("== ", model, "/", variant, past_gate ? ": the chain ends before $b (" : " $a -> $b: not translated (",
                    sprint(showerror, e), ")")
            break
        end
        t_all += t
        ref = DumpData(joinpath(dir, b))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n), names))
        bad = filter(!ispass, r)
        ok &= isempty(bad)
        println("== ", model, "/", variant, " input -> ", b, ": ", isempty(bad) ? "PASS" : "FAIL", " (", length(r), " symbols, ",
                sum(d -> d.n_ref, r; init=0), " GAMS records; ", a, " -> ", b, " in ", round(t; digits=1), " s",
                stp && b == "presolve" ? "; stepped run: less the $(length(STEPPED_LOOP_SYMBOLS)) symbols the loop of solve.stp assigns" : "", ")")
        for d in bad
            println("     ", d)
            foreach(e -> println("        ", e), d.examples)
        end
        qalog = joinpath(dir, "raw", "tjl_presolve_qa_check.log")
        if b in ("ppm", "presolve")
            if isfile(qalog)
                qok, note = qa_compare(qa_text(tm), read(qalog, String); complete=b == "presolve")
                ok &= qok
                println("== ", model, "/", variant, " QA log at ", b, ": ", qok ? "PASS" : "FAIL", " (", note, ")")
            else
                println("== ", model, "/", variant, " QA log at ", b, ": no GAMS log (reference/python/keep_qa_log.py)")
            end
        end
        reached = b
        # from DD files, TIMES.jl's state goes on alone: the checkpoint dumps are only compared
        from_dd === nothing && (tm = carry(tm, joinpath(dir, b)))
    end
    # The gate asks for the chain to ppm (docs/m13-plan.md "Gate"); past it, the coefficient stage and
    # the coef -> pre-solve step go as far as TIMES.jl translates them (reduced flows under REDUCE are
    # refused by the M1.2 coefficient stage, coef_ptr.mod L38-42 and coef_ext.vda L62-69)
    gate = reached in ("ppm", "coef", "equ", "presolve")
    println("== ", model, "/", variant, ": M1.3 chain", from_dd === nothing ? " " : " from DD files ",
            ok && gate ? "PASS" : "FAIL", " to ", reached, " (TIMES.jl ", round(t_all; digits=1), " s)")
    # M1.4: the model from TIMES.jl's own state, against GAMS's matrix and objective
    if stp
        # M1.5: no single model; the steps of solve.stp, each against GAMS's (stepped_check)
        if snap === nothing || reached != "presolve"
            println("== ", model, "/", variant, ": stepped run (TIMESTEP ", OpenTIMES.gswitch(tm, "TIMESTEP", ""), "): ",
                    snap === nothing ? "no per-step reference (steps/, harness 0.3.4), the steps are not run" :
                                       "the chain did not reach the pre-solve state, the steps are not run")
            return ok && gate
        end
        return stepped_check(snap, dir, model, variant) && ok && gate
    end
    reached == "presolve" && (from_dd !== nothing || solve) && (ok &= model_check(tm, dir, model, variant; solve))
    return ok && gate
end

if abspath(PROGRAM_FILE) == @__FILE__
    args = collect(ARGS)
    take_local!(args)
    solve = "--solve" in args
    filter!(!=("--solve"), args)
    i = findfirst(==("--from-dd"), args)
    from_dd = i === nothing ? nothing : abspath(args[i+1])
    i === nothing || deleteat!(args, i:i+1)
    refdir, roots, models = parse_probe_args(args)
    let t0 = GATE_T0
        for model in models, variant in ("reduce_off", "as_run")
            try
                gate13(refdir, model; roots, variant, from_dd, solve)
            catch e
                e isa OpenTIMES.UnportedError || rethrow()
                println("== ", model, "/", variant, ": not translated: ", sprint(showerror, e))
            end
            t1 = time()
            println("== ", model, "/", variant, ": whole run ", round(t1 - t0; digits=1), " s (wall time, with the checks against GAMS",
                    t0 == GATE_T0 ? " and the loading of TIMES.jl" : "", ")")
            t0 = t1
        end
    end
end
