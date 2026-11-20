# Unit commitment by start-up type in the linear formulation (eqlducs.vda L12-124 with coef_ext.vda
# L78 and equ_ext.vda L91; `eqlducs_prep!`, `eqlducs_equ!`, `eq_lducs!`; M1.3 change 40, 14 Nov
# 2026): EQ_SDLOGIC, EQ_SUDUPT, EQ_SDSLANT, EQ_SDMINON, EQ_SUDLOAD, EQ_SUDTIME and EQ_SUDPLL with
# the variable VAR_UPT, and the cost of the start-ups by type in EQ_OBJVAR (eqobjvar.mod L38).
# Two crafted cases, each from GAMS's pre-solve dump: the data as the preparation leaves it, the
# model against GAMS's matrix (layer 2), then rows of each family.
#   demo12_uc  (reference/dd/demo12_uc):  REG2 ELCTEGAS00, not vintaged, DAYNITE; every start-up
#              and shut-down time is shorter than a timeslice of the day.
#   demo12_ucv (reference/dd/demo12_ucv): REG2 ELCTNGAS01, vintaged, DAYNITE, with phases that
#              reach the neighbouring timeslice; REG1 ELCTECOA00, not vintaged, SEASON.
# In demo12 the cycle of a DAYNITE timeslice is the day of its season (SD and SN, WD and WN; a
# timeslice is 11.5 or 12.5 hours); each season is its own cycle of the year (RS_UP), so a SEASON
# process has no neighbouring timeslice in the terms that look across a cycle.

using OpenTIMES: TimesModel, generate!, eq_lducs!, untranslated_families, gparam, gset, gv
using OpenTIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp, family
import TOML

let
    variant(prefix) = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"] if v["prefix"] == prefix)
    load(prefix; more=Dict{String,String}()) = (vx = variant(prefix);
        TimesModel(joinpath(FIXTURES, "$(prefix)_presolve"); reduce=vx["reduce"], switches=merge(vx["switches"], more)))
    function against_gams(tm, prefix)                       # layer 2: (my LP, the comparison with GAMS's)
        generate!(tm)
        mine = canonical_from_jump(tm.model)
        ref = canonical_from_dump(joinpath(FIXTURES, "$(prefix)_matrix", "matrix"), joinpath(FIXTURES, "$(prefix)_matrix", "dictmap"))
        cmp = compare_lp(mine, ref)
        ispass(cmp) || foreach(println, cmp.examples)
        return mine, cmp
    end
    FAMS = ("EQ_SDLOGIC", "EQ_SUDUPT", "EQ_SDSLANT", "EQ_SDMINON", "EQ_SUDLOAD", "EQ_SUDTIME", "EQ_SUDPLL")
    UPT = ("COLD", "HOT", "WARM")
    dn = ("SD", "SN", "WD", "WN")
    nrows(lp) = [count(r -> family(r) == f, keys(lp.rows)) for f in FAMS]
    ncols(lp) = [count(c -> family(c) == f, keys(lp.cols)) for f in ("VAR_UDP", "VAR_UPS", "VAR_UPT")]
    unbounded(lp) = all(c -> (lp.cols[c].lb, lp.cols[c].ub) == (0.0, Inf), [c for c in keys(lp.cols) if family(c) in ("VAR_UDP", "VAR_UPS", "VAR_UPT")])
    terms(lp, r) = Dict(c => v for ((rr, c), v) in lp.coefs if rr == r && v != 0)
    lohi(lp, r) = (lp.rows[r].lo, lp.rows[r].hi)
    near(a, b; rtol=1e-12) = keys(a) == keys(b) && all(k -> isapprox(a[k], b[k]; rtol), keys(a))
    eq(a, b) = isapprox(a, b; rtol=1e-12)
    # the rows of a family in one period, as (region, the indexes after the process, without the last '1')
    shape(lp, f, t="2020") = sort(unique([(m[1], m[2]) for m in (match(Regex("^$f\\((REG\\d),\\d+,$t,[A-Z0-9]+,(.*),1\\)\$"), r) for r in keys(lp.rows)) if m !== nothing]))
    of(x, sh) = [s[2] for s in sh if s[1] == x]
    act(x, s) = "VAR_ACT($x,$s)"
    ups(x, s, l) = "VAR_UPS($x,$s,$l)"
    udp(x, s, l) = "VAR_UDP($x,$s,$l)"
    upt(x, s, ty) = "VAR_UPT($x,$s,$ty)"
    # the VAR_U* terms of a process and vintage in the objective row of its region
    obj(lp, x) = Dict(c => v for ((rr, c), v) in lp.coefs if rr == "EQ_OBJVAR($(x[1:4]),MEURO05)" && occursin(x, c) && occursin(r"^VAR_U", c))
    h(x) = x / 8760                                         # hours as a fraction of the year

    @testset "demo12_uc: phases shorter than a timeslice" begin
        tm = load("demo12_uc")
        U, E1 = ("REG2", "ELCTEGAS00"), ("REG1", "ELCTEGAS00")           # E1: linear dispatching only
        members(name, rp) = sort([k[3:end] for k in gset(tm, name) if k[1:2] == rp])
        val(name, k) = gv(gparam(tm, name), k).v
        fr(s) = val("G_YRFR", ("REG1", s))                  # the same in REG2
        prd(s) = val("RS_STGPRD", ("REG1", s))
        cap = val("PRC_CAPACT", U)                          # 31.536
        @testset "the data of the case" begin
            # L15-16: a process with ACT_CSTSD and a dispatching load range (RP_UPL 'FX'); L18-19: its
            # level and, for a DAYNITE process, the levels above it but ANNUAL
            @test collect(gset(tm, "RP_DP")) == [U]
            @test members("RP_UPL", U) == [("FX",)] && members("RP_PL", U) == [("FX",), ("N",)]
            @test members("RP_DPL", U) == [("DAYNITE",), ("SEASON",)]
            # L23: the start-up types with a cost, the shut-down under ('HOT','LO'), and every type
            # with a start-up time
            @test members("RP_UPT", U) == [("COLD", "UP"), ("HOT", "LO"), ("HOT", "UP"), ("WARM", "UP")]
            # L46-51: no start-up levels, cycling constraints or EQ_CAPLOAD rows of the linear
            # dispatching; RP_UPS 'FX' at the level above its own; start-up variables at every
            # timeslice of the process and above; VAR_CAP for a process that is not vintaged
            @test members("RP_UPS", U) == [("SEASON", "FX")] && isempty(members("RP_UPC", U))
            @test members("RP_UPS", E1) == [("DAYNITE", "UP"), ("SEASON", "FX")]
            @test !any(k -> (k[1], k[3]) == U, gset(tm, "AFUPS")) && any(k -> (k[1], k[3]) == E1, gset(tm, "AFUPS"))
            @test members("RPS_UPS", U) == [(s,) for s in ("S", "SD", "SN", "W", "WD", "WN")]
            @test U in gset(tm, "RP_UX") && all(t -> ("REG2", t, "ELCTEGAS00") in gset(tm, "RTP_VARP"), ("2005", "2010", "2015", "2020"))
            # L20-22: the start-up cost of the linear dispatching is replaced by EPS at the levels of
            # RP_DPL; L21: the cost of a start-up of a type includes the shut-down's
            @test haskey(gparam(tm, "ACT_CSTUP"), ("REG2", "2020", "ELCTEGAS00", "DAYNITE", "MEuro05")) &&
                  val("ACT_CSTUP", ("REG2", "2020", "ELCTEGAS00", "DAYNITE", "MEuro05")) == 0
            cst(ty) = val("ACT_CSTSD", ("REG2", "2020", "ELCTEGAS00", ty, "FX", "MEuro05"))
            @test eq(cst("HOT"), 0.01 + 0.005) && eq(cst("WARM"), 0.02 + 0.005) && eq(cst("COLD"), 0.04 + 0.005)
            # L26-32: the non-operational time before a start-up of each type, as a window 'LO' and
            # its width 'UP', in years. Minimum off-line time 4 h, start-up times 2, 4, 8 h, shut-down
            # 1 h, ACT_MAXNON 8 h (HOT) and 48 h (WARM). A maximum is taken only when it is shorter
            # than the cycle of the level (L27: 48 h is not, at DAYNITE)
            non(ty, tsl, bd) = val("DP_NON", ("REG2", "2020", "ELCTEGAS00", ty, tsl, bd))
            @test eq(non("HOT", "DAYNITE", "LO"), h(4 + 2 + 1)) && eq(non("HOT", "DAYNITE", "UP"), h(8 + 3 - 7))
            @test eq(non("WARM", "DAYNITE", "LO"), h(8 + 4 + 1)) && eq(non("WARM", "DAYNITE", "UP"), h(5 - 13))
            @test eq(non("WARM", "SEASON", "LO"), h(8 + 4 + 1)) && eq(non("WARM", "SEASON", "UP"), h(48 + 5 - 13))
            @test eq(non("COLD", "DAYNITE", "LO"), h(4 + 8 + 1)) && !haskey(gparam(tm, "DP_NON"), ("REG2", "2020", "ELCTEGAS00", "COLD", "DAYNITE", "UP"))
            # L36-41: the efficiency loss of a start-up. The shut-down's is deleted (L37: its phase
            # of 1 h has a slope of the whole minimum load); the HOT start-up's stays, as a factor
            lossd = [k[4:5] for k in keys(gparam(tm, "ACT_LOSSD").values) if k[1:3] == ("REG2", "2020", "ELCTEGAS00")]
            @test lossd == [("HOT", "UP")]
            @test [k[4:5] for k in keys(gparam(tm, "DP_PSUD").values) if k[1:3] == ("REG2", "2020", "ELCTEGAS00")] == [("HOT", "UP")]
            let p = 0.4 / 2
                @test eq(val("DP_PSUD", ("REG2", "2020", "ELCTEGAS00", "HOT", "UP")), p * (0.2 / 0.05 - 1) / (0.4 - p))
            end
            @test ("REG2", "2020", "ELCTEGAS00") in gset(tm, "DP_LOSD")
            @test isempty(untranslated_families(tm))
        end
        @testset "the model against GAMS's matrix (layer 2)" begin
            lp, cmp = against_gams(tm, "demo12_uc")
            @test ispass(cmp)
            @test nrows(lp) == [48, 48, 24, 16, 16, 32, 16]
            @test ncols(lp) == [88, 168, 72] && unbounded(lp)
            u = "REG2,2020,2020,ELCTEGAS00"                  # not vintaged: v = t
            ucap = "VAR_CAP(REG2,2020,ELCTEGAS00)"
            T(r) = terms(lp, r)

            # eq_sdlogic (L67-70): 'N', the on-line capacity from the timeslice before (SN before SD)
            # with the start-ups less the shut-downs; 'FX', the start-ups split by type. At the
            # process's level and the level above
            @test of("REG2", shape(lp, "EQ_SDLOGIC")) == sort(["$tsl,$s,$l" for (tsl, ss) in (("DAYNITE", dn), ("SEASON", ("S", "W"))) for s in ss for l in ("FX", "N")])
            @test lohi(lp, "EQ_SDLOGIC($u,DAYNITE,SD,N,1)") == (0.0, 0.0)
            @test near(T("EQ_SDLOGIC($u,DAYNITE,SD,N,1)"), Dict(udp(u, "SN", "N") => 1.0, udp(u, "SD", "N") => -1.0, ups(u, "SD", "LO") => -1.0, ups(u, "SD", "UP") => 1.0))
            @test near(T("EQ_SDLOGIC($u,SEASON,S,N,1)"), Dict(udp(u, "W", "N") => 1.0, udp(u, "S", "N") => -1.0, ups(u, "S", "LO") => -1.0, ups(u, "S", "UP") => 1.0))
            @test near(T("EQ_SDLOGIC($u,DAYNITE,SD,FX,1)"), merge(Dict(ups(u, "SD", "UP") => 1.0), Dict(upt(u, "SD", ty) => -1.0 for ty in UPT)))

            # eq_sudupt (L74-77): a HOT or WARM start-up needs a shut-down within its window in
            # another timeslice of the cycle. The windows here are too short to reach one: the row
            # is VAR_UPT =L= 0, as in GAMS. No row for COLD (no DP_NON 'UP')
            @test of("REG2", shape(lp, "EQ_SUDUPT")) == sort(["$tsl,$s,$ty" for (tsl, ss) in (("DAYNITE", dn), ("SEASON", ("S", "W"))) for s in ss for ty in ("HOT", "WARM")])
            @test lohi(lp, "EQ_SUDUPT($u,DAYNITE,SD,WARM,1)") == (-Inf, 0.0)
            @test near(T("EQ_SUDUPT($u,DAYNITE,SD,WARM,1)"), Dict(upt(u, "SD", "WARM") => 1.0))
            @test near(T("EQ_SUDUPT($u,SEASON,S,HOT,1)"), Dict(upt(u, "S", "HOT") => 1.0))

            # eq_sdslant (L81-90): the on-line capacity is what the level above has on-line (VAR_UPS
            # 'FX' of the season; the capacity itself at SEASON) less the capacity off-line. No phase
            # reaches another timeslice
            @test of("REG2", shape(lp, "EQ_SDSLANT")) == sort(vcat(["DAYNITE,$s" for s in dn], ["SEASON,S", "SEASON,W"]))
            @test lohi(lp, "EQ_SDSLANT($u,DAYNITE,SD,1)") == (0.0, 0.0)
            @test near(T("EQ_SDSLANT($u,DAYNITE,SD,1)"), Dict(udp(u, "SD", "N") => 1.0, ups(u, "S", "FX") => -1.0, ups(u, "SD", "N") => 1.0))
            @test near(T("EQ_SDSLANT($u,SEASON,S,1)"), Dict(ucap => -1.0, udp(u, "S", "N") => 1.0, ups(u, "S", "N") => 1.0))

            # eq_sdminon (L94-97): the capacity above the minimum load excludes the capacity in a
            # start-up longer than half the timeslice (COLD: 8 h against 12.5/2)
            @test of("REG2", shape(lp, "EQ_SDMINON")) == collect(dn)
            @test lohi(lp, "EQ_SDMINON($u,SD,1)") == (0.0, Inf)
            @test near(T("EQ_SDMINON($u,SD,1)"), Dict(udp(u, "S", "FX") => 1.0, udp(u, "SD", "FX") => -1.0, udp(u, "SD", "N") => 1.0, upt(u, "SD", "COLD") => -1.0))

            # eq_sudload (L101-103): the load is the minimum load 0.4 of the on-line capacity plus the
            # capacity above the minimum load up to the availability 1
            @test of("REG2", shape(lp, "EQ_SUDLOAD")) == collect(dn)
            for s in dn
                @test lohi(lp, "EQ_SUDLOAD($u,$s,1)") == (0.0, 0.0)
                @test near(T("EQ_SUDLOAD($u,$s,1)"), Dict(act(u, s) => 1 / fr(s) / cap, ucap => -0.4, udp(u, s, "FX") => -0.6,
                                                         ups(u, s[1:1], "N") => 0.4, ups(u, s, "N") => 0.4))
            end

            # eq_sudtime (L107-114), at the process's level. 'LO': the capacity off-line covers the
            # shut-downs of the last 4 h (minimum off-line time), counted after the shut-down phase:
            # none within the timeslice. 'UP': the capacity on-line covers the start-ups of the last
            # 4 h (minimum on-line time): the three types of the timeslice
            @test of("REG2", shape(lp, "EQ_SUDTIME")) == sort(["DAYNITE,$s,$bd" for s in dn for bd in ("LO", "UP")])
            @test lohi(lp, "EQ_SUDTIME($u,DAYNITE,SD,LO,1)") == (0.0, Inf)
            @test near(T("EQ_SUDTIME($u,DAYNITE,SD,LO,1)"), Dict(ups(u, "SD", "N") => 1.0))
            @test near(T("EQ_SUDTIME($u,DAYNITE,SD,UP,1)"), merge(Dict(udp(u, "SD", "N") => 1.0), Dict(upt(u, "SD", ty) => -1.0 for ty in UPT)))

            # eq_sudpll (L118-124): the efficiency loss of the phases longer than half the timeslice
            # (COLD), on the minimum load of the capacity started
            @test of("REG2", shape(lp, "EQ_SUDPLL")) == ["DAYNITE,$s" for s in dn]
            for s in dn
                @test lohi(lp, "EQ_SUDPLL($u,DAYNITE,$s,1)") == (0.0, Inf)
                @test near(T("EQ_SUDPLL($u,DAYNITE,$s,1)"), Dict(ups(u, s, "FX") => 1.0, upt(u, s, "COLD") => -cap * fr(s) * 0.4))
            end

            # EQ_OBJVAR (eqobjvar.mod L38): ACT_CSTSD 'FX' per start-up of a type, times the number of
            # cycles a year; nothing else of the process's start-up variables
            let pvt = val("OBJ_PVT", ("REG2", "2020", "MEuro05")), c = Dict("HOT" => 0.015, "WARM" => 0.025, "COLD" => 0.045)
                @test near(obj(lp, u), Dict(upt(u, s, ty) => c[ty] * pvt * prd(s) for s in ("S", "SD", "SN", "W", "WD", "WN") for ty in UPT))
            end
            # the dispatching rows the process keeps (eqactups.vda): the loss variable in EQE_ACTEFF,
            # the capacity on-line through the season (EQE_ACTUPS 'FX') and its start-ups (EQL_ACTUPS)
            @test isapprox(T("EQE_ACTEFF($u,NRG,IN,SD)")[ups(u, "SD", "FX")], -0.05; rtol=1e-12)
            @test near(T("EQE_ACTUPS($u,SEASON,FX,S)"), Dict(ucap => 1.0, udp(u, "S", "FX") => -1.0, ups(u, "S", "FX") => -1.0, ups(u, "S", "N") => -1.0))
            @test near(T("EQL_ACTUPS($u,SEASON,FX,S)"), Dict(ups(u, "S", "FX") => 1.0, ups(u, "SD", "UP") => -1.0, ups(u, "SN", "UP") => -1.0))
            @test !any(r -> occursin(Regex("^EQ_CAPLOAD\\($u,"), r), keys(lp.rows))
        end
    end

    @testset "demo12_ucv: a vintaged process, phases that reach the neighbouring timeslice, a SEASON process" begin
        tm = load("demo12_ucv")
        A, B = ("REG2", "ELCTNGAS01"), ("REG1", "ELCTECOA00")
        members(name, rp) = sort([k[3:end] for k in gset(tm, name) if k[1:2] == rp])
        val(name, k) = gv(gparam(tm, name), k).v
        fr(s) = val("G_YRFR", ("REG1", s))                  # the same in REG2
        prd(s) = val("RS_STGPRD", ("REG1", s))
        hrs(s) = 8760 * fr(s) / prd(s)                      # hours of a timeslice in its cycle
        cap = val("PRC_CAPACT", A)                          # 31.536, both processes
        psud(ty, bd) = val("DP_PSUD", ("REG2", "2010", "ELCTNGAS01", ty, bd))
        @testset "the data of the case" begin
            @test sort(collect(gset(tm, "RP_DP"))) == [B, A]
            @test members("RP_DPL", A) == [("DAYNITE",), ("SEASON",)] && members("RP_DPL", B) == [("SEASON",)]
            # L23: B gives no shut-down cost or time; ('HOT','LO') is set all the same
            @test members("RP_UPT", A) == members("RP_UPT", B) == [("COLD", "UP"), ("HOT", "LO"), ("HOT", "UP"), ("WARM", "UP")]
            # L51: RP_UPS 'FX' at the level above the process's own: ANNUAL for the SEASON process
            @test members("RP_UPS", A) == [("SEASON", "FX")] && members("RP_UPS", B) == [("ANNUAL", "FX")]
            @test members("RPS_UPS", A) == [(s,) for s in ("S", "SD", "SN", "W", "WD", "WN")] && members("RPS_UPS", B) == [("S",), ("W",)]
            # L50: VAR_CAP for the process that is not vintaged only
            @test collect(gset(tm, "RP_UX")) == [B] && all(t -> ("REG1", t, "ELCTECOA00") in gset(tm, "RTP_VARP"), ("2005", "2010", "2015", "2020", "2030"))
            @test isempty(gset(tm, "AFUPS")) && isempty(members("RP_UPC", A)) && isempty(members("RP_UPC", B))
            # eqactups.vda L25 with ppm_ext.vda L15: RP_PL from ACT_LOSPL 'FX', which B does not give
            @test members("RP_PL", A) == [("FX",), ("N",)] && isempty(members("RP_PL", B))
            # L26-32, in hours for A (minimum off-line time 14, start-up times 3, 9, 20, shut-down 19,
            # ACT_MAXNON 10 and 20, both shorter than the day) and B (2000; 500, 1500, 7000; no
            # shut-down time; 1000 and 3000, both shorter than the year but taken at SEASON only)
            nonA(ty, tsl, bd) = val("DP_NON", ("REG2", "2010", "ELCTNGAS01", ty, tsl, bd))
            nonB(ty, tsl, bd) = val("DP_NON", ("REG1", "2010", "ELCTECOA00", ty, tsl, bd))
            @test eq(nonA("HOT", "DAYNITE", "LO"), h(14 + 3 + 19)) && eq(nonA("HOT", "DAYNITE", "UP"), h(10 + 22 - 36))
            @test eq(nonA("WARM", "DAYNITE", "LO"), h(14 + 9 + 19)) && eq(nonA("WARM", "DAYNITE", "UP"), h(20 + 28 - 42))
            @test eq(nonA("COLD", "DAYNITE", "LO"), h(14 + 20 + 19)) && eq(nonA("HOT", "ANNUAL", "UP"), h(22 - 36))
            @test eq(nonB("HOT", "SEASON", "LO"), h(2000 + 500)) && eq(nonB("HOT", "SEASON", "UP"), h(1000 + 500 - 2500))
            @test eq(nonB("WARM", "SEASON", "LO"), h(2000 + 1500)) && eq(nonB("WARM", "SEASON", "UP"), h(3000 + 1500 - 3500))
            @test eq(nonB("COLD", "SEASON", "LO"), h(2000 + 7000)) && eq(nonB("WARM", "DAYNITE", "UP"), h(1500 - 3500))
            # L36-41, A: the slope of each phase (minimum load 0.4 over the phase's hours) and the
            # loss factor of every start-up type and of the shut-down, against ACT_LOSPL 'FX' 0.05
            for (ty, bd, hours, loss) in (("HOT", "UP", 3, 0.2), ("WARM", "UP", 9, 0.25), ("COLD", "UP", 20, 0.3), ("HOT", "LO", 19, 0.2))
                p = 0.4 / hours
                @test eq(psud(ty, bd), p * (loss / 0.05 - 1) / (0.4 - p))
            end
            # L38-40, B: an ACT_LOSSD makes it a member of DP_LOSD; without RP_PL 'N' its ACT_LOSPL
            # 'FX' defaults to 1, and a loss below that is deleted
            @test ("REG1", "2010", "ELCTECOA00") in gset(tm, "DP_LOSD") && ("REG2", "2010", "ELCTNGAS01") in gset(tm, "DP_LOSD")
            @test val("ACT_LOSPL", ("REG1", "2010", "ELCTECOA00", "FX")) == 1.0 && val("ACT_LOSPL", ("REG2", "2010", "ELCTNGAS01", "FX")) == 0.05
            # (the lines act on RTP only: the record of 2050, when the plant is retired, is left alone)
            @test [k[2] for k in keys(gparam(tm, "ACT_LOSSD").values) if k[3] == "ELCTECOA00"] == ["2050"] &&
                  !(("REG1", "2050", "ELCTECOA00") in gset(tm, "RTP"))
            @test !any(k -> k[3] == "ELCTECOA00", keys(gparam(tm, "DP_PSUD").values))
            # L21: B's cost of a start-up has no shut-down part
            @test val("ACT_CSTSD", ("REG1", "2010", "ELCTECOA00", "COLD", "FX", "MEuro05")) == 2.0
            @test eq(val("ACT_CSTSD", ("REG2", "2010", "ELCTNGAS01", "COLD", "FX", "MEuro05")), 0.04 + 0.005)
            @test isempty(untranslated_families(tm))
        end
        @testset "the model against GAMS's matrix (layer 2)" begin
            lp, cmp = against_gams(tm, "demo12_ucv")
            @test ispass(cmp)
            @test nrows(lp) == [188, 188, 94, 66, 66, 132, 66]
            @test ncols(lp) == [193, 381, 282] && unbounded(lp)
            a = "REG2,2010,2020,ELCTNGAS01"                  # the vintage 2010 in 2020
            b = "REG1,2020,2020,ELCTECOA00"                  # not vintaged: v = t
            acap, bcap = "VAR_NCAP(REG2,2010,ELCTNGAS01)", "VAR_CAP(REG1,2020,ELCTECOA00)"
            T(r) = terms(lp, r)
            day = (("SD", "SN"), ("SN", "SD"), ("WD", "WN"), ("WN", "WD"))        # a timeslice and the other one of its day
            @test hrs("SD") ≈ 12.5 && hrs("SN") ≈ 11.5 && hrs("WD") ≈ 11.5 && hrs("WN") ≈ 12.5

            # eq_sdlogic: as demo12_uc for A; B at SEASON only (the season before S is W)
            @test of("REG2", shape(lp, "EQ_SDLOGIC")) == sort(["$tsl,$s,$l" for (tsl, ss) in (("DAYNITE", dn), ("SEASON", ("S", "W"))) for s in ss for l in ("FX", "N")])
            @test of("REG1", shape(lp, "EQ_SDLOGIC")) == ["SEASON,S,FX", "SEASON,S,N", "SEASON,W,FX", "SEASON,W,N"]
            @test near(T("EQ_SDLOGIC($a,DAYNITE,SD,N,1)"), Dict(udp(a, "SN", "N") => 1.0, udp(a, "SD", "N") => -1.0, ups(a, "SD", "LO") => -1.0, ups(a, "SD", "UP") => 1.0))
            @test near(T("EQ_SDLOGIC($b,SEASON,S,N,1)"), Dict(udp(b, "W", "N") => 1.0, udp(b, "S", "N") => -1.0, ups(b, "S", "LO") => -1.0, ups(b, "S", "UP") => 1.0))
            @test near(T("EQ_SDLOGIC($b,SEASON,S,FX,1)"), merge(Dict(ups(b, "S", "UP") => 1.0), Dict(upt(b, "S", ty) => -1.0 for ty in UPT)))

            # eq_sudupt: A's WARM start-up (non-operational for 42 to 48 h) is within the shut-downs
            # of the other timeslice of the day; the HOT window (36 h, of no width) reaches none.
            # B's rows have no shut-down term: a season is alone in its cycle
            @test of("REG1", shape(lp, "EQ_SUDUPT")) == ["SEASON,$s,$ty" for s in ("S", "W") for ty in ("HOT", "WARM")]
            for (s, sl) in day
                @test lohi(lp, "EQ_SUDUPT($a,DAYNITE,$s,WARM,1)") == (-Inf, 0.0)
                @test near(T("EQ_SUDUPT($a,DAYNITE,$s,WARM,1)"), Dict(upt(a, s, "WARM") => 1.0, ups(a, sl, "LO") => -1.0))
                @test near(T("EQ_SUDUPT($a,DAYNITE,$s,HOT,1)"), Dict(upt(a, s, "HOT") => 1.0))
            end
            @test near(T("EQ_SUDUPT($a,SEASON,S,WARM,1)"), Dict(upt(a, "S", "WARM") => 1.0))
            @test near(T("EQ_SUDUPT($b,SEASON,S,WARM,1)"), Dict(upt(b, "S", "WARM") => 1.0))

            # eq_sdslant: capacity in a phase that began in the other timeslice of the day is not
            # on-line yet (a COLD start-up of 20 h), or still is (a shut-down of 19 h), for the part
            # of the phase that is left after the hours of that timeslice; the shut-downs of the
            # timeslice itself count whole. The vintage's VAR_NCAP is the capacity of A
            for (s, sl) in day
                @test lohi(lp, "EQ_SDSLANT($a,DAYNITE,$s,1)") == (0.0, 0.0)
                @test near(T("EQ_SDSLANT($a,DAYNITE,$s,1)"),
                           Dict(udp(a, s, "N") => 1.0, ups(a, s[1:1], "FX") => -1.0, ups(a, s, "N") => 1.0, ups(a, s, "LO") => 1.0,
                                ups(a, sl, "LO") => 1 - hrs(sl) / 19, upt(a, sl, "COLD") => 1 - hrs(sl) / 20); rtol=1e-9)
            end
            @test near(T("EQ_SDSLANT($a,SEASON,S,1)"), Dict(acap => -1.0, udp(a, "S", "N") => 1.0, ups(a, "S", "N") => 1.0))
            # B: the level above is ANNUAL; no phase term, though the COLD start-up is longer than
            # the season
            @test of("REG1", shape(lp, "EQ_SDSLANT")) == ["SEASON,S", "SEASON,W"]
            @test near(T("EQ_SDSLANT($b,SEASON,S,1)"), Dict(udp(b, "S", "N") => 1.0, ups(b, "ANNUAL", "FX") => -1.0, ups(b, "S", "N") => 1.0))

            # eq_sdminon: two start-up types longer than half the timeslice (WARM 9 h and COLD 20 h
            # against about 6 h); B: COLD only (7000 h against half a season)
            @test near(T("EQ_SDMINON($a,SD,1)"), Dict(udp(a, "S", "FX") => 1.0, udp(a, "SD", "FX") => -1.0, udp(a, "SD", "N") => 1.0,
                                                    upt(a, "SD", "COLD") => -1.0, upt(a, "SD", "WARM") => -1.0))
            @test of("REG1", shape(lp, "EQ_SDMINON")) == ["S", "W"]
            @test near(T("EQ_SDMINON($b,S,1)"), Dict(udp(b, "ANNUAL", "FX") => 1.0, udp(b, "S", "FX") => -1.0, udp(b, "S", "N") => 1.0, upt(b, "S", "COLD") => -1.0))

            # eq_sudload: the vintage's capacity for A; B (minimum load 0.35) has no level between
            # its own and ANNUAL, so one off-line term
            @test near(T("EQ_SUDLOAD($a,SD,1)"), Dict(act(a, "SD") => 1 / fr("SD") / cap, acap => -0.4, udp(a, "SD", "FX") => -0.6,
                                                    ups(a, "S", "N") => 0.4, ups(a, "SD", "N") => 0.4))
            for s in ("S", "W")
                @test lohi(lp, "EQ_SUDLOAD($b,$s,1)") == (0.0, 0.0)
                @test near(T("EQ_SUDLOAD($b,$s,1)"), Dict(act(b, s) => 1 / fr(s) / cap, bcap => -0.35, udp(b, s, "FX") => -0.65, ups(b, s, "N") => 0.35))
            end

            # eq_sudtime. 'LO' (minimum off-line time 14 h, after a shut-down phase of 19 h): the
            # shut-downs of the timeslice itself. 'UP' (minimum on-line time 40 h, less the phases):
            # the start-ups of the timeslice and the HOT and WARM start-ups of the other one
            for (s, sl) in day
                @test lohi(lp, "EQ_SUDTIME($a,DAYNITE,$s,LO,1)") == (0.0, Inf)
                @test near(T("EQ_SUDTIME($a,DAYNITE,$s,LO,1)"), Dict(ups(a, s, "N") => 1.0, ups(a, s, "LO") => -1.0))
                @test near(T("EQ_SUDTIME($a,DAYNITE,$s,UP,1)"), merge(Dict(udp(a, s, "N") => 1.0, upt(a, sl, "HOT") => -1.0, upt(a, sl, "WARM") => -1.0),
                                                                   Dict(upt(a, s, ty) => -1.0 for ty in UPT)))
            end
            # B (2000 h off-line, 2500 h on-line; a season is about 4200 h): no shut-down within the
            # season's half; the COLD start-up is longer than the minimum on-line time
            @test of("REG1", shape(lp, "EQ_SUDTIME")) == ["SEASON,$s,$bd" for s in ("S", "W") for bd in ("LO", "UP")]
            @test near(T("EQ_SUDTIME($b,SEASON,S,LO,1)"), Dict(ups(b, "S", "N") => 1.0))
            @test near(T("EQ_SUDTIME($b,SEASON,S,UP,1)"), Dict(udp(b, "S", "N") => 1.0, upt(b, "S", "HOT") => -1.0, upt(b, "S", "WARM") => -1.0))

            # eq_sudpll: the phases longer than half the timeslice (WARM, COLD, the shut-down) count
            # whole in their own timeslice; a COLD start-up or a shut-down of the other timeslice of
            # the day counts with its loss factor DP_PSUD for the hours of that timeslice out of the
            # phase's. The HOT start-up (3 h) is in no row
            for (s, sl) in day
                k = cap * fr(s) * 0.4
                w(hours, f) = 1 + hrs(sl) / hours * (f - 1)
                @test lohi(lp, "EQ_SUDPLL($a,DAYNITE,$s,1)") == (0.0, Inf)
                @test near(T("EQ_SUDPLL($a,DAYNITE,$s,1)"),
                           Dict(ups(a, s, "FX") => 1.0, ups(a, s, "LO") => -k, upt(a, s, "COLD") => -k, upt(a, s, "WARM") => -k,
                                ups(a, sl, "LO") => -k * w(19, psud("HOT", "LO")), upt(a, sl, "COLD") => -k * w(20, psud("COLD", "UP"))); rtol=1e-9)
            end
            # B is in DP_LOSD without a loss factor: its COLD start-up counts whole, on 0.35
            @test of("REG1", shape(lp, "EQ_SUDPLL")) == ["SEASON,S", "SEASON,W"]
            for s in ("S", "W")
                @test near(T("EQ_SUDPLL($b,SEASON,$s,1)"), Dict(ups(b, s, "FX") => 1.0, upt(b, s, "COLD") => -cap * fr(s) * 0.35))
            end

            # EQ_OBJVAR: the costs by type, for the vintage of A and for B
            let pvt = val("OBJ_PVT", ("REG1", "2020", "MEuro05")),                   # the same in REG2
                ca = Dict("HOT" => 0.015, "WARM" => 0.025, "COLD" => 0.045), cb = Dict("HOT" => 0.5, "WARM" => 1.0, "COLD" => 2.0)
                @test near(obj(lp, a), Dict(upt(a, s, ty) => ca[ty] * pvt * prd(s) for s in ("S", "SD", "SN", "W", "WD", "WN") for ty in UPT))
                @test near(obj(lp, b), Dict(upt(b, s, ty) => cb[ty] * pvt * prd(s) for s in ("S", "W") for ty in UPT))
            end
            # the dispatching rows: B's capacity on-line through the year and its start-ups in the
            # seasons; A's loss variable in EQE_ACTEFF (B has no ACT_LOSPL given, and no term)
            @test near(T("EQE_ACTUPS($b,ANNUAL,FX,ANNUAL)"), Dict(bcap => 1.0, udp(b, "ANNUAL", "FX") => -1.0, ups(b, "ANNUAL", "FX") => -1.0))
            @test near(T("EQL_ACTUPS($b,ANNUAL,FX,ANNUAL)"), Dict(ups(b, "ANNUAL", "FX") => 1.0, ups(b, "S", "UP") => -1.0, ups(b, "W", "UP") => -1.0))
            @test near(T("EQE_ACTUPS($a,SEASON,FX,S)"), Dict(acap => 1.0, udp(a, "S", "FX") => -1.0, ups(a, "S", "FX") => -1.0, ups(a, "S", "N") => -1.0))
            @test isapprox(T("EQE_ACTEFF($a,NRG,IN,SD)")[ups(a, "SD", "FX")], -0.05; rtol=1e-12)
            @test !any(((r, c),) -> startswith(r, "EQE_ACTEFF(REG1") && startswith(c, "VAR_UPS"), collect(keys(lp.coefs)))
        end
    end

    @testset "no data, no rows; the discrete unit commitment is refused" begin
        t0 = TimesModel(joinpath(FIXTURES, "demo12_red_presolve"); reduce=variant("demo12_uc")["reduce"], switches=variant("demo12_uc")["switches"])
        @test eq_lducs!(t0) == 0
        # eqlducs.vda L128-175 (the binary on-line indicator and its constraints), a MIP
        t1 = load("demo12_uc"; more=Dict("DUC" => "YES"))
        @test [x.family for x in untranslated_families(t1)] == ["(discrete unit commitment)"]
    end
end
