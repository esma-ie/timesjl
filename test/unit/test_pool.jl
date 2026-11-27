# The run pool's phase markers (src/pool.jl; James, 26 Nov 2026). No GAMS statement is translated
# here. A run started by reference/python/pool_run.py (TIMESJL_POOL_MARKERS set) prints
# `[timesjl-pool] phase=reporting` once its last solve is over, and the launcher then keeps one
# thread for it. Any other run prints nothing: its output is as before.
# run_model on TIMES_Demo demo12 (CC BY 4.0), as test_run_model.jl runs it.
using Test
using TIMES: pool_phase, POOL_MARKERS_ENV, times_demo_dir

@testset "pool_phase: nothing without the launcher" begin
    for v in (nothing, "", "0")
        withenv(POOL_MARKERS_ENV => v) do
            io = IOBuffer()
            @test pool_phase("reporting"; io) === false
            @test pool_phase("after-barrier"; io) === false
            @test isempty(take!(io))
        end
    end
    # TIMESJL_POOL is the size of the pool (runlimits.py), not the switch
    withenv(POOL_MARKERS_ENV => nothing, "TIMESJL_POOL" => "48") do
        io = IOBuffer()
        @test pool_phase("reporting"; io) === false
        @test isempty(take!(io))
    end
end

@testset "pool_phase: one line under the launcher" begin
    withenv(POOL_MARKERS_ENV => "1") do
        io = IOBuffer()
        @test pool_phase("after-barrier"; io) === true
        @test pool_phase("reporting"; io) === true
        @test String(take!(io)) == "[timesjl-pool] phase=after-barrier\n[timesjl-pool] phase=reporting\n"
        @test_throws ArgumentError pool_phase("solving"; io)
        @test isempty(take!(io))
    end
    @test_throws ArgumentError pool_phase("solving")        # also without the launcher
end

# what run_model prints (standard output), with TIMESJL_POOL_MARKERS set to `env`
function pool_run_model_output(env; kw...)
    run = joinpath(times_demo_dir(), "demo12.run")
    file = joinpath(mktempdir(), "stdout.txt")
    r = withenv(POOL_MARKERS_ENV => env) do
        open(file, "w") do f
            redirect_stdout(() -> run_model(run; out=mktempdir(), write_solution=false, kw...), f)
        end
    end
    return r, readlines(file)
end

@testset "run_model: the marker only when asked for, under the launcher, after the solve" begin
    marker = "[timesjl-pool] phase=reporting"
    r0, plain = pool_run_model_output(nothing)                           # as any run so far
    @test r0.ok
    @test !any(startswith("[timesjl-pool]"), plain)
    # asked for, without the launcher: the same lines (less the times and the temporary folders)
    r1, asked = pool_run_model_output(nothing; pool_markers=true)
    @test !any(startswith("[timesjl-pool]"), asked)
    @test length(asked) == length(plain)
    # under the launcher, not asked for (a process that may solve again): nothing
    r2, notasked = pool_run_model_output("1")
    @test !any(startswith("[timesjl-pool]"), notasked)
    # under the launcher and asked for: one marker, after the model is generated and before the solve is reported
    r3, lines = pool_run_model_output("1"; pool_markers=true)
    @test r3.ok
    @test count(==(marker), lines) == 1
    @test length(lines) == length(plain) + 1
    k = findfirst(==(marker), lines)
    @test occursin("model generated", lines[k-1])
    @test occursin("OPTIMAL", lines[k+1])
    @test r3.objective == r0.objective == r1.objective == r2.objective   # the marker changes nothing in the run
    # not solved: no marker
    r4, gen = pool_run_model_output("1"; pool_markers=true, solve=false)
    @test r4.status == :generated
    @test !any(startswith("[timesjl-pool]"), gen)
end
