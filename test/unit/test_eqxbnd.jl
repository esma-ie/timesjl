# EQ(l)_XBND (eqxbnd.mod L17-56 with eqmain.mod L241-243; `eq_xbnd!`), on the crafted case
# demo12_xbnd (reference/dd/demo12_xbnd; M1.3 change 35, 14 Nov 2026): limits on the total
# exchange of a commodity of a region (IRE_XBND), internal or external. The data as preppm.mod
# L194 leaves it, the model from GAMS's pre-solve dump against GAMS's matrix (layer 2), then the
# seventeen rows of the REDUCE variant and the records that give nothing. Under REDUCE the flow
# of a process whose activity is the exchange (RPC_AIRE: the imports and exports with an external
# region, the gas link) is VAR_ACT; the electricity link and the dummy import keep VAR_IRE.

using TIMES: TimesModel, generate!, eq_xbnd!, untranslated_families, gparam, gset, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_xbnd")
    tm = TimesModel(joinpath(FIXTURES, "demo12_xbnd_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    bnd = gparam(tm, "IRE_XBND")
    yrfr(s, r="REG1") = gv(gparam(tm, "G_YRFR"), (r, s)).v
    @testset "the data of the case" begin
        # the option 5 at the year '0': records from the first data year on; the option record is
        # gone. Internal and external regions alike (preppm.mod L194: ALL_REG)
        for r in ("REG1", "MINRNW")
            v = r == "REG1" ? 600.0 : 9000.0
            @test all(t -> gv(bnd, (r, t, "COA", "ANNUAL", "EXP", "UP")).v == v, ("2020", "2030", "2050"))
            @test !haskey(bnd, (r, "0", "COA", "ANNUAL", "EXP", "UP"))
            @test !haskey(bnd, (r, "2015", "COA", "ANNUAL", "EXP", "UP"))
        end
        # a record finer than the commodity's level stays as given: no pp_lvlbd.mod for IRE_XBND
        @test gv(bnd, ("REG1", "2030", "GAS", "WD", "IMP", "UP")).v == 5000.0
        @test !haskey(bnd, ("REG1", "2030", "GAS", "ANNUAL", "IMP", "UP"))
        # the values EPS and INF are in the data
        @test gv(bnd, ("REG2", "2020", "ELC", "SN", "IMP", "FX")).eps
        @test gv(bnd, ("IMPEXP", "2030", "COA", "ANNUAL", "IMP", "FX")).eps
        @test gv(bnd, ("REG2", "2030", "ELC", "WN", "IMP", "LO")).eps
        @test gv(bnd, ("REG2", "2030", "ELC", "WD", "IMP", "UP")).v == Inf
        # IRE_TSCVT: the given record, and the default of an external region (ANNUAL to ANNUAL only,
        # ppmain.mod L967-978)
        let cv = gparam(tm, "IRE_TSCVT")
            @test gv(cv, ("REG1", "W", "IMPEXP", "W")).v == 0.9
            @test sort([(k[2], k[4]) for k in cv.keys if k[1] == "REG2" && k[3] == "IMPEXP"]) == [("ANNUAL", "ANNUAL")]
            @test sort([(k[2], k[4]) for k in cv.keys if k[1] == "REG1" && k[3] == "IMPEXP"]) == [("ANNUAL", "ANNUAL"), ("W", "W")]
        end
        # RPC_IRE is a projection of TOP_IRE (ppmain.mod L44-45), so it holds the external regions:
        # their records pass the equation's domain
        @test ("IMPEXP", "IMPELC1", "ELC", "EXP") in gset(tm, "RPC_IRE")
        @test ("IMPEXP", "EXPGAS1", "GAS", "IMP") in gset(tm, "RPC_IRE")
        # the dummy import is an exchange process of the region, but its link from IMPEXP is
        # removed where the commodity has no IRE_BND (pp_prelv.vda L91, L111)
        @test ("REG1", "IMPNRGZ", "ELC", "IMP") in gset(tm, "RPC_IRE")
        @test !any(k -> k[5] == "IMPNRGZ", gset(tm, "TOP_IRE"))
        # the new import process runs at SEASON
        @test sort([k[5] for k in gset(tm, "RTPCS_VARF") if k[1:4] == ("REG1", "2020", "IMPELC2", "ELC")]) == ["S", "W"]
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_xbnd_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_xbnd_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_XBND\(", r)])
        @test rows == ["EQE_XBND(IMPEXP,2030,COA,ANNUAL,IMP)", "EQE_XBND(REG2,2020,ELC,ANNUAL,EXP)",
                       "EQE_XBND(REG2,2020,ELC,SN,IMP)",
                       "EQG_XBND(IMPEXP,2020,GAS,ANNUAL,IMP)", "EQG_XBND(REG1,2020,ELC,WD,IMP)",
                       "EQG_XBND(REG2,2020,GAS,ANNUAL,EXP)",
                       "EQL_XBND(IMPEXP,2020,ELC,ANNUAL,EXP)", "EQL_XBND(IMPEXP,2030,ELC,W,EXP)",
                       "EQL_XBND(MINRNW,2020,COA,ANNUAL,EXP)", "EQL_XBND(MINRNW,2030,COA,ANNUAL,EXP)",
                       "EQL_XBND(MINRNW,2050,COA,ANNUAL,EXP)", "EQL_XBND(REG1,2020,COA,ANNUAL,EXP)",
                       "EQL_XBND(REG1,2020,ELC,ANNUAL,IMP)", "EQL_XBND(REG1,2030,COA,ANNUAL,EXP)",
                       "EQL_XBND(REG1,2030,ELC,S,EXP)", "EQL_XBND(REG1,2030,GAS,WD,IMP)",
                       "EQL_XBND(REG1,2050,COA,ANNUAL,EXP)"]
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        tb(r, t, s, ie) = "VAR_IRE($r,$t,$t,TB_ELC_REG1_REG2_01,ELC,$s,$ie)"
        act(r, t, p, s) = "VAR_ACT($r,$t,$t,$p,$s)"
        dum(r, t, c) = "VAR_IRE($r,$t,$t,IMPNRGZ,$c,ANNUAL,IMP)"
        dn = ("SD", "SN", "WD", "WN")

        # L23-32, an internal region: every exchange process of the region with the commodity in
        # the direction, whatever the partner: the imports from IMPEXP (at DAYNITE and at SEASON),
        # the dummy import (at ANNUAL) and the imports from REG2
        @test lohi("EQL_XBND(REG1,2020,ELC,ANNUAL,IMP)") == (-Inf, 500.0)
        @test near(terms("EQL_XBND(REG1,2020,ELC,ANNUAL,IMP)"),
                   merge(Dict(act("REG1", "2020", "IMPELC1", s) => 1.0 for s in dn),
                         Dict(act("REG1", "2020", "IMPELC2", s) => 1.0 for s in ("S", "W")),
                         Dict(tb("REG1", "2020", s, "IMP") => 1.0 for s in dn),
                         Dict(dum("REG1", "2020", "ELC") => 1.0)))
        # ... L30, RS_FR: a flow at a timeslice above the bound's counts with the bound's share of it
        @test lohi("EQG_XBND(REG1,2020,ELC,WD,IMP)") == (30.0, Inf)
        @test near(terms("EQG_XBND(REG1,2020,ELC,WD,IMP)"),
                   Dict(act("REG1", "2020", "IMPELC1", "WD") => 1.0, act("REG1", "2020", "IMPELC2", "W") => yrfr("WD") / yrfr("W"),
                        tb("REG1", "2020", "WD", "IMP") => 1.0, dum("REG1", "2020", "ELC") => yrfr("WD")))
        # ... a bound at the season S: the flows below S in full
        @test lohi("EQL_XBND(REG1,2030,ELC,S,EXP)") == (-Inf, 100.0)
        @test near(terms("EQL_XBND(REG1,2030,ELC,S,EXP)"),
                   merge(Dict(act("REG1", "2030", "EXPELC1", s) => 1.0 for s in ("SD", "SN")),
                         Dict(tb("REG1", "2030", s, "EXP") => 1.0 for s in ("SD", "SN"))))
        # ... the export to the external region and the gas link, both by their activity
        @test lohi("EQG_XBND(REG2,2020,GAS,ANNUAL,EXP)") == (10.0, Inf)
        @test near(terms("EQG_XBND(REG2,2020,GAS,ANNUAL,EXP)"),
                   Dict(act("REG2", "2020", "EXPGAS1", "ANNUAL") => 1.0, act("REG2", "2020", "TU_GAS_REG2_REG1_01", "ANNUAL") => 1.0))
        # ... an equality
        @test lohi("EQE_XBND(REG2,2020,ELC,ANNUAL,EXP)") == (40.0, 40.0)
        @test near(terms("EQE_XBND(REG2,2020,ELC,ANNUAL,EXP)"),
                   merge(Dict(act("REG2", "2020", "EXPELC1", s) => 1.0 for s in dn), Dict(tb("REG2", "2020", s, "EXP") => 1.0 for s in dn)))
        # ... a bound finer than the commodity's level (GAS is tracked at ANNUAL): a row all the
        # same, the flows at ANNUAL with the share of WD (MINGAS3 has no flow in 2030 under REDUCE)
        @test lohi("EQL_XBND(REG1,2030,GAS,WD,IMP)") == (-Inf, 5000.0)
        @test near(terms("EQL_XBND(REG1,2030,GAS,WD,IMP)"),
                   merge(Dict(act("REG1", "2030", p, "ANNUAL") => yrfr("WD") for p in ("IMPGAS1", "MINGAS1", "MINGAS2", "TU_GAS_REG2_REG1_01")),
                         Dict(dum("REG1", "2030", "GAS") => yrfr("WD"))))
        # ... in each period of the interpolated bound
        for t in ("2020", "2030", "2050")
            @test lohi("EQL_XBND(REG1,$t,COA,ANNUAL,EXP)") == (-Inf, 600.0)
            @test near(terms("EQL_XBND(REG1,$t,COA,ANNUAL,EXP)"), Dict(act("REG1", t, "EXPCOA1", "ANNUAL") => 1.0))
        end
        # FX with the value EPS: a row with the right-hand side zero (eqmain.mod L242: YES)
        @test lohi("EQE_XBND(REG2,2020,ELC,SN,IMP)") == (0.0, 0.0)
        @test near(terms("EQE_XBND(REG2,2020,ELC,SN,IMP)"),
                   Dict(act("REG2", "2020", "IMPELC1", "SN") => 1.0, tb("REG2", "2020", "SN", "IMP") => 1.0,
                        dum("REG2", "2020", "ELC") => yrfr("SN", "REG2")))

        # L39-51, an external region: the flows of the internal regions in the other direction,
        # through the processes linked to it. A bound on the imports of IMPEXP: the exports of
        # REG1 and REG2 to it
        @test lohi("EQG_XBND(IMPEXP,2020,GAS,ANNUAL,IMP)") == (3.0, Inf)
        @test near(terms("EQG_XBND(IMPEXP,2020,GAS,ANNUAL,IMP)"), Dict(act(r, "2020", "EXPGAS1", "ANNUAL") => 1.0 for r in ("REG1", "REG2")))
        @test lohi("EQE_XBND(IMPEXP,2030,COA,ANNUAL,IMP)") == (0.0, 0.0)
        @test near(terms("EQE_XBND(IMPEXP,2030,COA,ANNUAL,IMP)"), Dict(act(r, "2030", "EXPCOA1", "ANNUAL") => 1.0 for r in ("REG1", "REG2")))
        # ... a bound on the exports of IMPEXP: the imports of REG1 and REG2 from it. The dummy
        # import has no link from IMPEXP left and is not in the row
        @test lohi("EQL_XBND(IMPEXP,2020,ELC,ANNUAL,EXP)") == (-Inf, 300.0)
        @test near(terms("EQL_XBND(IMPEXP,2020,ELC,ANNUAL,EXP)"),
                   merge(Dict(act(r, "2020", "IMPELC1", s) => 1.0 for r in ("REG1", "REG2") for s in dn),
                         Dict(act("REG1", "2020", "IMPELC2", s) => 1.0 for s in ("S", "W"))))
        # ... the mining of both regions, in each period of the interpolated bound (MINCOA3 of REG2
        # has no flow under REDUCE)
        for t in ("2020", "2030", "2050")
            @test lohi("EQL_XBND(MINRNW,$t,COA,ANNUAL,EXP)") == (-Inf, 9000.0)
            @test near(terms("EQL_XBND(MINRNW,$t,COA,ANNUAL,EXP)"),
                       merge(Dict(act("REG1", t, "MINCOA$i", "ANNUAL") => 1.0 for i in 1:3), Dict(act("REG2", t, "MINCOA$i", "ANNUAL") => 1.0 for i in 1:2)))
        end
        # ... L42, L48: a timeslice of the external region is reached through IRE_TSCVT. Only REG1
        # has a record to W of IMPEXP (0.9); the flows at and below REG1's season W
        @test lohi("EQL_XBND(IMPEXP,2030,ELC,W,EXP)") == (-Inf, 150.0)
        @test near(terms("EQL_XBND(IMPEXP,2030,ELC,W,EXP)"),
                   Dict(act("REG1", "2030", "IMPELC1", "WD") => 0.9, act("REG1", "2030", "IMPELC1", "WN") => 0.9, act("REG1", "2030", "IMPELC2", "W") => 0.9))
        # nothing: LO with the value EPS and UP INF (L241, L243), a commodity without an exchange
        # process, an external region's timeslice without IRE_TSCVT (a row without a variable), an
        # external region without a link for the commodity
        @test !any(r -> occursin("(REG2,2030,ELC,W", r) || occursin("TOTCO2", r) || occursin("(IMPEXP,2020,ELC,WD,", r) ||
                        occursin("(MINRNW,2020,ELC,", r), rows)
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_xbnd!(t0) == 0
    end
end
