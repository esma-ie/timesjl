# Preprocessing timings of TIMES.jl against GAMS (docs/m13-plan.md "Gate":
# "preprocessing timed against GAMS", docs/timings.md).
#
#   julia --project=test scripts/m13_timing.jl <reference dir> [--root name=path ...] <model> [...]
#
# TIMES.jl: the preprocessing chain from the input dump (scripts/m13_gate.jl,
# TIMES.jl's own state carried across the checkpoints; the carrying is not
# timed), run twice from a fresh state; the first pass includes compilation,
# the second is the warm figure. Three parts, as maindrv.mod L55-58 runs them:
# init_ext (main_ext.mod init_ext), ppmain.mod (with prep_ext.vda and
# pp_prelv.vda inside it) and ppm_ext (main_ext.mod ppm_ext). The dumps are
# read lazily, so a symbol is read (from Arrow) inside the first step that
# uses it.
#
# GAMS: the profile of one run of the reference (raw/tjl_<run>_profile.txt,
# profile=1) summed over the listing lines of each part, from maindrv.mod's
# include of main_ext.mod init_ext (L55) to its include of ppmain.mod (L56),
# from there to main_ext.mod ppm_ext (L58), and from there to maindrv.mod's
# next include; nested includes count with their part. Unload records (the
# harness's checkpoint dumps) are left out. The run is the reference solve
# when there is one, else the pre-solve run; both execute the same lines.
#
# Timings of the two sides compare only when both ran on the same machine
# under the same limits (CLAUDE.md: 12 threads, 4 heavy runs; both sides run
# preprocessing on one thread).

include(joinpath(@__DIR__, "m13_gate.jl"))       # M13_STEPS, M13_SEGMENTS, carry, run_switches, ...
include(joinpath(@__DIR__, "m12_timing.jl"))     # include_summary, profile_lines
using Printf

const M13_PARTS = [("init_ext", ["init_ext"]),
                   ("ppmain", ["ppmain_head", "ppmain_years", "timslice", "ppmain_rtp", "preppm", "prep_ext", "preppm_shape",
                               "ppmain_topo", "ppmain_tslvl", "ppmain_life", "pp_prelv", "pp_qafs", "ppmain_dflt",
                               "ppmain_tsattr", "ppmain_flo", "ppmain_flofs", "ppmain_ire", "ppmain_bnd", "ppmain_cum",
                               "ppmain_stg", "ppmain_uc", "ppmain_ucmap", "ppmain_blend", "ppmain_reduce"]),
                   ("ppm_ext", ["ppm_ext_actef", "ppm_ext"])]

"Global line ranges [from, to) of the three preprocessing parts in one run's listing."
function prep_ranges(inc)
    base(x) = lowercase(basename(replace(x, '\\' => '/')))
    md = only(filter(r -> base(r.file) == "maindrv.mod", inc))
    kids = sort(filter(r -> r.parent == md.seq, inc); by=r -> r.loc)       # maindrv.mod's own includes
    pm = first(filter(r -> base(r.file) == "ppmain.mod", kids))
    ie = last(filter(r -> base(r.file) == "main_ext.mod" && r.loc < pm.loc, kids))   # L55: init_ext
    pe = first(filter(r -> base(r.file) == "main_ext.mod" && r.loc > pm.loc, kids))  # L58: ppm_ext
    nx = first(filter(r -> r.loc > pe.loc, kids))
    return Dict("init_ext" => (ie.gline, pm.gline), "ppmain" => (pm.gline, pe.gline), "ppm_ext" => (pe.gline, nx.gline),
                "total" => (ie.gline, nx.gline))
end

"The preprocessing chain from the input dump: seconds per step name."
function timed_chain(dir, sw)
    tm = TimesModel(joinpath(dir, "input"); switches=sw)
    t = Dict{String,Float64}()
    for (a, b) in filter(s -> s[1] != "coef", M13_SEGMENTS)       # preprocessing only (input -> ppm)
        for (_, name, f, _, _) in filter(s -> s[1] == a, M13_STEPS)
            t[name] = @elapsed f(tm)
        end
        tm = carry(tm, joinpath(dir, b))
    end
    return t
end

function timing13(refdir, model; roots=Dict{String,String}(), variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    cold = timed_chain(dir, sw)
    GC.gc(true)
    warm = timed_chain(dir, sw)
    GC.gc(true)

    raw = joinpath(dir, "raw")
    solves = sort([t for (t, r) in m["runs"] if startswith(t, "solve_") && r["returncode"] == 0 &&
                   isfile(joinpath(raw, "tjl_$(t)_profile.txt"))])
    run = isempty(solves) ? "presolve" : first(solves)
    ranges = prep_ranges(include_summary(joinpath(raw, "tjl_$run.lst")))
    prof = profile_lines(joinpath(raw, "tjl_$(run)_profile.txt"))
    gsec(name) = (r = ranges[name]; sum((s for (l, s) in prof if r[1] <= l < r[2]); init=0.0))

    println("== ", model, "/", variant, ": ", first(split(m["runs"][run]["gams_version"], "  ")), " (", run, " run) on ",
            m["host"]["platform"], ", ", m["host"]["cpus"], " cpus; TIMES.jl on ", Sys.MACHINE, ", ", Sys.CPU_THREADS,
            " threads, Julia ", VERSION)
    ratio(j, g) = g < 0.0005 ? "—" : @sprintf("%.1f", j / g)
    @printf("   %-10s %10s %10s %10s %8s\n", "part", "julia cold", "julia warm", "GAMS", "warm/GAMS")
    tc, tw = 0.0, 0.0
    for (part, steps) in M13_PARTS
        c, w = sum(s -> cold[s], steps), sum(s -> warm[s], steps)
        tc += c; tw += w
        @printf("   %-10s %10.3f %10.3f %10.3f %8s\n", part, c, w, gsec(part), ratio(w, gsec(part)))
    end
    @printf("   %-10s %10.3f %10.3f %10.3f %8s\n", "total", tc, tw, gsec("total"), ratio(tw, gsec("total")))
    slow = sort(collect(warm); by=last, rev=true)[1:min(5, length(warm))]
    println("   slowest steps (warm): ", join([@sprintf("%s %.2f s", k, v) for (k, v) in slow], ", "))
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models
        timing13(refdir, model; roots)
    end
end
