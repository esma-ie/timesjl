# EQ(l)_IREBND (eqirebnd.mod L18-69 with eqmain.mod L152-154; `eq_irebnd!`), on the crafted case
# demo12_irebnd (reference/dd/demo12_irebnd; M1.3 change 34, 14 Nov 2026): limits on the trade of
# a commodity between a region and one partner region (IRE_BND). The data as preppm.mod L193 and
# ppmain.mod L995 leave it, the model from GAMS's pre-solve dump against GAMS's matrix (layer 2),
# then the thirteen rows of the REDUCE variant and the records that give nothing. Under REDUCE the
# flow of a process whose activity is the exchange (RPC_AIRE: the imports and exports with an
# external region, the gas link) is VAR_ACT; the electricity link keeps VAR_IRE.

using TIMES: TimesModel, generate!, eq_irebnd!, untranslated_families, gparam, gset, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_irebnd")
    tm = TimesModel(joinpath(FIXTURES, "demo12_irebnd_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    bnd = gparam(tm, "IRE_BND")
    yrfr(s) = gv(gparam(tm, "G_YRFR"), ("REG1", s)).v
    @testset "the data of the case" begin
        # ppmain.mod L995 (pp_lvlbd.mod): LO records below the commodity's level (GAS is tracked at
        # ANNUAL) are added up to it; the records themselves stay
        @test gv(bnd, ("REG1", "2030", "GAS", "ANNUAL", "IMPEXP", "IMP", "LO")).v == 150.0
        @test gv(bnd, ("REG1", "2030", "GAS", "SD", "IMPEXP", "IMP", "LO")).v == 50.0
        @test gv(bnd, ("REG1", "2030", "GAS", "WD", "IMPEXP", "IMP", "LO")).v == 100.0
        # the option 5 at the year '0': records from the first data year on; the option record is gone
        @test all(t -> gv(bnd, ("REG1", t, "COA", "ANNUAL", "MINRNW", "IMP", "UP")).v == 4000.0, ("2020", "2030", "2050"))
        @test !haskey(bnd, ("REG1", "0", "COA", "ANNUAL", "MINRNW", "IMP", "UP"))
        @test !haskey(bnd, ("REG1", "2015", "COA", "ANNUAL", "MINRNW", "IMP", "UP"))
        # the values EPS and INF, and the record of an external region, are in the data
        @test gv(bnd, ("REG2", "2020", "ELC", "SN", "IMPEXP", "IMP", "FX")).eps
        @test gv(bnd, ("REG2", "2030", "ELC", "WN", "IMPEXP", "IMP", "LO")).eps
        @test gv(bnd, ("REG2", "2030", "ELC", "WD", "IMPEXP", "IMP", "UP")).v == Inf
        @test gv(bnd, ("IMPEXP", "2020", "ELC", "ANNUAL", "REG1", "EXP", "UP")).v == 100.0
        # the efficiency of the electricity trade from REG2 to REG1, by timeslice of REG1, for every
        # vintage; the other direction keeps the default 1
        let f = gparam(tm, "IRE_FLO"), p = "TB_ELC_REG1_REG2_01"
            @test [gv(f, ("REG2", "2020", p, "ELC", "REG1", "ELC", s)).v for s in ("SD", "SN", "WD", "WN")] == [0.96, 0.97, 0.95, 0.98]
            @test all(s -> gv(f, ("REG1", "2020", p, "ELC", "REG2", "ELC", s)).v == 1.0, ("SD", "SN", "WD", "WN"))
        end
        # the new import process runs at SEASON
        @test sort([k[5] for k in gset(tm, "RTPCS_VARF") if k[1:4] == ("REG1", "2020", "IMPELC2", "ELC")]) == ["S", "W"]
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_irebnd_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_irebnd_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_IREBND\(", r)])
        @test rows == ["EQE_IREBND(REG2,2020,ELC,SN,IMPEXP,IMP)",
                       "EQG_IREBND(REG1,2020,ELC,WD,REG2,IMP)", "EQG_IREBND(REG1,2020,GAS,ANNUAL,IMPEXP,EXP)",
                       "EQG_IREBND(REG1,2020,GAS,ANNUAL,REG2,IMP)", "EQG_IREBND(REG1,2030,GAS,ANNUAL,IMPEXP,IMP)",
                       "EQL_IREBND(REG1,2020,COA,ANNUAL,MINRNW,IMP)", "EQL_IREBND(REG1,2020,ELC,ANNUAL,REG2,IMP)",
                       "EQL_IREBND(REG1,2020,ELC,WD,IMPEXP,IMP)", "EQL_IREBND(REG1,2030,COA,ANNUAL,MINRNW,IMP)",
                       "EQL_IREBND(REG1,2030,ELC,S,IMPEXP,IMP)", "EQL_IREBND(REG1,2050,COA,ANNUAL,MINRNW,IMP)",
                       "EQL_IREBND(REG2,2020,GAS,ANNUAL,REG1,EXP)", "EQL_IREBND(REG2,2030,ELC,S,REG1,EXP)"]
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        tb(r, t, s, ie) = "VAR_IRE($r,$t,$t,TB_ELC_REG1_REG2_01,ELC,$s,$ie)"
        act(r, t, p, s) = "VAR_ACT($r,$t,$t,$p,$s)"

        # L23-32, imports from an internal region: the exports of the partner, each times the
        # efficiency of the trade in the importing timeslice (IRE_FLO), summed over the year
        @test lohi("EQL_IREBND(REG1,2020,ELC,ANNUAL,REG2,IMP)") == (-Inf, 300.0)
        @test near(terms("EQL_IREBND(REG1,2020,ELC,ANNUAL,REG2,IMP)"),
                   Dict(tb("REG2", "2020", s, "EXP") => f for (s, f) in (("SD", 0.96), ("SN", 0.97), ("WD", 0.95), ("WN", 0.98))))
        # ... at the flow's own level, a lower bound
        @test lohi("EQG_IREBND(REG1,2020,ELC,WD,REG2,IMP)") == (20.0, Inf)
        @test near(terms("EQG_IREBND(REG1,2020,ELC,WD,REG2,IMP)"), Dict(tb("REG2", "2020", "WD", "EXP") => 0.95))
        # ... on the gas link, whose flow is the activity (RPC_AIRE)
        @test lohi("EQG_IREBND(REG1,2020,GAS,ANNUAL,REG2,IMP)") == (10.0, Inf)
        @test near(terms("EQG_IREBND(REG1,2020,GAS,ANNUAL,REG2,IMP)"), Dict(act("REG2", "2020", "TU_GAS_REG2_REG1_01", "ANNUAL") => 1.0))
        # L56-62, exports: the region's own export flows; here at the season S, above the flow's level
        @test lohi("EQL_IREBND(REG2,2030,ELC,S,REG1,EXP)") == (-Inf, 100.0)
        @test near(terms("EQL_IREBND(REG2,2030,ELC,S,REG1,EXP)"), Dict(tb("REG2", "2030", s, "EXP") => 1.0 for s in ("SD", "SN")))
        @test lohi("EQL_IREBND(REG2,2020,GAS,ANNUAL,REG1,EXP)") == (-Inf, 400.0)
        @test near(terms("EQL_IREBND(REG2,2020,GAS,ANNUAL,REG1,EXP)"), Dict(act("REG2", "2020", "TU_GAS_REG2_REG1_01", "ANNUAL") => 1.0))
        # ... to an external region
        @test lohi("EQG_IREBND(REG1,2020,GAS,ANNUAL,IMPEXP,EXP)") == (5.0, Inf)
        @test near(terms("EQG_IREBND(REG1,2020,GAS,ANNUAL,IMPEXP,EXP)"), Dict(act("REG1", "2020", "EXPGAS1", "ANNUAL") => 1.0))
        # L35-41, imports from an external region: the region's own import flows. A flow at a
        # timeslice above the bound's counts with the bound's share of it (L39): IMPELC2 at the season
        # W for the bound at WD, the dummy import at ANNUAL
        @test lohi("EQL_IREBND(REG1,2020,ELC,WD,IMPEXP,IMP)") == (-Inf, 100.0)
        @test near(terms("EQL_IREBND(REG1,2020,ELC,WD,IMPEXP,IMP)"),
                   Dict(act("REG1", "2020", "IMPELC1", "WD") => 1.0, act("REG1", "2020", "IMPELC2", "W") => yrfr("WD") / yrfr("W"),
                        "VAR_IRE(REG1,2020,2020,IMPNRGZ,ELC,ANNUAL,IMP)" => yrfr("WD")))
        # ... a bound at the season S: the flows at and below S in full
        @test lohi("EQL_IREBND(REG1,2030,ELC,S,IMPEXP,IMP)") == (-Inf, 400.0)
        @test near(terms("EQL_IREBND(REG1,2030,ELC,S,IMPEXP,IMP)"),
                   Dict(act("REG1", "2030", "IMPELC1", "SD") => 1.0, act("REG1", "2030", "IMPELC1", "SN") => 1.0,
                        act("REG1", "2030", "IMPELC2", "S") => 1.0, "VAR_IRE(REG1,2030,2030,IMPNRGZ,ELC,ANNUAL,IMP)" => yrfr("S")))
        # ... the sum over the processes of the link, in each period of the interpolated bound
        for t in ("2020", "2030", "2050")
            @test lohi("EQL_IREBND(REG1,$t,COA,ANNUAL,MINRNW,IMP)") == (-Inf, 4000.0)
            @test near(terms("EQL_IREBND(REG1,$t,COA,ANNUAL,MINRNW,IMP)"), Dict(act("REG1", t, "MINCOA$i", "ANNUAL") => 1.0 for i in 1:3))
        end
        # ... the records below the commodity's level, added up to ANNUAL
        @test lohi("EQG_IREBND(REG1,2030,GAS,ANNUAL,IMPEXP,IMP)") == (150.0, Inf)
        @test near(terms("EQG_IREBND(REG1,2030,GAS,ANNUAL,IMPEXP,IMP)"),
                   Dict(act("REG1", "2030", "IMPGAS1", "ANNUAL") => 1.0, "VAR_IRE(REG1,2030,2030,IMPNRGZ,GAS,ANNUAL,IMP)" => 1.0))
        # FX with the value EPS: a row with the right-hand side zero (eqmain.mod L153: YES)
        @test lohi("EQE_IREBND(REG2,2020,ELC,SN,IMPEXP,IMP)") == (0.0, 0.0)
        @test near(terms("EQE_IREBND(REG2,2020,ELC,SN,IMPEXP,IMP)"),
                   Dict(act("REG2", "2020", "IMPELC1", "SN") => 1.0, "VAR_IRE(REG2,2020,2020,IMPNRGZ,ELC,ANNUAL,IMP)" => yrfr("SN")))
        # nothing: LO with the value EPS and UP INF (L152, L154), the records below the commodity's
        # level themselves, a partner without a link (a row without a variable), an external region
        @test !any(r -> occursin("(REG2,2030,ELC,W", r) || occursin(",GAS,SD,", r) || occursin(",GAS,WD,", r) ||
                        occursin("ELC,ANNUAL,MINRNW", r) || occursin("(IMPEXP,", r), rows)
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_irebnd!(t0) == 0
    end
end
