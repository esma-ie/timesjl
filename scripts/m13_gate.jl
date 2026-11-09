# The M1.3 gate (docs/m13-plan.md "Gate"): the whole preprocessing chain from
# the input dump, TIMES.jl's own state carried from one segment to the next,
# compared with GAMS at every checkpoint (init, prep, prelv, ppm), then on
# through the M1.2 coefficient stage (coef) and the coef -> pre-solve step
# (presolve, M1.3 change 25), on every set and parameter at 1e-9.
#
#   julia --project=test scripts/m13_gate.jl <reference dir> [--root name=path ...] [<model> ...]
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

include(joinpath(@__DIR__, "m13_probe.jl"))      # M13_STEPS, M13_SEGMENTS, run_switches, runfile_of, suite_switches
using TIMES: coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, qa_warnings!, gams_warnings,
             qa_carry!, qa_text, qa_compare

"The M1.2 coefficient stage, ppm -> coef: coefmain.mod in order, then coef_ext.vda (maindrv.mod L62-73)."
const M12_COEF = (coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!)

"The gate's segments: M1.3's preprocessing, the M1.2 coefficient stage, then the coef -> pre-solve step."
const GATE_SEGMENTS = [filter(s -> s[1] != "coef", M13_SEGMENTS)..., ("ppm", "coef"), ("coef", "presolve")]
gate_steps(a) = a == "ppm" ? collect(M12_COEF) : [s[3] for s in M13_STEPS if s[1] == a]

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
    gate13(refdir, model; roots, variant) -> Bool

The chain input -> init -> prep -> prelv -> ppm -> coef -> presolve on one
reference run, as far as TIMES.jl translates it; true when every checkpoint
reached matches GAMS and the chain reaches ppm at least.
"""
function gate13(refdir, model; roots=Dict{String,String}(), variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || (println("== ", model, "/", variant, ": no reference"); return false)
    missing_cp = filter(c -> !isdir(joinpath(dir, c)), ["input", "init", "prep", "prelv", "ppm"])
    isempty(missing_cp) || (println("== ", model, "/", variant, ": no checkpoint dump ", join(missing_cp, ", ")); return false)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    tm = TimesModel(joinpath(dir, "input"); switches=sw)
    qa_warnings!(tm, gams_warnings(joinpath(dir, "raw", "tjl_presolve.lst")))   # $IF WARNINGS, ppmain.mod L35
    ok, t_all, reached = true, 0.0, "input"
    for (a, b) in GATE_SEGMENTS
        isdir(joinpath(dir, b)) || (println("== ", model, "/", variant, ": no ", b, " dump; the chain ends at ", a); break)
        names = gate_symbols(tm.data)                 # the segment's start dump
        t = try
            @elapsed foreach(f -> f(tm), gate_steps(a))
        catch e
            e isa TIMES.UnportedError || rethrow()
            # Before ppm a refusal fails the gate ("not translated", as run_overnight.ps1 counts it); past
            # ppm it only ends the chain, worded so that run_overnight.ps1 does not count it as a failure
            past_gate = reached in ("ppm", "coef")
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
                sum(d -> d.n_ref, r; init=0), " GAMS records; ", a, " -> ", b, " in ", round(t; digits=1), " s)")
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
        tm = carry(tm, joinpath(dir, b))
    end
    # The gate asks for the chain to ppm (docs/m13-plan.md "Gate"); past it, the coefficient stage and
    # the coef -> pre-solve step go as far as TIMES.jl translates them (reduced flows under REDUCE are
    # refused by the M1.2 coefficient stage, coef_ptr.mod L38-42 and coef_ext.vda L62-69)
    gate = reached in ("ppm", "coef", "presolve")
    println("== ", model, "/", variant, ": M1.3 chain ", ok && gate ? "PASS" : "FAIL", " to ", reached,
            " (TIMES.jl ", round(t_all; digits=1), " s)")
    return ok && gate
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models, variant in ("reduce_off", "as_run")
        try
            gate13(refdir, model; roots, variant)
        catch e
            e isa TIMES.UnportedError || rethrow()
            println("== ", model, "/", variant, ": not translated: ", sprint(showerror, e))
        end
    end
end
