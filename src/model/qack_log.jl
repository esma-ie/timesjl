# M1.3 (25b-2): pp_qack.mod's quality checks, written to the QA log
# (src/prep/qalog.jl), and the ERRLEV abort.
#
# GAMS (v4.9.7): pp_qack.mod L37-41 (QLOG reopened: NW=10, ND=2, PW=150;
# PUTGRP = 0), L62-201 (the checks every run makes), L203-372 (the extended
# checks, with %VDA% YES and %XTQA% YES or %DEBUG% YES), L374-387 (ERRLEV 33:
# an alert; above 33: ABORT; 'ALL QUALITY CHECKS PASSED' when nothing was
# written; the scalars cleared; PUTCLOSE).
#
# The checks read the state where pp_qack.mod has them, so `pp_qack_data!`
# (qack_prep.jl) calls `qack_checks!` at each point, in GAMS order. Every
# LOOP runs in GAMS order (`gams_sort!`). Where pp_qack.mod sets PUTGRP to 0
# only before one of two loops, the second goes on in the first one's group
# (L81-90: 'Commodity in CG ...' and 'No commodities in CG ...'; L216-230 and
# L233-240: the IRE checks), as in GAMS. `x.TE(x)` of an assigned record is
# its labels joined by '.' (G53).
#
# Not translated: %TIMESED% YES (L95-110, refused by `pp_qack_data!`) and
# RD_SHAR data (L127, MICRO); the EXECERROR block (L183-201) assumes no
# execution error, as TIMES.jl stops at the first one. L148
# (`IF(ERRLEV=33,SOLVESTAT(J)$=QASTAT(J))`) changes only the text of
# SOLVESTAT('1'), which err_stat.mod declares with that member.

"pp_qack.mod L37-41: QLOG reopened (append when PUTOUT), QLOG.NW=10, QLOG.ND=2, QLOG.PW=150; PUTGRP = 0."
function qack_open!(tm)
    q = qalog(tm)
    q.nw, q.nd, q.pw = 10, 2, 150
    qa_group!(tm)
    return tm
end

"""
    qack_checks!(tm, part) -> tm

The QA checks of pp_qack.mod at one point of the file (`part`), on the state
as it is there:

- `:yrfr` L62-71, `:topology` L72-91, `:commodity` L111-123,
  `:demand` L124-138, `:phantom` L139-149, `:pcg` L150-159 (before L160),
- `:fsemit` L161-167, `:refit` L168-172, `:afx` L173-182 (after L160),
- `:xtqa` L203-372 (with %VDA% and %XTQA% or %DEBUG%).

GAMS: pp_qack.mod L62-372, v4.9.7.
"""
function qack_checks!(tm, part::Symbol)
    d = tm.data
    S(name, n) = gset_opt(d, name, n).members
    Sk(name, n) = gset_opt(d, name, n).keys
    P(name, n) = gparam_opt(d, name, n)
    sorted(x) = gams_sort!(collect(x), d)
    put(level, desc, msg) = (pp_qaput!(tm, level, desc); qput!(qalog(tm), msg))
    q12 = qlab12
    reg = [k[1] for k in Sk("REG", 1)]
    regset = Set(reg)
    if part == :yrfr
        # L65-70: LOOP(R, TS_ARRAY(S) = 0; LOOP(TS_MAP(R,TS,S)$(G_YRFR(R,S) EQ 0), TS_ARRAY(S) = 1);
        #   LOOP(S$TS_ARRAY(S), pp_qaput 99 'Year Fraction G_YRFR is ZERO!'; PUT QLOG ' FATAL ERROR   -     R=',%RL%,' S=',S.TL))
        yrfr = P("G_YRFR", 2)
        tsmap = Sk("TS_MAP", 3)
        all_ts = [k[1] for k in Sk("ALL_TS", 1)]
        for r in reg
            zero = Set(s for (rr, _, s) in tsmap if rr == r && gv(yrfr, (r, s)).v == 0)
            for s in all_ts
                s in zero && put(99, "Year Fraction G_YRFR is ZERO!", " FATAL ERROR   -     R=" * q12(r) * " S=" * s)
            end
        end
        qa_group!(tm)                                                                   # L71
    elseif part == :topology
        # L75-78: LOOP(RPC(R,P,C(%PGPRIM%)), pp_qaput 99 'Illegal system commodity in topology.'; ...)
        pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
        com = S("COM", 1)
        for (r, p, c) in sorted(k for k in Sk("RPC", 3) if uppercase(k[3]) == pg && (k[3],) in com && k[1] in regset)
            put(99, "Illegal system commodity in topology.", " FATAL ERROR   -     R=" * q12(r) * " P=" * q12(p) * " C=" * c)
        end
        qa_group!(tm)                                                                   # L79
        # L81-90: LOOP(PRC_CG(R,P,CG)$(NOT COM_TYPE(CG)), IF(NOT SUM(COM_GMAP(R,CG,C)$RPC(R,P,C),1), Z = 1;
        #   LOOP(COM_GMAP(R,CG,C)$(NOT RPC(R,P,C)), Z = 0; pp_qaput 10 'Commodity in CG of process P but not in topology';
        #     PUT QLOG ' SEVERE WARNING  -   R=',%RL%,' P=',%PL%,' C=',%CL%,' CG=',CG.TL);
        #   IF(Z, pp_qaput 10 'No commodities in CG of process P'; PUT QLOG ' SEVERE WARNING  -   R=',%RL%,' P=',%PL%,' CG=',CG.TL)))
        rpc = S("RPC", 3)
        comtype = S("COM_TYPE", 1)
        members = Dict{NTuple{2,String},Vector{String}}()
        for (r, cg, c) in sorted(Sk("COM_GMAP", 3))
            push!(get!(() -> String[], members, (r, cg)), c)
        end
        z = nothing
        for (r, p, cg) in sorted(k for k in Sk("PRC_CG", 3) if k[1] in regset && !((k[3],) in comtype))
            cs = get(members, (r, cg), String[])
            any(c -> (r, p, c) in rpc, cs) && continue
            z = 1.0
            for c in cs
                z = 0.0
                put(10, "Commodity in CG of process P but not in topology",
                    " SEVERE WARNING  -   R=" * q12(r) * " P=" * q12(p) * " C=" * q12(c) * " CG=" * cg)
            end
            z == 1 && put(10, "No commodities in CG of process P", " SEVERE WARNING  -   R=" * q12(r) * " P=" * q12(p) * " CG=" * cg)
        end
        z === nothing || gput_scalar!(tm, "Z", z)                                       # the scratch Z, as the loop leaves it
        qa_group!(tm)                                                                   # L91
    elseif part == :commodity
        qa_group!(tm)                                                                   # L111 (after the %TIMESED% block)
        rc = Sk("RC", 2)
        comtype = S("COM_TYPE", 1)
        # L112-115: LOOP(RC(R,C(COM_TYPE)), pp_qaput 99 'Commodity type is also a commodity'; ' FATAL ERROR   -     R=',%RL%,' C=',C.TL)
        for (r, c) in sorted(k for k in rc if k[1] in regset && (k[2],) in comtype)
            put(99, "Commodity type is also a commodity", " FATAL ERROR   -     R=" * q12(r) * " C=" * c)
        end
        qa_group!(tm)                                                                   # L116
        # L117-122: LOOP(RC(R,C)$(SUM(COM_TMAP(R,COM_TYPE,C),1) NE 1), pp_qaput 09 'Commodity has ambiguous base type';
        #   ' FATAL ERROR   -  Several types: R=' or ' FATAL ERROR   -  Missing type : R=',%RL%,' C=',C.TL)
        ntype = Dict{NTuple{2,String},Int}()
        for (r, t, c) in Sk("COM_TMAP", 3)
            (t,) in comtype && (ntype[(r, c)] = get(ntype, (r, c), 0) + 1)
        end
        for (r, c) in sorted(k for k in rc if k[1] in regset && get(ntype, k, 0) != 1)
            put(9, "Commodity has ambiguous base type",
                (get(ntype, (r, c), 0) > 1 ? " FATAL ERROR   -  Several types: R=" : " FATAL ERROR   -  Missing type : R=") * q12(r) * " C=" * c)
        end
        qa_group!(tm)                                                                   # L123
    elseif part == :demand
        # L127-128: OPTION TRACKC < RD_SHAR; LOOP((R,T,C)$COM_PROJ(R,T,C),TRACKC(R,C) = YES)
        isempty(P("RD_SHAR", 4)) || throw(UnportedError("pp_qack.mod L127: RD_SHAR data (MICRO)"))
        T = S("MILESTONYR", 1)
        com = S("COM", 1)
        trackc = Set{NTuple{2,String}}((r, c) for (r, t, c) in keys(P("COM_PROJ", 3).values) if r in regset && (t,) in T && (c,) in com)
        # L129-131: LOOP(COM_GMAP(DEM(R,C),C)$(NOT TRACKC(R,C)), pp_qaput 01 'Demand: DEM commodity with missing COM_PROJ Projection'; ...)
        dem = S("DEM", 2)
        for (r, c, _) in sorted(k for k in Sk("COM_GMAP", 3) if k[2] == k[3] && (k[1], k[2]) in dem && !((k[1], k[2]) in trackc))
            put(1, "Demand: DEM commodity with missing COM_PROJ Projection", " WARNING       -     R=" * q12(r) * " C=" * c)
        end
        qa_group!(tm)                                                                   # L132
        # L133-136: LOOP(TRACKC(R,C)$(NOT DEM(R,C)), pp_qaput 01 'Demand: COM_PROJ specified for non-DEM commodity'; ...)
        for (r, c) in sorted(k for k in trackc if !(k in dem))
            put(1, "Demand: COM_PROJ specified for non-DEM commodity", " WARNING       -     R=" * q12(r) * " C=" * c)
        end
        qa_group!(tm)                                                                   # L138
    elseif part == :phantom
        # L143-146: OPTION TRACKPC<RPC; TRACKPC(RP(R,PRC(P)),C)$RC(R,C)=NO; LOOP(TRACKPC(RPC), pp_qaput 33
        #   'Phantom entries found in topology (process/commodity not in SET PRC/COM)';
        #   PUT QLOG ' FATAL ERROR   -     Phantom topology entry:   R.P.C= ',TRACKPC.TE(RPC))
        rp, prc, rc = S("RP", 2), S("PRC", 1), S("RC", 2)
        for k in sorted(k for k in Sk("RPC", 3) if k[1] in regset && !((k[1], k[2]) in rp && (k[2],) in prc && (k[1], k[3]) in rc))
            put(33, "Phantom entries found in topology (process/commodity not in SET PRC/COM)",
                " FATAL ERROR   -     Phantom topology entry:   R.P.C= " * join(k, "."))
        end
        # L148: IF(ERRLEV=33,SOLVESTAT(J)$=QASTAT(J)): the text of SOLVESTAT('1') only (see the header)
        qa_group!(tm)                                                                   # L149
    elseif part == :pcg
        # L150-158: PRC_YMAX(RP)=SUM(RP_PG(RP,CG),1)-1; LOOP(RP(R,P)$PRC_YMAX(R,P), pp_qaput 10
        #   'Process with missing or mismatched CG/PRC_ACTUNIT'; ' FATAL ERROR   -  No way to identify PCG:   R=' (< 0)
        #   or ' FATAL ERROR   -  Several PCG groups:       R=',%RL%,' P=',P.TL)
        npg = Dict{NTuple{2,String},Int}()
        foreach(k -> (npg[(k[1], k[2])] = get(npg, (k[1], k[2]), 0) + 1), Sk("RP_PG", 3))
        for (r, p) in sorted(k for k in Sk("RP", 2) if k[1] in regset && get(npg, k, 0) != 1)
            put(10, "Process with missing or mismatched CG/PRC_ACTUNIT",
                (get(npg, (r, p), 0) < 1 ? " FATAL ERROR   -  No way to identify PCG:   R=" : " FATAL ERROR   -  Several PCG groups:       R=") *
                q12(r) * " P=" * p)
        end
    elseif part == :fsemit
        qa_group!(tm)                                                                   # L161
        # L163-166: LOOP(FS_EMIT(R,P,COM,CG,C)$RPC_EMIS(R,P,C), pp_qaput 01 'Illegal dependency of substituted auxiliary
        #   commodities C1 and C2 in FLO_SUM'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' C1=',%CL%,' C2=',COM.TL)
        emis = S("RPC_EMIS", 3)
        for (r, p, cm, _, c) in sorted(k for k in Sk("FS_EMIT", 5) if k[1] in regset && (k[1], k[2], k[5]) in emis)
            put(1, "Illegal dependency of substituted auxiliary commodities C1 and C2 in FLO_SUM",
                " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " C1=" * q12(c) * " C2=" * cm)
        end
        qa_group!(tm)                                                                   # L167
    elseif part == :refit
        # L168-171: OPTION PRC_YMAX < PRC_REFIT; PRC_YMAX(RP)$(PRC_YMAX(RP)=1)=0; LOOP(RP(R,P)$PRC_YMAX(RP),
        #   pp_qaput 01 'Multiple host processes for REFIT option - Not supported'; PUT QLOG ' WARNING       -     REG=',R.TL,' PRC='P.TL)
        nhost = Dict{NTuple{2,String},Int}()
        foreach(k -> (nhost[(k[1], k[3])] = get(nhost, (k[1], k[3]), 0) + 1), keys(P("PRC_REFIT", 3).values))
        for (r, p) in sorted(k for k in Sk("RP", 2) if k[1] in regset && get(nhost, k, 0) > 1)
            put(1, "Multiple host processes for REFIT option - Not supported", " WARNING       -     REG=" * r * " PRC=" * p)
        end
        qa_group!(tm)                                                                   # L172
    elseif part == :afx
        # L173-177: IF(CARD(RP_UPL),OPTION TRACKP<NCAP_AFX; TRACKP(PRC_VINT)=NO; LOOP(RP_UPL(TRACKP(R,P),'FX'), pp_qaput 00
        #   'NCAP_AFX defined for NON-vintaged dispatchable process with ACT_MINLD';
        #   PUT QLOG ' NOTICE        -     AFX ignored on PRC_TSL:  R=',%RL%,' P=',%PL%); ... PUTGRP = 0)
        upl = Sk("RP_UPL", 3)
        if !isempty(upl)
            vint = S("PRC_VINT", 2)
            trackp = Set{NTuple{2,String}}((k[1], k[3]) for k in keys(P("NCAP_AFX", 3).values) if !((k[1], k[3]) in vint))
            for (r, p, _) in sorted(k for k in upl if k[3] == "FX" && k[1] in regset && (k[1], k[2]) in trackp)
                put(0, "NCAP_AFX defined for NON-vintaged dispatchable process with ACT_MINLD",
                    " NOTICE        -     AFX ignored on PRC_TSL:  R=" * q12(r) * " P=" * q12(p))
            end
            qa_group!(tm)                                                               # L177
        end
    elseif part == :xtqa
        qack_xtqa!(tm)
    else
        throw(ArgumentError("qack_checks!: unknown part $part"))
    end
    return tm
end

"""
    qack_xtqa!(tm) -> tm

pp_qack.mod L207-372, the extended checks (%VDA% YES with %XTQA% YES or
%DEBUG% YES): the same commodity in and out, IRE processes with flow
parameters, ACT_EFF groups, FLO_SUM commodities, PTRANS both ways, topology
entries no flow parameter covers, empty groups, NCAP_AF with NCAP_AFA,
COM_FR sums, commodity lead times, CHP parameters. The scratch sets these
checks use are left to `pp_qack_data!`.

GAMS: pp_qack.mod L207-372, v4.9.7.
"""
function qack_xtqa!(tm)
    d = tm.data
    S(name, n) = gset_opt(d, name, n).members
    Sk(name, n) = gset_opt(d, name, n).keys
    P(name, n) = gparam_opt(d, name, n)
    sorted(x) = gams_sort!(collect(x), d)
    put(level, desc, msg) = (pp_qaput!(tm, level, desc); qput!(qalog(tm), msg))
    q12 = qlab12
    reg = [k[1] for k in Sk("REG", 1)]
    regset = Set(reg)
    T = S("MILESTONYR", 1)
    rpc, top, rp = S("RPC", 3), S("TOP", 4), S("RP", 2)
    gmap = S("COM_GMAP", 3)
    rp_ire = S("RP_IRE", 2)

    # L207-211: LOOP(RPC(RP_STD(R,P),C)$(TOP(R,P,C,'IN')*TOP(R,P,C,'OUT')), pp_qaput 01
    #   'Same Commodity IN and OUT of a regular process'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' C=',C.TL)
    std = S("RP_STD", 2)
    for (r, p, c) in sorted(k for k in rpc if k[1] in regset && (k[1], k[2]) in std && (k..., "IN") in top && (k..., "OUT") in top)
        put(1, "Same Commodity IN and OUT of a regular process", " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " C=" * c)
    end
    qa_group!(tm)                                                                       # L212

    # L214-224: UNCD7(R,the Zth ALLYEAR,P,...) from FLO_FUNC (Z=1), FLO_SUM (2), FLO_SHAR (3), ACT_EFF (4) of IRE processes;
    #   LOOP(UNCD7(R,LL,P,CG,U2,U3,U4), Z = ORD(LL); pp_qaput 01 'IRE Process with invalid Parameters'; ...)
    years = [k[1] for k in Sk("ALLYEAR", 1)]
    allts = [k[1] for k in Sk("ALL_TS", 1)]
    lastts = allts[end]
    uncd7 = Set{NTuple{7,String}}()
    ire(k) = k[1] in regset && (k[1], k[3]) in rp_ire
    foreach(k -> ire(k) && push!(uncd7, (k[1], years[1], k[3], k[4], k[5], lastts, "0")), keys(P("FLO_FUNC", 6).values))
    foreach(k -> ire(k) && push!(uncd7, (k[1], years[2], k[3], k[4], k[5], k[6], lastts)), keys(P("FLO_SUM", 7).values))
    foreach(k -> ire(k) && push!(uncd7, (k[1], years[3], k[3], k[4], k[5], lastts, k[7])), keys(P("FLO_SHAR", 7).values))
    foreach(k -> ire(k) && push!(uncd7, (k[1], years[4], k[3], k[4], lastts, "0", "0")), keys(P("ACT_EFF", 5).values))
    what = Dict(years[1] => " WARNING       - IRE with FLO_FUNC: R=", years[2] => " WARNING       - IRE with FLO_SUM:  R=",
                years[3] => " WARNING       - IRE with FLO_SHAR: R=", years[4] => " WARNING       - IRE with ACT_EFF:  R=")
    for u in sorted(uncd7)
        (r, y, p, cg) = u[1:4]
        put(1, "IRE Process with invalid Parameters", what[y] * q12(r) * " P=" * q12(p) * (y == years[3] ? " C=" : " CG=") * cg)
    end
    # L225-229: LOOP(UC_QAFLO('1',UCN,SIDE,R,P,C)$(NOT UC_CAPFLO(UCN,SIDE,R,P,C)),RXX(R,P,UCN)=YES); LOOP(RXX(R,P,UC_N), pp_qaput 01
    #   'IRE Process with invalid Parameters'; PUT QLOG ' WARNING       - IRE with UC_FLO:   R=',%RL%,' P=',%PL%,' UC_N=',UC_N.TL)
    qaflo = Sk("UC_QAFLO", 6)
    capflo = S("UC_CAPFLO", 5)
    rxx = Set{NTuple{3,String}}((k[4], k[5], k[2]) for k in qaflo if k[1] == "1" && !(k[2:6] in capflo))
    for (r, p, u) in sorted(rxx)
        put(1, "IRE Process with invalid Parameters", " WARNING       - IRE with UC_FLO:   R=" * q12(r) * " P=" * q12(p) * " UC_N=" * u)
    end
    qa_group!(tm)                                                                       # L230
    # L231-234: LOOP(PRC_MAP(R,'IRE',P)$(RP(R,P)$(NOT RP_IRE(R,P))), pp_qaput 09 'Standard Flow Process with invalid Attributes';
    #   PUT QLOG ' SEVERE ERROR  - Process Group is IRE:  R=',%RL%,' P=',%PL%)
    for (r, _, p) in sorted(k for k in Sk("PRC_MAP", 3) if k[2] == "IRE" && k[1] in regset && (k[1], k[3]) in rp && !((k[1], k[3]) in rp_ire))
        put(9, "Standard Flow Process with invalid Attributes", " SEVERE ERROR  - Process Group is IRE:  R=" * q12(r) * " P=" * q12(p))
    end
    # L235-238: LOOP(UC_QAFLO('2',UC_N,SIDE,RPC(R,P,C)), pp_qaput 01 'Standard Flow Process with invalid Parameters';
    #   PUT QLOG ' WARNING       - FLO flow with UC_IRE:  R=',%RL%,' P=',%PL%,' C=',%CL%,' UC_N=',UC_N.TL)
    for k in sorted(k for k in qaflo if k[1] == "2" && (k[4], k[5], k[6]) in rpc && k[4] in regset)
        put(1, "Standard Flow Process with invalid Parameters",
            " WARNING       - FLO flow with UC_IRE:  R=" * q12(k[4]) * " P=" * q12(k[5]) * " C=" * q12(k[6]) * " UC_N=" * k[2])
    end
    qa_group!(tm)                                                                       # L240

    # L242-252: ACT_EFF groups: OPTION RP_GRP < ACT_EFF less RPC_ACE, RPC_PG and the groups of RPG_ACE and RPG_1ACE;
    #   LOOP(RP_GRP(R,P,CG), IF(NOT SUM((TOP(R,P,C(CG),IO),COM_GMAP(R,CG2,C))$RPG_ACE(R,P,CG2,IO),1), pp_qaput 01
    #   'Invalid Commodity / Group used in ACT_EFF - parameter ignored'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' CG=',CG.TL))
    actef = P("ACT_EFF", 5)
    if !isempty(actef)
        ace, pgc, rpg_ace, rpg_1ace = S("RPC_ACE", 3), S("RPC_PG", 3), Sk("RPG_ACE", 4), Sk("RPG_1ACE", 4)
        ace_g = Set((k[1], k[2], k[3]) for k in rpg_ace)
        one_g = Set((k[1], k[2], k[3]) for k in rpg_1ace)
        one_c = Set((k[1], k[2], k[4]) for k in rpg_1ace)
        com = S("COM", 1)
        rp_grp = Set{NTuple{3,String}}()
        for k in keys(actef.values)
            g = (k[1], k[3], k[4])
            (g in ace || g in pgc || g in ace_g || g in one_g || g in one_c) || push!(rp_grp, g)
        end
        ace_io = Dict{NTuple{2,String},Vector{NTuple{2,String}}}()                      # RPG_ACE by (R,P): (CG2, IO)
        foreach(k -> push!(get!(() -> NTuple{2,String}[], ace_io, (k[1], k[2])), (k[3], k[4])), rpg_ace)
        for (r, p, cg) in sorted(k for k in rp_grp if k[1] in regset)
            ok = (cg,) in com && any(((cg2, io),) -> (r, p, cg, io) in top && (r, cg2, cg) in gmap, get(ace_io, (r, p), NTuple{2,String}[]))
            ok || put(1, "Invalid Commodity / Group used in ACT_EFF - parameter ignored",
                      " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " CG=" * cg)
        end
    end
    qa_group!(tm)                                                                       # L253

    # L255-261: OPTION FSCK <= FLO_SUM; FSCK(RPC_EMIS(R,P,CG),C,CG)$RPC(R,P,C) = NO; LOOP(FSCK(R,P,CG,C,CG2)$(NOT RPC(R,P,C)),
    #   pp_qaput 01 'FLO_SUM Commodity Not in RPC - parameter ignored'; ' WARNING       -     R=',%RL%,' P=',%PL%,' CG=',CG.TL,' C=',C.TL)
    emis = S("RPC_EMIS", 3)
    fsck = Set{NTuple{5,String}}((k[1], k[3], k[4], k[5], k[6]) for k in keys(P("FLO_SUM", 7).values))
    filter!(k -> !((k[1], k[2], k[3]) in emis && k[5] == k[3] && (k[1], k[2], k[4]) in rpc), fsck)
    for (r, p, cg, c, _) in sorted(k for k in fsck if k[1] in regset && !((k[1], k[2], k[4]) in rpc))
        put(1, "FLO_SUM Commodity Not in RPC - parameter ignored", " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " CG=" * cg * " C=" * c)
    end
    qa_group!(tm)                                                                       # L262
    # L264-268: FSCK(RPC(R,P,COM),C,COM)$RPCC_FFUNC(R,P,COM,COM) = NO; LOOP(FSCK(R,P,CG,C,CG2)$(NOT COM_GMAP(R,CG,C)), pp_qaput 01
    #   'FLO_SUM Commodity Not in CG1 - parameter ignored'; ' WARNING       -     R=',%RL%,' P=',%PL%,' CG1=',CG.TL,' C=',C.TL)
    ccff = S("RPCC_FFUNC", 4)
    filter!(k -> !(k[5] == k[3] && (k[1], k[2], k[3]) in rpc && (k[1], k[2], k[3], k[3]) in ccff), fsck)
    for (r, p, cg, c, _) in sorted(k for k in fsck if k[1] in regset && !((k[1], k[3], k[4]) in gmap))
        put(1, "FLO_SUM Commodity Not in CG1 - parameter ignored", " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " CG1=" * cg * " C=" * c)
    end
    qa_group!(tm)                                                                       # L269
    # L271-277: FSCK(RP,C,COM,C)=NO; CG_GRP(R,P,CG1,CG2) from FSCK and from FLO_FUNC both ways;
    #   LOOP(CG_GRP(R,P,CG1,CG2)$CG_GRP(R,P,CG2,CG1), pp_qaput 10 'PTRANS between CG1 and CG2 in both directions';
    #   PUT QLOG ' FATAL ERROR   -     R=',%RL%,' P=',%PL%,' CG1=',CG1.TL,' CG2=',CG2.TL)
    filter!(k -> !(k[3] == k[5] && (k[1], k[2]) in rp), fsck)
    cg_grp = Set{NTuple{4,String}}((k[1], k[2], k[3], k[5]) for k in fsck)
    ff = P("FLO_FUNC", 6)
    for k in keys(ff.values)
        haskey(ff, (k[1], k[2], k[3], k[5], k[4], k[6])) && push!(cg_grp, (k[1], k[3], k[4], k[5]))
    end
    for (r, p, a, b) in sorted(k for k in cg_grp if k[1] in regset && (k[1], k[2], k[4], k[3]) in cg_grp)
        put(10, "PTRANS between CG1 and CG2 in both directions", " FATAL ERROR   -     R=" * q12(r) * " P=" * q12(p) * " CG1=" * a * " CG2=" * b)
    end
    qa_group!(tm)                                                                       # L280

    # L282-304: the topology entries that no ACTFLO, FLO_SHAR, FLO_FUNC or FLO_SUM covers
    cg_grp = Set{NTuple{4,String}}()
    foreach(k -> push!(cg_grp, (k[1], k[3], k[5], k[6])), keys(P("COEF_PTRAN", 7).values))   # OPTION RP_CCG < COEF_PTRAN (G26, G52)
    foreach(k -> push!(cg_grp, (k[1], k[3], k[4], k[5])), keys(P("FLO_SHAR", 7).values))     # OPTION RP_CCG < FLO_SHAR
    rp_grp = Set{NTuple{3,String}}((k[1], k[2], k[4]) for k in cg_grp)                 # OPTION RP_GRP < CG_GRP
    env = S("ENV", 2)
    filter!(k -> !(!((k[1], k[3]) in env) && (k[1], k[4]) in env), cg_grp)             # L289
    trackpc = Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in cg_grp)                # L290
    foreach(k -> k in rpc || push!(rp_grp, k), collect(trackpc))                       # L291
    foreach(k -> k in rpc && push!(trackpc, k), rp_grp)                                # L292
    filter!(k -> !(k in rpc), rp_grp)
    gmap_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], gmap_of, (k[1], k[2])), k[3]), gmap)
    for (r, p, cg) in rp_grp, c in get(gmap_of, (r, cg), String[])                     # L293
        (r, p, c) in rpc && push!(trackpc, (r, p, c))
    end
    rpc_ace = S("RPC_ACE", 3)                                                           # L294 (RPG_ACE is defined)
    ace_rp = Set((k[1], k[2]) for k in Sk("RPG_ACE", 4))
    foreach(k -> (k[1], k[2]) in ace_rp && push!(trackpc, k), rpc_ace)
    union!(trackpc, S("RPC_PG", 3))                                                     # L295
    foreach(k -> (k[1], k[2]) in rp_ire && push!(trackpc, k), rpc)                     # L296
    stg = S("RPC_STG", 3)
    foreach(k -> k in stg && push!(trackpc, k), S("RPC_SPG", 3))                        # L297
    union!(trackpc, S("RPC_NOFLO", 3), S("RPC_FFUNC", 3))                               # L298-299
    vflo = Set((k[1], k[2], k[3]) for k in Sk("OBJ_VFLO", 5))
    foreach(k -> k in vflo && push!(trackpc, k), S("RMKC", 3))                          # L300
    vara = S("RTP_VARA", 3)                                                             # L301
    trackp = Set{NTuple{2,String}}(k for k in std if any(t -> (k[1], t[1], k[2]) in vara, T))
    for (r, p, c, io) in sorted(k for k in top if k[1] in regset && (k[1], k[2], k[3]) in rpc && (k[1], k[2]) in trackp &&
                                                  !((k[1], k[2], k[3]) in trackpc))
        put(1, "RPC in TOP not found in any ACTFLO/FLO_SHAR/FLO_FUNC/FLO_SUM",
            " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " C=" * q12(c) * " IO=" * io)
    end
    qa_group!(tm)                                                                       # L307

    # L309-315: RP_GRP(RP_PG(R,P,CG))$(NOT SUM(RPC_PG(R,P,C),1)) = YES; RP_GRP(R,P,%PGPRIM%) = NO;
    #   LOOP(RP_GRP(RP(R,P),CG)$(NOT SUM(RPC(R,P,C)$COM_GMAP(R,CG,C),1)), pp_qaput 01 'Empty Group in FLO_SUM/FLO_FUNC/FLO_SHAR'; ...)
    pg_rp = Set((k[1], k[2]) for k in S("RPC_PG", 3))
    foreach(k -> ((k[1], k[2]) in pg_rp) || push!(rp_grp, k), Sk("RP_PG", 3))
    pgprim = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))
    filter!(k -> uppercase(k[3]) != pgprim, rp_grp)
    for (r, p, cg) in sorted(k for k in rp_grp if k[1] in regset && (k[1], k[2]) in rp &&
                                                 !any(c -> (k[1], k[2], c) in rpc, get(gmap_of, (k[1], k[3]), String[])))
        put(1, "Empty Group in FLO_SUM/FLO_FUNC/FLO_SHAR", " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " CG=" * cg)
    end
    qa_group!(tm)                                                                       # L316

    # L318-322: RVP(RTP(R,V,P))$(SUM(BD$NCAP_AFA(RTP,BD),1)$PRC_TSL(R,P,'ANNUAL')) = YES;
    #   LOOP((RVP(R,V,P),BD)$((NCAP_AF(R,V,P,'ANNUAL',BD) NE 1)$NCAP_AF(R,V,P,'ANNUAL',BD)), pp_qaput 01
    #   'Both NCAP_AF and NCAP_AFA specified for same process'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' V=',V.TL)
    afa, af = P("NCAP_AFA", 4), P("NCAP_AF", 5)
    tsl_ann = Set((k[1], k[2]) for k in Sk("PRC_TSL", 3) if k[3] == "ANNUAL")
    rtp = S("RTP", 3)
    rvp = Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in keys(afa.values) if (k[1], k[2], k[3]) in rtp && (k[1], k[3]) in tsl_ann)
    bds = [k[1] for k in Sk("BD", 1)]
    for (r, v, p) in sorted(rvp), b in bds
        x = get(af.values, (r, v, p, "ANNUAL", b), nothing)
        (x !== nothing && x != 1) || continue
        put(1, "Both NCAP_AF and NCAP_AFA specified for same process", " WARNING       -     R=" * q12(r) * " P=" * q12(p) * " V=" * v)
    end
    qa_group!(tm)                                                                       # L324

    # L326-329: LOOP(RTC(R,T,C)$(ABS(SUM(COM_TS(R,C,S),COM_FR(R,T,C,S))-1) GT 3E-3), pp_qaput 01
    #   'Commodity fractions do not sum up to 1'; PUT QLOG ' WARNING       -     R=',%RL%,' C=',%CL%,' T=',T.TL)
    comfr = P("COM_FR", 4)
    cts = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], cts, (k[1], k[2])), k[3]), Sk("COM_TS", 3))
    for (r, t, c) in sorted(k for k in Sk("RTC", 3) if k[1] in regset && (k[2],) in T)
        s = sum((gv(comfr, (r, t, c, ts)).v for ts in get(cts, (r, c), String[])); init=0.0)
        abs(s - 1) > 3e-3 && put(1, "Commodity fractions do not sum up to 1", " WARNING       -     R=" * q12(r) * " C=" * q12(c) * " T=" * t)
    end
    qa_group!(tm)                                                                       # L330

    # L332-335: LOOP((R,V,P,C)$NCAP_CLED(R,V,P,C), IF(NCAP_CLED(R,V,P,C) > COEF_ILED(R,V,P), pp_qaput 01
    #   'Too Long Commodity Lead Time'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%,' C=',C.TL))
    iled = P("COEF_ILED", 3)
    cled = P("NCAP_CLED", 4)
    for k in sorted(k for k in keys(cled.values) if k[1] in regset)
        cled[k] > Float64(gv(iled, (k[1], k[2], k[3]))) || continue
        put(1, "Too Long Commodity Lead Time", " WARNING       -     R=" * q12(k[1]) * " P=" * q12(k[3]) * " C=" * k[4])
    end
    qa_group!(tm)                                                                       # L336

    # L338-347: the CHP parameters of non-CHP processes (UNCD7('1'..'3',R,V,P,...)); LOOP(UNCD7(J,R,V,P,U2,U3,U4), Z=ORD(J);
    #   pp_qaput 01 'CHP parameter specified for Non-CHP process'; ' WARNING       -     NCAP_' BPME/CHPR/'CEH ' ': R=',%RL%,' P=',%PL%,' V=',V.TL)
    chp = S("CHP", 2)
    bdupx = Set(k[1] for k in Sk("BDUPX", 1))
    rows = NTuple{5,String}[]                                                           # (J,R,V,P,BD)
    foreach(k -> ((k[1], k[3]) in chp) || push!(rows, ("1", k[1], k[2], k[3], "")), keys(P("NCAP_BPME", 3).values))
    foreach(k -> ((k[1], k[3]) in chp || !(k[4] in bdupx)) || push!(rows, ("2", k[1], k[2], k[3], k[4])), keys(P("NCAP_CHPR", 4).values))
    foreach(k -> ((k[1], k[3]) in chp) || push!(rows, ("3", k[1], k[2], k[3], "")), keys(P("NCAP_CEH", 3).values))
    jpos = Dict(k[1] => i for (i, k) in enumerate(Sk("J", 1)))
    rowkey(u) = (u[1], u[2], u[3], u[4])
    keys4 = gams_sort!(unique(rowkey.(rows)), d)
    bdrank = Dict(b => i for (i, b) in enumerate(bds))
    for k4 in keys4, u in sort!(filter(u -> rowkey(u) == k4, rows); by=u -> get(bdrank, u[5], 0))
        (j, r, v, p) = k4
        put(1, "CHP parameter specified for Non-CHP process",
            " WARNING       -     NCAP_" * (j == "1" ? "BPME" : j == "2" ? "CHPR" : "CEH ") * ": R=" * q12(r) * " P=" * q12(p) * " V=" * v)
        gput_scalar!(tm, "Z", jpos[j])
    end
    qa_group!(tm)                                                                       # L348

    # L350-354: LOOP(CHP(RP_PGACT(R,P)), IF(SUM((T,BD)$NCAP_CHPR(R,T,P,BD),1), pp_qaput 01
    #   'PG of CHP process consists of single commodity yet has a CHP-ratio'; PUT QLOG ' SEVERE ERROR  -     R=',%RL%,' P=',%PL%))
    chpr = P("NCAP_CHPR", 4)
    pgact = S("RP_PGACT", 2)
    chpr_rt = Set((k[1], k[2], k[3]) for k in keys(chpr.values))
    for (r, p) in sorted(k for k in chp if k[1] in regset && k in pgact)
        any(t -> (r, t[1], p) in chpr_rt, T) || continue
        put(1, "PG of CHP process consists of single commodity yet has a CHP-ratio", " SEVERE ERROR  -     R=" * q12(r) * " P=" * q12(p))
    end
    qa_group!(tm)                                                                       # L355

    # L357-362: TRACKP(CHP(R,P))=SUM(RTP(R,T,P)$(NOT SUM(BD$NCAP_CHPR(R,T,P,BD),1)),1); LOOP(R, Z=SUM(TRACKP(R,P)$(NOT RP_PGACT(R,P)),1);
    #   IF(Z, pp_qaput 01 'Found CHP processes without CHP-ratio defined';
    #   PUT QLOG ' WARNING       -     R=',%RL%,' Number of PRCs without ratio: ',Z:0:0))
    for r in reg
        z = count(chp) do (rr, p)
            rr == r || return false
            n = count(k -> k[1] == r && k[3] == p && (k[2],) in T && !((r, k[2], p) in chpr_rt), rtp)
            n != 0 && !((r, p) in pgact)
        end
        z == 0 || put(1, "Found CHP processes without CHP-ratio defined",
                      " WARNING       -     R=" * q12(r) * " Number of PRCs without ratio: " * qnum(z, 0, 0))
    end
    qa_group!(tm)                                                                       # L363

    # L365-367: LOOP((CHP_ELC(R,P,C),RPG_PACE(R,P,CG)), pp_qaput 01 'Found CHP processes with PG commodity efficiencies -
    #   unsupported'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%)
    pace = Dict{NTuple{2,String},Int}()
    foreach(k -> (pace[(k[1], k[2])] = get(pace, (k[1], k[2]), 0) + 1), Sk("RPG_PACE", 3))
    for (r, p, _) in sorted(k for k in Sk("CHP_ELC", 3) if k[1] in regset), _ in 1:get(pace, (r, p), 0)
        put(1, "Found CHP processes with PG commodity efficiencies - unsupported", " WARNING       -     R=" * q12(r) * " P=" * q12(p))
    end
    qa_group!(tm)                                                                       # L368

    # L370-372: LOOP(CHP(R,P)$(NOT SUM(RPC_PG(R,P,C)$NRG_TMAP(R,'ELC',C),1)), pp_qaput 01
    #   'Found CHP processes without electricity in the PG'; PUT QLOG ' WARNING       -     R=',%RL%,' P=',%PL%)
    elc = Set((k[1], k[3]) for k in Sk("NRG_TMAP", 3) if k[2] == "ELC")
    pgc_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], pgc_of, (k[1], k[2])), k[3]), S("RPC_PG", 3))
    for (r, p) in sorted(k for k in chp if k[1] in regset && !any(c -> (k[1], c) in elc, get(pgc_of, k, String[])))
        put(1, "Found CHP processes without electricity in the PG", " WARNING       -     R=" * q12(r) * " P=" * q12(p))
    end
    return tm
end

"""
    qack_finish!(tm) -> tm

pp_qack.mod L374-387: ERRLEV 33 writes the alert 'Found severe modeling
errors' (the run goes on, its solution unreliable); a higher ERRLEV aborts
the run (here an error); with nothing written the log gets 'ALL QUALITY
CHECKS PASSED ***' (`PUTOUT\$PUTOUT` leaves PUTOUT 0); PUTOUT, PUTGRP and
ERRLEV are cleared and the log closed.

GAMS: pp_qack.mod L374-387, v4.9.7.
"""
function qack_finish!(tm)
    errlev = gscalar(tm, "ERRLEV")
    if errlev >= 33
        if errlev == 33
            qa_group!(tm)
            pp_qaput!(tm, 33, "Found severe modeling errors (see error code 33 above) ***")
            qput!(qalog(tm), " ERROR ALERT   -     Model Solution is Unreliable         ")
        else
            qclose!(qalog(tm))
            error("pp_qack.mod L380: ABORT '*** FATAL QA ERROR - Check the QA_CHECK.LOG file for details ***' (ERRLEV = $errlev)")
        end
    end
    # L384: $BATINCLUDE pp_qaput PUTOUT$PUTOUT PUTOUT * 'ALL QUALITY CHECKS PASSED ***'
    if iszero(gscalar(tm, "PUTOUT"))
        pp_qaput!(tm, nothing, "ALL QUALITY CHECKS PASSED ***"; grp=false)
        put_qa_scalar!(tm, "PUTOUT", 0)                                                 # PUTOUT$PUTOUT = 1 assigns nothing
    end
    # L385-386: OPTION CLEAR = PUTOUT, CLEAR = PUTGRP, CLEAR = ERRLEV; PUTCLOSE QLOG
    foreach(n -> put_qa_scalar!(tm, n, 0), ("PUTOUT", "PUTGRP", "ERRLEV"))
    qclose!(qalog(tm))
    return tm
end
