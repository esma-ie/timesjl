# M1.3 change 23: EQ(l)_FLOMRK, the market-share constraints of eqflomrk.mod L56-105 (v4.9.7),
# on the crafted case TIMES_Demo-demo12_flomrk (reference/dd/demo12_flomrk/flomrk.dd, as_run):
# the rows alone against the CONVERT export, and the branches spelled out. The whole model is
# checked against GAMS in test_public_parity.jl.

using TIMES: TimesModel, eq_flomrk!
using TIMES.Reference: canonical_from_jump, canonical_from_dump
import TOML
isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_flomrk")
    tm = TimesModel(joinpath(FIXTURES, "demo12_flomrk_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    @test eq_flomrk!(tm) == 23
    mine = canonical_from_jump(tm.model)
    ref = canonical_from_dump(joinpath(FIXTURES, "demo12_flomrk_matrix", "matrix"),
                              joinpath(FIXTURES, "demo12_flomrk_matrix", "dictmap"))
    @testset "the rows against CONVERT (layer 2)" begin
        for (fam, n) in (("EQG_FLOMRK", 1), ("EQE_FLOMRK", 1), ("EQL_FLOMRK", 21))
            @test check_family_parity(mine, ref, fam) == n
        end
    end
    @testset "branches" begin
        c(row, col) = get(mine.coefs, (row, col), nothing)
        # an exchange process (FX): the import flow against 0.4 of the coal production; under REDUCE
        # the flow of an RPC_AIRE process is its activity times PRC_ACTFLO (%IRED%, L58)
        @test c("EQE_FLOMRK(REG1,2005,MINCOA1,COA,ANNUAL)", "VAR_ACT(REG1,2005,2005,MINCOA1,ANNUAL)") ≈ 1.0
        @test c("EQE_FLOMRK(REG1,2005,MINCOA1,COA,ANNUAL)", "VAR_COMPRD(REG1,2005,COA,ANNUAL)") ≈ -0.4
        # a storage process: the storage output
        @test c("EQL_FLOMRK(REG1,2005,STKOIL1,OIL,ANNUAL)", "VAR_SOUT(REG1,2005,2005,STKOIL1,OIL,ANNUAL)") ≈ 1.0
        # a negative share of a standard process: no '0' RX_MARK, so the right-hand side factor is 0
        @test !any(k -> k[1] == "EQL_FLOMRK(REG2,2005,ELCTECOA00,ELC,SD)" && startswith(k[2], "VAR_COMPRD"), keys(mine.coefs))
    end
end
