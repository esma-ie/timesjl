# The M1.3 gate (docs/m13-plan.md "Gate"): the whole preprocessing chain from
# the input dump, TIMES.jl's own state carried from one segment to the next,
# compared with GAMS at every checkpoint (init, prep, prelv, ppm) on every set
# and parameter at 1e-9.
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
# and parameter of the segment's start dump, less the QA-log scalars PUTOUT,
# PUTGRP and ERRLEV, as at the segment ends of the probe. Both variants.

include(joinpath(@__DIR__, "m13_probe.jl"))      # M13_STEPS, M13_SEGMENTS, run_switches, runfile_of, suite_switches

"Carry `tm`'s state (every symbol read or written, and the switches) into a TimesModel of `dir`."
function carry(tm, dir)
    nt = TimesModel(dir; switches=tm.switches)
    merge!(nt.switches, tm.switches)
    merge!(nt.data.sets, tm.data.sets)
    merge!(nt.data.params, tm.data.params)
    return nt
end

"Every set and parameter of the dump `d`, less the QA-log scalars."
gate_symbols(d) = sort([i.name for i in values(d.dump.symbols) if i.kind in (:set, :parameter) && !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV"))])

"""
    gate13(refdir, model; roots, variant) -> Bool

The chain input -> init -> prep -> prelv -> ppm on one reference run; true
when every checkpoint matches GAMS.
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
    ok, t_all = true, 0.0
    # The chain runs input -> ppm; coef -> presolve (change 25) joins it once the whole step is
    # translated and the coefficient stage is carried into the chain.
    for (a, b) in filter(s -> s[1] != "coef", M13_SEGMENTS)
        names = gate_symbols(tm.data)                 # the segment's start dump
        t = @elapsed foreach(s -> s[3](tm), filter(s -> s[1] == a, M13_STEPS))
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
        tm = carry(tm, joinpath(dir, b))
    end
    println("== ", model, "/", variant, ": M1.3 chain ", ok ? "PASS" : "FAIL", " (TIMES.jl ", round(t_all; digits=1), " s)")
    return ok
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
