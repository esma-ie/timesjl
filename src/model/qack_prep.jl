# M1.3 change 25-4: the data statements of bndmain.mod, pp_qack.mod and pp_clean.mod, the end of
# the coef -> pre-solve step (maindrv.mod L92-111, v4.9.7).
#
# bndmain.mod sets bounds (`bndmain.jl`, which reads the data as this step leaves it) and changes a
# few parameters on the way: NCAP_BND and CAP_BND (L44-45, L51), UC_TS_SUM (L73), and in its
# includes FLO_BND and TRACKPC (bnd_flo.mod L16-24), the storage bounds (bnd_stg.mod L17-27),
# FLO_CUM, COM_CUM and RC_CUMCOM (bnd_cum.mod L12-20, L27-38). pp_qack.mod completes the generation control sets
# (L45-60: RPC_CONLY, RTPCS_VARF, RCS_COMBAL, RPG_RED, RTP, RTP_VNTBYR, COEF_VNT, RVP_KMAP) and PRC_CG
# (L150, L164) and runs the quality checks; their scratch sets are cleared again, but TS_ARRAY,
# PRC_YMAX, UNCD7 and Z keep what the checks leave. solve.mod L1 includes pp_clean.mod, which zeroes
# FLO_SUM, FLO_FUNC, NCAP_AF, NCAP_AFA, NCAP_AFS and the cost attributes to free memory unless
# MEMCLEAN is NO. The QA log (PUT QLOG, pp_qaput.mod, PUTOUT/PUTGRP/ERRLEV) is written by qack_log.jl (change 25b-2).
#
# Not translated (UnportedError): nested user constraints (pp_qack.mod L53, UC_UCN data); %TIMESED%
# (L97); stochastic or stepped runs.

"""
    qack_prep_symbols(tm) -> Vector{String}

The sets and parameters `bnd_data!`, `pp_qack_data!` and `pp_clean!` settle.
"""
qack_prep_symbols(tm) = ["NCAP_BND", "CAP_BND", "UC_TS_SUM", "UC_RHS", "UC_RHSR", "UC_RHST", "UC_RHSRT", "UC_RHSTS",
                         "UC_RHSRTS", "CNT", "FLO_BND", "FLO_CUM", "COM_CUM", "RC_CUMCOM", "RPC_CONLY", "RTPCS_VARF",
                         "RCS_COMBAL", "RPG_RED", "UC_GMAP_U", "RTP", "RTP_VNTBYR", "COEF_VNT", "RVP_KMAP", "TRACKPC",
                         "TRACKP", "RP_XRED", "TS_ARRAY", "TRACKC", "PRC_CG", "PRC_YMAX", "RXX", "FSCK", "CG_GRP",
                         "RP_CCG", "RP_GRP", "RVP", "UNCD7", "FLO_SUM", "FLO_FUNC", "NCAP_AF", "NCAP_AFA", "NCAP_AFS",
                         "NCAP_COST", "NCAP_FOM", "ACT_COST", "FLO_TAX", "FLO_SUB", "FLO_COST", "FLO_DELIV"]

"""
    bnd_data!(tm) -> tm

The data statements of bndmain.mod and its includes (the bounds themselves are `bndmain.jl`):

    FLO_BND(R,T,P,C,S,'LO')\$((NOT RPC_EMIS(R,P,C))\$(FLO_BND(R,T,P,C,S,'LO')=0)\$RP_FLO(R,P))=0;      (bnd_flo.mod L16)
    LOOP((RTPC(R,T,P,C),S,BD)\$FLO_BND(RTPC,S,BD),TRACKPC(RP_FLO(R,P),C)=YES);                       (L17)
    TRACKPC(PRC_VINT(R,P),C) = NO; TRACKPC(RPC_FFUNC(R,P,C))= NO; TRACKPC(RPC_EMIS(R,P,C)) = NO;      (L18-20)
    LOOP(T,FLO_BND(R,'0',P,C,S,BD)\$FLO_BND(R,T,P,C,S,BD) = EPS\$(NOT TRACKPC(R,P,C));
           FLO_BND(R,'0',P,CG,S,BD)\$((NOT C(CG))\$FLO_BND(R,T,P,CG,S,BD)) = EPS);                   (L22-23)
    TRACKPC(RPC_ACT(R,P,C)) = NO;                                                                    (L24)
    TRACKP(RP(R,P))\$((NOT PRC_VINT(R,P))\$PRC_MAP(R,'STG',P)) = YES;
    STG%2_BND(R,T,P,C,S,BD)\$((NOT TOP(R,P,C,'%2'))\$RP_STG(R,P)) = 0; ... OPTION CLEAR=TRACKP;      (bnd_stg.mod L17-27, IN and OUT)
    NCAP_BND(RTP_OFF,'UP') = EPS;                                                                    (bndmain.mod L44)
    NCAP_BND(RTP(R,T,P),'LO')\$(NCAP_BND(RTP,'UP')\$NCAP_BND(RTP,'LO')) = SMIN(BDNEQ,NCAP_BND(RTP,BDNEQ));   (L45)
    CAP_BND(RTP(RTP_VARP),'LO')\$CAP_BND(RTP,'UP') = SMIN(BDNEQ,CAP_BND(RTP,BDNEQ));                (L51)
    [bnd_cum.mod L12-20 on FLO_CUM, L27-38 on COM_CUM and RC_CUMCOM: `bnd_cum_flo`, `bnd_cum_com`]
    UC_TS_SUM(R,UC_N(OBV),S) = NO;                                                                   (L73)

%DFLBL% is '0' (initmty.mod L367). The bnd_cum.mod statements are applied here and only here:
with an 'N' record a second pass would not leave the data as it is (bndmain.jl takes the bounds
from the stored tables).

GAMS: bndmain.mod L15-79, bnd_flo.mod L16-24, bnd_stg.mod L17-27, bnd_cum.mod L12-20 and L27-38,
v4.9.7.
"""
function bnd_data!(tm::TimesModel)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    nz(x::GNum) = x.v != 0 || x.eps
    T = S("MILESTONYR", 1)
    rtp = S("RTP", 3)
    # bnd_flo.mod L16-24
    flo_bnd = gvalues(tm, "FLO_BND", 6)
    rpc_emis, rp_flo = S("RPC_EMIS", 3), S("RP_FLO", 2)
    for (k, x) in collect(flo_bnd)
        (r, t, p, c, s, bd) = k
        (bd == "LO" && x == 0.0 && !((r, p, c) in rpc_emis) && (r, p) in rp_flo) && delete!(flo_bnd, k)   # an EPS LO bound
    end
    trackpc = gmembers(tm, "TRACKPC", 3)
    rtpc = S("RTPC", 4)
    for (r, t, p, c, s, bd) in keys(flo_bnd)
        ((r, t, p, c) in rtpc && (r, p) in rp_flo) && push!(trackpc, (r, p, c))
    end
    vint, ffunc = S("PRC_VINT", 2), S("RPC_FFUNC", 3)
    filter!(k -> !((k[1], k[2]) in vint || k in ffunc || k in rpc_emis), trackpc)
    # L22-23: LOOP(T, FLO_BND(R,'0',P,C,S,BD)$FLO_BND(R,T,P,C,S,BD) = EPS$(NOT TRACKPC(R,P,C)); ... groups: EPS)
    cset = S("COM", 1)
    for (r, t, p, c, s, bd) in [k for k in keys(flo_bnd) if (k[2],) in T]
        if (c,) in cset
            gassign!(flo_bnd, (r, "0", p, c, s, bd), (r, p, c) in trackpc ? GZERO : GEPS)
        else
            gassign!(flo_bnd, (r, "0", p, c, s, bd), GEPS)
        end
    end
    filter!(k -> !(k in S("RPC_ACT", 3)), trackpc)
    gput!(tm, "FLO_BND", flo_bnd); gput!(tm, "TRACKPC", trackpc)
    # bnd_stg.mod L17-27 (SIN with IN, SOUT with OUT)
    top, rp_stg = S("TOP", 4), S("RP_STG", 2)
    for (io, name) in (("IN", "STGIN_BND"), ("OUT", "STGOUT_BND"))
        b = gvalues(tm, name, 6)
        filter!(((k, _),) -> !(!((k[1], k[3], k[4], io) in top) && (k[1], k[3]) in rp_stg), b)
        gput!(tm, name, b)
    end
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    # bndmain.mod L44-45: NCAP_BND
    ncap_bnd = gvalues(tm, "NCAP_BND", 4)
    for k in S("RTP_OFF", 3)
        gassign!(ncap_bnd, (k..., "UP"), GEPS)
    end
    for (r, t, p) in rtp
        (t,) in T || continue
        up, lo = gv(ncap_bnd, (r, t, p, "UP")), gv(ncap_bnd, (r, t, p, "LO"))
        (nz(up) && nz(lo)) && gassign!(ncap_bnd, (r, t, p, "LO"), gmin(lo, up))
    end
    gput!(tm, "NCAP_BND", ncap_bnd)
    # L51: CAP_BND
    cap_bnd = gvalues(tm, "CAP_BND", 4)
    varp = S("RTP_VARP", 3)
    for (r, t, p) in rtp
        ((r, t, p) in varp && nz(gv(cap_bnd, (r, t, p, "UP")))) || continue
        gassign!(cap_bnd, (r, t, p, "LO"), gmin(gv(cap_bnd, (r, t, p, "LO")), gv(cap_bnd, (r, t, p, "UP"))))
    end
    gput!(tm, "CAP_BND", cap_bnd)
    # bnd_cum.mod L12-20 and L27-38: FLO_CUM, COM_CUM and RC_CUMCOM as the statements before the bounds leave
    # them (`bnd_cum_flo`, `bnd_cum_com`, bndmain.jl); `bnd_cum!` then reads the bounds from them as stored
    stored(tab) = (vals = Dict{keytype(tab),Float64}(); foreach(((k, x),) -> gassign!(vals, k, x), tab); vals)
    Reference.has_symbol(d.dump, "FLO_CUM") && gput!(tm, "FLO_CUM", stored(bnd_cum_flo(tm)))
    if Reference.has_symbol(d.dump, "COM_CUM")
        ctab, rc_cumcom = bnd_cum_com(tm)
        gput!(tm, "COM_CUM", stored(ctab)); gput!(tm, "RC_CUMCOM", rc_cumcom)
    end
    # bnd_ucw.mod L13 (VAR_UC YES): CNT=0; bnd_ucv.mod L35, each UC right-hand side:
    # %5(...,'UP')$((NOT %5(...,'UP'))$%5(...,'N')) = INF
    if var_uc(tm)
        gput_scalar!(tm, "CNT", 0.0)
        for (name, n) in (("UC_RHS", 2), ("UC_RHSR", 3), ("UC_RHST", 3), ("UC_RHSRT", 4), ("UC_RHSTS", 4), ("UC_RHSRTS", 5))
            vals = gvalues(tm, name, n)
            for k in [k for k in keys(vals) if k[end] == "N"]
                ku = (k[1:end-1]..., "UP")
                haskey(vals, ku) || (vals[ku] = Inf)
            end
            Reference.has_symbol(d.dump, name) && gput!(tm, name, vals)
        end
    end
    # L73: UC_TS_SUM(R,UC_N(OBV),S) = NO
    obv = Set(k[1] for k in S("OBV", 1))
    gput!(tm, "UC_TS_SUM", filter(k -> !(k[2] in obv), gmembers(tm, "UC_TS_SUM", 3)))
    return tm
end

"""
    pp_qack_data!(tm) -> tm

The data statements of pp_qack.mod, with its QA checks (`qack_checks!`, qack_log.jl, M1.3 change 25b-2)
called where the file makes them and the end of the file (`qack_finish!`: the ERRLEV abort, the
scalars cleared):

    RPC_CONLY(RTPC(R,T,P,C))\$RPC_NOFLO(R,P,C) = YES; RTPCS_VARF(RPC_CONLY,S) = NO;                (L45-47)
    RCS_COMBAL(RHS_COMBAL,BDNEQ) = NO;                                                              (L49)
    TRACKPC(R,P,C)\$(RPC_ACT(R,P,C)+RPC_FFUNC(R,P,C)+RPC_EMIS(R,P,C)) = YES;
    RPG_RED(R,P,CG,IO)\$(NOT SUM(TOP(TRACKPC(R,P,C),IO)\$COM_GMAP(R,CG,C),1)) = NO;                  (L51-52)
    OPTION UC_GMAP_U<=UC_UCN; RTP(NO_RVP) = NO;                                                     (L53-54)
    OPTION RTP_VNTBYR < RTP_VINTYR, COEF_VNT < COEF_CPT, TRACKP < RP_UPL;                           (L56)
    TRACKP(R,P)\$=SUM(RP_PL(R,P,L),1); TRACKP(RP_XRED)=YES; TRACKP(CHP)=YES;                        (L57)
    RVP_KMAP(RTP(R,V,P),V)\$(PRC_VINT(R,P)\$TRACKP(R,P)) = YES; TRACKP(PRC_VINT)=NO;                (L58)
    RVP_KMAP(RTP(R,T,P),V)\$(COEF_VNT(RTP,V)\$TRACKP(R,P)) = YES;                                   (L59)
    OPTION CLEAR=TRACKPC,CLEAR=TRACKP,CLEAR=RP_XRED;                                                (L60)
    LOOP(R, TS_ARRAY(S) = 0; LOOP(TS_MAP(R,TS,S)\$(G_YRFR(R,S) EQ 0), TS_ARRAY(S) = 1); ...);       (L65-70)
    [L129-140: TRACKC, cleared]  [L146-150: TRACKPC, PRC_CG cleared]
    PRC_YMAX(RP)=SUM(RP_PG(RP,CG),1)-1;                                                             (L153)
    PRC_CG(RP_PG(R,P,CG))\$=SUM(RPC_AFLO(R,P,C)\$(NOT RPC_FFUNC(R,P,C)),1);                          (L164)
    OPTION PRC_YMAX < PRC_REFIT; PRC_YMAX(RP)\$(PRC_YMAX(RP)=1)=0;                                  (L172)
    IF(CARD(RP_UPL), ...; OPTION CLEAR=TRACKP,CLEAR=PRC_YMAX);                                      (L177-182)
    [with %VDA% and %XTQA%: L207-372, scratch sets for the extended checks; what survives is
     UNCD7 of the CHP check (L339-342) and Z of the CHP ratio check (L358-363)]

`OPTION a < b` of two parameters copies b's values when a has b's dimension (a permutation)
and counts b's records per projected tuple when it has fewer (G31), matching repeated domains
from the right (G52). An EXECERROR (L185-201) is assumed absent.

GAMS: pp_qack.mod L45-372, v4.9.7.
"""
function pp_qack_data!(tm::TimesModel)
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    nz(x::GNum) = x.v != 0 || x.eps
    uppercase(gswitch(tm, "TIMESED", "")) == "YES" && throw(UnportedError("pp_qack.mod L97: %TIMESED%"))
    isempty(P("UC_UCN", 5)) || throw(UnportedError("pp_qack.mod L53: nested user constraints (UC_UCN)"))
    qack_open!(tm)                                                             # L37-41
    T = S("MILESTONYR", 1)
    # L45-47
    noflo = S("RPC_NOFLO", 3)
    conly = gmembers(tm, "RPC_CONLY", 4)
    for (r, t, p, c) in S("RTPC", 4)
        (r, p, c) in noflo && push!(conly, (r, t, p, c))
    end
    gput!(tm, "RPC_CONLY", conly)
    gput!(tm, "RTPCS_VARF", filter(k -> !((k[1], k[2], k[3], k[4]) in conly), gmembers(tm, "RTPCS_VARF", 5)))
    # L49
    rhs_combal = S("RHS_COMBAL", 4)
    gput!(tm, "RCS_COMBAL", filter(k -> !(k[5] in ("LO", "UP") && (k[1], k[2], k[3], k[4]) in rhs_combal),
                                   gmembers(tm, "RCS_COMBAL", 5)))
    # L51-52
    trackpc = gmembers(tm, "TRACKPC", 3)
    union!(trackpc, S("RPC_ACT", 3), S("RPC_FFUNC", 3), S("RPC_EMIS", 3))
    gmap_of = indexby(S("COM_GMAP", 3), (1, 2))
    top = S("TOP", 4)
    rpg_red = filter(gmembers(tm, "RPG_RED", 4)) do (r, p, cg, io)
        any(k -> (r, p, k[3]) in trackpc && (r, p, k[3], io) in top, get(gmap_of, (r, cg), NTuple{3,String}[]))
    end
    gput!(tm, "RPG_RED", rpg_red)
    # L53-54
    gput!(tm, "UC_GMAP_U", Set{NTuple{3,String}}())
    no_rvp = S("NO_RVP", 3)
    rtp = filter(k -> !(k in no_rvp), gmembers(tm, "RTP", 3))
    gput!(tm, "RTP", rtp)
    # L56: RTP_VNTBYR(R,T,P,V) < RTP_VINTYR(R,V,T,P); COEF_VNT(R,T,P,V) < COEF_CPT(R,V,T,P); TRACKP < RP_UPL
    gput!(tm, "RTP_VNTBYR", Set((r, t, p, v) for (r, v, t, p) in S("RTP_VINTYR", 4)))
    coef_vnt = Dict{NTuple{4,String},Float64}()                               # same dimension: values copied (G31)
    for ((r, v, t, p), x) in P("COEF_CPT", 4).values
        coef_vnt[(r, t, p, v)] = x
    end
    gput!(tm, "COEF_VNT", coef_vnt)
    trackp = Set((k[1], k[2]) for k in S("RP_UPL", 3))
    # L57
    foreach(k -> push!(trackp, (k[1], k[2])), S("RP_PL", 3))
    union!(trackp, S("RP_XRED", 2), S("CHP", 2))
    # L58-59
    vint = S("PRC_VINT", 2)
    rvp_kmap = gmembers(tm, "RVP_KMAP", 4)
    for (r, v, p) in rtp
        ((r, p) in vint && (r, p) in trackp) && push!(rvp_kmap, (r, v, p, v))
    end
    filter!(k -> !(k in vint), trackp)
    for (r, t, p, v) in keys(coef_vnt)
        ((r, t, p) in rtp && (t,) in T && (r, p) in trackp) && push!(rvp_kmap, (r, t, p, v))
    end
    gput!(tm, "RVP_KMAP", rvp_kmap)
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}()); gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RP_XRED", Set{NTuple{2,String}}())
    # L65-66: TS_ARRAY as the last region leaves it
    g_yrfr = P("G_YRFR", 2)
    regs = [k[1] for k in S("REG", 1).keys]
    ts_array = Dict{Tuple{String},Float64}()
    if !isempty(regs)
        r = regs[end]
        for (rr, ts, s) in S("TS_MAP", 3)
            (rr == r && gv(g_yrfr, (r, s)).v == 0) && (ts_array[(s,)] = 1.0)
        end
    end
    gput!(tm, "TS_ARRAY", ts_array)
    # L62-159: the QA checks on the state they see (PRC_CG before L147 and L160)
    foreach(part -> qack_checks!(tm, part), (:yrfr, :topology, :commodity, :demand, :phantom, :pcg))
    # L129-150: TRACKC, TRACKPC and PRC_CG cleared
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())
    # L164: PRC_CG(RP_PG(R,P,CG)) $= SUM(RPC_AFLO(R,P,C)$(NOT RPC_FFUNC(R,P,C)),1)
    aflo_of = indexby(S("RPC_AFLO", 3), (1, 2))
    ffunc = S("RPC_FFUNC", 3)
    prc_cg = Set{NTuple{3,String}}()
    for (r, p, cg) in S("RP_PG", 3)
        any(k -> !(k in ffunc), get(aflo_of, (r, p), NTuple{3,String}[])) && push!(prc_cg, (r, p, cg))
    end
    gput!(tm, "PRC_CG", prc_cg)
    # L161-182: the QA checks after L160
    foreach(part -> qack_checks!(tm, part), (:fsemit, :refit, :afx))
    # L172: OPTION PRC_YMAX < PRC_REFIT (counts per (R, the last PRC)); entries of 1 removed
    ymax = Dict{NTuple{2,String},Float64}()
    for (r, prc, p) in P("PRC_REFIT", 3).keys
        ymax[(r, p)] = get(ymax, (r, p), 0.0) + 1
    end
    filter!(((k, x),) -> x != 1, ymax)
    isempty(S("RP_UPL", 3)) || empty!(ymax)                                    # L182
    gput!(tm, "PRC_YMAX", ymax)
    # L207-372 (extended checks, %VDA% and %XTQA%): scratch sets end cleared, but UNCD7 and Z remain
    xtqa = uppercase(gswitch(tm, "VDA", "")) == "YES" &&
           (uppercase(gswitch(tm, "XTQA", "")) == "YES" || uppercase(gswitch(tm, "DEBUG", "")) == "YES")
    if xtqa
        qack_checks!(tm, :xtqa)                                                # the checks (qack_log.jl)
        gput!(tm, "RXX", Set{NTuple{3,String}}())
        for (name, n) in (("FSCK", 5), ("CG_GRP", 4), ("RP_CCG", 4), ("RP_GRP", 3), ("RVP", 3))
            gput!(tm, name, Set{NTuple{n,String}}())
        end
        chp = S("CHP", 2)
        uncd7 = Set{NTuple{7,String}}()                                        # L339-342
        for (r, v, p) in P("NCAP_BPME", 3).keys
            (r, p) in chp || push!(uncd7, ("1", r, v, p, "", "", ""))
        end
        for (r, v, p, bd) in P("NCAP_CHPR", 4).keys
            ((r, p) in chp || !(bd in ("UP", "FX"))) || push!(uncd7, ("2", r, v, p, bd, "", ""))
        end
        for (r, v, p) in P("NCAP_CEH", 3).keys
            (r, p) in chp || push!(uncd7, ("3", r, v, p, "", "", ""))
        end
        isempty(uncd7) || register_uel!(d, "")                                 # '' of L339-341, in no dump record (G36)
        gput!(tm, "UNCD7", uncd7)
        # L358-363: Z = SUM(TRACKP(R,P)$(NOT RP_PGACT(R,P)),1) for the last region
        chpr, pgact, rtp_ = P("NCAP_CHPR", 4), S("RP_PGACT", 2), S("RTP", 3)
        if !isempty(regs)
            r = regs[end]
            z = count(chp.keys) do (rr, p)
                rr == r || return false
                n = count(k -> k[1] == r && k[3] == p && (k[2],) in T &&
                               !any(bd -> haskey(chpr, (r, k[2], p, bd)), ("LO", "UP", "FX")), rtp_.keys)
                n != 0 && !((r, p) in pgact)
            end
            gput_scalar!(tm, "Z", z)
        end
    end
    qack_finish!(tm)                                                           # L374-387
    return tm
end

"""
    pp_clean!(tm) -> tm

pp_clean.mod L1-14 (solve.mod L1): unless MEMCLEAN is NO, FLO_SUM, FLO_FUNC, NCAP_AF, NCAP_AFA,
NCAP_AFS, NCAP_COST, NCAP_FOM, ACT_COST, FLO_TAX, FLO_SUB, FLO_COST and FLO_DELIV are set to 0,
which removes every record (the coefficients built from them stay).

GAMS: pp_clean.mod L1-14, v4.9.7.
"""
function pp_clean!(tm::TimesModel)
    uppercase(gswitch(tm, "MEMCLEAN", "")) == "NO" && return tm
    for (name, n) in (("FLO_SUM", 7), ("FLO_FUNC", 6), ("NCAP_AF", 5), ("NCAP_AFA", 4), ("NCAP_AFS", 5),
                      ("NCAP_COST", 4), ("NCAP_FOM", 4), ("ACT_COST", 4), ("FLO_TAX", 6), ("FLO_SUB", 6),
                      ("FLO_COST", 6), ("FLO_DELIV", 6))
        Reference.has_symbol(tm.data.dump, name) && gput!(tm, name, Dict{NTuple{n,String},Float64}())
    end
    return tm
end
