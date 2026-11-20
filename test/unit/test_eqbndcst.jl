# EQ_BNDCST and VAR_CUMCST (eqbndcst.mod L42-77 and L81-213 with eqmain.mod L192, bnd_cum.mod
# L44-48; `eqmain_prep!`, `eq_bndcst!`, `bnd_cum!`), on the crafted case demo12_bndcst
# (reference/dd/demo12_bndcst; M1.3 change 39, 14 Nov 2026): bounds on the costs of a region by cost type,
# for a single period (REG_BNDCST) and over a range of years (REG_CUMCST). From GAMS's ppm dump
# through the coefficient stage and the coef -> pre-solve step with TIMES.jl's own state; every
# set and parameter against the pre-solve dump (1e-9); the statements of eqbndcst.mod L42-77;
# the model from that state against GAMS's matrix (layer 2); then the 79 rows of the REDUCE
# variant, the terms of chosen rows and the bounds of VAR_CUMCST.

using OpenTIMES: TimesModel, DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!,
             prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, eqmain_prep_symbols, bnd_data!, pp_qack_data!,
             pp_clean!, generate!, eq_bndcst!, untranslated_families, gset, gparam, gset_opt, gv
using OpenTIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_bndcst")
    tm = TimesModel(joinpath(FIXTURES, "demo12_bndcst_ppm"); reduce=vx["reduce"], switches=vx["switches"])
    names = sort([i.name for i in values(tm.data.dump.symbols) if i.kind in (:set, :parameter)])
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!))
    # the state after eqmain.mod's data statements, on the symbols that step settles (the comparison
    # of scripts/m13_probe.jl), and the scratch set UNCD7 as it stands there
    step = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_bndcst_presolve")), eqmain_prep_symbols(tm))
    uncd7_eqmain = length(gset_opt(tm.data, "UNCD7", 7).keys)
    foreach(f -> f(tm), (bnd_data!, pp_qack_data!, pp_clean!))
    cum, ann = gparam(tm, "REG_CUMCST"), gparam(tm, "CST_ANNC")
    c(k...) = gv(cum, (k[1:4]..., "MEuro05", k[5]))
    a(k...) = gv(ann, (k..., "MEuro05")).v
    @testset "ppm -> pre-solve, every set and parameter" begin
        ref = DumpData(joinpath(FIXTURES, "demo12_bndcst_presolve"))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))
        foreach(d -> ispass(d) || println("demo12_bndcst ppm -> presolve: ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
        @test isempty(untranslated_families(tm))
    end
    @testset "the eqmain step on the symbols it settles" begin
        foreach(d -> ispass(d) || println("demo12_bndcst eqmain step: ", d, " ", d.examples), step)
        @test length(step) == 30 && all(ispass, step)
        # UNCD7 is not one of them without dispatching data: eqmain.mod leaves the decommissioning
        # spreads of eqobjinv.mod L245-247 in it (11 here), and pp_qack.mod L258 and L339-342 replace
        # them with the empty set of the pre-solve dump
        @test !("UNCD7" in eqmain_prep_symbols(tm))
        @test uncd7_eqmain == 11 && isempty(gset_opt(tm.data, "UNCD7", 7).keys)
    end
    @testset "the statements of eqbndcst.mod L42-77" begin
        # L42: a bound of a single period becomes a bound over the range (T,T); the interpolated
        # and extrapolated bound (option 5) in every period from 2010; the value EPS is kept
        @test c("REG1", "2020", "2020", "INV", "UP").v == 1.0e6
        @test all(t -> c("REG1", t, t, "FOMALL", "UP").v == 1.0e6, ("2010", "2015", "2020", "2030", "2050"))
        @test !haskey(cum, ("REG1", "2005", "2005", "FOMALL", "MEuro05", "UP"))
        @test c("REG2", "2015", "2015", "INVSUB", "UP").eps
        # L44-45: a bound on an aggregate gives each of its components without an upper bound the
        # upper bound INF; a component with its own bound keeps it
        @test all(x -> c("REG1", "2050", "2050", x, "UP").v == Inf, ("INVTAX", "INVSUB"))
        @test all(x -> c("REG1", "2010", "2010", x, "UP").v == Inf, ("FOM", "FOMTAX", "FOMSUB"))
        @test c("REG1", "2030", "2030", "FOM", "UP").v == 1.0e6 && c("REG1", "2020", "2020", "FOMSUB", "UP").v == 1.0e6
        @test count(k -> k[1:3] == ("REG1", "2005", "2060") && gv(cum, k).v == Inf, cum.keys) == 8
        # ... also where the aggregate has a lower bound only (BD, not 'UP' alone)
        @test all(x -> c("REG2", "2013", "2040", x, "UP").v == Inf, ("INVSUB", "FOMSUB", "COMSUB", "FLOSUB"))
        @test count(k -> k[1:3] == ("REG2", "2030", "2030") && k[4] != "COMTAX" && k[6] == "UP" && gv(cum, k).v == Inf, cum.keys) == 7
        # L46-47: a lower or fixed bound alone gets the upper bound INF
        @test c("REG1", "2030", "2030", "INVSUB", "LO").v == 1.0 && c("REG1", "2030", "2030", "INVSUB", "UP").v == Inf
        @test c("REG1", "2006", "2052", "FOMTAX", "LO").v == 0.1 && c("REG1", "2006", "2052", "FOMTAX", "UP").v == Inf
        @test c("REG1", "2021", "2060", "FLOSUB", "FX").v == 14000.0 && c("REG1", "2021", "2060", "FLOSUB", "UP").v == Inf
        @test c("REG2", "2013", "2040", "ALLSUB", "UP").v == Inf && c("REG2", "2030", "2030", "FIXALL", "UP").v == Inf
        @test length(cum.keys) == 84 && count(k -> k[6] == "UP", cum.keys) == 79
        # L51, L68: the bounds of single periods on INV, and on INVTAX or INVSUB (the value EPS
        # counts: REG2 2015), also where L44-45 gave them (INVTAXSUB 2050, INVALL 2020-2020,
        # FIXALL 2030). A bound over a range of years gives none
        @test sort(gset(tm, "RT_IAN").keys) ==
              [("REG1", "2020", "2020", "MEuro05", "INV"), ("REG1", "2020", "2020", "MEuro05", "INVTAXSUB"),
               ("REG1", "2030", "2030", "MEuro05", "INV"), ("REG1", "2030", "2030", "MEuro05", "INVTAXSUB"),
               ("REG1", "2050", "2050", "MEuro05", "INVTAXSUB"), ("REG2", "2015", "2015", "MEuro05", "INVTAXSUB"),
               ("REG2", "2020", "2020", "MEuro05", "INV"), ("REG2", "2020", "2020", "MEuro05", "INVTAXSUB"),
               ("REG2", "2030", "2030", "MEuro05", "INV"), ("REG2", "2030", "2030", "MEuro05", "INVTAXSUB")]
        # L77: TRACKP and RTP_IAN are cleared
        @test isempty(gset_opt(tm.data, "RTP_IAN", 4).keys) && isempty(gset_opt(tm.data, "TRACKP", 2).keys)
        # L55-64, L70-76: CST_ANNC, the annual investment cost, tax and subsidy of a unit of
        # capacity by vintage and period; the subsidy is stored with a minus sign (L75)
        @test length(ann.keys) == 318
        @test Dict(u => count(k -> k[5] == u, ann.keys) for u in ("INVCOST", "INVTAX", "INVSUB")) ==
              Dict("INVCOST" => 277, "INVTAX" => 22, "INVSUB" => 19)
        @test all(k -> gv(ann, k).v < 0, filter(k -> k[5] == "INVSUB", ann.keys))
        @test a("REG1", "2020", "ELCTNCOA01", "2020", "INVTAX") ≈ 11.100602126863816
        @test a("REG1", "2020", "ELCRNWIN01", "2030", "INVSUB") ≈ -22.92645348305468
        # ... only the vintages whose own period has such a bound (RTP_IAN, L52 and L69): REG1 has
        # no bound of a single period on an investment type in 2010 or 2015
        @test !any(k -> k[1] == "REG1" && k[2] in ("2005", "2010", "2015"), ann.keys)
        # ... ELCTNOIL01 (a 10-year life, decommissioning costs, L60-64): the vintage 2020 has
        # another coefficient in 2030 than in 2020, and no tax in 2030
        @test a("REG1", "2020", "ELCTNOIL01", "2020", "INVCOST") ≈ 30.834422610823037
        @test a("REG1", "2020", "ELCTNOIL01", "2030", "INVCOST") ≈ 10.491673275178437
        @test !haskey(ann, ("REG1", "2020", "ELCTNOIL01", "2030", "INVTAX", "MEuro05"))
    end
    @testset "the model from that state (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_bndcst_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_bndcst_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        # one row per upper bound, with the period TT the last year lies in (SUPERYR)
        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ_BNDCST\(", r)])
        superyr = gset(tm, "SUPERYR").keys
        @test length(rows) == 79 == count(k -> startswith(k, "VAR_CUMCST("), keys(mine.cols))
        @test rows == sort(["EQ_BNDCST($r,$y,$tt,$ll,$cat,MEURO05)" for (r, y, ll, cat, _, bd) in cum.keys if bd == "UP"
                            for (tt, l2) in superyr if l2 == ll])
        @test all(r -> (mine.rows[r].lo, mine.rows[r].hi) == (0.0, 0.0), rows)
        # ... a last year after a milestone year belongs to the next period; a range inside one
        # period has a row; a last year after the horizon belongs to the last period
        @test "EQ_BNDCST(REG1,2000,2015,2012,FLOTAX,MEURO05)" in rows && "EQ_BNDCST(REG2,2022,2030,2024,INV,MEURO05)" in rows
        @test "EQ_BNDCST(REG1,2021,2050,2060,FLOSUB,MEURO05)" in rows && "EQ_BNDCST(REG1,2045,2050,2100,COMTAX,MEURO05)" in rows
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        near(x, y) = keys(x) == keys(y) && all(k -> isapprox(x[k], y[k]; rtol=1e-6), keys(x))
        cst(r, y, ll, cat) = "VAR_CUMCST($r,$y,$ll,$cat,MEURO05)"
        ncap(r, t, p) = "VAR_NCAP($r,$t,$p)"
        dn = ("SD", "SN", "WD", "WN")

        # L210, an aggregate: its components, a subsidy with a minus sign
        @test near(terms("EQ_BNDCST(REG1,2050,2050,2050,INVTAXSUB,MEURO05)"),
                   Dict(cst("REG1", "2050", "2050", "INVTAXSUB") => -1.0, cst("REG1", "2050", "2050", "INVTAX") => 1.0,
                        cst("REG1", "2050", "2050", "INVSUB") => -1.0))
        @test near(terms("EQ_BNDCST(REG2,2030,2030,2030,FIXALL,MEURO05)"),
                   merge(Dict(cst("REG2", "2030", "2030", x) => 1.0 for x in ("INV", "INVTAX", "FOM", "FOMTAX")),
                         Dict(cst("REG2", "2030", "2030", x) => -1.0 for x in ("INVSUB", "FOMSUB", "FIXALL"))))
        # ... ALLSUB adds the subsidies up: its components have the type TAX in COST_GMAP (L34)
        @test near(terms("EQ_BNDCST(REG2,2013,2050,2040,ALLSUB,MEURO05)"),
                   merge(Dict(cst("REG2", "2013", "2040", x) => 1.0 for x in ("INVSUB", "FOMSUB", "COMSUB", "FLOSUB")),
                         Dict(cst("REG2", "2013", "2040", "ALLSUB") => -1.0)))
        @test length(terms("EQ_BNDCST(REG1,2005,2050,2060,ALLTAXSUB,MEURO05)")) == 9

        # L164-172, commodities: the tax times the years of the period in the range. One year
        # for a bound of a single period
        @test near(terms("EQ_BNDCST(REG1,2020,2020,2020,COMTAX,MEURO05)"),
                   merge(Dict("VAR_COMNET(REG1,2020,ELCCO2,ANNUAL)" => 2.0, cst("REG1", "2020", "2020", "COMTAX") => -1.0),
                         Dict("VAR_COMPRD(REG1,2020,ELC,$s)" => 0.3 for s in dn)))
        # ... 2005-2060: every period with its length (3, 5, 5, 8, 15 and 12 years)
        let t = terms("EQ_BNDCST(REG1,2005,2050,2060,COMTAX,MEURO05)")
            @test [t["VAR_COMNET(REG1,$y,ELCCO2,ANNUAL)"] for y in ("2005", "2010", "2015", "2020", "2030", "2050")] ≈
                  [6.0, 10.0, 10.0, 16.0, 30.0, 24.0]
            @test length(t) == 31
        end
        # ... 2045-2100: the years 2045 to 2052 of the last period
        @test near(terms("EQ_BNDCST(REG1,2045,2050,2100,COMTAX,MEURO05)"),
                   merge(Dict("VAR_COMNET(REG1,2050,ELCCO2,ANNUAL)" => 16.0, cst("REG1", "2045", "2100", "COMTAX") => -1.0),
                         Dict("VAR_COMPRD(REG1,2050,ELC,$s)" => 2.4 for s in dn)))
        # ... a subsidy counts positive in its own row (OBJ_COMPD holds it with a minus sign, L169)
        @test near(terms("EQ_BNDCST(REG2,2020,2020,2020,COMSUB,MEURO05)"),
                   merge(Dict(cst("REG2", "2020", "2020", "COMSUB") => -1.0), Dict("VAR_COMPRD(REG2,2020,ELC,$s)" => 0.05 for s in dn)))
        # L175-207, flows: 2000 is before the years YK holds, so no year passes YK(Y_EOH,YEAR)
        # and the row has the variable alone (GAMS's row is the same)
        @test !any(k -> k[2] == "2000", gset(tm, "YK").keys)
        @test near(terms("EQ_BNDCST(REG1,2000,2015,2012,FLOTAX,MEURO05)"), Dict(cst("REG1", "2000", "2012", "FLOTAX") => -1.0))
        # ... ordinary processes by their activity under REDUCE, the electricity link by VAR_IRE
        let t = terms("EQ_BNDCST(REG1,2020,2020,2020,FLOTAX,MEURO05)")
            fam(x) = count(k -> startswith(k, x), keys(t))
            @test (fam("VAR_ACT("), fam("VAR_IRE("), fam("VAR_CUMCST(")) == (17, 8, 1)
        end

        # L95, L109, L116: a bound of a single period on an investment type takes the annual
        # coefficients CST_ANNC of the vintages up to the period
        @test near(terms("EQ_BNDCST(REG1,2020,2020,2020,INVTAX,MEURO05)"),
                   merge(Dict(ncap("REG1", "2020", p) => a("REG1", "2020", p, "2020", "INVTAX") for p in ("ELCNNNUC01", "ELCTNCOA01", "ELCTNOIL01")),
                         Dict(cst("REG1", "2020", "2020", "INVTAX") => -1.0)))
        # ... the subsidy with a minus sign on the negative CST_ANNC (L116); a lower bound alone has
        # a row all the same (the upper bound INF of L46-47)
        @test near(terms("EQ_BNDCST(REG1,2030,2030,2030,INVSUB,MEURO05)"),
                   merge(Dict(ncap("REG1", "2020", p) => -a("REG1", "2020", p, "2030", "INVSUB") for p in ("ELCNNNUC01", "ELCRNWIN01")),
                         Dict(ncap("REG1", "2030", p) => -a("REG1", "2030", p, "2030", "INVSUB") for p in ("ELCNNNUC01", "ELCRNWIN01", "ELCTNOIL01")),
                         Dict(cst("REG1", "2030", "2030", "INVSUB") => -1.0)))
        # ... the bound with the value EPS: a row, and the variable fixed at zero
        @test near(terms("EQ_BNDCST(REG2,2015,2015,2015,INVSUB,MEURO05)"),
                   Dict(ncap("REG2", "2015", "ELCRNWIN01") => 11.46322674152734, cst("REG2", "2015", "2015", "INVSUB") => -1.0))
        # L90-94, L106-108: a bound over a range of years takes the payments year by year
        let t = terms("EQ_BNDCST(REG1,2008,2030,2025,INVTAX,MEURO05)")
            @test length(t) == 9 && count(k -> startswith(k, "VAR_NCAP("), keys(t)) == 8
        end
        @test length(terms("EQ_BNDCST(REG1,2012,2050,2034,INV,MEURO05)")) == 177
        @test length(terms("EQ_BNDCST(REG2,2022,2030,2024,INV,MEURO05)")) == 123

        # L121-160, fixed costs: the subsidy of ELCRNWIN01 has a shape and a multiplier (the
        # correction of L154-159), that of ELCTNOIL01 has none
        @test near(terms("EQ_BNDCST(REG1,2010,2010,2010,FOMSUB,MEURO05)"),
                   Dict(ncap("REG1", "2010", "ELCRNWIN01") => 3.76, ncap("REG1", "2010", "ELCTNOIL01") => 1.0,
                        cst("REG1", "2010", "2010", "FOMSUB") => -1.0))
        @test near(terms("EQ_BNDCST(REG1,2050,2050,2050,FOMSUB,MEURO05)"),
                   Dict(ncap("REG1", "2050", "ELCRNWIN01") => 6.671, ncap("REG1", "2050", "ELCTNOIL01") => 1.0,
                        cst("REG1", "2050", "2050", "FOMSUB") => -1.0))
        # ... the tax of ELCTNCOA01 has a shape (L140-145)
        let t = terms("EQ_BNDCST(REG1,2010,2010,2010,FOMTAX,MEURO05)")
            @test isapprox(t[ncap("REG1", "2010", "ELCTNCOA01")], 4.78947; rtol=1e-5) && t[ncap("REG1", "2010", "ELCTNOIL01")] ≈ 2.0
            @test length(t) == 3
        end
        @test length(terms("EQ_BNDCST(REG1,2010,2030,2030,FOM,MEURO05)")) == 124

        # bnd_cum.mod L44-48, the bounds of VAR_CUMCST: an aggregate with an upper bound is free
        # below; an upper bound; INF; a lower bound alone; a fixed value; the value EPS; a lower
        # bound on an aggregate (L47 after the -INF of L44-45)
        lohi(k...) = (x = mine.cols[cst(k...)]; (x.lb, x.ub))
        @test lohi("REG1", "2005", "2060", "ALLTAXSUB") == (-Inf, 1.0e7)
        @test lohi("REG1", "2050", "2050", "INVTAXSUB") == (-Inf, 1.0e6)
        @test lohi("REG1", "2020", "2020", "INV") == (0.0, 1.0e6)
        @test lohi("REG1", "2005", "2060", "COMSUB") == (0.0, Inf)
        @test lohi("REG1", "2006", "2052", "FOMTAX") == (0.1, Inf)
        @test lohi("REG1", "2021", "2060", "FLOSUB") == (14000.0, 14000.0)
        @test lohi("REG2", "2015", "2015", "INVSUB") == (0.0, 0.0)
        @test lohi("REG2", "2030", "2030", "FIXALL") == (1.0, Inf)
        @test lohi("REG2", "2013", "2040", "ALLSUB") == (0.1, Inf)
        @test count(k -> startswith(k, "VAR_CUMCST(") && mine.cols[k].lb == -Inf, keys(mine.cols)) == 10
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_bndcst!(t0) == 0
    end
end
