# EQ(l)_FLOBND (eqflobnd.mod L15-43 with eqmain.mod L111-113; `eq_flobnd!`), on the crafted case
# demo12_flobnd (reference/dd/demo12_flobnd; M1.3 change 32, 14 Nov 2026): bounds on process flows
# (FLO_BND) that cannot be bounds of one flow variable. The model from GAMS's pre-solve dump
# against GAMS's matrix (layer 2), then the sixteen rows of the REDUCE variant, the bounds that
# stay on a variable, and the records that give nothing.

using TIMES: TimesModel, generate!, eq_flobnd!, untranslated_families, gparam, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_flobnd")
    tm = TimesModel(joinpath(FIXTURES, "demo12_flobnd_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    @testset "the data of the case" begin
        fb = gparam(tm, "FLO_BND")
        # bnd_flo.mod L22-23: an EPS at the year '0' marks each record that is not a bound of one variable
        @test gv(fb, ("REG1", "0", "ELCTEGAS00", "ELCGAS", "ANNUAL", "UP")).eps          # above the flow's level
        @test gv(fb, ("REG2", "0", "ELCTNGAS01", "ELCGAS", "WD", "UP")).eps              # a vintaged process
        @test gv(fb, ("REG1", "0", "REFEOIL00", "REFEOIL00_NRGO", "ANNUAL", "LO")).eps   # a commodity group
        @test gv(fb, ("REG1", "0", "TB_ELC_REG1_REG2_01", "ELC", "S", "UP")).eps         # an exchange process; the option 5 is overwritten
        @test !haskey(fb, ("REG1", "0", "FTE-AGROIL", "DSL", "ANNUAL", "UP"))            # a bound of VAR_FLO
        @test !haskey(fb, ("REG1", "0", "ELCREBIO00", "ELC", "WN", "UP"))                # a bound of VAR_ACT under REDUCE
        # L16: a LO EPS is deleted for a single commodity that is not an emission flow, and kept for a
        # group and for an emission flow
        @test !haskey(fb, ("REG2", "2020", "ELCTEGAS00", "ELCGAS", "ANNUAL", "LO"))
        @test gv(fb, ("REG1", "2020", "REFEOIL00", "REFEOIL00_NRGO", "ANNUAL", "LO")).eps
        @test gv(fb, ("REG2", "2020", "ELCTEGAS00", "ELCCO2", "SD", "LO")).eps
        @test gv(fb, ("REG2", "2020", "ELCTEGAS00", "ELCGAS", "ANNUAL", "UP")).v == Inf
        # the option 5 at the year '0': records in the milestone years from the first data year on
        @test all(t -> gv(fb, ("REG1", t, "TB_ELC_REG1_REG2_01", "ELC", "S", "UP")).v == 30, ("2020", "2030", "2050"))
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_flobnd_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_flobnd_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_FLOBND\(", r)])
        @test rows == ["EQE_FLOBND(REG1,2030,ELCTNGAS01,ELC,W)",
                       "EQG_FLOBND(REG1,2020,REFEOIL00,REFEOIL00_NRGO,ANNUAL)", "EQG_FLOBND(REG1,2030,ELCREHYD00,ELC,W)",
                       "EQG_FLOBND(REG2,2020,ELCTEGAS00,ELCCO2,SD)", "EQG_FLOBND(REG2,2030,TB_ELC_REG1_REG2_01,NRG,W)",
                       "EQL_FLOBND(REG1,2020,ELCTEGAS00,ELCCO2,ANNUAL)", "EQL_FLOBND(REG1,2020,ELCTEGAS00,ELCGAS,ANNUAL)",
                       "EQL_FLOBND(REG1,2020,TB_ELC_REG1_REG2_01,ELC,S)", "EQL_FLOBND(REG1,2030,ELCTEOIL00,ELCOIL,SD)",
                       "EQL_FLOBND(REG1,2030,IMPELC1,ELC,ANNUAL)", "EQL_FLOBND(REG1,2030,REFEOIL00,REFEOIL00_NRGO,ANNUAL)",
                       "EQL_FLOBND(REG1,2030,TB_ELC_REG1_REG2_01,ELC,S)", "EQL_FLOBND(REG1,2050,TB_ELC_REG1_REG2_01,ELC,S)",
                       "EQL_FLOBND(REG2,2020,ELCTNGAS01,ELCGAS,WD)", "EQL_FLOBND(REG2,2020,IMPELC1,ELC,WN)",
                       "EQL_FLOBND(REG2,2030,TB_ELC_REG1_REG2_01,NRG,W)"]
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        vars(r) = sort(collect(keys(terms(r))))
        daynite = ("SD", "SN", "WD", "WN")

        # above the flow's level: the sum over the timeslices below (L24). Under REDUCE the fuel input
        # is the activity times the flow's coefficient (cal_red.red)
        r = "EQL_FLOBND(REG1,2020,ELCTEGAS00,ELCGAS,ANNUAL)"
        @test lohi(r) == (-Inf, 500.0)
        @test vars(r) == ["VAR_ACT(REG1,2020,2020,ELCTEGAS00,$ts)" for ts in daynite]
        @test all(v -> isapprox(v, 2.028809089064719; rtol=1e-12), values(terms(r)))
        # the activity flow at a season, LO
        r = "EQG_FLOBND(REG1,2030,ELCREHYD00,ELC,W)"
        @test lohi(r) == (60.0, Inf)
        @test terms(r) == Dict("VAR_ACT(REG1,2030,2030,ELCREHYD00,$ts)" => 1.0 for ts in ("WD", "WN"))
        # a vintaged process: the sum over the vintages (L26), at the flow's own timeslice and above it
        r = "EQL_FLOBND(REG2,2020,ELCTNGAS01,ELCGAS,WD)"
        @test lohi(r) == (-Inf, 1500.0)
        @test vars(r) == ["VAR_ACT(REG2,$v,2020,ELCTNGAS01,WD)" for v in ("2010", "2015", "2020")]
        r = "EQE_FLOBND(REG1,2030,ELCTNGAS01,ELC,W)"
        @test lohi(r) == (950.0, 950.0)
        @test terms(r) == Dict("VAR_ACT(REG1,$v,2030,ELCTNGAS01,$ts)" => 1.0
                               for v in ("2010", "2015", "2020", "2030"), ts in ("WD", "WN"))
        # a flow REDUCE replaced by the activity (RPC_FFUNC), at its own timeslice: an equation
        r = "EQL_FLOBND(REG1,2030,ELCTEOIL00,ELCOIL,SD)"
        @test lohi(r) == (-Inf, 50.0)
        @test terms(r) == Dict("VAR_ACT(REG1,2030,2030,ELCTEOIL00,SD)" => 4.0)
        # an emission flow: UP at ANNUAL, and LO EPS at its own timeslice, a right-hand side of zero
        r = "EQL_FLOBND(REG1,2020,ELCTEGAS00,ELCCO2,ANNUAL)"
        @test lohi(r) == (-Inf, 100000.0)
        @test vars(r) == ["VAR_ACT(REG1,2020,2020,ELCTEGAS00,$ts)" for ts in daynite]
        r = "EQG_FLOBND(REG2,2020,ELCTEGAS00,ELCCO2,SD)"
        @test lohi(r) == (0.0, Inf)
        @test vars(r) == ["VAR_ACT(REG2,2020,2020,ELCTEGAS00,SD)"]
        # a commodity group: the sum over its commodities; LO EPS is a row with a right-hand side of zero
        group = ("DSL", "GSL", "HFO", "KER", "LPG", "NAP", "OPP")
        r = "EQL_FLOBND(REG1,2030,REFEOIL00,REFEOIL00_NRGO,ANNUAL)"
        @test lohi(r) == (-Inf, 9500.0)
        @test terms(r) == Dict("VAR_FLO(REG1,2030,2030,REFEOIL00,$c,ANNUAL)" => 1.0 for c in group)
        r = "EQG_FLOBND(REG1,2020,REFEOIL00,REFEOIL00_NRGO,ANNUAL)"
        @test lohi(r) == (0.0, Inf)
        @test terms(r) == Dict("VAR_FLO(REG1,2020,2020,REFEOIL00,$c,ANNUAL)" => 1.0 for c in group)
        # an exchange process whose flow is the activity under REDUCE (RPC_AIRE, L34-35)
        r = "EQL_FLOBND(REG1,2030,IMPELC1,ELC,ANNUAL)"
        @test lohi(r) == (-Inf, 500.0)
        @test terms(r) == Dict("VAR_ACT(REG1,2030,2030,IMPELC1,$ts)" => 1.0 for ts in daynite)
        r = "EQL_FLOBND(REG2,2020,IMPELC1,ELC,WN)"
        @test lohi(r) == (-Inf, 550.0)
        @test terms(r) == Dict("VAR_ACT(REG2,2020,2020,IMPELC1,WN)" => 1.0)
        # an exchange process with imports and exports: a single commodity bounds their sum, in every
        # period the interpolation gave a record (2020, 2030, 2050) ...
        for t in ("2020", "2030", "2050")
            r = "EQL_FLOBND(REG1,$t,TB_ELC_REG1_REG2_01,ELC,S)"
            @test lohi(r) == (-Inf, 30.0)
            @test terms(r) == Dict("VAR_IRE(REG1,$t,$t,TB_ELC_REG1_REG2_01,ELC,$ts,$ie)" => 1.0
                                   for ts in ("SD", "SN"), ie in ("IMP", "EXP"))
        end
        # ... and a group bounds the net import: exports count negative (L37)
        for (r, lh) in (("EQL_FLOBND(REG2,2030,TB_ELC_REG1_REG2_01,NRG,W)", (-Inf, 25.0)),
                        ("EQG_FLOBND(REG2,2030,TB_ELC_REG1_REG2_01,NRG,W)", (-25.0, Inf)))
            @test lohi(r) == lh
            @test terms(r) == Dict("VAR_IRE(REG2,2030,2030,TB_ELC_REG1_REG2_01,ELC,$ts,$ie)" => (ie == "EXP" ? -1.0 : 1.0)
                                   for ts in ("WD", "WN"), ie in ("IMP", "EXP"))
        end
        # the bounds that stay on a variable (bnd_flo.mod L27-29 and, under REDUCE, L34-39)
        @test mine.cols["VAR_FLO(REG1,2020,2020,FTE-AGROIL,DSL,ANNUAL)"].ub == 160.0
        @test mine.cols["VAR_ACT(REG1,2020,2020,ELCREBIO00,WN)"].ub == 20.0
        @test mine.cols["VAR_ACT(REG1,2020,2020,ELCREBIO00,WD)"].ub == Inf
        # nothing: UP INF (an empty body), a timeslice below the flow's, a period without the process
        @test !any(r -> occursin("(REG2,2020,ELCTEGAS00,ELCGAS,", r), rows)
        @test !any(r -> occursin("ELCTECOA00", r) || occursin("ELCRESOL00", r), rows)
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_flobnd!(t0) == 0
    end
end
