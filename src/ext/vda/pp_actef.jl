# EQE_ACTEFF (VDA extension): activity efficiency. The efficiency-weighted
# flows of a commodity group equal the process activity.
#
# GAMS: pp_actef.vda L50-80 (the EQUA label), v4.9.7, included from
# equ_ext.vda L85 (`$BATINCLUDE pp_actef.mod`, VDA always loaded,
# initmty.mod L458); declared equ_ext.vda L17 (R,ALLYEAR,ALLYEAR,P,CG,IO,S);
# in the model through mod_ext.vda L10. The preprocessing part of the file
# (L1-48: ACT_EFF levelling, RPG_ACE, RPC_ACE) is M1.3; its results are read
# from the pre-solve dump.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); RTS(S) -> S; %PGPRIM% -> 'ACT'
# (initmty.mod L138), so %SHP1% (L51-53) is
#   *(1+RTP_FFCX(R,V,T,P,CG,'ACT')$PRC_VINT(R,P)) [*(1+RTP_FFCS(R,V,P,CG,'ACT')) when RTP_FFCS is DEFINED].
# V = MODLYEAR, T = MILESTONYR.
#
# The partial-load term L78-80 (RP_PL(R,P,'FX'), VAR_UPS; dispatching,
# eqactups.jl) is checked on the crafted case demo12_disp. The RPG_PACE
# branch (L72-76, ACT_EFF on primary-group commodities) is translated but
# not yet parity-checked.

"""
    eq_acteff!(tm::TimesModel) -> Int

Generate every EQE_ACTEFF row. Returns the number of rows.

    EQE_ACTEFF(RTP_VINTYR(R,V,T,P),CG,IO,S)\$(RPS_S1(R,P,S)\$RPG_ACE(R,P,CG,IO)) ..
      SUM((RPC_ACE(R,P,C),COM_GMAP(R,CG,C),TS_MAP(R,S,TS))\$RTPCS_VARF(R,T,P,C,TS),
          (1+(ACT_EFF(R,V,P,C,TS)-1)\$ACT_EFF(R,V,P,C,TS)) * VAR_FLO(R,V,T,P,C,TS)) *
      SUM(TS_ANN(S,TS),ACT_EFF(R,V,P,CG,TS)) %SHP1%
      =E=
      SUM(PRC_TS(R,P,TS)\$RS_FR(R,S,TS), RS_FR(R,S,TS) *
          (VAR_ACT(R,V,T,P,TS)\$(NOT RP_PGFLO(R,P)) +
           SUM(RPC_PG(R,P,C),(VAR_ACT(R,V,T,P,TS)\$RP_PGACT(R,P)+(VAR_FLO(R,V,T,P,C,TS)/PRC_ACTFLO(R,V,P,C))\$(NOT RP_PGACT(R,P))) *
               (1+RTCS_FR(R,T,C,S,TS)))\$RP_PGFLO(R,P)))\$(NOT RPG_PACE(R,P,CG)) +
      SUM(PRC_TS(R,P,TS)\$RS_FR(R,S,TS), RS_FR(R,S,TS) *
          SUM(RPC_PG(R,P,C), (VAR_ACT(R,V,T,P,TS)\$RP_PGACT(R,P) + (VAR_FLO(R,V,T,P,C,TS)/PRC_ACTFLO(R,V,P,C))\$(NOT RP_PGACT(R,P))) /
              (1+(ACT_EFF(R,V,P,C,TS)-1)\$ACT_EFF(R,V,P,C,TS)) * (1+RTCS_FR(R,T,C,S,TS))))\$RPG_PACE(R,P,CG)
      SUM(RP_PL(R,P,L('FX')),ACT_LOSPL(R,V,P,L) *
        SUM(PRC_TS(R,P,TS)\$RS_FR(R,S,TS),VAR_UPS(R,V,T,P,TS,L)*RS_FR(R,S,TS)));

GAMS: pp_actef.vda L50-80, v4.9.7.
"""
function eq_acteff!(tm::TimesModel)
    rpg_ace = gset_opt(tm.data, "RPG_ACE", 4)
    isempty(rpg_ace) && return 0
    rp_pl, act_lospl = gset_opt(tm.data, "RP_PL", 3), gparam_opt(tm.data, "ACT_LOSPL", 4)
    modlyear, tx = gset(tm, "MODLYEAR"), eq_periods(tm)   # %R_V_T%: SUBT in a stepped run (maindrv.mod L38-40)
    rpc_ace_of_rp = indexby(gset(tm, "RPC_ACE"), (1, 2))           # (r,p) -> RPC_ACE(r,p,c)
    com_gmap = gset(tm, "COM_GMAP")
    tsmap_of_rs = indexby(gset(tm, "TS_MAP"), (1, 2))              # (r,s) -> TS_MAP(r,s,ts)
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    tsann_of_s = indexby(gset(tm, "TS_ANN"), (1,))                 # s -> TS_ANN(s,ts)
    vt_of_rp = indexby(gset(tm, "RTP_VINTYR"), (1, 4))             # (r,p) -> RTP_VINTYR(r,v,t,p)
    s1_of_rp = indexby(gset(tm, "RPS_S1"), (1, 2))                 # (r,p) -> RPS_S1(r,p,s)
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))                 # (r,p) -> PRC_TS(r,p,ts)
    pg_of_rp = indexby(gset(tm, "RPC_PG"), (1, 2))                 # (r,p) -> RPC_PG(r,p,c)
    rp_pgflo, rp_pgact = gset(tm, "RP_PGFLO"), gset(tm, "RP_PGACT")
    rpg_pace = gset_opt(tm.data, "RPG_PACE", 3)
    prc_vint = gset(tm, "PRC_VINT")
    act_eff = gparam(tm, "ACT_EFF")
    rs_fr, rtcs_fr = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    rtp_ffcx = gparam(tm, "RTP_FFCX")
    rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5)
    no2, no3, no4 = NTuple{2,String}[], NTuple{3,String}[], NTuple{4,String}[]
    # (1+(ACT_EFF(k)-1)$ACT_EFF(k)): the value where present (EPS gives 0, G6), else 1.
    aeff(k) = 1 + gif(gv(act_eff, k) - 1, haskey(act_eff, k))

    rows = NTuple{7,String}[]
    off = rts_off(tm)                    # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 63)
    for (r, p, cg, io) in rpg_ace, (_, v, t, _) in get(vt_of_rp, (r, p), no4)
        ((v,) in modlyear && (t,) in tx) || continue
        for (_, _, s) in get(s1_of_rp, (r, p), no3)
            off(r, t, s) && continue
            push!(rows, (r, v, t, p, cg, io, s))
        end
    end
    gams_sort!(rows, tm.data)

    n = 0
    for (r, v, t, p, cg, io, s) in rows
        # LHS, L59-62.
        grp = GZERO
        for (_, ts) in get(tsann_of_s, (s,), no2)
            grp = grp + gv(act_eff, (r, v, p, cg, ts))
        end
        shp1 = (1 + gif(gv(rtp_ffcx, (r, v, t, p, cg, "ACT")), (r, p) in prc_vint)) *
               (1 + gv(rtp_ffcs, (r, v, p, cg, "ACT")))
        lhs = JuMP.AffExpr(0.0)
        for (_, _, c) in get(rpc_ace_of_rp, (r, p), no3)
            (r, cg, c) in com_gmap || continue
            for (_, _, ts) in get(tsmap_of_rs, (r, s), no3)
                (r, t, p, c, ts) in rtpcs_varf || continue
                addterm!(lhs, aeff((r, v, p, c, ts)) * grp * shp1, tm, "VAR_FLO", r, v, t, p, c, ts)
            end
        end
        # RHS, L66-76.
        rhs = JuMP.AffExpr(0.0)
        pace = (r, p, cg) in rpg_pace
        pgflo, pgact = (r, p) in rp_pgflo, (r, p) in rp_pgact
        for (_, _, ts) in get(ts_of_rp, (r, p), no3)
            haskey(rs_fr, (r, s, ts)) || continue
            fr = gv(rs_fr, (r, s, ts))
            if !pace
                pgflo || addterm!(rhs, fr, tm, "VAR_ACT", r, v, t, p, ts)
                pgflo || continue
            end
            for (_, _, c) in get(pg_of_rp, (r, p), no3)
                w = fr * (pace ? GNum(1.0) / aeff((r, v, p, c, ts)) : GNum(1.0)) * (1 + gv(rtcs_fr, (r, t, c, s, ts)))
                if pgact
                    addterm!(rhs, w, tm, "VAR_ACT", r, v, t, p, ts)
                else
                    addterm!(rhs, w * (GNum(1.0) / gv(prc_actflo, (r, v, p, c))), tm, "VAR_FLO", r, v, t, p, c, ts)
                end
            end
        end
        # Partial loads, L78-80.
        if (r, p, "FX") in rp_pl
            lp = gv(act_lospl, (r, v, p, "FX"))
            for (_, _, ts) in get(ts_of_rp, (r, p), no3)
                haskey(rs_fr, (r, s, ts)) || continue
                addterm!(rhs, lp * gv(rs_fr, (r, s, ts)), tm, "VAR_UPS", r, v, t, p, ts, "FX")
            end
        end
        gconstraint!(tm, "EQE_ACTEFF", (r, v, t, p, cg, io, s), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
