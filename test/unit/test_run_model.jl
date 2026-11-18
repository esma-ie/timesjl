# run_model (src/run.jl, 18 Nov 2026): TIMES_Demo demo12 (CC BY 4.0) from its own run file and DD
# files, as the README's Quick start runs it, against the licensed GAMS reference runs of 31 Oct 2026:
# - the matrix size of the as_run variant (demo12.run sets REDUCE YES): fixture demo12_red in
#   test/fixtures/public_fixtures.toml (3233 rows, 4485 columns);
# - the objective: GAMS/CPLEX's OBJZ (fixture demo12_off_solution.json; reduce_off and as_run reach
#   the same optimum, 23960685.737 in both reference runs), at the layer-3 tolerance 1e-6.
using Test, TOML, JSON
import JuMP
using TIMES: times_demo_dir, run_switches, PRESOLVE_STEPS

let fx = only(filter(f -> f["prefix"] == "demo12_red",
                     TOML.parsefile(joinpath(@__DIR__, "..", "fixtures", "public_fixtures.toml"))["fixture"])),
    objz = JSON.parsefile(joinpath(@__DIR__, "..", "fixtures", "demo12_off_solution.json"))["levels_CPLEX"]["OBJZ"],
    run = joinpath(times_demo_dir(), "demo12.run")

    @test run_switches(run)["REDUCE"] == "YES"
    @test length(PRESOLVE_STEPS) == length(unique(s[2] for s in PRESOLVE_STEPS))

    out = mktempdir()
    r = run_model(run; out=out, verbose=false)
    @test r.ok
    @test r.status == :solved
    @test JuMP.num_constraints(r.model.model; count_variable_in_set_constraints=false) == fx["rows"]
    @test JuMP.num_variables(r.model.model) == fx["cols"]
    @test isapprox(r.objective, objz; rtol=1e-6)
    @test isfile(joinpath(out, "QA_CHECK.LOG"))
    @test isdir(joinpath(out, "solution"))
    @test isfile(joinpath(out, "demo12.run"))       # the patched copy; the run file itself is untouched
    @test !occursin("SOLVE_NOW NO", read(run, String))

    g = run_model(run; solve=false, verbose=false)
    @test g.ok && g.status == :generated && g.objective === nothing
    @test_throws ArgumentError run_model(joinpath(out, "no_such.run"); verbose=false)
end
