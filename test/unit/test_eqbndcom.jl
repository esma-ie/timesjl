# EQ(l)_BNDNET and EQ(l)_BNDPRD (eqbndcom.mod L16-24 with eqmain.mod L54-59; `eq_bndcom!`), on the
# crafted case demo12_bndc (reference/dd/demo12_bndc; M1.3 change 31, 14 Nov 2026): bounds on the
# net amount and the production of ELC, a commodity tracked at DAYNITE, given at ANNUAL and at a
# season. The model from GAMS's pre-solve dump against GAMS's matrix (layer 2), then the six rows,
# the bound that stays a bound of the variable, and the records that give no row.

using TIMES: TimesModel, generate!, eq_bndcom!, untranslated_families, gparam, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_bndc")
    tm = TimesModel(joinpath(FIXTURES, "demo12_bndc_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    @testset "the data of the case" begin
        net, prd = gparam(tm, "COM_BNDNET"), gparam(tm, "COM_BNDPRD")
        @test gv(prd, ("REG1", "2020", "ELC", "ANNUAL", "LO")).v == 6000
        @test gv(net, ("REG2", "2030", "ELC", "ANNUAL", "FX")).eps            # a stored EPS: a row, eqmain.mod L55
        @test gv(net, ("REG1", "2020", "RSDELC", "ANNUAL", "LO")).eps         # LO NE 0 fails: no row, L54
        @test gv(net, ("REG1", "2020", "COMELC", "ANNUAL", "UP")).v == Inf    # UP NE INF fails: no row, L56
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_bndc_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_bndc_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_BND(NET|PRD)\(", r)])
        @test rows == ["EQE_BNDNET(REG2,2030,ELC,ANNUAL)", "EQE_BNDPRD(REG2,2030,ELC,S)", "EQG_BNDNET(REG1,2030,ELC,ANNUAL)",
                       "EQG_BNDPRD(REG1,2020,ELC,ANNUAL)", "EQL_BNDNET(REG2,2020,ELC,W)", "EQL_BNDPRD(REG1,2030,ELC,ANNUAL)"]
        terms(r) = sort([c => v for ((rr, c), v) in mine.coefs if rr == r])
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        var(kind, r, t, tss) = ["VAR_COM$kind($r,$t,ELC,$ts)" => 1.0 for ts in tss]
        daynite = ("SD", "SN", "WD", "WN")
        # G with LO, L with UP, E with FX: the bound on the right-hand side
        @test lohi("EQG_BNDPRD(REG1,2020,ELC,ANNUAL)") == (6000.0, Inf)
        @test lohi("EQL_BNDPRD(REG1,2030,ELC,ANNUAL)") == (-Inf, 6000.0)
        @test lohi("EQE_BNDPRD(REG2,2030,ELC,S)") == (4100.0, 4100.0)
        @test lohi("EQG_BNDNET(REG1,2030,ELC,ANNUAL)") == (50.0, Inf)
        @test lohi("EQL_BNDNET(REG2,2020,ELC,W)") == (-Inf, 10.0)
        @test lohi("EQE_BNDNET(REG2,2030,ELC,ANNUAL)") == (0.0, 0.0)          # FX EPS: a right-hand side of zero
        # L19: the sum over the commodity's own timeslices at or below the bound's (TS_MAP)
        @test terms("EQG_BNDPRD(REG1,2020,ELC,ANNUAL)") == var("PRD", "REG1", "2020", daynite)
        @test terms("EQL_BNDPRD(REG1,2030,ELC,ANNUAL)") == var("PRD", "REG1", "2030", daynite)
        @test terms("EQE_BNDPRD(REG2,2030,ELC,S)") == var("PRD", "REG2", "2030", ("SD", "SN"))
        @test terms("EQG_BNDNET(REG1,2030,ELC,ANNUAL)") == var("NET", "REG1", "2030", daynite)
        @test terms("EQL_BNDNET(REG2,2020,ELC,W)") == var("NET", "REG2", "2020", ("WD", "WN"))
        @test terms("EQE_BNDNET(REG2,2030,ELC,ANNUAL)") == var("NET", "REG2", "2030", daynite)
        # a bound at the commodity's own level stays a bound of the variable (bndmain.mod L58)
        @test mine.cols["VAR_COMPRD(REG2,2020,ELC,WD)"].ub == 1600.0
        @test mine.cols["VAR_COMPRD(REG2,2020,ELC,WN)"].ub == Inf
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_bndcom!(t0) == 0
    end
end
