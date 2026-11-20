# Model-generation timings of TIMES.jl against GAMS, per equation family, for
# reference runs (translation-guide.md, definition of done: "timings logged
# against GAMS").
#
#   julia --project=test scripts/m11_timing.jl <reference dir> [--root name=path ...] <model> [...]
#
# For each model (reduce_off) TIMES.jl builds the model twice from the
# pre-solve dump, each generator of generate! timed separately in its order;
# the first pass includes compilation, the second is the warm figure. The dump
# is read lazily, so each set or parameter is read (from Arrow) inside the
# first step that uses it and "load" is only the manifest. The GAMS
# side is read from the run's own files: the profile of the reference solve
# (raw/tjl_solve_<solver>_profile.txt; "Equation" records are the generation
# of each equation, "Solve Fini" the hand-over of the model) and the log's
# elapsed times at "Starting execution" and "Executing <solver>". Timings of
# the two sides are comparable only when both ran on the same machine.

include(joinpath(@__DIR__, "m11_probe.jl"))     # run_switches, runfile_of, suite_switches, parse_probe_args
using Printf

"generate! in order (src/model/generate.jl), with the GAMS equations each generator writes."
const GEN_STEPS = [
    (:eq_obj!, r"^EQ_OBJ"), (:eq_actflo!, r"^EQ_ACTFLO$"), (:eq_actbnd!, r"^EQ[EGL]_ACTBND$"),
    (:eq_capact!, r"^EQ[EGL]_CAPACT$"), (:eq_cpt!, r"^EQ[EGL]_CPT$"), (:eq_cumcom!, r"^EQ_CUM(NET|PRD)$"),
    (:eq_cumflo!, r"^EQ_CUMFLO$"), (:eq_combal!, r"^EQ[EGL]_(COMBAL|COMPRD)$"),
    (:eq_floshr!, r"^EQ[EGL]_(IN|OUT)SHR$"), (:eq_ire!, r"^EQ_IRE$"), (:eq_peak!, r"^EQ_PEAK$"),
    (:eq_ptrans!, r"^EQ_PTRANS$"), (:eq_stgaux!, r"^EQ_STGAUX$"), (:eq_stgtss!, r"^EQ_(STGTSS|STSBAL)$"),
    (:eq_stgflo!, r"^EQ[EGL]_STG(IN|OUT)$"), (:eq_uc!, r"^EQ[EGL]_UC"), (:eq_acteff!, r"^EQ[EGL]_ACTEFF$"),
    (:eq_caflac!, r"^EQ[EGL]_(CAFLAC|CAPFLO)$"), (:eq_ashar!, r"^EQ[EGL]_ASHAR$")]

"Seconds and records per profile item type/name, from a GAMS profile file."
function gams_profile(path)
    eq = Dict{String,Tuple{Float64,Int}}()
    other = Dict{String,Float64}()
    for ln in eachline(path)
        f = split(ln)
        length(f) >= 5 || continue
        t = tryparse(Float64, f[3])
        t === nothing && continue
        if f[5] == "Equation" && length(f) >= 6
            s, n = get(eq, f[6], (0.0, 0))
            eq[f[6]] = (s + t, n + parse(Int, f[2]))
        else
            key = f[5] == "Solve" && length(f) >= 6 ? "Solve " * f[6] : f[5]
            other[key] = get(other, key, 0.0) + t
        end
    end
    return eq, other
end

"Elapsed seconds at the first log line containing `marker` (GAMS: `elapsed h:mm:ss.sss`)."
function gams_elapsed(log, marker)
    for ln in eachline(log)
        occursin(marker, ln) || continue
        m = match(r"elapsed (\d+):(\d+):(\d+\.\d+)", ln)
        m === nothing || return 3600 * parse(Int, m[1]) + 60 * parse(Int, m[2]) + parse(Float64, m[3])
    end
    return NaN
end

"One TIMES.jl build: load, untranslated check, each generator, bounds, objective."
function timed_build(dir, sw)
    steps = Tuple{String,Float64,Int,Float64}[]          # (step, seconds, rows, GB allocated)
    r = @timed TimesModel(dir; switches=sw)
    tm = r.value
    push!(steps, ("load pre-solve dump", r.time, 0, r.bytes / 2^30))
    r = @timed untranslated_families(tm)
    isempty(r.value) || error("untranslated families: ", join(unique(x.family for x in r.value), ", "))
    push!(steps, ("untranslated_families", r.time, 0, r.bytes / 2^30))
    for (f, _) in GEN_STEPS
        r = @timed getfield(OpenTIMES, f)(tm)
        push!(steps, (string(f), r.time, r.value, r.bytes / 2^30))
    end
    r = @timed OpenTIMES.apply_bounds!(tm)
    push!(steps, ("apply_bounds!", r.time, 0, r.bytes / 2^30))
    r = @timed JuMP.@objective(tm.model, Min, OpenTIMES.getvar!(tm, "OBJZ"))
    push!(steps, ("objective", r.time, 0, r.bytes / 2^30))
    nrow = JuMP.num_constraints(tm.model; count_variable_in_set_constraints=false)
    ncol = JuMP.num_variables(tm.model)
    return steps, nrow, ncol
end

function timing(refdir, model; roots=Dict{String,String}(), variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    pres = joinpath(dir, "presolve")

    cold, _, _ = timed_build(pres, sw)
    GC.gc(true)
    warm, nrow, ncol = timed_build(pres, sw)
    GC.gc(true)

    # GAMS: the first solve that reached its solver (licensed reference solver).
    solver = first(sort([uppercase(t[7:end]) for (t, r) in m["runs"] if startswith(t, "solve_") && r["returncode"] == 0]))
    raw = joinpath(dir, "raw")
    prof = joinpath(raw, "tjl_solve_$(lowercase(solver))_profile.txt")
    log = joinpath(raw, "tjl_solve_$(lowercase(solver)).log")
    geq, gother = gams_profile(prof)
    t_exec = gams_elapsed(log, "Starting execution")
    t_handoff = gams_elapsed(log, "Executing $(solver)")
    si = m["runs"]["solve_$(lowercase(solver))"]["solveinfo"]

    println("== ", model, "/", variant, ": ", nrow, " rows, ", ncol, " columns (GAMS: ",
            Int(si["numequ"]), " x ", Int(si["numvar"]), "); GAMS ", m["runs"]["solve_$(lowercase(solver))"]["gams_version"][1:12],
            " on ", m["host"]["platform"], ", ", m["host"]["cpus"], " cpus")
    @printf("   %-24s %10s %10s %9s %8s | %10s %9s\n", "step", "julia cold", "julia warm", "rows", "GB alloc", "GAMS s", "GAMS rows")
    matched = Set{String}()
    for (i, (step, tw, rows, gb)) in enumerate(warm)
        tc = cold[i][2]
        k = findfirst(x -> string(x[1]) == step, GEN_STEPS)
        gs, gn = 0.0, 0
        if k !== nothing
            for (name, (s, n)) in geq
                occursin(GEN_STEPS[k][2], name) || continue
                gs += s; gn += n; push!(matched, name)
            end
        end
        @printf("   %-24s %10.3f %10.3f %9d %8.2f | %10s %9s\n", step, tc, tw, rows, gb,
                k === nothing ? "" : @sprintf("%.3f", gs), k === nothing ? "" : string(gn))
    end
    unmatched = [k for k in setdiff(keys(geq), matched) if geq[k][2] > 0]     # equations with rows
    isempty(unmatched) || println("   GAMS equations not mapped to a generator: ", join(sort!(collect(unmatched)), ", "))
    jgen = sum(x[2] for x in warm if x[1] != "load pre-solve dump")
    ggen = sum(first(v) for v in values(geq))
    @printf("   TIMES.jl warm: load %.2f s, generation incl. bounds %.2f s\n", warm[1][2], jgen)
    @printf("   GAMS: compile %.2f s, execution to solver hand-off %.2f s (equations %.2f s, Solve Fini %.2f s, model status %s)\n",
            t_exec, t_handoff - t_exec, ggen, get(gother, "Solve Fini", NaN), si["modelstat"])
    @printf("   ratio TIMES.jl generation / GAMS equations + Solve Fini: %.1f\n", jgen / (ggen + get(gother, "Solve Fini", 0.0)))
end

refdir, roots, models = parse_probe_args(ARGS)
for model in models
    timing(refdir, model; roots)
end
