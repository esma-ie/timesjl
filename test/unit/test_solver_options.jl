# Solver option files (src/solver_options.jl, run_model's `optfile`; James, 20 Nov 2026, q1).
# GAMS: solve.mod L14-15, initsys.mod L168, v4.9.7: OPTFILE = 1, so the solver reads <solver>.opt from
# the run folder. An option file changes how HiGHS reaches the optimum, not the LP: demo12 (CC BY 4.0)
# solved with HiGHS's interior point method from a highs.opt reaches GAMS/CPLEX's objective at the
# layer-3 tolerance (1e-6), as the default solve does in test_run_model.jl.
using Test, JSON
import JuMP, HiGHS
using TIMES: times_demo_dir, read_optfile, highs_options, find_optfile

@testset "read_optfile: GAMS option-file lines" begin
    f = joinpath(mktempdir(), "highs.opt")
    write(f, """
    * a comment line

    Solver ipm
    run_crossover=on
    THREADS = 7
    primal_feasibility_tolerance 1e-8
    log_file "a b.log"
    presolve
    """)
    @test read_optfile(f) == ["solver" => "ipm",
                              "run_crossover" => "on", "threads" => "7", "primal_feasibility_tolerance" => "1e-8",
                              "log_file" => "a b.log", "presolve" => ""]
end

@testset "highs_options: HiGHS's types, notes, the threads limit" begin
    o, n = highs_options(["solver" => "ipm", "threads" => "4", "primal_feasibility_tolerance" => "1e-8",
                          "mip_detect_symmetry" => "no", "random_seed" => "1e1", "echo" => "on"]; threads=12)
    @test o == ["solver" => "ipm", "threads" => 4, "primal_feasibility_tolerance" => 1e-8,
                "mip_detect_symmetry" => false, "random_seed" => 10]
    @test o[2].second isa Int && o[3].second isa Float64 && o[4].second isa Bool
    @test isempty(n)
    # a name HiGHS does not know, a value of the wrong type, a value out of range: left out, each with a note
    o, n = highs_options(["lpmethod" => "4", "threads" => "many", "solver" => "barrier", "time_limit" => "-1"]; threads=12)
    @test isempty(o)
    @test length(n) == 4 && occursin("lpmethod: not a HiGHS option", n[1])
    # more threads than the run's limit, or HiGHS's own choice (0): the limit; the later of two lines wins
    @test highs_options(["threads" => "48"]; threads=12)[1] == ["threads" => 12]
    @test highs_options(["threads" => "0"]; threads=12)[1] == ["threads" => 12]
    @test highs_options(["solver" => "ipm", "solver" => "simplex"]; threads=12)[1] == ["solver" => "simplex"]
end

@testset "find_optfile: <solver>.opt in the run folder" begin
    d = mktempdir()
    for f in ("highs.opt", "cplex.opt", "convert.opt")
        write(joinpath(d, f), "")
    end
    p, n = find_optfile(d, "HiGHS")
    @test p == joinpath(d, "highs.opt")
    @test n == ["cplex.opt not read: an option file for CPLEX, and this run solves with HiGHS"]
    rm(joinpath(d, "highs.opt"))
    @test find_optfile(d, "HiGHS")[1] === nothing
end

@testset "run_model: demo12 with a highs.opt (interior point) reaches GAMS's optimum" begin
    objz = JSON.parsefile(joinpath(@__DIR__, "..", "fixtures", "demo12_off_solution.json"))["levels_CPLEX"]["OBJZ"]
    d = mktempdir()
    run = joinpath(d, "demo12.run")
    cp(joinpath(times_demo_dir(), "demo12.run"), run)
    write(joinpath(d, "highs.opt"), "* demo12, HiGHS's interior point method\nsolver ipm\nrun_crossover on\nthreads 2\nlpmethod 4\n")
    write(joinpath(d, "cplex.opt"), "lpmethod 4\n")
    r = run_model(run; dd=[times_demo_dir()], out=joinpath(d, "out"), verbose=false)
    @test r.ok && r.status == :solved
    @test r.optfile == joinpath(d, "highs.opt")
    @test Dict(r.solver_options) == Dict("threads" => 2, "solver" => "ipm", "run_crossover" => "on")
    @test JuMP.get_attribute(r.model.model, "solver") == "ipm"        # the option reached HiGHS
    @test JuMP.get_attribute(r.model.model, "threads") == 2
    @test isapprox(r.objective, objz; rtol=1e-6)

    # optfile=false reads none; a missing file, or a file for another solver, stops the run at once
    g = run_model(run; dd=[times_demo_dir()], optfile=false, solve=false, verbose=false)
    @test g.ok && g.optfile === nothing
    @test g.solver_options == ["threads" => parse(Int, get(ENV, "TIMESJL_THREADS", "12"))]
    @test_throws ArgumentError run_model(run; optfile=joinpath(d, "no_such.opt"), verbose=false)
    @test_throws ArgumentError run_model(run; optfile=joinpath(d, "cplex.opt"),
                                         optimizer=JuMP.optimizer_with_attributes(HiGHS.Optimizer), verbose=false)
end
