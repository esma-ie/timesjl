# M1.2 infrastructure (src/coef/state.jl): GAMS assignment semantics.
# The gput! and layer-1 tests ran on DemoS dumps and were removed
# on 27 Oct 2026 with the DemoS models (docs/test-models.md); layer 1 of the
# coefficient files now runs in test_public_parity.jl on openly licensed
# fixtures.

using TIMES: GNum, GEPS, gassign!

@testset "gassign!: GAMS stores no zero, keeps EPS" begin
    d = Dict{NTuple{2,String},Float64}(("a", "b") => 3.0)
    gassign!(d, ("a", "b"), GNum(0.0))
    @test !haskey(d, ("a", "b"))                       # an exact zero removes the entry
    gassign!(d, ("a", "c"), GEPS)
    @test d[("a", "c")] === 0.0                         # EPS is an entry with value 0.0
    gassign!(d, ("a", "d"), 1.5)
    @test d[("a", "d")] == 1.5
end

@testset "gset: an alias follows its target's current state (PYR, ALIAS(PASTYEAR,PYR))" begin
    # TIMES.jl computes PASTYEAR in preprocessing; PYR read after that must be the new PASTYEAR, as in
    # GAMS, not PASTYEAR's records in the dump (found by the M1.4 from-DD gate on TIMES-NZ, REDUCE YES)
    tm = TIMES.TimesModel(joinpath(@__DIR__, "..", "fixtures", "demo12_off_input"))
    @test TIMES.gset(tm, "PYR").keys == TIMES.gset(tm, "PASTYEAR").keys
    new = Set(TIMES.gset(tm, "PASTYEAR").keys)
    pop!(new, first(TIMES.gset(tm, "PASTYEAR").keys))
    TIMES.gput!(tm, "PASTYEAR", new)
    @test Set(TIMES.gset(tm, "PYR").keys) == new
    @test !haskey(tm.data.sets, "PYR")                  # never cached under the alias's own name
end
