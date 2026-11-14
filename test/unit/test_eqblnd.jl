# EQ(l)_BLND (eqblnd.mod L67-71 with eqmain.mod L249-252; `eq_blnd!`), on the crafted case
# demo12_blnd (reference/dd/demo12_blnd; M1.3 change 37, 14 Nov 2026): refinery blending. The data
# as ppmain.mod L1228-1333 leaves it, the model from GAMS's pre-solve dump against GAMS's matrix
# (layer 2), then the 35 rows of the REDUCE variant, the blending variable's terms in the commodity
# balance (eqcombal.mod L30-35, L75-80), the peak equation (eqpeak.mod L78) and the objective
# (coef_obj.mod L93-94, eqobjvar.mod L105-107), and the blending costs in curex.gms (L59-60).

using TIMES: TimesModel, generate!, eq_blnd!, untranslated_families, curex_subr!, gparam, gset, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_blnd")
    tm = TimesModel(joinpath(FIXTURES, "demo12_blnd_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    T6 = ("2005", "2010", "2015", "2020", "2030", "2050")
    yrfr(s, r="REG1") = gv(gparam(tm, "G_YRFR"), (r, s)).v
    @testset "the data of the case" begin
        # ppmain.mod L1246: BLE_SPE from BL_TYPE, also of a commodity that is not a blend (KER)
        @test length(gset(tm, "BLE_SPE")) == 9 && ("REG1", "KER", "OCT") in gset(tm, "BLE_SPE")
        # L1254-1256: BLE_TP, the periods of a blend from its earliest BL_START on (REG1: OCT in
        # 2010, the others later), every period without one (TRAGSL in REG2); nothing for KER
        tp = gset(tm, "BLE_TP")
        @test sort([k[2] for k in tp if k[1] == "REG1"]) == collect(T6[2:end])
        @test sort([k[2] for k in tp if k[1] == "REG2" && k[3] == "TRAGSL"]) == collect(T6)
        @test sort([k[2] for k in tp if k[1] == "REG2" && k[3] == "GSL"]) == ["2020", "2030", "2050"]
        @test length(tp) == 14 && !any(k -> k[3] == "KER", tp)
        # L1257: BL_UNIT defaults to 1 (energy) for the specifications of a blend
        unit = gparam(tm, "BL_UNIT")
        @test length(unit.values) == 8 && gv(unit, ("REG1", "TRAGSL", "OCT")).v == 1 && gv(unit, ("REG2", "TRAGSL", "DEN")).v == 1
        @test !haskey(unit, ("REG1", "KER", "OCT"))
        # L1264, L1288-1290: the streams of a blend from BL_COM; GSL is a blend in REG2 and a stream of TRAGSL
        @test sort([k[3] for k in gset(tm, "BLE_OPR") if k[1:2] == ("REG1", "TRAGSL")]) == ["BIO", "GSL", "LPG", "NAP"]
        @test sort([k[3] for k in gset(tm, "BLE_OPR") if k[1:2] == ("REG2", "GSL")]) == ["LPG", "NAP"]
        @test ("REG2", "TRAGSL", "GSL") in gset(tm, "BLE_OPR")
        @test length(gset(tm, "BLE_OPR")) == 9 && length(gset(tm, "BLE_SPEOPR")) == 20
        # BLE_INP is given by the case (TIMES only declares it); BLE_SPEINP and RU_FEQ are in no equation
        @test gset(tm, "BLE_INP").members == Set([("REG1", "TRAGSL", "ELC")]) && length(gset(tm, "BLE_SPEINP")) == 4
        @test length(gparam(tm, "RU_FEQ").values) == 48
        # L1251: REFUNIT defaults to 1; L1296: PEAKDA_BL to 1 for a blend with an input that is a peak commodity
        @test gparam(tm, "REFUNIT").values == Dict(("REG1",) => 1.0, ("REG2",) => 2.0)
        @test gv(gparam(tm, "PEAKDA_BL"), ("REG1", "TRAGSL", "2020")).v == 0.8
        @test gv(gparam(tm, "PEAKDA_BL"), ("REG1", "TRAGSL", "2005")).v == 1.0
        # L1310-1332: RU_CVT by REFUNIT and BL_UNIT. REFUNIT 1 (energy): unit 1 gives 1, unit 2 1/WCV,
        # unit 3 1/VCV; REFUNIT 2 (weight): unit 1 gives WCV, unit 2 1, unit 3 1/DENS
        cvt = gparam(tm, "RU_CVT")
        @test length(cvt.values) == 20
        @test gv(cvt, ("REG1", "TRAGSL", "OCT", "NAP")).v == 1.0
        @test gv(cvt, ("REG1", "TRAGSL", "SUL", "GSL")).v ≈ 1 / 1.02
        @test gv(cvt, ("REG1", "TRAGSL", "RVP", "LPG")).v ≈ 1 / 0.57
        @test gv(cvt, ("REG2", "TRAGSL", "OCT", "GSL")).v == 1.02
        @test gv(cvt, ("REG2", "GSL", "OCT", "LPG")).v == 1.0
        @test gv(cvt, ("REG2", "TRAGSL", "SUL", "NAP")).v ≈ 1 / 0.70
        # L1301-1306: BLE_BAL, the blend made by a unit of the stream: 1 under REFUNIT 1, WCV under 2,
        # and 1 for a blend that is itself a stream (GSL)
        bal = gparam(tm, "BLE_BAL")
        @test gv(bal, ("REG1", "2020", "TRAGSL", "BIO")).v == 1.0 && gv(bal, ("REG2", "2020", "TRAGSL", "BIO")).v == 0.62
        @test gv(bal, ("REG2", "2020", "GSL", "LPG")).v == 1.0
        @test !haskey(bal, ("REG1", "2005", "TRAGSL", "GSL"))              # before the blend starts
        # coef_obj.mod L93-94: BL_VAROMC + BL_INP * BL_DELIVC, in every year
        obj = gparam(tm, "OBJ_BLNDV")
        @test all(((k, v),) -> v ≈ (k[1] == "REG1" ? 0.05 + 0.02 * 1.5 : 0.02), obj.values)
        @test Set(k[1:4] for k in keys(obj.values) if k[2] == "2005") ==
              Set([("REG1", "2005", "TRAGSL", o) for o in ("BIO", "GSL", "LPG", "NAP")]) ∪ Set([("REG2", "2005", "GSL", o) for o in ("LPG", "NAP")])
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_blnd_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_blnd_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        colterms(c) = Dict(r => v for ((r, cc), v) in mine.coefs if cc == c && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        bl(r, t, b, o) = "VAR_BLND($r,$t,$b,$o)"
        row(l, r, t, b, s) = "EQ$(l)_BLND($r,$t,$b,$s,1)"
        objvar(r) = only(k for k in keys(mine.rows) if uppercase(k) == "EQ_OBJVAR($r,MEURO05)")
        dn = ("SD", "SN", "WD", "WN")

        # the rows: BLE_TP by the type of the specification; the last index is the label 1 (%SWX%)
        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGLN]_BLND\(", r)])
        @test rows == sort(vcat([row("E", "REG1", t, "TRAGSL", "RVP") for t in T6[2:end]],
                                [row("G", "REG1", t, "TRAGSL", "OCT") for t in T6[2:end]],
                                [row("G", "REG2", t, "TRAGSL", "OCT") for t in T6],
                                [row("G", "REG2", t, "GSL", "OCT") for t in T6[4:end]],
                                [row("L", "REG1", t, "TRAGSL", "SUL") for t in T6[2:end]],
                                [row("L", "REG2", t, "TRAGSL", "SUL") for t in T6],
                                [row("N", "REG1", t, "TRAGSL", "DEN") for t in T6[2:end]]))
        @test length(rows) == 35
        # the blending variable: every stream of a blend in every period (OBJ_BLNDV has no BLE_TP),
        # positive
        cols = [c for c in keys(mine.cols) if startswith(c, "VAR_BLND(")]
        @test length(cols) == 54 && all(c -> (mine.cols[c].lb, mine.cols[c].ub) == (0.0, Inf), cols)

        # L67-71: (BL_COM - BL_SPEC) * RU_CVT. Type 2 (=G=), a specification by energy under REFUNIT 1
        for t in T6[2:end]
            @test lohi(row("G", "REG1", t, "TRAGSL", "OCT")) == (0.0, Inf)
            @test near(terms(row("G", "REG1", t, "TRAGSL", "OCT")),
                       Dict(bl("REG1", t, "TRAGSL", "BIO") => 19.0, bl("REG1", t, "TRAGSL", "GSL") => 4.0,
                            bl("REG1", t, "TRAGSL", "LPG") => 9.0, bl("REG1", t, "TRAGSL", "NAP") => -21.0))
        end
        # ... type 1 (=L=), by weight (unit 2) under REFUNIT 1: 1/WCV. LPG has no BL_COM for SUL
        @test lohi(row("L", "REG1", "2020", "TRAGSL", "SUL")) == (-Inf, 0.0)
        @test near(terms(row("L", "REG1", "2020", "TRAGSL", "SUL")),
                   Dict(bl("REG1", "2020", "TRAGSL", "BIO") => (1 - 40) / 0.62, bl("REG1", "2020", "TRAGSL", "GSL") => (30 - 40) / 1.02,
                        bl("REG1", "2020", "TRAGSL", "NAP") => (80 - 40) / 0.98))
        # ... type 3 (=E=), by volume (unit 3): 1/VCV. GSL meets the specification exactly:
        # no term. The row starts with the blend (2010), not at the specification's BL_START (2015)
        @test lohi(row("E", "REG1", "2010", "TRAGSL", "RVP")) == (0.0, 0.0)
        @test near(terms(row("E", "REG1", "2010", "TRAGSL", "RVP")),
                   Dict(bl("REG1", "2010", "TRAGSL", "LPG") => (20 - 60) / 0.57, bl("REG1", "2010", "TRAGSL", "NAP") => (80 - 60) / 0.72))
        # ... type 4 (=N=): a free row
        @test lohi(row("N", "REG1", "2030", "TRAGSL", "DEN")) == (-Inf, Inf)
        @test near(terms(row("N", "REG1", "2030", "TRAGSL", "DEN")),
                   Dict(bl("REG1", "2030", "TRAGSL", "BIO") => 0.79 - 0.76, bl("REG1", "2030", "TRAGSL", "GSL") => 0.75 - 0.76,
                        bl("REG1", "2030", "TRAGSL", "NAP") => 0.70 - 0.76))
        # ... REFUNIT 2 (weight): unit 1 gives WCV, unit 3 1/DENS, unit 2 gives 1
        @test near(terms(row("G", "REG2", "2005", "TRAGSL", "OCT")),
                   Dict(bl("REG2", "2005", "TRAGSL", "GSL") => (95 - 93) * 1.02, bl("REG2", "2005", "TRAGSL", "NAP") => (70 - 93) * 0.98))
        @test near(terms(row("L", "REG2", "2050", "TRAGSL", "SUL")),
                   Dict(bl("REG2", "2050", "TRAGSL", "GSL") => (30 - 50) / 0.75, bl("REG2", "2050", "TRAGSL", "NAP") => (80 - 50) / 0.70))
        @test near(terms(row("G", "REG2", "2020", "GSL", "OCT")),
                   Dict(bl("REG2", "2020", "GSL", "LPG") => 12.0, bl("REG2", "2020", "GSL", "NAP") => -18.0))
        # nothing: a type 5, a commodity that is not a blend
        @test !any(r -> occursin("REG2,2020,TRAGSL,DEN", r) || occursin("KER", r), rows)

        # the blending variable in the other equations. Before the blend starts: the emission
        # (eqcombal.mod L30-35 has no BLE_TP) and the cost only
        @test near(colterms(bl("REG1", "2005", "TRAGSL", "GSL")),
                   Dict("EQE_COMBAL(REG1,2005,TRACO2,ANNUAL)" => 0.5, objvar("REG1") => colterms(bl("REG1", "2005", "TRAGSL", "BIO"))[objvar("REG1")]))
        @test collect(keys(colterms(bl("REG2", "2005", "GSL", "LPG")))) == [objvar("REG2")]
        # ... the cost: OBJ_BLNDV 0.08 in REG1 and 0.02 in REG2, the same discounting in both
        @test colterms(bl("REG1", "2020", "TRAGSL", "GSL"))[objvar("REG1")] ≈ 4 * colterms(bl("REG2", "2020", "GSL", "LPG"))[objvar("REG2")]
        # ... eqcombal.mod L75-80: the stream is consumed (-1), the blend is made (BLE_BAL), the
        # input of the blend is consumed (BL_INP) in each timeslice of its balance (G_YRFR);
        # eqpeak.mod L78: the input in the peak equation, by PEAKDA_BL
        let c = colterms(bl("REG1", "2020", "TRAGSL", "GSL"))
            @test length(c) == 15
            @test c["EQG_COMBAL(REG1,2020,GSL,ANNUAL)"] == -1.0 && c["EQG_COMBAL(REG1,2020,TRAGSL,ANNUAL)"] == 1.0
            @test c["EQE_COMBAL(REG1,2020,TRACO2,ANNUAL)"] == 0.5
            @test all(s -> c["EQE_COMBAL(REG1,2020,ELC,$s)"] ≈ -0.02 * yrfr(s), dn)
            @test all(s -> c["EQ_PEAK(REG1,2020,ELC,$s)"] ≈ 0.8 * c["EQE_COMBAL(REG1,2020,ELC,$s)"], dn)
            @test c[row("G", "REG1", "2020", "TRAGSL", "OCT")] == 4.0 && c[row("N", "REG1", "2020", "TRAGSL", "DEN")] ≈ -0.01
        end
        @test colterms(bl("REG1", "2020", "TRAGSL", "NAP"))["EQE_COMBAL(REG1,2020,TRACO2,ANNUAL)"] == 0.4
        @test !haskey(colterms(bl("REG1", "2020", "TRAGSL", "BIO")), "EQE_COMBAL(REG1,2020,TRACO2,ANNUAL)")
        # ... REFUNIT 2: the blend made by a unit of the stream is its WCV
        @test near(colterms(bl("REG2", "2020", "TRAGSL", "BIO")),
                   Dict("EQG_COMBAL(REG2,2020,BIO,ANNUAL)" => -1.0, "EQG_COMBAL(REG2,2020,TRAGSL,ANNUAL)" => 0.62))
        # ... GSL in REG2: made as a blend (it is itself a stream: BLE_BAL 1, whatever the REFUNIT)
        # and consumed as a stream of TRAGSL
        let c = colterms(bl("REG2", "2030", "GSL", "LPG"))
            @test c["EQG_COMBAL(REG2,2030,LPG,ANNUAL)"] == -1.0 && c["EQG_COMBAL(REG2,2030,GSL,ANNUAL)"] == 1.0
            @test c["EQE_COMBAL(REG2,2030,TRACO2,ANNUAL)"] == 0.2 && c[row("G", "REG2", "2030", "GSL", "OCT")] == 12.0
            @test length(c) == 5
        end
        @test colterms(bl("REG2", "2020", "TRAGSL", "GSL"))["EQG_COMBAL(REG2,2020,GSL,ANNUAL)"] == -1.0
    end
    @testset "no data, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_blnd!(t0) == 0
    end
    @testset "curex.gms L59-60: the blending costs, without a year index" begin
        # $BATINCLUDE curex BL_VAROMC BL_VAROMC R '' 'COM': no L77 filter, the full rate on every
        # record (L81), the records outside RDCUR removed (L82). MUSD is mapped to MEuro05 at 0.9,
        # MGBP nowhere; a region outside the call's regions is left as it is
        vals = Dict(("REG1", "TRAGSL", "MEuro05") => 0.05, ("REG1", "TRAGSL", "MUSD") => 0.1, ("REG1", "TRAGSL", "MGBP") => 0.07,
                    ("REG1", "0", "MUSD") => -13.0, ("XREG", "TRAGSL", "MUSD") => 2.0)
        targets = Dict(("REG1", "MUSD") => ["MEuro05"], ("REG1", "MEuro05") => ["MEuro05"])
        rcx = Dict(("REG1", "MUSD", "MEuro05") => 0.9, ("REG1", "MEuro05", "MEuro05") => 1.0)
        curex_subr!(vals, Val(3), 3, false, Set(["REG1"]), targets, rcx, Set([("REG1", "MEuro05")]), Dict{String,Int}(); year=false)
        @test keys(vals) == Set([("REG1", "TRAGSL", "MEuro05"), ("REG1", "0", "MEuro05"), ("XREG", "TRAGSL", "MUSD")])
        @test vals[("REG1", "TRAGSL", "MEuro05")] ≈ 0.05 + 0.1 * 0.9 && vals[("REG1", "0", "MEuro05")] ≈ -13.0 * 0.9
        @test vals[("XREG", "TRAGSL", "MUSD")] == 2.0
    end
end
