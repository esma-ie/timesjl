# M1.2 (7): the VDA extension's coefficient stage, after coefmain.mod.
#
# GAMS (v4.9.7): coef_ext.vda L12-83, as maindrv.mod L73 includes it through
# main_ext.mod for the VDA extension (initmty.mod L458: VDA is always in
# %EXTEND%). The other extensions' coef_ext files (coef_ext.etl, .cli, .abs
# and the MACRO ones) are refused when their switch is set.
#
# Paths:
# - L12-13: VDA_DISC declared and cleared; L14-17 (WAVER YES, refused): the
#   weighted centred averaging of PRC_RESID and COM_PROJ.
# - L21-27: residual capacities. TRACKP marks the processes with a positive
#   PRC_RESID in some period; for the PYR_S vintage, PRC_RCAP processes get
#   RTFORC (forced retirements) and a flat PRC_RESID, NCAP_PASTI(R,PYR_S,P)
#   becomes the duration-weighted average of PRC_RESID where PRC_RESID(R,'0',P)
#   is given (and is removed for processes outside TRACKP), the '0' records
#   of processes outside TRACKP go, and COEF_CPT at the PYR_S vintage is
#   PRC_RESID(R,T,P)/NCAP_PASTI(R,PYR_S,P).
# - L30-32: compile-time macros; RP_STL of RP_STS processes cleared unless
#   STSFLX is YES.
# - L35-37: COEF_AFUPS (NCAP_AF UP on storage timeslices without an UP
#   CAFLAC, then NCAP_AFC('ACT') on the storage levels; non-capacity
#   processes dropped). L39: ACT_CSTUP of processes with STG_MAXCYC turned
#   into an annuity.
# - L42-53: commodity balances kept only for commodities that are inputs,
#   exports, IRE_FLOSUM auxiliaries, demands or RPC_NOFLO flows of some
#   process (TRACKC); UCU-unit commodities not among them lose RTCS_VARC
#   outside RHS_COMPRD, mark RPC_CONLY and drop their 'IMPEXP' TOP_IRE.
# - L55-57: user constraints with UC_TIME(UCN,R,'0') = -13 switched off.
# - L60, L71-76: singleton ACT_EFF groups (RPG_1ACE) become COEF_PTRAN
#   records, their ACT_EFF is zeroed, RPCC_FFUNC gains the group pairs;
#   RPCG_PTRAN cleared unless SENSIS; work sets cleared.
# - L78-80: eqlducs.vda and eqashar.vda are included; with no
#   unit-commitment data eqlducs.vda does nothing. eqashar.vda L16-33 is
#   `eqashar_prep!` (src/ext/vda/eqashar.jl): RPCG_ASHAR, the levelling of
#   FLO_ASHAR, UNCD7. powerflo.vda CSTBAL is included only when COM_CSTBAL
#   has data (`$IF DEFINED`, G35).
# - L81-83: COEF_PVT defaults to FPD; VDA_DISC; COEF_ILED of processes with
#   an NCAP_BND 'N'.
#
# Refused: WAVER YES (fillwave.gms); the ETL, CLI, ABS and MACRO extensions;
# reduced flows (RPC_FFUNC or RPCG_PTRAN not empty: L62-69, which coef_ptr
# also refuses through KEEP_FLOF); unit-commitment data (eqlducs.vda
# L12-41); COM_CSTBAL (powerflo.vda L372-396).

"The coef_ext.vda paths this model would take that are not translated; empty when coef_ext! can run."
function coef_ext_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    yes("WAVER") && push!(out, "coef_ext.vda L14-17 (WAVER YES: fillwave.gms)")
    for n in ("ETL", "CLI", "ABS")
        yes(n) && push!(out, "coef_ext.$(lowercase(n)) ($n YES)")
    end
    gswitch(tm, "MACRO", "") == "" || push!(out, "coef_ext.msa/mlf (MACRO set)")
    for (s, n, kind) in (("ACT_CSTSD", 6, :param), ("ACT_SDTIME", 5, :param), ("ACT_MAXNON", 4, :param),
                         ("ACT_LOSSD", 5, :param), ("ACT_LOSPL", 4, :param), ("ACT_MINLD", 3, :param),
                         ("RP_PL", 3, :set), ("RP_DP", 2, :set), ("RP_UPT", 4, :set))
        empty = kind == :set ? isempty(gset_opt(tm.data, s, n)) : isempty(gparam_opt(tm.data, s, n))
        empty || push!(out, "eqlducs.vda L12-41 (unit commitment: $s has data)")
    end
    isempty(gparam_opt(tm.data, "COM_CSTBAL", 6)) || push!(out, "coef_ext.vda L80, powerflo.vda L372-396 (COM_CSTBAL has data)")
    return out
end

"""
    coef_ext!(tm) -> tm

coef_ext.vda on the GAMS state in `tm`, after coefmain.mod: the residual
capacity coefficients (RTFORC, NCAP_PASTI, PRC_RESID, COEF_CPT at the PYR_S
vintage), COEF_AFUPS and the ACT_CSTUP annuity, the commodity balance
pruning (RCS_COMBAL, RTCS_VARC, RPC_CONLY, TOP_IRE), UC_TIME/UC_ON, the
singleton ACT_EFF groups as COEF_PTRAN with RPCC_FFUNC and ACT_EFF zeroed,
COEF_PVT defaulted to FPD, VDA_DISC and COEF_ILED; TRACKP, TRACKC, RCS,
TRACKPC, RP_GRP, CG_GRP, RP_DCGG, RTP_CAPYR, RP_CGC (and RPCG_PTRAN unless
SENSIS) left cleared; then the "advanced" flow shares ([`eqashar_prep!`](@ref):
RPCG_ASHAR, FLO_ASHAR levelled, UNCD7).

GAMS: coef_ext.vda L12-83 (maindrv.mod L73), v4.9.7.
"""
function coef_ext!(tm)
    u = coef_ext_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    S1(n) = gset(tm, n)
    one = GNum(1)
    t_list = [k[1] for k in S1("MILESTONYR").keys]
    milestones = Set(t_list)
    rtp = S1("RTP")
    rtp_cptyr = S1("RTP_CPTYR")
    cptyr_by_rvp = indexby(rtp_cptyr, (1, 2, 4))
    D = gparam(tm, "D")
    reg_set = S1("REG")
    regs = [k[1] for k in reg_set.keys]

    # L12-13: PARAMETER VDA_DISC(R,ALLYEAR); $CLEAR VDA_DISC
    vda_disc = Dict{NTuple{2,String},Float64}()

    # L21: LOOP(T, TRACKP(R,P)$((PRC_RESID(R,T,P)>0)$PRC_RESID(R,T,P)) = YES)
    resid = gvalues(tm, "PRC_RESID", 3)
    trackp = gmembers(tm, "TRACKP", 2)
    for ((r, t, p), x) in resid
        (t in milestones && x > 0) && push!(trackp, (r, p))
    end
    # L22-25: LOOP(PYR_S(V), ...)
    pyr_s = [k[1] for k in S1("PYR_S").keys]
    prc_rcap = S1("PRC_RCAP")
    rtforc = gvalues(tm, "RTFORC", 4)
    pasti = gvalues(tm, "NCAP_PASTI", 3)
    rp_resid0 = Set((k[1], k[3]) for k in keys(resid) if k[2] == "0")
    rcap_loop = [k for k in prc_rcap.keys if k in trackp]
    gams_sort!(rcap_loop, tm.data)                       # LOOP order: the scratch Z is the last pass's
    for v in pyr_s
        # L23: LOOP(PRC_RCAP(TRACKP(R,P)), Z = SMAX(T,PRC_RESID(R,T,P));
        #        RTFORC(RTP_CPTYR(R,V,T,P)) = Z-PRC_RESID(R,T,P)+EPS; PRC_RESID(R,T,P)$RTFORC(R,V,T,P) = Z)
        for (r, p) in rcap_loop
            z = maximum((Float64(gv(resid, (r, t, p))) for t in t_list); init=-Inf)
            gput_scalar!(tm, "Z", z)                         # scratch, as the last pass leaves it
            for (_, _, t, _) in get(cptyr_by_rvp, (r, v, p), NTuple{4,String}[])
                gassign!(rtforc, (r, v, t, p), GNum(z) - gv(resid, (r, t, p)) + GEPS)
                haskey(rtforc, (r, v, t, p)) && gassign!(resid, (r, t, p), GNum(z))
            end
        end
        # L24: NCAP_PASTI(R,V,P)$PRC_RESID(R,'0',P) = (SUM(T,PRC_RESID(R,T,P)*D(T))/SUM(T$(PRC_RESID(R,T,P)>0),D(T)))$TRACKP(R,P)
        for (r, p) in rp_resid0
            if (r, p) in trackp
                num = sum((gv(resid, (r, t, p)) * gv(D, (t,)) for t in t_list); init=GZERO)
                den = sum((gv(D, (t,)) for t in t_list if Float64(gv(resid, (r, t, p))) > 0); init=GZERO)
                gassign!(pasti, (r, v, p), num / den)
            else
                delete!(pasti, (r, v, p))
            end
        end
    end
    gput!(tm, "RTFORC", rtforc)
    gput!(tm, "NCAP_PASTI", pasti)
    # L26: PRC_RESID(R,'0',P)$(NOT TRACKP(R,P)) = 0
    for (r, p) in rp_resid0
        (r, p) in trackp || delete!(resid, (r, "0", p))
    end
    gput!(tm, "PRC_RESID", resid)
    # L27: COEF_CPT(RTP_CPTYR(R,PYR_S(V),T,P))$TRACKP(R,P) = PRC_RESID(R,T,P)/NCAP_PASTI(R,V,P)
    coef_cpt = gvalues(tm, "COEF_CPT", 4)
    for v in pyr_s, (r, p) in trackp
        for (_, _, t, _) in get(cptyr_by_rvp, (r, v, p), NTuple{4,String}[])
            gassign!(coef_cpt, (r, v, t, p), gv(resid, (r, t, p)) / gv(pasti, (r, v, p)))
        end
    end
    gput!(tm, "COEF_CPT", coef_cpt)

    # L32: $IFI NOT %STSFLX%==YES RP_STL(RP_STS,TSL,BD) = 0 - the BD (LO, UP, FX) records; the 'N' ones of
    #      ppmain.mod L1089 are outside BD and stay
    if uppercase(gswitch(tm, "STSFLX", "")) != "YES"
        rp_sts, bd = S1("RP_STS"), S1("BD")
        rp_stl = gmembers(tm, "RP_STL", 4)
        filter!(k -> !((k[1], k[2]) in rp_sts && (k[4],) in bd), rp_stl)
        gput!(tm, "RP_STL", rp_stl)
    end

    # L35: COEF_AFUPS(RTP(R,V,P),S)$(NOT RPS_CAFLAC(R,P,S,'UP')) $= NCAP_AF(RTP,S,'UP')$RPS_STG(R,P,S)
    afups = gvalues(tm, "COEF_AFUPS", 4)
    rps_stg, rps_caflac = S1("RPS_STG"), S1("RPS_CAFLAC")
    ncap_af, ncap_afc = gparam(tm, "NCAP_AF"), gparam(tm, "NCAP_AFC")
    stg_by_rp = indexby(rps_stg, (1, 2))
    stl = Set(k[1] for k in S1("STL").keys)
    for (r, v, p) in rtp.keys
        for (_, _, s) in get(stg_by_rp, (r, p), NTuple{3,String}[])
            (r, p, s, "UP") in rps_caflac && continue
            x = gv(ncap_af, (r, v, p, s, "UP"))
            iszero(x) || gassign!(afups, (r, v, p, s), x)
        end
        # L36: COEF_AFUPS(RTP(R,V,P),S(STL))$RPS_STG(R,P,S) $= NCAP_AFC(RTP,'ACT',STL)
        for (_, _, s) in get(stg_by_rp, (r, p), NTuple{3,String}[])
            s in stl || continue
            x = gv(ncap_afc, (r, v, p, "ACT", s))
            iszero(x) || gassign!(afups, (r, v, p, s), x)
        end
    end
    # L37: COEF_AFUPS(R,V,P,S)$(NOT PRC_CAP(R,P)) = NO
    prc_cap = S1("PRC_CAP")
    filter!(kv -> (kv[1][1], kv[1][3]) in prc_cap, afups)
    gput!(tm, "COEF_AFUPS", afups)
    # L39: ACT_CSTUP(RTP(R,V,P),TSL(S),CUR)$(RDCUR(R,CUR)$STG_MAXCYC(RTP)) = ACT_CSTUP*G_DRATE(R,V,CUR)/(1-(1+G_DRATE(R,V,CUR))**(-NCAP_TLIFE(RTP)))
    #      TSL(S): the timeslice levels that are also timeslices (ALL_TS), i.e. 'ANNUAL' alone in a usual model
    cstup = gvalues(tm, "ACT_CSTUP", 5)
    maxcyc, gdrate, tlife = gparam(tm, "STG_MAXCYC"), gparam(tm, "G_DRATE"), gparam(tm, "NCAP_TLIFE")
    rdcur, all_ts = S1("RDCUR"), S1("ALL_TS")
    tslvl = [k[1] for k in S1("TSLVL").keys if k in all_ts]
    for (r, v, p) in rtp.keys
        haskey(maxcyc, (r, v, p)) || continue
        for (rr, cur) in rdcur.keys
            rr == r || continue
            gd = gv(gdrate, (r, v, cur))
            for tsl in tslvl
                old = gv(cstup, (r, v, p, tsl, cur))
                gassign!(cstup, (r, v, p, tsl, cur), old * gd / (one - gpow(one + gd, -gv(tlife, (r, v, p)))))
            end
        end
    end
    gput!(tm, "ACT_CSTUP", cstup)

    # L42: OPTION TRACKP < RTP, TRACKC < RHS_COMBAL, RCS < IRE_FLOSUM (G26: right to left, RCS's COM is the
    #      rightmost COM of IRE_FLOSUM(REG,ALLYEAR,PRC,COM,TS,IE,COM,IO), the auxiliary commodity)
    trackp = Set((k[1], k[3]) for k in rtp.keys)
    trackc = Set((k[1], k[3]) for k in S1("RHS_COMBAL").keys)
    rcs = Set((k[1], k[7], k[5]) for k in keys(gparam(tm, "IRE_FLOSUM").values))
    # L43: LOOP(TRACKP(R,P), TRACKC(R,C)$TOP(R,P,C,'IN') = YES)
    for (r, p, c, io) in S1("TOP").keys
        (io == "IN" && (r, p) in trackp) && push!(trackc, (r, c))
    end
    # L44: TRACKC(R,C) $= SUM(RPC_IRE(TRACKP(R,P),C,'EXP'),1)
    for (r, p, c, ie) in S1("RPC_IRE").keys
        (ie == "EXP" && (r, p) in trackp) && push!(trackc, (r, c))
    end
    # L45: TRACKC(RC) $= SUM(RCS(RC,S),1); TRACKC(DEM) = YES
    rc = S1("RC")
    for (r, c, _) in rcs
        (r, c) in rc && push!(trackc, (r, c))
    end
    union!(trackc, S1("DEM").keys)
    # L46: TRACKC(R,C) $= SUM(RPC_NOFLO(TRACKP(R,P),C),1)
    for (r, p, c) in S1("RPC_NOFLO").keys
        (r, p) in trackp && push!(trackc, (r, c))
    end
    # L47: RCS_COMBAL(RTCS_VARC(R,T,C,S),L)$(NOT TRACKC(R,C)) = NO
    rtcs_varc = gmembers(tm, "RTCS_VARC", 4)
    rcs_combal = gmembers(tm, "RCS_COMBAL", 5)
    filter!(k -> (k[1], k[3]) in trackc || !((k[1], k[2], k[3], k[4]) in rtcs_varc), rcs_combal)
    gput!(tm, "RCS_COMBAL", rcs_combal)
    # L49: TRACKC(RC) = COM_UNIT(RC,'UCU')$(NOT TRACKC(RC))
    com_unit = S1("COM_UNIT")
    old = trackc
    trackc = Set(k for k in old if !(k in rc))
    for (r, c) in rc.keys
        ((r, c, "UCU") in com_unit && !((r, c) in old)) && push!(trackc, (r, c))
    end
    # L50: RTCS_VARC(R,T,C,S)$((NOT RHS_COMPRD(R,T,C,S))$TRACKC(R,C)) = NO
    rhs_comprd = S1("RHS_COMPRD")
    filter!(k -> !((k[1], k[3]) in trackc) || k in rhs_comprd, rtcs_varc)
    gput!(tm, "RTCS_VARC", rtcs_varc)
    # L51: RPC_CONLY(RTPC(R,T,P,C))$(NOT RTC(R,T,C)) $= TRACKC(R,C)
    rpc_conly = gmembers(tm, "RPC_CONLY", 4)
    rtc = S1("RTC")
    for (r, t, p, c) in S1("RTPC").keys
        (!((r, t, c) in rtc) && (r, c) in trackc) && push!(rpc_conly, (r, t, p, c))
    end
    gput!(tm, "RPC_CONLY", rpc_conly)
    # L52: TOP_IRE('IMPEXP',C,TRACKC,P) = NO
    top_ire = gmembers(tm, "TOP_IRE", 5)
    filter!(k -> !(k[1] == "IMPEXP" && (k[3], k[4]) in trackc), top_ire)
    gput!(tm, "TOP_IRE", top_ire)
    # L53: OPTION CLEAR=TRACKC, CLEAR=TRACKP, CLEAR=RCS
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    gput!(tm, "RCS", Set{NTuple{3,String}}())

    # L55-57: IF(CARD(UC_TIME), OPTION R_UC < UC_TIME; LOOP(R_UC(R,UCN)$(ROUND(UC_TIME(UCN,R,'0')) = -13),
    #   UC_ON(R_UC) = NO; IF(UC_R_SUM(R_UC), UC_ON(UC_R_SUM(REG,UCN)) = NO));
    #   UC_TIME(UCN,R,T)$((NOT UC_ON(R,UCN))$R_UC(R,UCN)) = 0; OPTION CLEAR=R_UC)
    uc_time = gvalues(tm, "UC_TIME", 3)
    if !isempty(uc_time)
        r_uc = Set((k[2], k[1]) for k in keys(uc_time))
        uc_on = gmembers(tm, "UC_ON", 2)
        uc_r_sum = S1("UC_R_SUM")
        for (r, ucn) in r_uc                                        # R: a region of REG
            (r,) in reg_set || continue
            glead(Float64(gv(uc_time, (ucn, r, "0")))) == -13 || continue
            delete!(uc_on, (r, ucn))
            if (r, ucn) in uc_r_sum
                for (reg, u) in uc_r_sum.keys
                    (u == ucn && (reg,) in reg_set) && delete!(uc_on, (reg, u))
                end
            end
        end
        for (r, ucn) in r_uc
            ((r,) in reg_set && !((r, ucn) in uc_on)) || continue
            for t in t_list
                delete!(uc_time, (ucn, r, t))
            end
        end
        gput!(tm, "UC_ON", uc_on)
        gput!(tm, "UC_TIME", uc_time)
        gput!(tm, "R_UC", Set{NTuple{2,String}}())
    end

    # L60: RP_CGC(RPG_1ACE) = YES; OPTION TRACKPC < RPG_1ACE, RP_GRP < RP_CGC
    rpg_1ace = S1("RPG_1ACE")
    rp_cgc = union(gmembers(tm, "RP_CGC", 4), rpg_1ace.keys)
    trackpc = Set((k[1], k[2], k[4]) for k in rpg_1ace.keys)
    rp_grp = Set((k[1], k[2], k[3]) for k in rp_cgc)
    # L62: TRACKPC(TRACKPC) = RPC_FFUNC(TRACKPC)
    rpc_ffunc = S1("RPC_FFUNC").members
    filter!(k -> k in rpc_ffunc, trackpc)
    act_eff0 = gvalues(tm, "ACT_EFF", 5)
    if !isempty(trackpc)
        # L63: ACT_FLO(RTP(R,V,P),C,S)$(RPCS_VAR(R,P,C,S)$TRACKPC(R,P,C)) =
        #   1/SUM(RP_CGC(R,P,CG,C),MAX(MICRO,ACT_EFF(RTP,CG,S)*(1+(ACT_EFF(RTP,C,S)-1)$ACT_EFF(RTP,C,S))))
        micro = GNum(gscalar(tm, "MICRO"))
        act_flo = gvalues(tm, "ACT_FLO", 5)
        rpcs_of = indexby(S1("RPCS_VAR"), (1, 2, 3))
        cg_of = Dict{NTuple{3,String},Vector{String}}()
        foreach(k -> push!(get!(() -> String[], cg_of, (k[1], k[2], k[4])), k[3]), rp_cgc)
        tr_of = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(() -> String[], tr_of, (k[1], k[2])), k[3]), trackpc)
        for (r, v, p) in rtp.keys, c in get(tr_of, (r, p), String[]), (_, _, _, s) in get(rpcs_of, (r, p, c), NTuple{4,String}[])
            ec = gv(act_eff0, (r, v, p, c, s))
            den = GZERO
            for cg in get(cg_of, (r, p, c), String[])
                den += gmax(micro, gv(act_eff0, (r, v, p, cg, s)) * (GNum(1.0) + gif(ec - GNum(1.0), !iszero(ec))))
            end
            gassign!(act_flo, (r, v, p, c, s), GNum(1.0) / den)
        end
        gput!(tm, "ACT_FLO", act_flo)
    end
    # L65: OPTION CG_GRP <= RTP_FFCX   (RTP_FFCX(R,V,T,P,CG,CG2): positions 1, 4, 5, 6)
    ffcx = gvalues(tm, "RTP_FFCX", 6)
    cg_grp = Set{NTuple{4,String}}((k[1], k[4], k[5], k[6]) for k in keys(ffcx))
    # L66: LOOP(RPCG_PTRAN(RP,C,COM,CG,CG2)$CG_GRP(RP,CG,CG2),
    #   IF(RPC_FFUNC(RP,C), RP_DCGG(RP,C,CG,CG2,'UP')=YES; ELSE RP_DCGG(RP,COM,CG,CG2,'LO')=YES))
    dcgg = Set{NTuple{6,String}}()
    for (r, p, c, com, cg, cg2) in S1("RPCG_PTRAN").keys
        (r, p, cg, cg2) in cg_grp || continue
        (r, p, c) in rpc_ffunc ? push!(dcgg, (r, p, c, cg, cg2, "UP")) : push!(dcgg, (r, p, com, cg, cg2, "LO"))
    end
    # L67: RP_DCGG(TRACKPC(RP,COM),CG,C,'UP')$(RP_CGC(RP,CG,COM)$RPC_ACT(RP,C)) $= CG_GRP(RP,CG,C)
    rpc_act = S1("RPC_ACT").members
    for (r, p, cg, com) in rp_cgc
        (r, p, com) in trackpc || continue
        for k in cg_grp
            (k[1] == r && k[2] == p && k[3] == cg && (r, p, k[4]) in rpc_act) && push!(dcgg, (r, p, com, cg, k[4], "UP"))
        end
    end
    if !isempty(dcgg)
        # L68: RTP_FFCX(RTP_CAPYR(R,V,T,P),ACTCG,C)$RPC_FFUNC(R,P,C) $=
        #   SUM(RP_DCGG(R,P,C,CG,CG2,L),(POWER(RTP_FFCX(R,V,T,P,CG,CG2)+1,BDSIG(L))-1)$(RTP_FFCX(R,V,T,P,CG,CG2)-MIN(0,BDSIG(L))))
        bdsig = Dict("LO" => 1.0, "UP" => -1.0)
        actcg = [k[1] for k in S1("ACTCG").keys]
        sums = Dict{NTuple{6,String},GNum}()                                 # the right side reads the old values (G11)
        for (r, v, t, p) in S1("RTP_CAPYR").keys, (rr, pp, c, cg, cg2, l) in dcgg
            (rr == r && pp == p && (r, p, c) in rpc_ffunc) || continue
            x = gv(ffcx, (r, v, t, p, cg, cg2))
            b = bdsig[l]
            iszero(x - GNum(min(0.0, b))) && continue
            y = gpower(x + GNum(1.0), GNum(b)) - GNum(1.0)
            for a in actcg
                sums[(r, v, t, p, a, c)] = get(sums, (r, v, t, p, a, c), GZERO) + y
            end
        end
        foreach(((k, y),) -> iszero(y) || gassign!(ffcx, k, y), sums)      # $=
        # L69: LOOP(RP_DCGG(R,P,C,CG,CG2,L),RTP_FFCX(R,V,T,P,CG,CG2)=0)
        gone = Set((k[1], k[2], k[4], k[5]) for k in dcgg)
        filter!(kv -> !((kv[1][1], kv[1][4], kv[1][5], kv[1][6]) in gone), ffcx)
        gput!(tm, "RTP_FFCX", ffcx)
    end
    # L71: RP_CGC(R,P,CG,C)$TRACKPC(R,P,C) = NO
    filter!(k -> !((k[1], k[2], k[4]) in trackpc), rp_cgc)
    # L72: COEF_PTRAN(RTP(R,V,P),CG,C,COM,S)$(RPCS_VAR(R,P,C,S)$RPC_PG(R,P,COM)$RP_CGC(R,P,CG,C))
    #        = ACT_EFF(RTP,CG,S)*PRC_ACTFLO(RTP,COM)*(1+(ACT_EFF(RTP,C,S)-1)$ACT_EFF(RTP,C,S))
    coef_ptran = gvalues(tm, "COEF_PTRAN", 7)
    act_eff = gvalues(tm, "ACT_EFF", 5)
    actflo = gparam(tm, "PRC_ACTFLO")
    rpcs_by_rpc = indexby(S1("RPCS_VAR"), (1, 2, 3))
    pg_by_rp = indexby(S1("RPC_PG"), (1, 2))
    cgc_by_rp = Dict{NTuple{2,String},Vector{NTuple{4,String}}}()
    for k in rp_cgc
        push!(get!(() -> NTuple{4,String}[], cgc_by_rp, (k[1], k[2])), k)
    end
    for (r, v, p) in rtp.keys
        for (_, _, cg, c) in get(cgc_by_rp, (r, p), NTuple{4,String}[])
            for (_, _, _, s) in get(rpcs_by_rpc, (r, p, c), NTuple{4,String}[])
                ec = gv(act_eff, (r, v, p, c, s))
                f = gv(act_eff, (r, v, p, cg, s)) * (one + gif(ec - one, !iszero(ec)))
                for (_, _, com) in get(pg_by_rp, (r, p), NTuple{3,String}[])
                    gassign!(coef_ptran, (r, v, p, cg, c, com, s), f * gv(actflo, (r, v, p, com)))
                end
            end
        end
    end
    gput!(tm, "COEF_PTRAN", coef_ptran)
    # L73: ACT_EFF(R,LL,P,CG,S)$RP_GRP(R,P,CG) = 0
    filter!(kv -> !((kv[1][1], kv[1][3], kv[1][4]) in rp_grp), act_eff)
    gput!(tm, "ACT_EFF", act_eff)
    # L74: OPTION RP_GRP < RP_CGC (after L71); RPCC_FFUNC(RP_GRP(R,P,CG),COM)$RPC_PG(R,P,COM) = YES
    rp_grp = Set((k[1], k[2], k[3]) for k in rp_cgc)
    rpcc_ffunc = gmembers(tm, "RPCC_FFUNC", 4)
    for (r, p, cg) in rp_grp, (_, _, com) in get(pg_by_rp, (r, p), NTuple{3,String}[])
        push!(rpcc_ffunc, (r, p, cg, com))
    end
    gput!(tm, "RPCC_FFUNC", rpcc_ffunc)
    # L75: $IFI NOT %SENSIS%==YES OPTION CLEAR=RPCG_PTRAN; L76: work sets cleared
    uppercase(strip(gswitch(tm, "SENSIS", ""))) == "YES" || gput!(tm, "RPCG_PTRAN", Set{NTuple{6,String}}())
    for (n, N) in (("TRACKPC", 3), ("RP_GRP", 3), ("CG_GRP", 4), ("RP_DCGG", 6), ("RTP_CAPYR", 4), ("RP_CGC", 4))
        gput!(tm, n, Set{NTuple{N,String}}())
    end
    # L78: eqlducs.vda (no unit-commitment data: nothing); L79: eqashar.vda L16-33;
    # L80: powerflo.vda CSTBAL is not included (COM_CSTBAL has no data)
    eqashar_prep!(tm)

    # L81: COEF_PVT(R,T)$(NOT COEF_PVT(R,T)) = FPD(T); L82: VDA_DISC(R,T) $= COEF_PVT(R,T)
    coef_pvt = gvalues(tm, "COEF_PVT", 2)
    fpd = gparam(tm, "FPD")
    for r in regs, t in t_list
        iszero(gv(coef_pvt, (r, t))) && gassign!(coef_pvt, (r, t), gv(fpd, (t,)))
        x = gv(coef_pvt, (r, t))
        iszero(x) || gassign!(vda_disc, (r, t), x)
    end
    gput!(tm, "COEF_PVT", coef_pvt)
    gput!(tm, "VDA_DISC", vda_disc)
    # L83: COEF_ILED(RTP(R,T,P))$NCAP_BND(RTP,'N') = MOD(COEF_ILED(RTP),1000)+EPS$NCAP_ILED(RTP)
    coef_iled = gvalues(tm, "COEF_ILED", 3)
    ncap_bnd, ncap_iled = gparam(tm, "NCAP_BND"), gparam(tm, "NCAP_ILED")
    for (r, t, p) in rtp.keys
        (t in milestones && haskey(ncap_bnd, (r, t, p, "N"))) || continue
        x = gv(coef_iled, (r, t, p))
        m = GNum(rem(x.v, 1000.0), x.eps)
        gassign!(coef_iled, (r, t, p), m + gif(GEPS, haskey(ncap_iled, (r, t, p))))
    end
    gput!(tm, "COEF_ILED", coef_iled)
    return tm
end
