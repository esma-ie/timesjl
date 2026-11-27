# M1.0 gate check on one reference run.
#
#   julia --project=. scripts/m10_gate.jl ../timesjl-reference/TIMES_Demo-demo12/reduce_off
#
# Loads every dump the harness wrote, compares each with itself (must give zero
# differences), and prints what the CONVERT matrix export contains so the
# layer-2 adapter can be finalised (docs/discrepancies.md, U1-U2).

using TIMES.Reference
import JSON

dir = isempty(ARGS) ? error("usage: julia --project=. scripts/m10_gate.jl <reference run dir>") : ARGS[1]
manifest = JSON.parsefile(joinpath(dir, "manifest.json"))
println("Model ", manifest["model"], " / ", manifest["variant"], " — TIMES ", manifest["times"]["version"],
        " @ ", something(manifest["times"]["commit"], "?"))
for (tag, run) in manifest["runs"]
    # the pre-solve run (harness >= 0.2.0) solves nothing and has no solveinfo
    si = get(run, "solveinfo", Dict{String,Any}())
    println(rpad(tag, 16), " rc=", run["returncode"], " wall=", run["wall_s"], " s  ", run["gams_version"])
    isempty(si) || println(" "^17, join(("$k=$(si[k])" for k in sort(collect(keys(si)))), "  "))
end

ok = true
subs = ["ppm", "coef", "final", "matrix", "matrix_dictmap"]
# postsolve/ (harness 0.3.10, M1.6: the solution before the reports) where the reference has it:
# earlier references, and stepped and stochastic runs, have none
isdir(joinpath(dir, "postsolve")) && insert!(subs, 3, "postsolve")
for sub in subs
    p = joinpath(dir, sub)
    if !isdir(p)
        println(rpad(sub, 16), " MISSING")
        global ok = false
        continue
    end
    d = load_dump(p)
    t = @elapsed r = compare_dumps(d, d; kinds=(:set, :parameter, :variable, :equation))
    kinds = Dict{Symbol,Int}()
    for s in values(d.symbols)
        kinds[s.kind] = get(kinds, s.kind, 0) + 1
    end
    println(rpad(sub, 16), " ", length(d.symbols), " symbols ", kinds, "  self-compare ",
            ispass(r) ? "PASS" : "FAIL", " (", round(t; digits=1), " s)")
    ispass(r) || (global ok = false)
    if startswith(sub, "matrix")
        for name in symbol_names(d)
            s = d.symbols[uppercase(name)]
            println("    ", rpad(name, 20), rpad(string(s.kind), 10), " dim=", s.dimension, " domain=", s.domain,
                    " records=", s.records)
        end
    end
end

mps = joinpath(dir, "raw", "tjl_model.mps.gz")
if isfile(mps)
    lp = canonical_from_mps(mps; keyfn=identity)
    println("CONVERT MPS: ", lp)
    println("    first rows: ", first(sort(collect(keys(lp.rows))), 5))
    println("    first cols: ", first(sort(collect(keys(lp.cols))), 5))
end
println(ok ? "M1.0 gate: PASS" : "M1.0 gate: FAIL")
exit(ok ? 0 : 1)
