# EQ(l)_FLOMRK, the market-share constraint of a process in total commodity
# production: eqflomrk.mod L56-105 (v4.9.7), included from eqmain.mod L139-141
# as `eqflomrk.mod G LO`, `E FX`, `L UP`.
#
# The preparation half of the file (L13-52: RTX_MARK, RX_MARK, RMKC, the
# PRC_MARK clean-up, RHS_COMPRD for the groups) runs from ppmain.mod L842
# and is translated with the preprocessing (`ppmain_flofs!`, M1.3 change
# 11b); this file reads its results from the state.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> ''
# (setglobs.gms L348); %R_T% -> 'R,T' (maindrv.mod L39); %cal_red% is
# cal_nored.red, or cal_red.red under REDUCE (`cal_nored!`); %IRED% (L58) is
# '' unless REDUCE is YES, when an exchange flow of an RPC_AIRE process is
# its activity times PRC_ACTFLO; %SIGO%/%SIGI% (L60) test the sign of
# PRC_MARK(R,T,P,ITEM,COM,BD).

"The three includes of eqmain.mod L139-141: (equation type, bound type)."
const FLOMRK_VARIANTS = (("G", "LO"), ("E", "FX"), ("L", "UP"))

"""
    eq_flomrk!(tm::TimesModel) -> Int

Generate the EQG_FLOMRK, EQE_FLOMRK and EQL_FLOMRK rows:

    EQ%1_FLOMRK(R,T,ITEM,COM,S)\$RTX_MARK(R,T,ITEM,COM,'%2',S)..
      SUM((COM_GMAP(R,COM,C),RPC(R,P,C))\$PRC_MARK(R,T,P,ITEM,COM,'%2'),
        POWER(PRC_MARK(R,T,P,ITEM,COM,'%2'),1\$RX_MARK(R,'0',ITEM,COM,'%2')-1) *
        SUM(RHS_COMPRD(R,T,C,SL)\$RS_FR(R,S,SL),
          (SUM(RTPCS_VARF(R,T,P,C,TS)\$RS_FR(R,SL,TS),
             SUM(RTP_VNTBYR(R,T,P,V), [cal_red C COM1 TS P T]) * RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,C,SL,TS)))
           *(1+(COM_IE(R,T,C,SL)-1)\$TOP(R,P,C,'OUT')))\$RP_STD(R,P)
        + SUM(RTPCS_VARF(R,T,P,C,TS)\$RS_FR(R,SL,TS),
            SUM(RTP_VNTBYR(R,T,P,V),
              ((VAR_IRE(R,V,T,P,C,TS,'IMP')%IRED%)*(1+IRE_FLOSUM(R,T,P,C,S,'IMP',C,'OUT'))*COM_IE(R,T,C,SL))\$(%SIGO%\$RPC_IRE(R,P,C,'IMP'))
             -((VAR_IRE(R,V,T,P,C,TS,'EXP')%IRED%)*(1+IRE_FLOSUM(R,T,P,C,S,'EXP',C,'IN')))\$(%SIGI%\$RPC_IRE(R,P,C,'EXP'))) *
            RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,C,SL,TS)))\$RP_IRE(R,P)
        + SUM(RPCS_VAR(RPC_STG(R,P,C),TS)\$RS_FR(R,SL,TS),
            SUM(RTP_VNTBYR(R,T,P,V),
              ((VAR_SOUT(R,V,T,P,C,TS)*STG_EFF(R,V,P)*COM_IE(R,T,C,SL))\$%SIGO% - VAR_SIN(R,V,T,P,C,TS)\$%SIGI%)) *
            RS_FR(R,SL,TS)*(1+RTCS_FR(R,T,C,SL,TS)))\$PRC_MAP(R,'STG',P)))
      =%1=
      SUM((COM_GMAP(R,COM,C),RHS_COMPRD(R,T,C,SL))\$RS_FR(R,S,SL),VAR_COMPRD(R,T,C,SL)) *
      PROD(RX_MARK(R,LL,P(ITEM),COM,'%2'),PRC_MARK(R,T,P,P,COM,'%2')\$LASTLL(LL));

The exponent of the POWER is 0 (a factor 1) when RX_MARK(R,'0',ITEM,COM,BD)
holds and -1 otherwise. The PROD on the right-hand side runs over the
RX_MARK entries of ITEM when ITEM is a process (P(ITEM)); with none it is 1.
Returns the number of rows.

GAMS: eqflomrk.mod L56-105, eqmain.mod L139-141, v4.9.7.
"""
function eq_flomrk!(tm::TimesModel)
    rtx_mark = gset(tm, "RTX_MARK")
    isempty(rtx_mark) && return 0
    d = tm.data
    prc_mark = gparam(tm, "PRC_MARK")
    rx_mark = gset(tm, "RX_MARK")
    rx_of_ricb = indexby(rx_mark, (1, 3, 4, 5))                      # (r,item,com,bd) -> RX_MARK(r,ll,item,com,bd)
    lastll = gset(tm, "LASTLL")
    prc = gset(tm, "PRC")
    gmap_of_rcom = indexby(gset(tm, "COM_GMAP"), (1, 2))             # (r,com) -> COM_GMAP(r,com,c)
    rpc_of_rc = indexby(gset(tm, "RPC"), (1, 3))                     # (r,c) -> RPC(r,p,c)
    comprd_of_rtc = indexby(gset(tm, "RHS_COMPRD"), (1, 2, 3))       # (r,t,c) -> RHS_COMPRD(r,t,c,sl)
    varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))     # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    vnt_of_rtp = indexby(gset(tm, "RTP_VNTBYR"), (1, 2, 3))          # (r,t,p) -> RTP_VNTBYR(r,t,p,v)
    rpcs_var_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))       # (r,p,c) -> RPCS_VAR(r,p,c,ts)
    rs_fr, rtcs_fr, com_ie = gparam(tm, "RS_FR"), gparam(tm, "RTCS_FR"), gparam(tm, "COM_IE")
    ire_flosum, stg_eff, prc_actflo = gparam(tm, "IRE_FLOSUM"), gparam(tm, "STG_EFF"), gparam(tm, "PRC_ACTFLO")
    rp_std, rp_ire, rpc_stg, rpc_aire = gset(tm, "RP_STD"), gset(tm, "RP_IRE"), gset(tm, "RPC_STG"), gset(tm, "RPC_AIRE")
    rpc_ire, top = gset(tm, "RPC_IRE"), gset(tm, "TOP")
    stg = Set((k[1], k[3]) for k in gset(tm, "PRC_MAP") if k[2] == "STG")
    ired = tm.reduce                                                   # %IRED% (L58): REDUCE YES
    no2, no3, no4, no5 = NTuple{2,String}[], NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]
    w(r, t, c, sl, ts) = gv(rs_fr, (r, sl, ts)) * (1 + gv(rtcs_fr, (r, t, c, sl, ts)))

    # VAR_IRE(R,V,T,P,C,TS,IE)%IRED%, times k
    function ire!(lhs, k, r, v, t, p, c, ts, ie)
        if !ired || !((r, p, c) in rpc_aire)
            addterm!(lhs, k, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
        else
            addterm!(lhs, k * gv(prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, ts)
        end
    end

    n = 0
    for (eqtype, bd) in FLOMRK_VARIANTS
        name = "EQ$(eqtype)_FLOMRK"
        for (r, t, item, com, b, s) in rtx_mark
            b == bd || continue
            lhs = JuMP.AffExpr(0.0)
            pw = gif(GNum(1.0), (r, "0", item, com, bd) in rx_mark) - 1
            for (_, _, c) in get(gmap_of_rcom, (r, com), no3), (_, p, _) in get(rpc_of_rc, (r, c), no3)
                haskey(prc_mark, (r, t, p, item, com, bd)) || continue
                pm = gv(prc_mark, (r, t, p, item, com, bd))
                sigo, sigi = pm.v >= 0, pm.v <= 0
                f = gpower(pm, pw)
                for (_, _, _, sl) in get(comprd_of_rtc, (r, t, c), no4)
                    haskey(rs_fr, (r, s, sl)) || continue
                    if (r, p) in rp_std
                        ief = (r, p, c, "OUT") in top ? 1 + (gv(com_ie, (r, t, c, sl)) - 1) : GNum(1.0)
                        for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                            haskey(rs_fr, (r, sl, ts)) || continue
                            k = f * (w(r, t, c, sl, ts) * ief)
                            for (_, _, _, v) in get(vnt_of_rtp, (r, t, p), no4)
                                cal_nored!(lhs, tm, k, r, v, t, p, c, ts)
                            end
                        end
                    end
                    if (r, p) in rp_ire
                        isimp = sigo && (r, p, c, "IMP") in rpc_ire
                        isexp = sigi && (r, p, c, "EXP") in rpc_ire
                        for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, c), no5)
                            haskey(rs_fr, (r, sl, ts)) || continue
                            ws = w(r, t, c, sl, ts)
                            for (_, _, _, v) in get(vnt_of_rtp, (r, t, p), no4)
                                isimp && ire!(lhs, f * ((1 + gv(ire_flosum, (r, t, p, c, s, "IMP", c, "OUT"))) *
                                                      gv(com_ie, (r, t, c, sl)) * ws), r, v, t, p, c, ts, "IMP")
                                isexp && ire!(lhs, f * (-(1 + gv(ire_flosum, (r, t, p, c, s, "EXP", c, "IN"))) * ws),
                                            r, v, t, p, c, ts, "EXP")
                            end
                        end
                    end
                    if (r, p) in stg && (r, p, c) in rpc_stg
                        for (_, _, _, ts) in get(rpcs_var_of_rpc, (r, p, c), no4)
                            haskey(rs_fr, (r, sl, ts)) || continue
                            ws = w(r, t, c, sl, ts)
                            for (_, _, _, v) in get(vnt_of_rtp, (r, t, p), no4)
                                sigo && addterm!(lhs, f * (gv(stg_eff, (r, v, p)) * gv(com_ie, (r, t, c, sl)) * ws),
                                                 tm, "VAR_SOUT", r, v, t, p, c, ts)
                                sigi && addterm!(lhs, f * (-ws), tm, "VAR_SIN", r, v, t, p, c, ts)
                            end
                        end
                    end
                end
            end
            # PROD(RX_MARK(R,LL,P(ITEM),COM,'%2'),PRC_MARK(R,T,P,P,COM,'%2')$LASTLL(LL))
            g = GNum(1.0)
            if (item,) in prc
                for (_, ll, _, _, _) in get(rx_of_ricb, (r, item, com, bd), no5)
                    g = g * gif(gv(prc_mark, (r, t, item, item, com, bd)), (ll,) in lastll)
                end
            end
            rhs = JuMP.AffExpr(0.0)
            for (_, _, c) in get(gmap_of_rcom, (r, com), no3), (_, _, _, sl) in get(comprd_of_rtc, (r, t, c), no4)
                haskey(rs_fr, (r, s, sl)) || continue
                addterm!(rhs, g, tm, "VAR_COMPRD", r, t, c, sl)
            end
            gconstraint!(tm, name, (r, t, item, com, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
