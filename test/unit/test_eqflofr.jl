# EQ(l)_FLOFR (eqflofr.mod L15-27 with eqmain.mod L118-120; `eq_flofr!`), on the crafted case
# demo12_flofr (reference/dd/demo12_flofr; M1.3 change 33, 14 Nov 2026): the share of a process
# flow in a timeslice (FLO_FR). The data as ppmain.mod L992 and pp_prelv.vda L99-109 leave it, the
# model from GAMS's pre-solve dump against GAMS's matrix (layer 2), then the twenty-seven rows of
# the REDUCE variant and the records that give nothing. Under REDUCE the flows of the power plants
# are the activity times the flow's coefficient (cal_red.red), so the rows are on VAR_ACT; the
# variables of an aggregate flow are VAR_FLO.

using TIMES: TimesModel, generate!, eq_flofr!, untranslated_families, gparam, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_flofr")
    tm = TimesModel(joinpath(FIXTURES, "demo12_flofr_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    fr = gparam(tm, "FLO_FR")
    yrfr(s) = gv(gparam(tm, "G_YRFR"), ("REG1", s)).v
    @testset "the data of the case" begin
        # pp_prelv.vda L100-103: a record at ANNUAL is levelised. A DAYNITE flow: 'N' at the seasons
        # (their share of the year), the bound in each timeslice times its share of the year
        @test gv(fr, ("REG1", "2030", "ELCRNWIN01", "ELC", "S", "N")).v == yrfr("S")
        @test gv(fr, ("REG1", "2030", "ELCRNWIN01", "ELC", "W", "N")).v == yrfr("W")
        @test all(s -> gv(fr, ("REG1", "2030", "ELCRNWIN01", "ELC", s, "UP")).v ≈ 1.1 * yrfr(s), ("SD", "SN", "WD", "WN"))
        @test !any(s -> haskey(fr, ("REG1", "2030", "ELCRNWIN01", "ELC", "ANNUAL", s)), ("UP", "N"))
        # a SEASON flow: 'N' at ANNUAL (the seasons make up the year), the bound in each season
        @test gv(fr, ("REG1", "2030", "ELCTECOA00", "ELCCOA", "ANNUAL", "N")).v ≈ 1.0
        @test all(s -> gv(fr, ("REG1", "2030", "ELCTECOA00", "ELCCOA", s, "LO")).v ≈ 0.9 * yrfr(s), ("S", "W"))
        # L105-109: the record at the year '0' and ANNUAL, with bounds of the same type below: 'N' 1 at
        # ANNUAL and 'N' EPS at the seasons; the record itself stays
        for (r, t, p, c, bd) in (("REG1", "2020", "FTE-RSDELC", "ELC", "UP"), ("REG2", "2030", "ELCTNGAS01", "ELCGAS", "LO"))
            @test gv(fr, (r, t, p, c, "ANNUAL", "N")) == TIMES.GNum(1.0)
            @test all(s -> gv(fr, (r, t, p, c, s, "N")).eps, ("S", "W"))
            @test gv(fr, (r, "0", p, c, "ANNUAL", bd)).v == 1.0
        end
        # ppmain.mod L992 (pp_lvlbd.mod): UP records below the flow's level are added up where they
        # cover the whole of the timeslice above (SD and SN), and not otherwise (WD alone)
        @test gv(fr, ("REG1", "2020", "ELCNENUC00", "ELC", "S", "UP")).v == 0.6
        @test gv(fr, ("REG2", "2020", "ELCNENUC00", "ELC", "WD", "UP")).v == 0.45
        @test !haskey(fr, ("REG2", "2020", "ELCNENUC00", "ELC", "W", "UP"))
        # the option 5 at the year '0': records from the first data year on; the option record is gone
        @test all(t -> gv(fr, ("REG2", t, "ELCTEGAS00", "ELC", "WN", "LO")).v == 0.1, ("2020", "2030", "2050"))
        @test !haskey(fr, ("REG2", "0", "ELCTEGAS00", "ELC", "WN", "LO"))
        @test gv(fr, ("REG2", "2030", "ELCRNWIN01", "ELC", "SN", "LO")).eps
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_flofr_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_flofr_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_FLOFR\(", r)])
        @test rows == ["EQE_FLOFR(REG1,2020,ELCTNGAS01,ELC,W,FX)", "EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,ANNUAL,N)",
                       "EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,S,N)", "EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,W,N)",
                       "EQE_FLOFR(REG1,2030,ELCRNWIN01,ELC,S,N)", "EQE_FLOFR(REG1,2030,ELCRNWIN01,ELC,W,N)",
                       "EQE_FLOFR(REG1,2030,ELCTECOA00,ELCCOA,ANNUAL,N)", "EQE_FLOFR(REG2,2020,ELCREWIN00,ELC,W,N)",
                       "EQE_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,ANNUAL,N)", "EQE_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,S,N)",
                       "EQE_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,W,N)",
                       "EQG_FLOFR(REG1,2020,ELCNENUC00,ELC,S,UP)", "EQG_FLOFR(REG1,2020,ELCREHYD00,ELC,WD,UP)",
                       "EQG_FLOFR(REG1,2020,FTE-RSDELC,ELC,SD,UP)", "EQG_FLOFR(REG1,2020,FTE-RSDELC,ELC,W,UP)",
                       "EQG_FLOFR(REG1,2030,ELCRNWIN01,ELC,SD,UP)", "EQG_FLOFR(REG1,2030,ELCRNWIN01,ELC,SN,UP)",
                       "EQG_FLOFR(REG1,2030,ELCRNWIN01,ELC,WD,UP)", "EQG_FLOFR(REG1,2030,ELCRNWIN01,ELC,WN,UP)",
                       "EQG_FLOFR(REG2,2020,ELCREWIN00,ELC,WD,UP)", "EQG_FLOFR(REG2,2020,ELCTNGAS01,ELCCO2,SD,UP)",
                       "EQL_FLOFR(REG1,2020,ELCTEGAS00,ELCGAS,SD,LO)", "EQL_FLOFR(REG1,2030,ELCTECOA00,ELCCOA,S,LO)",
                       "EQL_FLOFR(REG1,2030,ELCTECOA00,ELCCOA,W,LO)", "EQL_FLOFR(REG2,2020,ELCTEGAS00,ELC,WN,LO)",
                       "EQL_FLOFR(REG2,2030,ELCRNWIN01,ELC,SN,LO)", "EQL_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,SN,LO)"]
        # the terms of a row, all on the left-hand side (fraction * reference flow - flow in the
        # timeslice), without the EPS coefficients
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        daynite = ("SD", "SN", "WD", "WN")
        @test all(r -> lohi(r) == (0.0, 0.0), filter(startswith("EQE"), rows))
        @test all(r -> lohi(r) == (0.0, Inf), filter(startswith("EQG"), rows))      # an upper bound on the share
        @test all(r -> lohi(r) == (-Inf, 0.0), filter(startswith("EQL"), rows))     # a lower bound on the share

        # a value above zero: a share of the flow of the year, at the flow's own level (L19: every
        # timeslice of the flow)
        @test near(terms("EQG_FLOFR(REG1,2020,ELCREHYD00,ELC,WD,UP)"),
                   Dict("VAR_ACT(REG1,2020,2020,ELCREHYD00,$ts)" => (ts == "WD" ? 0.4 - 1 : 0.4) for ts in daynite))
        @test near(terms("EQL_FLOFR(REG2,2020,ELCTEGAS00,ELC,WN,LO)"),
                   Dict("VAR_ACT(REG2,2020,2020,ELCTEGAS00,$ts)" => (ts == "WN" ? 0.1 - 1 : 0.1) for ts in daynite))
        # a negative value: a share of the flow of the parent timeslice (L19: RS_FR(R,SL,TS)); the gas
        # input is the activity times 2.0288...
        let t = terms("EQL_FLOFR(REG1,2020,ELCTEGAS00,ELCGAS,SD,LO)"), a = 2.028809089064719
            @test near(t, Dict("VAR_ACT(REG1,2020,2020,ELCTEGAS00,SD)" => (0.6 - 1) * a,
                               "VAR_ACT(REG1,2020,2020,ELCTEGAS00,SN)" => 0.6 * a))
        end
        # above the flow's level, FX, on the vintaged process: the flow of the season W against half
        # the flow of the year, over the vintages (L17, L25)
        @test near(terms("EQE_FLOFR(REG1,2020,ELCTNGAS01,ELC,W,FX)"),
                   Dict("VAR_ACT(REG1,$v,2020,ELCTNGAS01,$ts)" => (ts in ("WD", "WN") ? 0.5 - 1 : 0.5)
                        for v in ("2010", "2015", "2020"), ts in daynite))
        # UP records below the flow's level, added up to the season S (pp_lvlbd.mod)
        @test near(terms("EQG_FLOFR(REG1,2020,ELCNENUC00,ELC,S,UP)"),
                   Dict("VAR_ACT(REG1,2020,2020,ELCNENUC00,S)" => 0.6 - 1, "VAR_ACT(REG1,2020,2020,ELCNENUC00,W)" => 0.6))
        # an emission flow of the vintaged process: three times the weight at SD, with the other sign
        let t = terms("EQG_FLOFR(REG2,2020,ELCTNGAS01,ELCCO2,SD,UP)")
            @test length(t) == 12
            @test all(v -> all(ts -> t["VAR_ACT(REG2,$v,2020,ELCTNGAS01,SD)"] ≈ -3 * t["VAR_ACT(REG2,$v,2020,ELCTNGAS01,$ts)"],
                               ("SN", "WD", "WN")), ("2010", "2015", "2020"))
        end

        # a record at ANNUAL, levelised, on a DAYNITE flow: a variable for each season ('N', L17 with
        # L25-27) and each timeslice against the variable of its season (L18)
        for (s, below) in (("S", ("SD", "SN")), ("W", ("WD", "WN")))
            agg = "VAR_FLO(REG1,2030,2030,ELCRNWIN01,ELC,$s)"
            @test near(terms("EQE_FLOFR(REG1,2030,ELCRNWIN01,ELC,$s,N)"),
                       merge(Dict(agg => yrfr(s)), Dict("VAR_ACT(REG1,2030,2030,ELCRNWIN01,$ts)" => -1.0 for ts in below)))
            for ts in below
                @test near(terms("EQG_FLOFR(REG1,2030,ELCRNWIN01,ELC,$ts,UP)"),
                           Dict(agg => 1.1 * yrfr(ts), "VAR_ACT(REG1,2030,2030,ELCRNWIN01,$ts)" => -1.0))
            end
        end
        # ... and on a SEASON flow: a variable for the year
        let agg = "VAR_FLO(REG1,2030,2030,ELCTECOA00,ELCCOA,ANNUAL)", t = terms("EQE_FLOFR(REG1,2030,ELCTECOA00,ELCCOA,ANNUAL,N)")
            a = t["VAR_ACT(REG1,2030,2030,ELCTECOA00,S)"]
            @test a < 0 && near(t, Dict(agg => 1.0, "VAR_ACT(REG1,2030,2030,ELCTECOA00,S)" => a, "VAR_ACT(REG1,2030,2030,ELCTECOA00,W)" => a))
            for s in ("S", "W")
                @test near(terms("EQL_FLOFR(REG1,2030,ELCTECOA00,ELCCOA,$s,LO)"),
                           Dict(agg => 0.9 * yrfr(s), "VAR_ACT(REG1,2030,2030,ELCTECOA00,$s)" => a))
            end
        end
        # the variable of the annual flow (pp_prelv.vda L105-109): 'N' 1 at ANNUAL defines it; the rows
        # of the 'N' EPS at the seasons are kept and have no other coefficient (L27: no right-hand
        # side); the bounds are against the ANNUAL variable (L18: an EPS is not above zero)
        let agg = "VAR_FLO(REG1,2020,2020,FTE-RSDELC,ELC,ANNUAL)", act(ts) = "VAR_ACT(REG1,2020,2020,FTE-RSDELC,$ts)"
            @test near(terms("EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,ANNUAL,N)"), merge(Dict(agg => 1.0), Dict(act(ts) => -1.0 for ts in daynite)))
            @test isempty(terms("EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,S,N)"))
            @test isempty(terms("EQE_FLOFR(REG1,2020,FTE-RSDELC,ELC,W,N)"))
            @test near(terms("EQG_FLOFR(REG1,2020,FTE-RSDELC,ELC,SD,UP)"), Dict(agg => 0.35, act("SD") => -1.0))
            @test near(terms("EQG_FLOFR(REG1,2020,FTE-RSDELC,ELC,W,UP)"), Dict(agg => 0.5, act("WD") => -1.0, act("WN") => -1.0))
        end
        # the same on the vintaged process: a variable of the annual flow for each vintage
        let vs = ("2010", "2015", "2020", "2030"), t = terms("EQL_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,SN,LO)")
            @test sort(collect(keys(t))) == sort(vcat(["VAR_ACT(REG2,$v,2030,ELCTNGAS01,SN)" for v in vs],
                                                      ["VAR_FLO(REG2,$v,2030,ELCTNGAS01,ELCGAS,ANNUAL)" for v in vs]))
            @test all(v -> t["VAR_FLO(REG2,$v,2030,ELCTNGAS01,ELCGAS,ANNUAL)"] == 0.15 && t["VAR_ACT(REG2,$v,2030,ELCTNGAS01,SN)"] < 0, vs)
            n = terms("EQE_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,ANNUAL,N)")
            @test length(n) == 20 && all(v -> n["VAR_FLO(REG2,$v,2030,ELCTNGAS01,ELCGAS,ANNUAL)"] == 1.0, vs)
            @test isempty(terms("EQE_FLOFR(REG2,2030,ELCTNGAS01,ELCGAS,S,N)"))
        end
        # a record 'N' of the user at the season W, and a bound below it against the variable of W (L18)
        let agg = "VAR_FLO(REG2,2020,2020,ELCREWIN00,ELC,W)", act(ts) = "VAR_ACT(REG2,2020,2020,ELCREWIN00,$ts)"
            @test near(terms("EQE_FLOFR(REG2,2020,ELCREWIN00,ELC,W,N)"), Dict(agg => 1.0, act("WD") => -1.0, act("WN") => -1.0))
            @test near(terms("EQG_FLOFR(REG2,2020,ELCREWIN00,ELC,WD,UP)"), Dict(agg => 0.6, act("WD") => -1.0))
        end
        # LO with the value EPS: the row is kept, 0 =L= the flow at SN
        @test terms("EQL_FLOFR(REG2,2030,ELCRNWIN01,ELC,SN,LO)") == Dict("VAR_ACT(REG2,2030,2030,ELCRNWIN01,SN)" => -1.0)
        # nothing: an UP at WD alone below the flow's level, a period without the process (ELCRESOL00
        # in 2030, ELCTEGAS00 in REG2 after 2020), an exchange process
        @test !any(r -> occursin("(REG2,2020,ELCNENUC00,", r) || occursin("ELCRESOL00", r) || occursin("IMPELC1", r), rows)
        @test count(r -> occursin("ELCTEGAS00,ELC,WN", r), rows) == 1
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_flofr!(t0) == 0
    end
end
