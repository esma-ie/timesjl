# Dispatching in the linear formulation (eqactups.vda L9-117 with equ_ext.vda L90; `eqactups_prep!`,
# `eq_actups!`), on the crafted case demo12_disp (reference/dd/demo12_disp; M1.3 change 36, 14 Nov
# 2026): EQ_CAPLOAD, EQ_ACTRAMP, EQE_ACTUPS, EQL_ACTUPS, EQL_ACTUPC, EQ_ACTPL and EQ_ACTRMPC with the
# variables VAR_UPS and VAR_UDP, and their terms in EQ_OBJVAR (eqobjvar.mod L36-39), EQE_ACTEFF
# (pp_actef.vda L78-80) and EQ(l)_CAPACT (eqactups.vda L11). The data as the preparation leaves it,
# the model from GAMS's pre-solve dump against GAMS's matrix (layer 2), then rows of each family.
# REG1 ELCTEGAS00 is not vintaged: its capacity is VAR_CAP (RP_UX). REG2 ELCTNGAS01 is vintaged:
# VAR_NCAP by vintage. Both run at DAYNITE.

using TIMES: TimesModel, generate!, eq_actups!, afs_solve, untranslated_families, gparam, gset, gv
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp, family
import TOML

let vx = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
              if v["prefix"] == "demo12_disp")
    tm = TimesModel(joinpath(FIXTURES, "demo12_disp_presolve"); reduce=vx["reduce"], switches=vx["switches"])
    E, N = ("REG1", "ELCTEGAS00"), ("REG2", "ELCTNGAS01")
    members(name, rp) = sort([k[3:end] for k in gset(tm, name) if k[1:2] == rp])
    val(name, k) = gv(gparam(tm, name), k).v
    fr(s) = val("G_YRFR", ("REG1", s))                      # the same in REG2
    prd(s) = val("RS_STGPRD", ("REG1", s))
    cap = val("PRC_CAPACT", E)                              # 31.536, both processes
    dn = ("SD", "SN", "WD", "WN")
    @testset "the data of the case" begin
        @test Set(k[1:2] for k in gset(tm, "RP_UPL")) == Set([E, N])
        # ppm_ext.vda L13-15: RP_UPL from ACT_UPS, RP_PL from ACT_LOSPL 'FX'; eqactups.vda L25: a
        # start-up cost at ANNUAL (the ACT_CSTPL of REG2, init_ext.vda L68-72) gives RP_PL 'N'
        @test members("RP_UPL", E) == [("FX",), ("LO",), ("UP",)] && members("RP_UPL", N) == [("FX",), ("UP",)]
        @test members("RP_PL", E) == [("FX",), ("N",)] && members("RP_PL", N) == [("N",)]
        @test val("ACT_CSTUP", ("REG2", "2010", "ELCTNGAS01", "ANNUAL", "MEuro05")) == 0.5
        # L33: RP_UPR is the processes with ramping costs. The cycle limit of REG2 (ACT_TIME 'N')
        # needs start-ups at the process's own timeslice level (L31) and gives nothing
        @test members("RP_UPR", E) == [("LO",), ("UP",)] && isempty(members("RP_UPR", N))
        @test members("RP_UPC", E) == [("DAYNITE", "LO"), ("DAYNITE", "UP"), ("SEASON", "N")] && isempty(members("RP_UPC", N))
        # L16-25: the start-up levels; L12, L20-21: the timeslices of the off-line capacity
        @test members("RP_UPS", E) == [("DAYNITE", "UP"), ("SEASON", "FX")]
        @test members("RP_UPS", N) == [("ANNUAL", "UP"), ("SEASON", "UP")]
        @test members("RPS_UPS", E) == [(s,) for s in dn] && members("RPS_UPS", N) == [("S",), ("W",)]
        # L13: a process that is not vintaged gets VAR_CAP
        @test collect(gset(tm, "RP_UX")) == [E]
        @test all(t -> ("REG1", t, "ELCTEGAS00") in gset(tm, "RTP_VARP"), ("2005", "2010", "2015", "2020"))
        # the minimum stable load: ACT_UPS 'FX' 0.25 is raised to ACT_MINLD 0.3 (REG1); ACT_MINLD
        # defaults to ACT_UPS 'FX' (REG2)
        @test val("ACT_UPS", ("REG1", "2020", "ELCTEGAS00", "ANNUAL", "FX")) == 0.3
        @test val("ACT_MINLD", ("REG2", "2020", "ELCTNGAS01")) == 0.35
        # L26: the load range of the partial-load loss, where it is not given: LO max(.1, ACT_MINLD),
        # UP max(.6, ACT_MINLD). REG2 gives UP 0.7
        @test val("ACT_LOSPL", ("REG1", "2020", "ELCTEGAS00", "LO")) == 0.3 && val("ACT_LOSPL", ("REG1", "2020", "ELCTEGAS00", "UP")) == 0.6
        @test val("ACT_LOSPL", ("REG2", "2020", "ELCTNGAS01", "LO")) == 0.35 && val("ACT_LOSPL", ("REG2", "2020", "ELCTNGAS01", "UP")) == 0.7
        # L29: the loss starts at the minimum load, for both
        @test ("REG1", "2020", "ELCTEGAS00") in gset(tm, "RTP_PL") && ("REG2", "2010", "ELCTNGAS01") in gset(tm, "RTP_PL")
        # L18: the costs are in the objective's currency set
        @test ("REG1", "ELCTEGAS00", "ACT", "MEuro05") in gset(tm, "RPC_CUR") && ("REG2", "ELCTNGAS01", "ACT", "MEuro05") in gset(tm, "RPC_CUR")
        # L11: the availability of a dispatched process at its timeslices goes to AFUPS (EQ_CAPLOAD)
        # and leaves AFS (EQ(l)_CAPACT); the annual availability stays
        @test sort([k[4] for k in gset(tm, "AFUPS") if k[1:3] == ("REG1", "2020", "ELCTEGAS00")]) == collect(dn)
        @test sort([k[4] for k in gset(tm, "AFUPS") if k[1:3] == ("REG2", "2020", "ELCTNGAS01")]) == collect(dn)
        let afs = afs_solve(tm)
            @test [k[4:5] for k in afs.keys if k[1:3] == ("REG1", "2020", "ELCTEGAS00")] == [("ANNUAL", "UP")]
            @test [k[4:5] for k in afs.keys if k[1:3] == ("REG2", "2020", "ELCTNGAS01")] == [("ANNUAL", "UP")]
            @test length([k for k in afs.keys if k[1:3] == ("REG1", "2020", "ELCTNGAS01")]) == 5     # not dispatched in REG1
        end
        @test isempty(untranslated_families(tm))
    end
    @testset "the model against GAMS's matrix (layer 2)" begin
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "demo12_disp_matrix", "matrix"),
                                  joinpath(FIXTURES, "demo12_disp_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        @test ispass(cmp)

        nrows(f) = count(r -> family(r) == f, keys(mine.rows))
        @test [nrows(f) for f in ("EQ_CAPLOAD", "EQ_ACTRAMP", "EQE_ACTUPS", "EQL_ACTUPS", "EQL_ACTUPC", "EQ_ACTPL", "EQ_ACTRMPC")] ==
              [144, 88, 66, 8, 40, 72, 16]
        @test count(c -> family(c) == "VAR_UPS", keys(mine.cols)) == 226 && count(c -> family(c) == "VAR_UDP", keys(mine.cols)) == 40
        # neither variable has an upper bound
        @test all(c -> (mine.cols[c].lb, mine.cols[c].ub) == (0.0, Inf), [c for c in keys(mine.cols) if family(c) in ("VAR_UPS", "VAR_UDP")])
        terms(r) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == r && v != 0)
        lohi(r) = (mine.rows[r].lo, mine.rows[r].hi)
        near(a, b) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol=1e-12), keys(a))
        e = "REG1,2020,2020,ELCTEGAS00"                      # not vintaged: v = t
        n = "REG2,2010,2020,ELCTNGAS01"                      # the vintage 2010 in 2020
        ecap, ncap = "VAR_CAP(REG1,2020,ELCTEGAS00)", "VAR_NCAP(REG2,2010,ELCTNGAS01)"
        act(x, s) = "VAR_ACT($x,$s)"
        ups(x, s, l) = "VAR_UPS($x,$s,$l)"
        udp(x, s, l) = "VAR_UDP($x,$s,$l)"
        # the rows of a family in one period, as (region, the indexes after the process)
        shape(f, t="2020") = sort(unique([(m[1], m[2]) for m in (match(Regex("^$f\\((REG\\d),\\d+,$t,[A-Z0-9]+,(.*)\\)\$"), r) for r in keys(mine.rows)) if m !== nothing]))

        # EQ_CAPLOAD (L39-46), both bounds at each timeslice of AFUPS. LO: where the partial-load
        # loss starts at the minimum load (RTP_PL), the activity is at least the loss variable
        @test lohi("EQ_CAPLOAD($e,SD,LO)") == (0.0, Inf)
        @test near(terms("EQ_CAPLOAD($e,SD,LO)"), Dict(act(e, "SD") => 1.0, ups(e, "SD", "FX") => -1.0))
        @test near(terms("EQ_CAPLOAD($n,SD,LO)"), Dict(act(n, "SD") => 1.0, ups(n, "SD", "FX") => -1.0))
        # ... UP: the activity within the on-line capacity: VAR_CAP less the capacity off-line in the
        # timeslice (REG1: start-ups at DAYNITE), or the vintage's VAR_NCAP less the capacity
        # off-line in the season (REG2: start-ups at SEASON)
        @test lohi("EQ_CAPLOAD($e,SD,UP)") == (0.0, Inf)
        @test near(terms("EQ_CAPLOAD($e,SD,UP)"), Dict(act(e, "SD") => -1.0, ecap => cap * fr("SD"), ups(e, "SD", "N") => -cap * fr("SD")))
        @test near(terms("EQ_CAPLOAD($e,WN,UP)"), Dict(act(e, "WN") => -1.0, ecap => cap * fr("WN"), ups(e, "WN", "N") => -cap * fr("WN")))
        @test near(terms("EQ_CAPLOAD($n,SD,UP)"), Dict(act(n, "SD") => -1.0, ncap => cap * fr("SD"), ups(n, "S", "N") => -cap * fr("SD")))

        # EQ_ACTRAMP (L50-61): the change of load from the timeslice before (SN before SD in the
        # cycle of the season S) within the ramp rate times the on-line capacity. REG1 both ways
        # (0.5 of the capacity an hour), with the start-ups and shut-downs at the minimum load 0.3
        @test [x for x in shape("EQ_ACTRAMP") if x[1] == "REG1"] == [("REG1", "$s,$bd") for s in dn for bd in ("LO", "UP")]
        @test [x for x in shape("EQ_ACTRAMP") if x[1] == "REG2"] == [("REG2", "$s,UP") for s in dn]
        let a = cap * 0.5, c = prd("SD") * 2 / (fr("SD") + fr("SN")) / 8760, k = c * cap * 0.3
            @test lohi("EQ_ACTRAMP($e,SD,LO)") == (0.0, Inf)
            @test near(terms("EQ_ACTRAMP($e,SD,LO)"),
                       Dict(act(e, "SD") => c / fr("SD"), act(e, "SN") => -c / fr("SN"), ecap => a,
                            ups(e, "SD", "N") => k, ups(e, "SN", "N") => -a - k))
            @test near(terms("EQ_ACTRAMP($e,SD,UP)"),
                       Dict(act(e, "SD") => -c / fr("SD"), act(e, "SN") => c / fr("SN"), ecap => a,
                            ups(e, "SD", "N") => -a - k, ups(e, "SN", "N") => k))
            # REG2 upwards only (0.4): its off-line capacity is at the season, the same in SD and SN
            @test near(terms("EQ_ACTRAMP($n,SD,UP)"),
                       Dict(act(n, "SD") => -c / fr("SD"), act(n, "SN") => c / fr("SN"), ncap => cap * 0.4, ups(n, "S", "N") => -cap * 0.4))
        end

        # EQE_ACTUPS (L65-72). 'UP' at a level below ANNUAL: the off-line capacity changes from the
        # timeslice before by the shut-downs less the start-ups
        @test shape("EQE_ACTUPS") == [("REG1", "DAYNITE,UP,SD"), ("REG1", "DAYNITE,UP,SN"), ("REG1", "DAYNITE,UP,WD"), ("REG1", "DAYNITE,UP,WN"),
                                      ("REG1", "SEASON,FX,S"), ("REG1", "SEASON,FX,W"),
                                      ("REG2", "ANNUAL,UP,ANNUAL"), ("REG2", "SEASON,UP,S"), ("REG2", "SEASON,UP,W")]
        @test lohi("EQE_ACTUPS($e,DAYNITE,UP,SD)") == (0.0, 0.0)
        @test near(terms("EQE_ACTUPS($e,DAYNITE,UP,SD)"),
                   Dict(ups(e, "SD", "N") => 1.0, ups(e, "SN", "N") => -1.0, ups(e, "SD", "LO") => -1.0, ups(e, "SD", "UP") => 1.0))
        @test near(terms("EQE_ACTUPS($n,SEASON,UP,S)"),
                   Dict(ups(n, "S", "N") => 1.0, ups(n, "W", "N") => -1.0, ups(n, "S", "LO") => -1.0, ups(n, "S", "UP") => 1.0))
        # ... 'UP' at ANNUAL (the partial-load cost of REG2): the sum of the loss variables
        @test near(terms("EQE_ACTUPS($n,ANNUAL,UP,ANNUAL)"),
                   merge(Dict(ups(n, "ANNUAL", "UP") => 1.0), Dict(ups(n, s, "FX") => -1.0 for s in dn)))
        # ... 'FX' at the level above the start-ups: the capacity on-line through the season
        @test near(terms("EQE_ACTUPS($e,SEASON,FX,S)"), Dict(ecap => 1.0, udp(e, "S", "FX") => -1.0, ups(e, "S", "FX") => -1.0))
        # EQL_ACTUPS (L76-82): that capacity is not started up in the season's timeslices
        @test shape("EQL_ACTUPS") == [("REG1", "SEASON,FX,S"), ("REG1", "SEASON,FX,W")]
        @test lohi("EQL_ACTUPS($e,SEASON,FX,S)") == (-Inf, 0.0)
        @test near(terms("EQL_ACTUPS($e,SEASON,FX,S)"), Dict(ups(e, "S", "FX") => 1.0, ups(e, "SD", "UP") => -1.0, ups(e, "SN", "UP") => -1.0))

        # EQL_ACTUPC (L86-95), REG1 only: the minimum on-line (UP) and off-line (LO) hours, 6 each,
        # shorter than a timeslice of the day, and the 200 cycles a year (N)
        @test shape("EQL_ACTUPC") == vcat([("REG1", "DAYNITE,$bd,$s") for bd in ("LO", "UP") for s in dn], [("REG1", "SEASON,N,S"), ("REG1", "SEASON,N,W")])
        @test lohi("EQL_ACTUPC($e,DAYNITE,LO,SD)") == (-Inf, 0.0)
        @test near(terms("EQL_ACTUPC($e,DAYNITE,LO,SD)"), Dict(ups(e, "SD", "N") => -1.0))
        @test near(terms("EQL_ACTUPC($e,DAYNITE,UP,SD)"), Dict(ups(e, "SD", "N") => 1.0, ups(e, "S", "FX") => -1.0))
        @test near(terms("EQL_ACTUPC($e,SEASON,N,S)"), Dict(ups(e, "SD", "UP") => 1.0, ups(e, "SN", "UP") => 1.0, ecap => -200.0))

        # EQ_ACTPL (L99-105): the partial-load loss variable, from the load range LO to UP
        @test length(shape("EQ_ACTPL")) == 8
        for (x, c, s, lo, up) in ((e, ecap, "SD", 0.3, 0.6), (e, ecap, "WN", 0.3, 0.6))
            den = up * (1 / lo - 1)
            k = cap * fr(s) * (up + lo * (1 - up)) / den
            @test lohi("EQ_ACTPL($x,$s)") == (0.0, Inf)
            @test near(terms("EQ_ACTPL($x,$s)"), Dict(ups(x, s, "FX") => 1.0, act(x, s) => 1 / den, c => -k, ups(x, s, "N") => k))
        end
        let den = 0.7 * (1 / 0.35 - 1), k = cap * fr("SD") * (0.7 + 0.35 * (1 - 0.7)) / den
            @test near(terms("EQ_ACTPL($n,SD)"), Dict(ups(n, "SD", "FX") => 1.0, act(n, "SD") => 1 / den, ncap => -k, ups(n, "S", "N") => k))
        end

        # EQ_ACTRMPC (L113-117), REG1 only (ramping costs): the load changes VAR_UDP. The row of SD
        # is the change from SD to the timeslice after it, SN
        @test shape("EQ_ACTRMPC") == [("REG1", s) for s in dn]
        @test lohi("EQ_ACTRMPC($e,SD)") == (0.0, 0.0)
        @test near(terms("EQ_ACTRMPC($e,SD)"),
                   Dict(act(e, "SD") => 1 / fr("SD") / cap, act(e, "SN") => -1 / fr("SN") / cap, udp(e, "SN", "LO") => -1.0, udp(e, "SN", "UP") => 1.0,
                        ups(e, "SD", "N") => 0.3, ups(e, "SN", "N") => -0.3))
        @test near(terms("EQ_ACTRMPC($e,WN)"),
                   Dict(act(e, "WN") => 1 / fr("WN") / cap, act(e, "WD") => -1 / fr("WD") / cap, udp(e, "WD", "LO") => -1.0, udp(e, "WD", "UP") => 1.0,
                        ups(e, "WN", "N") => 0.3, ups(e, "WD", "N") => -0.3))

        # EQ_OBJVAR (eqobjvar.mod L36-39): the start-ups (ACT_CSTUP, a cost per unit of capacity
        # started) and the load changes (ACT_CSTRMP), each times the number of cycles a year
        let obj(x) = Dict(c => v for ((rr, c), v) in mine.coefs if rr == "EQ_OBJVAR($(x[1:4]),MEURO05)" && occursin(x, c) && occursin(r"^VAR_U", c)),
            pvt = val("OBJ_PVT", ("REG1", "2020", "MEuro05"))                # the same in REG2
            @test near(obj(e), merge(Dict(ups(e, s, "UP") => 0.02 * pvt * prd(s) for s in dn),
                                     Dict(udp(e, s, bd) => 0.001 * pvt * prd(s) for s in dn for bd in ("LO", "UP"))))
            @test near(obj(n), Dict(ups(n, "ANNUAL", "UP") => 0.5 * pvt, ups(n, "S", "UP") => 0.03 * pvt, ups(n, "W", "UP") => 0.03 * pvt))
        end
        # EQE_ACTEFF (pp_actef.vda L78-80): the partial-load loss ACT_LOSPL 'FX' 0.1 adds to the
        # input (REG1; REG2 has no 'FX')
        @test isapprox(terms("EQE_ACTEFF($e,NRG,IN,SD)")[ups(e, "SD", "FX")], -0.1; rtol=1e-12)
        @test !any(((r, c),) -> startswith(r, "EQE_ACTEFF(REG2") && startswith(c, "VAR_UPS"), collect(keys(mine.coefs)))
        # EQ(l)_CAPACT: the annual row only for a dispatched process
        @test [r for r in keys(mine.rows) if occursin(Regex("^EQ._CAPACT\\($e,"), r)] == ["EQL_CAPACT($e,ANNUAL)"]
        @test [r for r in keys(mine.rows) if occursin(Regex("^EQ._CAPACT\\($n,"), r)] == ["EQL_CAPACT($n,ANNUAL)"]
        @test length([r for r in keys(mine.rows) if occursin(r"^EQ._CAPACT\(REG1,2010,2020,ELCTNGAS01,", r)]) == 5
    end
    @testset "no data, no rows; the discrete unit commitment is refused" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=vx["reduce"], switches=vx["switches"])
        @test eq_actups!(t0) == 0
        # eqlducs.vda L128-175 and the DP_UNS term of EQ_ACTPL (eqactups.vda L106-109), a MIP
        t1 = TimesModel(joinpath(FIXTURES, "demo12_disp_presolve"); reduce=vx["reduce"], switches=merge(vx["switches"], Dict("DUC" => "YES")))
        @test [x.family for x in untranslated_families(t1)] == ["(discrete unit commitment)"]
    end
end
