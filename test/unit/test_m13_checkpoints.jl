# M1.3 (0): the checkpoint fixtures of TIMES_Demo demo12 reduce_off (harness
# 0.3.0; scripts/make_m13_fixture.jl), made by make_reference.py --only
# presolve with the PyPI GAMS 54.6.1 (no solve). The ppm/ end point is the
# licensed reference fixture of 21 Oct 2026 (GAMS 52.1.0), so the chain also
# checks that the cloud-made checkpoints lead to it: every symbol the four
# segments leave alone must be in ppm/ as the input dump has it.

using OpenTIMES: TimesModel
using OpenTIMES.Reference: load_dump, compare_dumps, ispass
import TOML

const M13_CHECKPOINTS = ["input", "init", "prep", "prelv"]

@testset "demo12 checkpoint dumps" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    dumps = [load_dump(joinpath(FIXTURES, "demo12_off_$c")) for c in M13_CHECKPOINTS]
    ppm = load_dump(joinpath(FIXTURES, "demo12_off_ppm"))
    @test all(d -> length(d.symbols) > 800, dumps)
    # TIMES.jl can start from the input dump (the M1.3 starting state)
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    @test !isempty(OpenTIMES.gset(tm, "MILESTONYR"))
    # what each segment changes (sets and parameters, records at 1e-9, order ignored);
    # the last segment ends at the licensed ppm fixture, on the symbols prelv/ has
    ends = [dumps[2:end]; ppm]
    changed = Set{String}()
    counts = Int[]
    for (a, b) in zip(dumps, ends)
        names = b === ppm ? [n for (n, i) in a.symbols if i.kind in (:set, :parameter)] : nothing
        r = compare_dumps(a, b; symbols=names, kinds=(:set, :parameter), check_order=false, max_examples=0)
        seg = Set(vcat([c.name for c in r.symbols if !ispass(c)], r.only_left, r.only_right))
        push!(counts, length(seg))
        union!(changed, seg)
    end
    @test counts == [7, 86, 50, 76]          # docs/m13-plan.md (demo12 column)
    common = [n for (n, i) in dumps[1].symbols if i.kind in (:set, :parameter) && haskey(ppm.symbols, n) && !(n in changed)]
    @test length(common) > 500
    @test ispass(compare_dumps(dumps[1], ppm; symbols=common, kinds=(:set, :parameter), check_order=false))
end
