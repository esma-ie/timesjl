# EQ(l)_CAPVAC (coef_csv.mod L11-77 with eqcapvac.mod L14-28; `coef_csv!`, `eq_capvac!`), on the
# crafted case demo12_capvac (reference/dd/demo12_capvac; M1.3 change 38, 14 Nov 2026): eight processes
# with simulated vintages (PRC_SIMV). The data as coef_csv.mod leaves it, the model from GAMS's
# pre-solve dump against GAMS's matrix (layer 2), then the 263 rows of the REDUCE variant: the
# past capacity of a simulated vintage, a new vintage carried into a later period, the E and G
# rows, and the flow form of a trade process with a commodity availability.

using OpenTIMES: TimesModel, generate!, eq_capvac!, simv_defined, untranslated_families, gparam, gparam_opt, gset,
             gset_opt, gv
using OpenTIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_capvac")
    tm = TimesModel(joinpath(FIXTURES, "demo12_capvac_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    d = tm.data
    csv = gparam(tm, "COEF_CSV")
    yrfr(s, r="REG1") = gv(gparam(tm, "G_YRFR"), (r, s)).v
    capact(r, p) = gv(gparam(tm, "PRC_CAPACT"), (r, p)).v
    pasti(r, k, p) = gv(gparam(tm, "NCAP_PASTI"), (r, k, p)).v
    # (true vintage, period, simulated vintage) of a process, and its (simulated vintage, period)
    kts(r, p) = sort([(k[2], k[3], k[5]) for k in csv.keys if k[1] == r && k[4] == p])
    vt(r, p) = sort([(k[2], k[3]) for k in gset(tm, "RTP_VINTYR").keys if k[1] == r && k[4] == p])
    new_vt = [("2010", "2010"), ("2010", "2020"), ("2015", "2015"), ("2015", "2030"), ("2020", "2020"),
              ("2030", "2030"), ("2030", "2050"), ("2050", "2050")]
    @testset "the data of the case" begin
        @test simv_defined(tm)
        @test sort(collect(gset(tm, "PRC_SIMV").keys)) ==
              [("REG1", "ELCREHYD00"), ("REG1", "ELCRNWIN01"), ("REG1", "ELCTNCOA01"), ("REG1", "ELCTNGAS01"),
               ("REG1", "TB_ELC_REG1_REG2_01"), ("REG1", "TU_GAS_REG2_REG1_01"), ("REG2", "ELCTNCOA01"),
               ("REG2", "ELCTNGAS01")]
        # coef_csv.mod L48 as GAMS 54.6.1 runs it: `OPTION FIL < T` leaves FIL empty, so FIL is the
        # one year MIYR_1-LEAD, VTV and PASTSUM stay empty and L60-63 share nothing
        @test collect(gset_opt(d, "FIL", 1).keys) == [("2004",)]
        @test isempty(gset_opt(d, "VTV", 2))
        @test isempty(gparam_opt(d, "PASTSUM", 3))
        @test isempty(gparam_opt(d, "COEF_CAP", 4))                    # cleared at L73
        @test length(csv) == 77

        # L50: the past investments go to the simulated vintage 2004. L65 multiplies COEF_CPT into
        # that vintage: the 1960 plant ends within 2010, the 1980 plant within 2030
        @test kts("REG1", "ELCREHYD00") == [("1960", "2005", "2004"), ("1960", "2010", "2004"), ("1980", "2005", "2004"),
                                           ("1980", "2010", "2004"), ("1980", "2015", "2004"), ("1980", "2020", "2004"),
                                           ("1980", "2030", "2004")]
        @test gv(csv, ("REG1", "1960", "2005", "ELCREHYD00", "2004")).v == 1.0
        @test gv(csv, ("REG1", "1960", "2010", "ELCREHYD00", "2004")).v ==
              gv(gparam(tm, "COEF_CPT"), ("REG1", "1960", "2010", "ELCREHYD00")).v
        @test 0 < gv(csv, ("REG1", "1960", "2010", "ELCREHYD00", "2004")).v < 1
        @test 0 < gv(csv, ("REG1", "1980", "2030", "ELCREHYD00", "2004")).v < 1
        # L68-72: RTP_VINTYR of a simulated process is its simulated vintages
        @test vt("REG1", "ELCREHYD00") == [("2004", t) for t in ("2005", "2010", "2015", "2020", "2030")]
        # L44: a new vintage that is a marked year is its own simulated vintage, with the value 1
        # (no COEF_CPT: L65 reaches the vintage 2004 only). A past investment in the year 2004
        # itself (NCAP_PASTI) is the simulated vintage 2004
        @test kts("REG1", "ELCTNCOA01") == vcat([("2004", t, "2004") for t in ("2005", "2010", "2015", "2020", "2030", "2050")],
                                               [(v, t, v) for (v, t) in new_vt])
        @test all(k -> gv(csv, ("REG1", k[1], k[2], "ELCTNCOA01", k[3])).v == 1.0, kts("REG1", "ELCTNCOA01")[1:end .!= 6])
        @test 0 < gv(csv, ("REG1", "2004", "2050", "ELCTNCOA01", "2004")).v < 1
        @test vt("REG1", "ELCTNCOA01") == vcat([("2004", t) for t in ("2005", "2010", "2015", "2020", "2030", "2050")], new_vt)
        # ... with NCAP_START 2005 in REG2, the vintage 2005 exists there
        @test ("2005", "2005") in vt("REG2", "ELCTNCOA01") && !(("2005", "2005") in vt("REG1", "ELCTNCOA01"))
        # ... a process without past capacity. A true vintage that is not a simulated vintage of
        # the period gives nothing: the gas plant's vintage 2010 has no entry in 2015
        @test vt("REG1", "ELCTNGAS01") == sort(vcat(new_vt, [("2015", "2050")]))
        @test !any(k -> k[1] == "REG1" && k[4] == "ELCTNGAS01" && k[2] != k[5], csv.keys)
        @test vt("REG1", "TU_GAS_REG2_REG1_01") == [("2005", "2005"), ("2010", "2010"), ("2015", "2015"), ("2020", "2020"),
                                                    ("2020", "2030"), ("2030", "2030"), ("2050", "2050")]
        # ppmain.mod L590, pp_qack.mod L54: the first period of a process that cannot be built
        # in it is in NO_RVP
        @test sort(collect(gset_opt(d, "NO_RVP", 3).keys)) ==
              [("REG1", "2005", "ELCRNWIN01"), ("REG1", "2005", "ELCTNGAS01"), ("REG2", "2005", "ELCTNGAS01")]

        # L74: the AFS entries of the simulated processes are in AFSV, and none is left in AFS
        afsv, simv = gset(tm, "AFSV"), gset(tm, "PRC_SIMV")
        @test length(afsv) == 147
        @test !any(k -> (k[1], k[3]) in simv, gset(tm, "AFS").keys)
        @test sort(unique([(k[1], k[3], k[5]) for k in afsv.keys])) ==
              [("REG1", "ELCREHYD00", "UP"), ("REG1", "ELCRNWIN01", "FX"), ("REG1", "ELCRNWIN01", "UP"),
               ("REG1", "ELCTNCOA01", "UP"), ("REG1", "ELCTNGAS01", "UP"), ("REG1", "TU_GAS_REG2_REG1_01", "UP"),
               ("REG2", "ELCTNCOA01", "UP"), ("REG2", "ELCTNGAS01", "LO"), ("REG2", "ELCTNGAS01", "UP")]
        # NCAP_AFC on the gas plant's one output gives no RPS_CAFLAC (ppm_ext.vda L123: a standard
        # process whose group is its activity); on the trade process it does
        @test gv(gparam(tm, "NCAP_AFCS"), ("REG1", "2020", "ELCTNGAS01", "ELC", "ANNUAL")).v == 0.8
        @test gv(gparam(tm, "NCAP_AFCS"), ("REG1", "2020", "TU_GAS_REG2_REG1_01", "GAS", "ANNUAL")).v == 0.9
        @test collect(gset_opt(d, "RPS_CAFLAC", 4).keys) == [("REG1", "TU_GAS_REG2_REG1_01", "ANNUAL", "UP")]
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_capvac_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_capvac_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        rows = sort([r for r in keys(mine.rows) if occursin(r"^EQ[EGL]_CAPVAC\(", r)])
        @test length(rows) == 263
        @test all(endswith(",1)"), rows)                               # %SWX%: the ALLSOW element '1'
        nrows(eq, r, p) = count(x -> startswith(x, "$(eq)_CAPVAC($r,") && occursin(",$p,", x), rows)
        @test nrows("EQE", "REG1", "ELCRNWIN01") == 9 && nrows("EQG", "REG2", "ELCTNGAS01") == 9
        @test count(startswith("EQE"), rows) == 9 && count(startswith("EQG"), rows) == 9
        @test [nrows("EQL", r, p) for (r, p) in (("REG1", "ELCREHYD00"), ("REG1", "ELCRNWIN01"), ("REG1", "ELCTNCOA01"),
                                                 ("REG1", "ELCTNGAS01"), ("REG1", "TU_GAS_REG2_REG1_01"),
                                                 ("REG2", "ELCTNCOA01"), ("REG2", "ELCTNGAS01"))] == [25, 36, 42, 45, 7, 45, 45]
        # the simulated processes have no EQ(l)_CAPACT row; the electricity link has no capacity
        # row under REDUCE, here as in GAMS
        @test !any(r -> occursin(r"^EQ[EGL]_CAPACT\(", r) && any(k -> occursin("($(k[1]),", r) && occursin(",$(k[2]),", r),
                                                                gset(tm, "PRC_SIMV").keys), keys(mine.rows))
        @test !any(occursin("TB_ELC_REG1_REG2_01"), rows)

        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        act(r, v, t, p, s) = "VAR_ACT($r,$v,$t,$p,$s)"
        ncap(r, k, p) = "VAR_NCAP($r,$k,$p)"
        row(eq, r, v, t, p, s) = "$(eq)_CAPVAC($r,$v,$t,$p,$s,1)"
        dn = ("SD", "SN", "WD", "WN")
        hyd(k) = pasti("REG1", k, "ELCREHYD00")

        # L27, past capacity: NCAP_PASTI of each true vintage with a COEF_CSV entry, as it is
        # (no COEF_CSV, no COEF_AF), times PRC_CAPACT and G_YRFR. No VAR_NCAP: 1960, 1980 are not T
        let r = row("EQL", "REG1", "2004", "2005", "ELCREHYD00", "ANNUAL")
            @test lohi(r)[1] == -Inf
            @test lohi(r)[2] ≈ 977.616 rtol = 1e-12
            @test lohi(r)[2] ≈ (hyd("1960") + hyd("1980")) * capact("REG1", "ELCREHYD00") rtol = 1e-12
            @test near(terms(r), Dict(act("REG1", "2004", "2005", "ELCREHYD00", s) => 1.0 for s in dn))
        end
        # ... in 2010 the 1960 plant has a COEF_CSV below 1 and still counts in full; in 2030 only
        # the 1980 plant has an entry
        let r10 = row("EQL", "REG1", "2004", "2010", "ELCREHYD00", "SD"), r30 = row("EQL", "REG1", "2004", "2030", "ELCREHYD00", "SD")
            @test lohi(r10)[2] ≈ (hyd("1960") + hyd("1980")) * capact("REG1", "ELCREHYD00") * yrfr("SD") rtol = 1e-12
            @test lohi(r30)[2] ≈ hyd("1980") * capact("REG1", "ELCREHYD00") * yrfr("SD") rtol = 1e-12
            @test lohi(r30)[2] ≈ 126.0 rtol = 1e-12
            @test near(terms(r30), Dict(act("REG1", "2004", "2030", "ELCREHYD00", "SD") => 1.0))
        end
        # ... a past investment in the year of the simulated vintage itself (2004 is not a period)
        let r = row("EQL", "REG1", "2004", "2050", "ELCTNCOA01", "S")
            @test lohi(r)[1] == -Inf
            @test lohi(r)[2] ≈ 0.5 * capact("REG1", "ELCTNCOA01") * yrfr("S") rtol = 1e-12
            @test near(terms(r), Dict(act("REG1", "2004", "2050", "ELCTNCOA01", "S") => 1.0))
        end
        @test lohi(row("EQL", "REG2", "2004", "2005", "ELCTNCOA01", "ANNUAL"))[2] ≈ 0.4 * capact("REG2", "ELCTNCOA01") rtol = 1e-12
        @test near(terms(row("EQL", "REG2", "2004", "2005", "ELCTNCOA01", "ANNUAL")),
                   Dict(act("REG2", "2004", "2005", "ELCTNCOA01", s) => 1.0 for s in ("S", "W")))

        # L27, a new vintage: COEF_CSV*COEF_AF*PRC_CAPACT*G_YRFR on VAR_NCAP of the true vintage,
        # in its own period and in the later period that keeps it as a simulated vintage
        @test lohi(row("EQL", "REG1", "2010", "2020", "ELCTNCOA01", "S")) == (-Inf, 0.0)
        @test near(terms(row("EQL", "REG1", "2010", "2020", "ELCTNCOA01", "S")),
                   Dict(act("REG1", "2010", "2020", "ELCTNCOA01", "S") => 1.0, ncap("REG1", "2010", "ELCTNCOA01") => -15.12))
        @test terms(row("EQL", "REG1", "2010", "2020", "ELCTNCOA01", "S"))[ncap("REG1", "2010", "ELCTNCOA01")] ≈
              -gv(gparam(tm, "COEF_AF"), ("REG1", "2010", "2020", "ELCTNCOA01", "S", "UP")).v * capact("REG1", "ELCTNCOA01") * yrfr("S") rtol = 1e-12
        # ... the vintage 2005 of REG2 (NCAP_START), at the ANNUAL level over the process's seasons
        @test near(terms(row("EQL", "REG2", "2005", "2005", "ELCTNCOA01", "ANNUAL")),
                   Dict(act("REG2", "2005", "2005", "ELCTNCOA01", "S") => 1.0, act("REG2", "2005", "2005", "ELCTNCOA01", "W") => 1.0,
                        ncap("REG2", "2005", "ELCTNCOA01") => -26.8056))
        # ... NCAP_AF FX: an equality (the E include), beside the UP rows of the same process
        @test sort([(split(r, ",")[2], split(r, ",")[3]) for r in rows if startswith(r, "EQE")]) ==
              sort(vcat(new_vt[1:2], [("2010", "2030"), ("2015", "2015"), ("2020", "2020"), ("2020", "2030")], new_vt[6:8]))
        @test lohi(row("EQE", "REG1", "2010", "2030", "ELCRNWIN01", "SD")) == (0.0, 0.0)
        @test near(terms(row("EQE", "REG1", "2010", "2030", "ELCRNWIN01", "SD")),
                   Dict(act("REG1", "2010", "2030", "ELCRNWIN01", "SD") => 1.0, ncap("REG1", "2010", "ELCRNWIN01") => -2.3625))
        @test near(terms(row("EQL", "REG1", "2010", "2030", "ELCRNWIN01", "ANNUAL")),
                   merge(Dict(act("REG1", "2010", "2030", "ELCRNWIN01", s) => 1.0 for s in dn), Dict(ncap("REG1", "2010", "ELCRNWIN01") => -11.0376)))
        # ... NCAP_AFA LO: a lower limit (the G include)
        @test lohi(row("EQG", "REG2", "2015", "2050", "ELCTNGAS01", "ANNUAL")) == (0.0, Inf)
        @test near(terms(row("EQG", "REG2", "2015", "2050", "ELCTNGAS01", "ANNUAL")),
                   merge(Dict(act("REG2", "2015", "2050", "ELCTNGAS01", s) => 1.0 for s in dn), Dict(ncap("REG2", "2015", "ELCTNGAS01") => -3.1536)))

        # L19-22, a process with a commodity availability (RPS_CAFLAC): the flows of the primary
        # group, each divided by PRC_ACTFLO and by its NCAP_AFCS (0.9). A trade process: VAR_IRE
        let r = row("EQL", "REG1", "2020", "2030", "TU_GAS_REG2_REG1_01", "ANNUAL")
            @test lohi(r) == (-Inf, 0.0)
            @test near(terms(r), Dict("VAR_IRE(REG1,2020,2030,TU_GAS_REG2_REG1_01,GAS,ANNUAL,IMP)" => 1 / 0.9,
                                      ncap("REG1", "2020", "TU_GAS_REG2_REG1_01") => -1.0))
        end
        @test near(terms(row("EQL", "REG1", "2030", "2030", "TU_GAS_REG2_REG1_01", "ANNUAL")),
                   Dict("VAR_IRE(REG1,2030,2030,TU_GAS_REG2_REG1_01,GAS,ANNUAL,IMP)" => 1 / 0.9,
                        ncap("REG1", "2030", "TU_GAS_REG2_REG1_01") => -1.0))
    end
    @testset "no PRC_SIMV, no rows" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test !simv_defined(t0)
        @test eq_capvac!(t0) == 0
    end
end
