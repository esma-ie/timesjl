# M1.2 (3): the process-transformation coefficients of EQ_PTRANS.
#
# GAMS (v4.9.7): coef_ptr.mod L9-54.
#
# FLO_SUM and FLO_FUNC become COEF_PTRAN (L12-34), and the EQ_PTRANS control
# set RPCC_FFUNC and the QA groups of PRC_CG are rebuilt (L44-51). The
# reduced-flow conversion (L36-42) needs KEEP_FLOF or RPCG_PTRAN, which only
# the REDUCE paths fill; no reference run (all REDUCE off) has either, so
# they raise UnportedError, as REDUCE YES does in M1.1.
#
# GAMS semantics this relies on (confirmed on GAMS 54.6.0, docs/discrepancies.md
# G26-G28):
# - `OPTION a <= b` / `OPTION a < b` match a's indices to b's by domain set,
#   left to right (`<=`) or right to left (`<`); a COM position never matches
#   a COM_GRP one, so CG_GRP <= CGTEST(R,LL,P,CG,C,CG) takes positions 4 and
#   6, and `RP_GRP < CG_GRP` takes the second group. A parameter's EPS
#   records are projected like any other.
# - An index that is an alias of a subset filters a set's members: V
#   (MODLYEAR) in CGTEST(R,V,P,...), C (COM) at a COM_GRP position in
#   CGTEST(RTP,C,COM,CG), RTP as the first three indices.
# - EPS in FLO_SUM: `YES$FLO_SUM` is true, `1$(NOT FLO_SUM)` is 0, so the
#   coefficient is EPS (G6, G25); `$= FLO_SUM` stores EPS (G24).

const NO_RTP = NTuple{3,String}[]
const NO_GMAP = NTuple{3,String}[]
const NO_RPCS = NTuple{4,String}[]
const NO_TSL = NTuple{3,String}[]

"The coef_ptr.mod paths this model would take that are not translated; empty when coef_ptr! can run."
function coef_ptr_unported(tm)
    return String[]                   # the reduced flows (L38-42) are translated (draft, 9 Nov 2026)
end

"""
    coef_ptr!(tm) -> tm

coef_ptr.mod on the GAMS state in `tm`: COEF_PTRAN from FLO_SUM and FLO_FUNC
(L12-34), KEEP_FLOF less RPC_AFLO (L37), RPCC_FFUNC and PRC_CG (L45-51),
and the work sets CGTEST, CGTES2, CG_GRP and RP_GRP left empty (L54). The
reduced-flow conversion L38-40 and L42 is refused (see the file header).

GAMS: coef_ptr.mod L9-54, v4.9.7.
"""
function coef_ptr!(tm)
    u = coef_ptr_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    T6 = NTuple{6,String}
    T4 = NTuple{4,String}
    modlyear, com = gset(tm, "MODLYEAR"), gset(tm, "COM")
    inV(v) = (v,) in modlyear
    inC(c) = (c,) in com
    rpc, rtp = gset(tm, "RPC"), gset(tm, "RTP")
    flo_sum, flo_func = gparam_opt(tm.data, "FLO_SUM", 7), gparam_opt(tm.data, "FLO_FUNC", 6)
    com_gmap = indexby(gset(tm, "COM_GMAP"), (1, 2))                 # (r,cg) -> (r,cg,c)
    rtp_by_rp = indexby(rtp, (1, 3))                                  # (r,p) -> (r,v,p)

    # L12-13: SET CGTEST, CGTES2 //   (empty; declared in this file)
    # L15: OPTION CGTEST <= FLO_SUM   (positions 1-6, EPS records included, G26)
    cgtest = Set{T6}(k[1:6] for k in flo_sum.keys)
    # L16: CGTEST(R,V,P,COM_GRP,C,CG)$(NOT RPC(R,P,C)) = NO   (V filters, G27)
    filter!(k -> !(inV(k[2]) && !((k[1], k[3], k[5]) in rpc)), cgtest)

    # (r,v,p,cg1,cg2) with a FLO_FUNC entry (or EPS) at some timeslice
    ffunc = Set{NTuple{5,String}}(k[1:5] for k in flo_func.keys)

    # L18: LOOP((CGTEST(R,V,P,COM_GRP,C,CG),S)$FLO_FUNC(R,V,P,CG,COM_GRP,S), CG_GRP(R,P,COM_GRP,CG) = YES)
    #      (adds to CG_GRP as it stands; it is empty in every reference run's ppm dump)
    cg_grp = Set{T4}(gmembers(tm, "CG_GRP", 4))
    for (r, v, p, cg1, c, cg2) in cgtest
        inV(v) && (r, v, p, cg2, cg1) in ffunc && push!(cg_grp, (r, p, cg1, cg2))
    end

    # L19: CGTES2(RTP(R,V,P),COM_GRP,C,CG)$((COM_GMAP(R,COM_GRP,C)*RPC(R,P,C))$CG_GRP(R,P,COM_GRP,CG)) = YES
    cgtes2 = Set{T6}()
    for (r, p, cg1, cg2) in cg_grp
        for (_, v, _) in get(rtp_by_rp, (r, p), NO_RTP), (_, _, c) in get(com_gmap, (r, cg1), NO_GMAP)
            inV(v) && inC(c) && (r, p, c) in rpc && push!(cgtes2, (r, v, p, cg1, c, cg2))
        end
    end

    # L21: OPTION CG_GRP <= FLO_FUNC   (positions 1, 3, 4, 5)
    cg_grp = Set{T4}((k[1], k[3], k[4], k[5]) for k in flo_func.keys)
    # L22: CGTES2(RTP(R,V,P),COM_GRP,C,CG)$(COM_GMAP(R,COM_GRP,C)$RPC(R,P,C)$CG_GRP(R,P,COM_GRP,CG))
    #        $= SUM(S$FLO_FUNC(RTP,COM_GRP,CG,S),1)
    for (r, v, p, cg1, cg2) in ffunc                       # the SUM is >= 1 exactly here
        (inV(v) && (r, v, p) in rtp && (r, p, cg1, cg2) in cg_grp) || continue
        for (_, _, c) in get(com_gmap, (r, cg1), NO_GMAP)
            inC(c) && (r, p, c) in rpc && push!(cgtes2, (r, v, p, cg1, c, cg2))
        end
    end
    # L23: CGTES2(CGTEST(RTP,C,COM,CG)) $= CGTES2(RTP,C,C,CG)   (right side read before the statement, G11)
    add = T6[]
    for (r, v, p, x, c, cg) in cgtest
        (r, v, p) in rtp && inC(x) && (r, v, p, x, x, cg) in cgtes2 && push!(add, (r, v, p, x, c, cg))
    end
    union!(cgtes2, add)
    # L24: OPTION CG_GRP <= CGTEST   (positions 1, 3, 4, 6: the COM position 5 is skipped, G26)
    cg_grp = Set{T4}((k[1], k[3], k[4], k[6]) for k in cgtest)

    # L27-33: COEF_PTRAN(CGTES2(R,V,P,COM_GRP,C,CG),S)$((YES$FLO_SUM(CGTES2,S)+(NOT CG_GRP(R,P,CG,COM_GRP)))
    #           $RPCS_VAR(R,P,C,S)) = SUM((PRC_TSL(R,P,TSL),TS_GROUP(R,TSL,TS))$TS_MAP(R,TS,S),
    #           ((1+(1/FLO_FUNC(R,V,P,CG,COM_GRP,TS)-1)$FLO_FUNC(R,V,P,CG,COM_GRP,TS))$(NOT FLO_FUNC(R,V,P,COM_GRP,CG,TS))
    #            + FLO_FUNC(R,V,P,COM_GRP,CG,TS)) * (1$(NOT FLO_SUM(CGTES2,S)) + FLO_SUM(CGTES2,S)))
    coef_ptran = gvalues(tm, "COEF_PTRAN", 7)
    rpcs_var = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))              # (r,p,c) -> (r,p,c,s)
    prc_tsl = indexby(gset(tm, "PRC_TSL"), (1, 2))                    # (r,p) -> (r,p,tsl)
    ts_group = indexby(gset(tm, "TS_GROUP"), (1, 2))                  # (r,tsl) -> (r,tsl,ts)
    ts_map = gset(tm, "TS_MAP")
    one = GNum(1)
    for k in cgtes2
        r, v, p, cg1, c, cg2 = k
        inV(v) || continue
        for (_, _, _, s) in get(rpcs_var, (r, p, c), NO_RPCS)
            hfs = haskey(flo_sum, (k..., s))
            (hfs || !((r, p, cg2, cg1) in cg_grp)) || continue
            fs = gif(one, !hfs) + gv(flo_sum, (k..., s))
            x = GZERO
            for (_, _, tsl) in get(prc_tsl, (r, p), NO_TSL), (_, _, ts) in get(ts_group, (r, tsl), NO_TSL)
                (r, ts, s) in ts_map || continue
                k12, k21 = (r, v, p, cg1, cg2, ts), (r, v, p, cg2, cg1, ts)
                # a guarded term is not evaluated when its condition is false (G14): no 1/EPS error then
                ff = haskey(flo_func, k12) ? GZERO + gv(flo_func, k12) :
                     one + (haskey(flo_func, k21) ? one / gv(flo_func, k21) - one : GZERO)
                x += ff * fs
            end
            gassign!(coef_ptran, (k..., s), x)
        end
    end
    # L34: COEF_PTRAN(CGTEST(R,V,P,CG,C,CG2),S)$((NOT CGTES2(CGTEST))$RPCS_VAR(R,P,C,S)) $= FLO_SUM(CGTEST,S)
    for k in cgtest
        (inV(k[2]) && !(k in cgtes2)) || continue
        for (_, _, _, s) in get(rpcs_var, (k[1], k[3], k[5]), NO_RPCS)
            haskey(flo_sum, (k..., s)) && gassign!(coef_ptran, (k..., s), gv(flo_sum, (k..., s)))
        end
    end
    gput!(tm, "COEF_PTRAN", coef_ptran)

    # L37: KEEP_FLOF(RPC_AFLO(R,P,C)) = NO
    rpc_aflo = gset_opt(tm.data, "RPC_AFLO", 3)
    keep_flof = Set(k for k in gmembers(tm, "KEEP_FLOF", 3) if !(inC(k[3]) && k in rpc_aflo))
    gput!(tm, "KEEP_FLOF", keep_flof)
    # L38-40: ACT_FLO(RTP(R,V,P),C,S)$(RPCS_VAR(R,P,C,S)$KEEP_FLOF(R,P,C)) =
    #   SUM((RPCG_PTRAN(RPC_ACT(R,P,COM),C,CG,CG4),PRC_TS(R,P,TS))$TS_MAP(R,TS,S),PRC_ACTFLO(RTP,COM)*COEF_PTRAN(RTP,CG,COM,CG4,TS)) +
    #   SUM(RPCG_PTRAN(R,P,C,COM,CG,CG4)$COEF_PTRAN(RTP,CG,C,CG4,S),PRC_ACTFLO(RTP,COM)/COEF_PTRAN(RTP,CG,C,CG4,S))
    ptran = gset_opt(tm.data, "RPCG_PTRAN", 6).keys
    if !isempty(keep_flof)
        act_flo = gvalues(tm, "ACT_FLO", 5)
        actflo = gparam(tm, "PRC_ACTFLO")
        rpc_act = gset_opt(tm.data, "RPC_ACT", 3).members
        prc_ts = indexby(gset(tm, "PRC_TS"), (1, 2))
        tsmap = gset(tm, "TS_MAP").members
        by_red = indexby(gset_opt(tm.data, "RPCG_PTRAN", 6), (1, 2, 4))      # (R,P,C) at position 4
        by_c3 = indexby(gset_opt(tm.data, "RPCG_PTRAN", 6), (1, 2, 3))       # (R,P,C) at position 3
        keep_of = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(() -> String[], keep_of, (k[1], k[2])), k[3]), keep_flof)
        for (r, v, p) in rtp.keys, c in get(keep_of, (r, p), String[])
            for (_, _, _, s) in get(rpcs_var, (r, p, c), NO_RPCS)
                x = GZERO
                for (_, _, com, _, cg, cg4) in get(by_red, (r, p, c), NTuple{6,String}[])
                    (r, p, com) in rpc_act || continue
                    for (_, _, ts) in get(prc_ts, (r, p), NTuple{3,String}[])
                        (r, ts, s) in tsmap || continue
                        x += gv(actflo, (r, v, p, com)) * gv(coef_ptran, (r, v, p, cg, com, cg4, ts))
                    end
                end
                for (_, _, _, com, cg, cg4) in get(by_c3, (r, p, c), NTuple{6,String}[])
                    y = gv(coef_ptran, (r, v, p, cg, c, cg4, s))
                    iszero(y) || (x += gv(actflo, (r, v, p, com)) / y)
                end
                gassign!(act_flo, (r, v, p, c, s), x)
            end
        end
        gput!(tm, "ACT_FLO", act_flo)
    end
    # L41: CGTEST(CGTES2) = YES
    union!(cgtest, cgtes2)
    # L42: COEF_PTRAN(CGTEST(R,V,P,CG,C,COM),S)$RPCG_PTRAN(R,P,C,COM,CG,COM) = 0
    if !isempty(ptran)
        pt = Set(ptran)
        filter!(kv -> !(kv[1][1:6] in cgtest && (kv[1][1], kv[1][3], kv[1][5], kv[1][6], kv[1][4], kv[1][6]) in pt), coef_ptran)
        gput!(tm, "COEF_PTRAN", coef_ptran)
    end

    # L45: OPTION CG_GRP <= CGTEST; L46: CG_GRP(RPCC_FFUNC) = NO; L47: OPTION RPCC_FFUNC <= CG_GRP
    rpcc_ffunc = gset(tm, "RPCC_FFUNC")
    cg_grp = Set{T4}((k[1], k[3], k[4], k[6]) for k in cgtest)
    filter!(k -> !(k in rpcc_ffunc), cg_grp)
    # L50: OPTION RP_GRP <= CG_GRP; PRC_CG(RP_GRP)=YES; OPTION RP_GRP < CG_GRP; PRC_CG(RP_GRP)=YES
    prc_cg = gmembers(tm, "PRC_CG", 3)
    for (r, p, cg1, cg2) in cg_grp
        push!(prc_cg, (r, p, cg1), (r, p, cg2))
    end
    gput!(tm, "PRC_CG", prc_cg)
    # L51: RPCC_FFUNC(R,P,CG,C)$(RC(R,C)$(NOT RPC(R,P,C))) = NO
    rc = gset(tm, "RC")
    filter!(k -> !(inC(k[4]) && (k[1], k[4]) in rc && !((k[1], k[2], k[4]) in rpc)), cg_grp)
    gput!(tm, "RPCC_FFUNC", cg_grp)

    # L54: OPTION CLEAR=CG_GRP, CLEAR=RP_GRP, CLEAR=CGTEST, CLEAR=CGTES2
    gput!(tm, "CG_GRP", Set{T4}())
    gput!(tm, "RP_GRP", Set{NTuple{3,String}}())
    gput!(tm, "CGTEST", Set{T6}())
    gput!(tm, "CGTES2", Set{T6}())
    return tm
end

