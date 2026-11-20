# Copy one reference run into test/fixtures as an M1.1 whole-model fixture:
#
#   <prefix>_presolve/          the pre-solve dump (model input)
#   <prefix>_matrix/matrix      the CONVERT DumpGDX matrix
#   <prefix>_matrix/dictmap     its DictMap (row/column names)
#   <prefix>_solution.json      objective and variable levels per GAMS solver
#
# Usage, from the repository root:
#   julia --project=test scripts/make_m11_fixture.jl <reference>/<model>/<variant> <prefix>
#
# Manifest source paths are rewritten to "<reference>/..." so fixtures do not
# record the machine they were made on.

using OpenTIMES
using OpenTIMES.Reference: solution_levels, canonical_from_dump
using JSON

function copy_dump(src, dst, refroot)
    isdir(dst) && rm(dst; recursive=true)
    cp(src, dst)
    mf = joinpath(dst, "manifest.json")
    text = read(mf, String)
    text = replace(text, refroot => "<reference>")
    write(mf, text)
end

function main(run_dir, prefix)
    run_dir = abspath(run_dir)
    refroot = dirname(dirname(run_dir))   # run_dir is <reference>/<model>/<variant>
    fixtures = joinpath(@__DIR__, "..", "test", "fixtures")
    manifest = JSON.parsefile(joinpath(run_dir, "manifest.json"))
    copy_dump(joinpath(run_dir, "presolve"), joinpath(fixtures, prefix * "_presolve"), refroot)
    mdir = joinpath(fixtures, prefix * "_matrix")
    mkpath(mdir)
    copy_dump(joinpath(run_dir, "matrix"), joinpath(mdir, "matrix"), refroot)
    copy_dump(joinpath(run_dir, "matrix_dictmap"), joinpath(mdir, "dictmap"), refroot)

    sol = Dict{String,Any}()
    m = match(r"GAMS (\d+\.\d+\.\d+)", manifest["runs"]["presolve"]["gams_version"])
    sol["gams"] = m === nothing ? "?" : m[1]
    sol["model"] = manifest["model"] * "/" * manifest["variant"]
    sol["times"] = manifest["times"]["version"] * " @ " * first(something(manifest["times"]["commit"], "?"), 7)
    sol["objval"] = Dict{String,Float64}()
    # Levels of the model's columns only (the dump also holds variables the
    # MODEL statement does not use).
    cols = keys(canonical_from_dump(joinpath(mdir, "matrix"), joinpath(mdir, "dictmap")).cols)
    for (tag, run) in manifest["runs"]
        startswith(tag, "solve_") || continue
        solver = uppercase(tag[7:end])
        if get(run, "returncode", 0) != 0 || !haskey(run, "solveinfo")
            # e.g. GAMS/HiGHS under a licence without it (fails above 2,000 rows): no optimum to keep
            println("skipping ", tag, ": the GAMS run failed (return code ", get(run, "returncode", "?"), ")")
            continue
        end
        info = run["solveinfo"]
        (info["modelstat"] == 1 && info["solvestat"] == 1) ||
            error("$tag did not solve to optimality: $info")
        sol["objval"][solver] = info["objval"]
        # make_reference.py: the first solver's dump is final/, the others final_<solver>/.
        final = isdir(joinpath(run_dir, "final_" * lowercase(solver))) ? "final_" * lowercase(solver) : "final"
        sol["levels_" * solver] = solution_levels(joinpath(run_dir, final); columns=cols)
    end
    open(joinpath(fixtures, prefix * "_solution.json"), "w") do io
        JSON.print(io, sol, 1)
    end
    println("wrote ", prefix, "_presolve, ", prefix, "_matrix, ", prefix, "_solution.json")
end

main(ARGS...)
