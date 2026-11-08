# M1.3 change 22: the user-constraint attribute factors of uc_*.mod (v4.9.7) on the crafted
# case TIMES_Demo-demo12_ucattr (reference/dd/demo12_ucattr/ucattr.dd, as_run): the
# user-constraint rows alone against the CONVERT export, and a few coefficients spelled out.
# The whole model is checked against GAMS in test_public_parity.jl.

using TIMES: TimesModel, eq_uc!
using TIMES.Reference: canonical_from_jump, canonical_from_dump
import TOML
isdefined(@__MODULE__, :check_family_parity) || include("parity_helpers.jl")

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_ucattr")
    tm = TimesModel(joinpath(FIXTURES, "demo12_ucattr_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    @test eq_uc!(tm) == 39
    mine = canonical_from_jump(tm.model)
    ref = canonical_from_dump(joinpath(FIXTURES, "demo12_ucattr_matrix", "matrix"),
                              joinpath(FIXTURES, "demo12_ucattr_matrix", "dictmap"))
    @testset "the user-constraint rows against CONVERT (layer 2)" begin
        for (fam, n) in (("EQE_UCR", 1), ("EQE_UCRT", 20), ("EQE_UCRSU", 12), ("EQE_UCRTS", 6))
            @test check_family_parity(mine, ref, fam) == n
        end
    end
    @testset "attribute factors" begin
        c(row, col) = mine.coefs[(row, col)]
        # TAX on COMNET and COST on COMPRD (OBJ_COMNT, OBJ_COMPD), divided by COM_IE 0.95 (COMNET and
        # COMPRD group types without EFF); the flow terms are folded into activities under REDUCE
        @test c("EQE_UCRT(REG2,2005,ATT_COST)", "VAR_COMNET(REG2,2005,ELC,SD)") ≈ 0.5 / 0.95
        @test c("EQE_UCRT(REG2,2005,ATT_COST)", "VAR_COMPRD(REG2,2005,ELC,SD)") ≈ 0.05 / 0.95
        # PERIOD on ACT: FPD(2020) = 8; PERIOD on NCAP brings the 2015 investment commissioned in 2020
        # (RVPT), with BUILDUP 1/LEAD(2020) = 0.2
        @test c("EQE_UCRT(REG1,2020,ATT_PER)", "VAR_ACT(REG1,2020,2020,ELCTECOA00,S)") ≈ 8.0
        @test c("EQE_UCRT(REG1,2020,ATT_PER)", "VAR_NCAP(REG1,2015,ELCNNNUC01)") ≈ 0.2
        # CUMSUM on the RHS NCAP term: investments of the periods before T-1 (with PERIOD)
        @test c("EQE_UCRSU(REG1,2030,ATT_CSUM)", "VAR_NCAP(REG1,2015,ELCNNNUC01)") ≈ -1.0
    end
end
