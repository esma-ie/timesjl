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
# compared less the symbols that loop assigns (STEPPED_LOOP_SYMBOLS). No model: the stepped solve
# is M1.5.

include(joinpath(@__DIR__, "m13_probe.jl"))      # M13_STEPS, M13_SEGMENTS, run_switches, runfile_of, suite_switches
include(joinpath(@__DIR__, "m14_models.jl"))     # REFGAMS, dd_model_dirs, take_local!
import HiGHS, JuMP
using TIMES: compile_run, write_dump, generate!
using TIMES.Reference: load_dump, compare_dumps, canonical_from_jump, canonical_from_dump, compare_lp
using TIMES: coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, qa_warnings!, gams_warnings,
             qa_carry!, qa_text, qa_compare

"The M1.2 coefficient stage, ppm -> coef: coefmain.mod in order, then coef_ext.vda (maindrv.mod L62-73)."
const M12_COEF = (coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!)

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
gate_segments(tm, dir) = TIMES.stepped(tm) && isdir(joinpath(dir, "equ")) ?
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
- L127, eqobsalv.mod STP EXIT (L26-82 for the last step): OBJ_SUMS, SALV_INV, OBJSCC, OBJ_DCEOH.
"""
const STEPPED_LOOP_SYMBOLS = ("YR_V1", "YR_VL", "MY_FYEAR", "G_OVERLAP", "F", "Z", "SUBT", "BACKWARD", "RT_PP", "NO_RT",
                              "RTC_NET", "RTC_PRD", "RVT", "UC_RN", "R_UC", "RTP_CAPYR", "STP_UCT", "UNCD1", "UC_BND",
                              "NO_RVP", "FIL", "PRESOL", "YK1", "OBJ_SUMS", "SALV_INV", "OBJSCC", "OBJ_DCEOH")

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
    model_check(tm, dir, model, variant; solve) -> Bool

Layer 2: the model generated from TIMES.jl's state against GAMS's CONVERT matrix (1e-9). Layer 3
with `solve`: HiGHS (TIMESJL_THREADS threads, an hour at most) against GAMS/CPLEX's objective (1e-6).
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
    JuMP.set_time_limit_sec(tm.model, 3600.0)
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
    stp = TIMES.stepped(tm)
    for (a, b) in gate_segments(tm, dir)
        isdir(joinpath(dir, b)) || (println("== ", model, "/", variant, ": no ", b, " dump; the chain ends at ", a); break)
        names = gate_symbols(tm.data)                 # the segment's start dump
        # a stepped run's pre-solve dump is the state after the loop of solve.stp (STEPPED_LOOP_SYMBOLS)
        stp && b == "presolve" && filter!(n -> !(n in STEPPED_LOOP_SYMBOLS), names)
        t = try
            @elapsed foreach(f -> f(tm), gate_steps(a, b))
        catch e
            e isa TIMES.UnportedError || rethrow()
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
        println("== ", model, "/", variant, ": the chain ends before the model (stepped run, TIMESTEP ",
                TIMES.gswitch(tm, "TIMESTEP", ""), ": the stepped solve, solve.stp, is M1.5)")
        return ok && gate
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
    for model in models, variant in ("reduce_off", "as_run")
        try
            gate13(refdir, model; roots, variant, from_dd, solve)
        catch e
            e isa TIMES.UnportedError || rethrow()
            println("== ", model, "/", variant, ": not translated: ", sprint(showerror, e))
        end
    end
end
