# M1.3 change 21: dynamic user constraints in the RHS direction, equserco.mod L80-106 with
# uc_pasti.mod and the UC_TMAP of eqmain.mod L211-215 (v4.9.7), on the crafted case
# TIMES_Demo-demo12_ucdyn (reference/dd/demo12_ucdyn/ucdyn.dd, as_run). The whole model is
# checked against GAMS in test_public_parity.jl; here the pieces: UC_TMAP against GAMS's,
# the direction rule, and the user-constraint rows alone against the CONVERT export.

using TIMES: TimesModel, DumpData, gset, gset_opt, gput!, uc_tmap, uc_rhsdir, eq_uc!, UnportedError
using TIMES.Reference: canonical_from_jump, canonical_from_dump
import TOML
isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_ucdyn")
    presolve = joinpath(FIXTURES, "demo12_ucdyn_presolve")
    mk() = TimesModel(presolve; reduce=vx["reduce"], switches=vx["switches"])

    @testset "UC_TMAP as eqmain.mod L211-215 builds it" begin
        tm = mk()
        @test uc_tmap(tm).keys == gset_opt(DumpData(presolve), "UC_TMAP", 5).keys     # 57 entries, GAMS order
        # 6 milestones: N 6 LHS + 5 RHS, CUMSUM 15 LHS + 10 RHS, SYNC 6, CUM+ 15
        @test length(uc_tmap(tm)) == 57
        @test ("2010", "2005", "2005", "RHS", "N") in uc_tmap(tm)
        @test ("2020", "2015", "2005", "RHS", "CUMSUM") in uc_tmap(tm) && !(("2015", "2010", "2010", "RHS", "CUMSUM") in uc_tmap(tm))
    end

    @testset "the direction of a dynamic row (equserco.mod L78, L106)" begin
        tm = mk()
        @test uc_rhsdir(tm, "GRW_HYD", "REG2")
        @test !uc_rhsdir(tm, "GRW_IMP", "REG2")      # UC_DYNDIR(REG2,GRW_IMP,'RHS') is not set ...
        @test uc_rhsdir(tm, "GRW_IMP")               # ... but the region-summed row takes any region
        # ppmain.mod L1168: an RHS SYNC adds the N attribute, which drops the N entry (LIM xor UC_ATTR)
        @test ("REG1", "SYN_GAS", "RHS", "ACT", "N") in gset(tm, "UC_ATTR")
    end

    @testset "the user-constraint rows alone against CONVERT (layer 2)" begin
        tm = mk()
        @test eq_uc!(tm) == 50
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_ucdyn_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_ucdyn_matrix", "dictmap"))
        for (fam, n) in (("EQE_UCRSU", 18), ("EQE_UCSU", 6), ("EQE_UCRSUS", 6), ("EQE_UCSUS", 6))
            @test check_family_parity(mine, ref, fam) == n
        end
        # uc_pasti.mod: the first period's hydro rows carry the past investments on the right-hand side
        r = mine.rows["EQE_UCRSU(REG1,2005,GRW_HYD)"]
        @test r.hi != 0 && isapprox(r.hi, ref.rows["EQE_UCRSU(REG1,2005,GRW_HYD)"].hi; rtol=1e-9)
    end

    @testset "attributes still refused" begin
        tm = mk()
        attr = Set(gset(tm, "UC_ATTR").keys)
        push!(attr, ("REG1", "GRW_NUC", "RHS", "NCAP", "ANNUL"))      # CST_ANNC, eqbndcst.mod (change 22 leaves it)
        gput!(tm, "UC_ATTR", attr)
        @test_throws UnportedError eq_uc!(tm)
    end
end
