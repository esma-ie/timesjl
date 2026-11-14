# Coefficient-stage timings of TIMES.jl against GAMS, per coefficient file, for
# reference runs (translation-guide.md, definition of done: "timings logged
# against GAMS"; the M1.2 gate).
#
#   julia --project=test scripts/m12_timing.jl <reference dir> [--root name=path ...] <model> [...]
#
# TIMES.jl: each translated file of the coefficient stage (scripts/m12_probe.jl
# M12_STEPS, in coefmain.mod order) runs twice on the model's ppm dump, from a
# fresh state each time; the first pass includes compilation, the second is the
# warm figure. The dump is read lazily, so a set or parameter is read (from
# Arrow) inside the first step that uses it.
#
# GAMS: the profile of one run of the reference (raw/tjl_<run>_profile.txt,
# written with profile=1) summed over the listing lines of each file. The
# listing's Include File Summary gives where each include starts (global line
# numbers, as the profile counts them): a coefficient file runs from its
# $BATINCLUDE in coefmain.mod to the next one, coef_ext.vda from maindrv.mod
# L73 (main_ext.mod coef_ext) to mod_vars (maindrv.mod L77); nested includes
# (filparam.gms, fillcost.gms, fillwave.gms, ...) count with their file.
# Unload records (the harness's dumps) are left out. The run is the reference
# solve (raw/tjl_solve_<solver>*) when there is one, else the pre-solve run;
# both execute the same coefficient stage.
#
# Timings of the two sides compare only when both ran on the same machine
# under the same limits (CLAUDE.md: 12 threads, 4 heavy runs; both sides run
# this stage on one thread).

include(joinpath(@__DIR__, "m12_probe.jl"))     # M12_STEPS, run_switches, runfile_of, suite_switches, parse_probe_args
include(joinpath(@__DIR__, "gams_profile.jl"))  # include_summary, profile_lines, prep_ranges
using Printf

"Global line ranges [from, to) of the coefficient files in one run's listing, by step name."
function coef_ranges(inc)
    base(x) = lowercase(basename(replace(x, '\\' => '/')))
    md = only(filter(r -> base(r.file) == "maindrv.mod", inc))
    kids = filter(r -> r.parent == md.seq, inc)                          # maindrv.mod's own includes
    cm = only(filter(r -> base(r.file) == "coefmain.mod", kids))
    after = filter(r -> r.loc > cm.loc, kids)
    ext = first(filter(r -> base(r.file) == "main_ext.mod", after))     # maindrv.mod L73: coef_ext
    modvars = first(filter(r -> r.loc > ext.loc, after))                 # maindrv.mod L77: mod_vars
    files = unique(r -> r.gline, filter(r -> r.parent == cm.seq && occursin(r"^coef_.*\.(mod|lin)$", base(r.file)), inc))
    ranges = Dict{String,Tuple{Int,Int}}()
    for (i, r) in enumerate(files)
        to = i < length(files) ? files[i+1].gline : ext.gline
        ranges[replace(base(r.file), r"\.(mod|lin)$" => "")] = (r.gline, to)
    end
    ranges["coef_ext"] = (ext.gline, modvars.gline)
    ranges["coefmain total"] = (cm.gline, modvars.gline)
    return ranges
end

"Each coefficient step on a fresh state from the ppm dump: (name, seconds) in order."
function timed_coef(dir, sw)
    tm = TimesModel(joinpath(dir, "ppm"); switches=sw)
    out = Tuple{String,Float64}[]
    for (name, f, _, _) in M12_STEPS
        push!(out, (name, @elapsed f(tm)))
    end
    return out
end

function timing12(refdir, model; roots=Dict{String,String}(), variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    cold = timed_coef(dir, sw)
    GC.gc(true)
    warm = timed_coef(dir, sw)
    GC.gc(true)

    raw = joinpath(dir, "raw")
    solves = sort([t for (t, r) in m["runs"] if startswith(t, "solve_") && r["returncode"] == 0 &&
                   isfile(joinpath(raw, "tjl_$(t)_profile.txt"))])
    run = isempty(solves) ? "presolve" : first(solves)
    ranges = coef_ranges(include_summary(joinpath(raw, "tjl_$run.lst")))
    prof = profile_lines(joinpath(raw, "tjl_$(run)_profile.txt"))
    gsec(name) = (r = get(ranges, name, nothing); r === nothing ? NaN : sum((s for (l, s) in prof if r[1] <= l < r[2]); init=0.0))

    println("== ", model, "/", variant, ": ", first(split(m["runs"][run]["gams_version"], "  ")), " (", run, " run) on ",
            m["host"]["platform"], ", ", m["host"]["cpus"], " cpus; TIMES.jl on ", Sys.MACHINE, ", ", Sys.CPU_THREADS,
            " threads, Julia ", VERSION)
    ratio(j, g) = g < 0.0005 ? "—" : @sprintf("%.1f", j / g)       # the profile counts milliseconds
    @printf("   %-16s %10s %10s %10s %8s\n", "file", "julia cold", "julia warm", "GAMS", "warm/GAMS")
    for (i, (name, tw)) in enumerate(warm)
        g = gsec(name)
        @printf("   %-16s %10.3f %10.3f %10.3f %8s\n", name, cold[i][2], tw, g, ratio(tw, g))
    end
    jw = sum(last, warm)
    g = gsec("coefmain total")
    @printf("   %-16s %10.3f %10.3f %10.3f %8s\n", "stage", sum(last, cold), jw, g, ratio(jw, g))
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models
        timing12(refdir, model; roots)
    end
end
