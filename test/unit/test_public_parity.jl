# Whole-model parity with the GAMS code on openly licensed test models
# (CLAUDE.md "Test-model licences"; docs/test-models.md). One entry per
# reference run in test/fixtures/public_fixtures.toml; every layer whose files
# are present runs (tolerances: docs/translation-guide.md):
#
#   layer 2  <prefix>_presolve + <prefix>_matrix: the model TIMES.jl generates
#            from the GAMS pre-solve state vs the CONVERT export (rows, columns,
#            coefficients, right-hand sides, bounds, objective), 1e-9
#   layer 3  <prefix>_solution.json: HiGHS optimum vs every GAMS solver's
#            objective; ours feasible in the GAMS matrix and theirs in ours, 1e-6
#   layer 1  <prefix>_ppm + <prefix>_coef, with coef_symbols: coef_cpt!,
#            coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp! and coef_ext! (the
#            whole coefficient stage) vs the GAMS coef dump, 1e-9
#
# This replaces the per-family tests on the DemoS models, removed on 27 Oct 2026.

isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")
import TOML, JSON, JuMP, HiGHS
using OpenTIMES: TimesModel, DumpData, generate!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, layer1
using OpenTIMES.Reference: canonical_from_jump, canonical_from_dump, compare_lp, evaluate_point, ispass, family,
                       jump_name_key

const PUBLIC_FIXTURES = TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))
# the model suite and the crafted cases built on its open models (reference/crafted.toml)
const SUITE_MODELS = Dict(m["name"] => m for f in ("suite.toml", "crafted.toml")
                          for m in TOML.parsefile(joinpath(@__DIR__, "..", "..", "reference", f))["model"])

fixture_path(fx, part) = joinpath(FIXTURES, fx["prefix"] * "_" * part)

function check_layer2_3(fx)
    tm = TimesModel(fixture_path(fx, "presolve"); reduce=get(fx, "reduce", false),
                    switches=Dict{String,String}(k => string(v) for (k, v) in get(fx, "switches", Dict())))
    generate!(tm)
    mine = canonical_from_jump(tm.model)
    ref = canonical_from_dump(joinpath(fixture_path(fx, "matrix"), "matrix"),
                              joinpath(fixture_path(fx, "matrix"), "dictmap"))
    cmp = compare_lp(mine, ref)
    @test ispass(cmp)
    if !ispass(cmp)
        foreach(println, cmp.examples)
        # localise the mismatch by equation family
        for fam in sort!(unique(family(k) for k in keys(ref.rows)))
            check_family_parity(mine, ref, fam)
        end
    end
    haskey(fx, "rows") && @test length(mine.rows) == fx["rows"]
    haskey(fx, "cols") && @test length(mine.cols) == fx["cols"]
    haskey(fx, "nonzeros") && @test length(mine.coefs) == fx["nonzeros"]

    solfile = fixture_path(fx, "solution.json")
    isfile(solfile) || return
    sol = JSON.parsefile(solfile)
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer)
    JuMP.set_silent(tm.model)
    JuMP.optimize!(tm.model)
    @test JuMP.termination_status(tm.model) == JuMP.OPTIMAL
    obj = JuMP.objective_value(tm.model)
    for (solver, gobj) in sol["objval"]
        @test isapprox(obj, gobj; rtol=1e-6)
    end
    # Our optimum in GAMS's matrix, and each GAMS optimum in ours.
    x = Dict(jump_name_key(JuMP.name(v)) => JuMP.value(v) for v in JuMP.all_variables(tm.model))
    e = evaluate_point(ref, x)
    @test e.feasible && isempty(e.missing_columns)
    for (solver, gobj) in sol["objval"]
        haskey(sol, "levels_" * solver) || continue
        g = evaluate_point(mine, Dict{String,Float64}(sol["levels_" * solver]))
        @test g.feasible && isempty(g.missing_columns)
        @test isapprox(g.objective, gobj; rtol=1e-6)
    end
end

function check_layer1_coef(fx)
    tm = TimesModel(fixture_path(fx, "ppm");
                    switches=Dict{String,String}(k => string(v) for (k, v) in get(fx, "switches", Dict())))
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm)   # coefmain.mod order
    coef_ext!(tm)                                               # the VDA extension's stage: the last file
    r = layer1(tm, DumpData(fixture_path(fx, "coef")), fx["coef_symbols"])      # nothing left to later files
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test all(ispass, r)
end

fixtures = get(PUBLIC_FIXTURES, "fixture", Any[])

@testset "fixture registry" begin
    for fx in fixtures
        name = get(fx, "model", "")
        @test haskey(SUITE_MODELS, name)
        haskey(SUITE_MODELS, name) || continue
        m = SUITE_MODELS[name]
        @test m["redistribute"] == "public" && !haskey(m, "exception")
        @test occursin(r"^[a-z0-9_]+$", fx["prefix"])
    end
end

if isempty(fixtures)
    @info "No openly licensed whole-model fixture yet: layers 1-3 are not checked in CI " *
          "(docs/test-models.md, \"Adding a test model\")."
    @test_skip !isempty(fixtures)
end

for fx in fixtures
    @testset "$(fx["model"]) $(get(fx, "variant", ""))" begin
        if isdir(fixture_path(fx, "presolve")) && isdir(fixture_path(fx, "matrix"))
            @testset "layers 2-3" begin
                check_layer2_3(fx)
            end
        end
        if haskey(fx, "coef_symbols") && isdir(fixture_path(fx, "ppm")) && isdir(fixture_path(fx, "coef"))
            @testset "layer 1, coefficients" begin
                check_layer1_coef(fx)
            end
        end
    end
end
