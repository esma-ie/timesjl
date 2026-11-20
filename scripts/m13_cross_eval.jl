# Layer 3 without a TIMES.jl solve: the GAMS/CPLEX optimum (end-of-run dump) evaluated in the
# TIMES.jl model, feasibility and OBJz, with GAMS's own CONVERT matrix as the baseline. For models
# where HiGHS cannot solve the TIMES.jl LP in reasonable time (OTUS9r, 6 Nov 2026).
#
#   julia --project=test scripts/m13_cross_eval.jl <model> <variant> [<variant> ...]
#
# Reads the references beside the repository (../timesjl-reference), or TIMESJL_REFERENCE.
include(joinpath(@__DIR__, "m11_probe.jl"))   # run_switches, runfile_of, as_feasible_as
using OpenTIMES, OpenTIMES.Reference, JSON
const REF = get(ENV, "TIMESJL_REFERENCE", joinpath(@__DIR__, "..", "..", "timesjl-reference"))
function cross(model, variant)
    dir = joinpath(REF, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    si = m["runs"]["solve_cplex"]["solveinfo"]
    tm = OpenTIMES.TimesModel(joinpath(dir, "presolve"); reduce=(variant == "as_run"), switches=run_switches(runfile_of(REF, model, variant)))
    t = @elapsed OpenTIMES.generate!(tm)
    mine = canonical_from_jump(tm.model)
    println("$model/$variant: generated in $(round(t; digits=1)) s; ", mine); flush(stdout)
    empty!(tm.cache); empty!(tm.data.sets); empty!(tm.data.params); tm = nothing; GC.gc(true)
    ref = canonical_from_dump(joinpath(dir, "matrix"), joinpath(dir, "matrix_dictmap"))
    x = solution_levels(joinpath(dir, "final"); columns=union(keys(mine.cols), keys(ref.cols)))
    g = evaluate_point(mine, x; nworst=20)
    gref = evaluate_point(ref, x; nworst=20)
    gobj = Float64(si["objval"])
    rel(a) = abs(a - gobj) / max(1.0, abs(gobj))
    println("  CPLEX objective (GAMS solveinfo): ", gobj)
    println("  in TIMES.jl's model: OBJz = ", g.objective, " (rel diff ", rel(g.objective), "); max row violation ",
            g.max_row_violation, ", max bound violation ", g.max_bound_violation, "; columns without a GAMS level ", length(g.missing_columns))
    println("  in GAMS's own matrix: OBJz = ", gref.objective, " (rel diff ", rel(gref.objective), "); max row violation ",
            gref.max_row_violation, ", max bound violation ", gref.max_bound_violation)
    for (k, v) in first(g.worst_rows, 5); println("    worst in TIMES.jl: ", k, " ", v, "  (in GAMS: ", get(Dict(gref.worst_rows), k, 0.0), ")"); end
    ok = as_feasible_as(g, gref) && rel(g.objective) <= 1e-6 && isempty(g.missing_columns)
    println("  ", ok ? "PASS" : "FAIL", ": CPLEX's optimum is ", g.feasible ? "feasible" : (as_feasible_as(g, gref) ? "as feasible as in GAMS's own matrix" : "NOT as feasible"),
            " in TIMES.jl's model, OBJz ", rel(g.objective) <= 1e-6 ? "equal" : "DIFFERENT", " (rtol 1e-6)"); flush(stdout)
end
for v in ARGS[2:end]; cross(ARGS[1], v); GC.gc(true); end
