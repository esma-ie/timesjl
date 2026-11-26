# EQ_BNDCST: the undiscounted costs of a region by cost type, added up over a
# range of years and set equal to VAR_CUMCST, whose bounds are the limits the
# user gives (REG_BNDCST for a single period, REG_CUMCST for a range of years).
#
# GAMS: eqbndcst.mod L81-213, v4.9.7, included from eqmain.mod L192; declared
# eqdeclr.mod L140 (REG,ALLYEAR,T,ALLYEAR,COSTCAT,CUR); in the model,
# mod_equa.mod L196. The variable is VAR_CUMCST(R,ALLYEAR,ALLYEAR,COSTAGG,CUR)
# (mod_vars.mod L38), positive; its bounds are set in bnd_cum.mod L44-48
# (`bnd_cum!`, bndmain.jl).
#
# The data statements of the file are translated in `eqmain_prep!`
# (eqmain_prep.jl): L38-40 SUPERYR, L42-47 REG_CUMCST (the bounds of single
# periods; the upper bound INF for the components of a bounded aggregate and
# for a lower or fixed bound alone), L50-77 RT_IAN and the annual investment
# coefficients CST_ANNC. COST_GMAP (L20-35) is compile-time data: aggregate,
# component, type (COST, TAX, SUB).
#
# One row per bound: the row (R,YEAR,TT,ALLYEAR,COSTCAT,CUR) covers the costs
# of the years YEAR to ALLYEAR; TT is the period ALLYEAR lies in
# (SUPERYR(TT,ALLYEAR): the period's own years up to its milestone year, the
# years after the milestone year of the period before, and for the last
# period every year after its middle year M(T)).
#
# As GAMS has the file, where Part II says otherwise (docs/discrepancies.md, D37 to D39): a
# single-period INV row holds the decommissioning costs twice (in CST_ANNC, L60-64, and in
# the term L99-103); FLOTAX and FLOSUB take the net of FLO_TAX and FLO_SUB (L177, L194); a
# single-period row of INV, INVTAX or INVSUB holds only the vintages in RTP_IAN (L52, L69).
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VART% -> VAR, %SOW%/%SWS%/%SWT%/%SWTD%/
# %SWSW% -> '' (setglobs.gms L348; STAGES and SCUM are refused);
# %DECLIF% -> DELIF (eqobjinv.mod L24); OBJ_ICOST/ITAX/ISUB/DCOST/FOM/FTX/FSB
# and OBJ_FTAX are the $macros over OB_* (coef_obj.mod L156-168, `obmac`);
# %cal_red% is cal_nored.mod, or cal_red.red under REDUCE (`cal_nored!`).
# %TPULSE% (L84-87, the last applicable line wins; OBJ and VARCOST are the
# global switches: eqobj.mod L59's `$SET` is local to eqobj.mod):
#   default        (PERIODYR(T,Y_EOH),YK(ALLYEAR,Y_EOH))$YK(Y_EOH,YEAR),
#   OBJ LIN        (TPULSEYR(T,Y_EOH),YK(ALLYEAR,Y_EOH))$YK(Y_EOH,YEAR),TPULSE(T,Y_EOH)*
#   VARCOST LIN    (PERIODYR(T,Y),MILESTONYR(Y_EOH),YK(ALLYEAR,Y))$(YK(Y,YEAR)$TPULSE(Y_EOH,Y)),TPULSE(Y_EOH,Y)*
#   both           (TPULSEYR(T,Y),MILESTONYR(Y_EOH),YK(ALLYEAR,Y))$(YK(Y,YEAR)$TPULSE(Y_EOH,Y)),TPULSE(Y_EOH,Y)*TPULSE(T,Y)*
# VARCOST is LIN also for OBLONG with OBJ ALT (initmty.mod L431).
#
# Index sets (eqobj.jl header): T, TT = MILESTONYR; K = EACHYEAR; Y, Y_EOH and
# K_EOH are sets of their own; LL, YEAR, ALLYEAR = all years; JOT = AGE = LIFE
# = SPAN (ALIAS(AGE,SPAN), setglobs.gms). `K_EOH(LL)` in an index list binds LL
# to the K_EOH index. `SPAN(AGE+n)` with AGE controlled is a test, not a new
# index: it holds when the element n places from AGE exists, and n is never
# positive here, so when ORD(AGE)+n >= 1. ORD of a year is its place in
# ALLYEAR, ORD of an age its place in AGE. YK(Y,K) holds for YEARVAL(K) <=
# YEARVAL(Y). `MULTI(JJ,LL+n)` past the last year is 0.
#
# The terms, by cost type (SAMEAS(COSTCAT,..)):
# - INV, L90-96: the annual payments of the investments of the vintages T up
#   to TT (YK(TT,T)), counted over the years YEAR..ALLYEAR; where the bound is
#   on a single period (RT_IAN(..,'INV')), CST_ANNC 'INVCOST' instead.
#   L99-103: the decommissioning costs, in both cases (as written: with
#   RT_IAN, CST_ANNC 'INVCOST' already holds them, L60-64).
# - INVTAX, INVSUB, L106-118: the same for taxes and subsidies, counted by
#   ORD and without the MAX(0,..) of L93; with RT_IAN(..,'INVTAXSUB'), CST_ANNC
#   'INVTAX' and minus CST_ANNC 'INVSUB' (stored negative, L75).
# - FOM, FOMTAX, FOMSUB, L121-160: the fixed costs, and the correction for
#   shapes and multipliers (RTP_SHAPE '1', '2', '3').
# - COMTAX, COMSUB, L164-172: the taxes and subsidies on commodities, of every
#   period with a year in the range. COMSUB is subtracted: OBJ_COMNT and
#   OBJ_COMPD hold subsidies with a minus sign.
# - FLOTAX, FLOSUB, L175-207: the positive part and the negative part of
#   OBJ_FTAX (taxes less subsidies), on the flows of ordinary processes
#   (%cal_red%) and of exchange processes (as eqobjvar.mod L74-87, without the
#   RTP_FFCS factor and with RTPCS_VARF on the auxiliary flow's source).
# - an aggregate, L210: its components' VAR_CUMCST, a component of type SUB
#   with a minus sign.

"""
    eq_bndcst!(tm::TimesModel) -> Int

Generate every EQ_BNDCST row. Returns the number of rows.

    EQ_BNDCST(R,YEAR,SUPERYR(TT,ALLYEAR),COSTCAT,CUR)\$REG_CUMCST(R,YEAR,ALLYEAR,COSTCAT,CUR,'UP') ..
      (SUM((OBJ_SUMII(R,T,P,AGE,K_EOH(LL),JOT),SPAN(AGE+MIN(ORD(LL)+ORD(JOT)-ORD(YEAR)-1,0)))\$YK(TT,T),
         SUM(INVSPRED(K_EOH,JOT,Y,K)\$YK(ALLYEAR,Y), OBJ_ICOST(R,K,P,CUR) *
           MAX(0,MIN(YEARVAL(ALLYEAR)+1,YEARVAL(Y)+ORD(AGE))-MAX(YEARVAL(YEAR),YEARVAL(Y)))) *
         VAR_NCAP(R,T,P) * OBJ_CRF(R,T,P,CUR) / OBJ_DIVI(R,T,P))\$(NOT RT_IAN(R,YEAR,ALLYEAR,CUR,'INV')) +
       SUM((T,P)\$CST_ANNC(R,T,P,TT,'INVCOST',CUR),CST_ANNC(R,T,P,TT,'INVCOST',CUR)*VAR_NCAP(R,T,P))\$RT_IAN(R,YEAR,ALLYEAR,CUR,'INV')
      )\$SAMEAS(COSTCAT,'INV') +
      SUM(RTP(R,T,P)\$(YK(TT,T)\$OBJ_DCOST(R,T,P,CUR)),
        SUM(OBJ_SUMIII(R,T,P,K_EOH,K,LL)\$YK(ALLYEAR,LL), OBJ_DCOST(R,K,P,CUR) *
          MAX(0,MIN(ORD(ALLYEAR)+1,ORD(LL)+ROUND(NCAP_DELIF(R,T,P)))-MAX(ORD(YEAR),ORD(LL)))) *
        VAR_NCAP(R,T,P) * OBJ_CRFD(R,T,P,CUR) / OBJ_DIVIII(R,T,P))\$SAMEAS(COSTCAT,'INV') +
      (SUM(OBJ_SUMII(R,T,P,AGE,K_EOH,JOT)\$(YK(TT,T)\$OBJ_ITAX(R,T,P,CUR)),
         SUM((INVSPRED(K_EOH,JOT,LL,K),SPAN(AGE+MIN(ORD(LL)-ORD(YEAR),0)))\$YK(ALLYEAR,LL),
           OBJ_ITAX(R,K,P,CUR) * (MIN(ORD(ALLYEAR)+1,ORD(LL)+ORD(AGE))-MAX(ORD(YEAR),ORD(LL)))) *
         VAR_NCAP(R,T,P) * OBJ_CRF(R,T,P,CUR) / OBJ_DIVI(R,T,P))\$(NOT RT_IAN(R,YEAR,ALLYEAR,CUR,'INVTAXSUB')) +
       SUM((T,P)\$CST_ANNC(R,T,P,TT,'INVTAX',CUR),CST_ANNC(R,T,P,TT,'INVTAX',CUR)*VAR_NCAP(R,T,P))\$RT_IAN(R,YEAR,ALLYEAR,CUR,'INVTAXSUB')
      )\$SAMEAS(COSTCAT,'INVTAX') +
      ([the same with OBJ_ISUB] - SUM((T,P)\$CST_ANNC(R,T,P,TT,'INVSUB',CUR),...)\$RT_IAN(R,YEAR,ALLYEAR,CUR,'INVTAXSUB')
      )\$SAMEAS(COSTCAT,'INVSUB') +
      SUM((OBJ_SUMIV(LL,R,T,P,JOT,LIFE),SPAN(LIFE+MIN(ORD(LL)+ORD(JOT)-ORD(YEAR)-1,0)))\$YK(TT,T),
        SUM(INVSTEP(LL,JOT,K,JOT)\$YK(ALLYEAR,K), OBJ_FOM(R,K,P,CUR) *
          MAX(0,MIN(YEARVAL(ALLYEAR)+1,YEARVAL(K)+ORD(LIFE))-MAX(YEARVAL(YEAR),YEARVAL(K)))) *
        VAR_NCAP(R,T,P) / OBJ_DIVIV(R,T,P))\$SAMEAS(COSTCAT,'FOM') +
      SUM(RTP_SHAPE(R,T,P,'1',J,JJ)\$YK(TT,T),
        SUM((OBJ_SUMIV(K,R,T,P,JOT,LIFE),INVSTEP(K,JOT,LL,JOT),SPAN(LIFE+MIN(ORD(LL)-ORD(YEAR),0)))\$YK(ALLYEAR,LL),
          SUM(OPYEAR(LIFE,AGE)\$((ORD(LL)+ORD(AGE) > ORD(YEAR))\$(ORD(LL)+ORD(AGE) < ORD(ALLYEAR)+2)),
              SHAPE(J,AGE)*MULTI(JJ,LL+(ORD(AGE)-1))-1) * OBJ_FOM(R,LL,P,CUR)) *
        VAR_NCAP(R,T,P) / OBJ_DIVIV(R,T,P))\$SAMEAS(COSTCAT,'FOM') +
      [the same two sums with OBJ_FTX, shape '2' and the condition \$OBJ_FTX(R,T,P,CUR)]\$SAMEAS(COSTCAT,'FOMTAX') +
      [the same two sums with OBJ_FSB, shape '3' and the condition \$OBJ_FSB(R,T,P,CUR)]\$SAMEAS(COSTCAT,'FOMSUB') +
      SUM(%TPULSE%
         (SUM(RHS_COMBAL(R,T,C,S), VAR_COMNET(R,T,C,S) * OBJ_COMNT(R,Y_EOH,C,S,'TAX',CUR)) +
          SUM(RHS_COMPRD(R,T,C,S), VAR_COMPRD(R,T,C,S) * OBJ_COMPD(R,Y_EOH,C,S,'TAX',CUR))))\$SAMEAS(COSTCAT,'COMTAX') -
      SUM(%TPULSE% [the same with 'SUB'])\$SAMEAS(COSTCAT,'COMSUB') +
      SUM(T\$(YK(TT,T)*(M(T)+LAGT(T) GT YEARVAL(YEAR))),
         SUM(RTPCS_VARF(R,T,P,C,S)\$OBJ_VFLO(R,P,C,CUR,'TAX'),
            SUM(TS_ANN(S,TS), SUM(%TPULSE% MAX(0,OBJ_FTAX(R,Y_EOH,P,C,TS,CUR)))) *
            SUM(RTP_VINTYR(R,V,T,P),
              [%cal_red% C COM S P T]\$(NOT RP_IRE(R,P)) +
              (SUM(RPC_IRE(R,P,C,IE), VAR_IRE(R,V,T,P,C,S,IE)\$(NOT RPC_AIRE(R,P,C)) +
                                      (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C)) +
               SUM((RPC_IRE(R,P,COM,IE),IO)\$(RTPCS_VARF(R,T,P,COM,S)\$IRE_FLOSUM(R,T,P,COM,S,IE,C,IO)),
                   IRE_FLOSUM(R,T,P,COM,S,IE,C,IO) *
                   (VAR_IRE(R,V,T,P,COM,S,IE)\$(NOT RPC_AIRE(R,P,COM)) +
                    (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,COM))\$RPC_AIRE(R,P,COM))))\$RP_IRE(R,P))))\$SAMEAS(COSTCAT,'FLOTAX') +
      [the same with OBJ_VFLO(R,P,C,CUR,'SUB') and MAX(0,-OBJ_FTAX(R,Y_EOH,P,C,TS,CUR))]\$SAMEAS(COSTCAT,'FLOSUB') +
      SUM(COST_GMAP(COSTCAT,COSTAGG,COSTYPE), VAR_CUMCST(R,YEAR,ALLYEAR,COSTAGG,CUR)*(1-2*DIAG(COSTYPE,'SUB')))
      =E= VAR_CUMCST(R,YEAR,ALLYEAR,COSTCAT,CUR);

A division is made even when the sum it follows is empty (docs/discrepancies.md
G9).

The SOW tags (sow_tags.jl): the row is `%EQ%_BNDCST(... %SOW%)\$(%SWT% ...)`
with %SWT% set to `SW_T(TT%SOW%)\$` (L78, L81): one row per SOW of period TT,
the SOW last in the index. Every cost term is `%VART%_X(..,T,.. %SWS%)`
(`at = t`; L94-204), and the flows of %cal_red% are summed the same way
(`%SWTD%(%SWSW%`, with %SOW% set to `,WW`: L83, L179, L196). The VAR_CUMCST
terms are `%VAR%_CUMCST(... %SOW%)` again (L209-213). The %SCUM% form (L79,
L162: SPINES) is change 75.

GAMS: eqbndcst.mod L78-213, v4.9.7 (a STAGES run is refused until change 74).
"""
function eq_bndcst!(tm::TimesModel)
    reg_cumcst = gparam_opt(tm.data, "REG_CUMCST", 6)
    isempty(reg_cumcst) && return 0
    x = objective_context(tm)
    sw = objective_switches(tm)
    obj_lin, var_lin = sw.obj == "LIN", sw.varcost == "LIN"                    # L84-87
    reg, yk = gset(tm, "REG"), gset(tm, "YK")
    ord, aord = x.allyear_ord, x.age_ord
    yearval = gparam(tm, "YEARVAL")
    yval(y) = gv(yearval, (y,)).v
    lead(ll, n) = (i = ord[ll] + n; 1 <= i <= length(x.allyear) ? x.allyear[i] : nothing)
    no2, no3 = NTuple{2,String}[], NTuple{3,String}[]
    superyr_of = indexby(gset(tm, "SUPERYR"), (2,))                           # (allyear,)       -> SUPERYR(tt,allyear)
    gmap_of = indexby(gset(tm, "COST_GMAP"), (1,))                            # (aggregate,)     -> COST_GMAP(aggregate,component,type)
    rt_ian = gset(tm, "RT_IAN")
    cst_annc = gparam(tm, "CST_ANNC")
    annc_of = indexby(cst_annc, (1, 4, 5, 6))                                 # (r,tt,name,cur)  -> CST_ANNC(r,t,p,tt,name,cur)
    obj_crf, obj_crfd, ncap_delif = gparam(tm, "OBJ_CRF"), gparam(tm, "OBJ_CRFD"), gparam(tm, "NCAP_DELIF")
    rtp_of_r = indexby(gset(tm, "RTP"), (1,))                                 # (r,)             -> RTP(r,t,p)
    sumiii_of = indexby(gset(tm, "OBJ_SUMIII"), (1, 2, 3))                    # (r,t,p)          -> OBJ_SUMIII(r,t,p,k_eoh,k,ll)
    invstep_of = indexby(gset(tm, "INVSTEP"), (1, 2))                         # (ll,jot)         -> INVSTEP(ll,jot,k,jot')
    sumiv_of_rtp = indexby(gset(tm, "OBJ_SUMIV"), (2, 3, 4))                  # (r,t,p)          -> OBJ_SUMIV(k,r,t,p,jot,life)
    shape_of_rcls = indexby(gset(tm, "RTP_SHAPE"), (1, 4))                    # (r,cls)          -> RTP_SHAPE(r,t,p,cls,j,jj)
    tvec = [k[1] for k in x.t.keys]
    periodyr_of = indexby(gset(tm, "PERIODYR"), (1,))                         # (t,)             -> PERIODYR(t,y)
    tpulseyr_of = indexby(gset_opt(tm.data, "TPULSEYR", 2), (1,))             # (t,)             -> TPULSEYR(t,y)
    tpulse_p = gparam_opt(tm.data, "TPULSE", 2)
    tpulse_of_y = indexby(tpulse_p, (2,))                                     # (y,)             -> TPULSE(t,y)
    combal_of_rt = indexby(gset(tm, "RHS_COMBAL"), (1, 2))                    # (r,t)            -> RHS_COMBAL(r,t,c,s)
    comprd_of_rt = indexby(gset(tm, "RHS_COMPRD"), (1, 2))                    # (r,t)            -> RHS_COMPRD(r,t,c,s)
    obj_comnt, obj_compd = gparam(tm, "OBJ_COMNT"), gparam(tm, "OBJ_COMPD")
    M, lagt = gparam(tm, "M"), gparam(tm, "LAGT")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    varf_of_r = indexby(rtpcs_varf, (1,))                                     # (r,)             -> RTPCS_VARF(r,t,p,c,s)
    obj_vflo = gset(tm, "OBJ_VFLO")
    ts_ann_of_s = indexby(gset(tm, "TS_ANN"), (1,))                           # (s,)             -> TS_ANN(s,ts)
    ob_ftax = gparam(tm, "OB_FTAX")
    vint_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))                  # (r,t,p)          -> RTP_VINTYR(r,v,t,p)
    rp_ire, rpc_aire = gset(tm, "RP_IRE"), gset(tm, "RPC_AIRE")
    ire_of_rpc = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))                      # (r,p,c)          -> RPC_IRE(r,p,c,ie)
    ire_of_rp = indexby(gset(tm, "RPC_IRE"), (1, 2))                          # (r,p)            -> RPC_IRE(r,p,com,ie)
    ire_flosum, prc_actflo = gparam(tm, "IRE_FLOSUM"), gparam(tm, "PRC_ACTFLO")
    io_set = [k[1] for k in gset(tm, "IN_OUT")]

    # %TPULSE% for the period T of a row (YEAR, ALLYEAR): the years the costs are taken at, with their weights
    function pulse(t, year, allyear)
        out = Tuple{String,GNum}[]
        for (_, y) in get(obj_lin ? tpulseyr_of : periodyr_of, (t,), no2)
            ((allyear, y) in yk && (y, year) in yk) || continue
            if !var_lin                                                       # L84-85: Y_EOH is the year
                (y,) in x.y_eoh || continue
                push!(out, (y, obj_lin ? gv(tpulse_p, (t, y)) : GNum(1.0)))
            else                                                              # L86-87: Y the year, Y_EOH a milestone year
                (y,) in x.y || continue
                for k in get(tpulse_of_y, (y,), no2)
                    m = k[1]
                    ((m,) in x.t && (m,) in x.y_eoh) || continue
                    push!(out, (m, obj_lin ? gv(tpulse_p, k) * gv(tpulse_p, (t, y)) : gv(tpulse_p, k)))
                end
            end
        end
        return out
    end
    function ire_or_act!(expr, k, r, v, t, p, c, s, ie)
        if !((r, p, c) in rpc_aire)
            addterm!(expr, k, tm, "VAR_IRE", r, v, t, p, c, s, ie; at=t)   # %VART%_IRE(... %SWS%) (L183-204)
        else
            addterm!(expr, k * gv(prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, s; at=t)   # %VART%_ACT(... %SWS%)
        end
    end
    # SUM((T,P)$CST_ANNC(R,T,P,TT,name,CUR), CST_ANNC(R,T,P,TT,name,CUR)*VAR_NCAP(R,T,P)), times `sgn`
    function annual!(lhs, name, sgn, r, tt, cur)
        for k in get(annc_of, (r, tt, name, cur), NO6)
            (k[2],) in x.t || continue
            c = gv(cst_annc, k)
            addterm!(lhs, sgn > 0 ? c : -c, tm, "VAR_NCAP", r, k[2], k[3]; at=k[2])   # %VART%_NCAP(R,T,P %SWS%) (L95, L110, L117)
        end
    end

    # L90-96 and L99-103: investment and decommissioning costs
    function inv!(lhs, r, year, tt, allyear, cur)
        if !((r, year, allyear, cur, "INV") in rt_ian)                                            # L90-94
            for (_, t, p, age, ll, jot) in get(x.sumii_of_r, (r,), NO6)
                ((t,) in x.t && (ll,) in x.k_eoh && (tt, t) in yk) || continue
                oa = aord[age]
                oa + min(ord[ll] + aord[jot] - ord[year] - 1, 0) >= 1 || continue                 # SPAN(AGE+MIN(..))
                s = GZERO
                for (_, _, y, k) in get(x.invspred_of, (ll, jot), NO4)
                    ((y,) in x.y && (k,) in x.k && (allyear, y) in yk) || continue
                    s = s + obmac(x.ob_icost, r, k, p, cur) *
                            max(0.0, min(yval(allyear) + 1, yval(y) + oa) - max(yval(year), yval(y)))
                end
                addterm!(lhs, s * gv(obj_crf, (r, t, p, cur)) / gv(x.obj_divi, (r, t, p)), tm, "VAR_NCAP", r, t, p; at=t)
            end
        else                                                                                      # L95
            annual!(lhs, "INVCOST", 1, r, tt, cur)
        end
        for (_, t, p) in get(rtp_of_r, (r,), no3)                                                 # L99-103
            ((t,) in x.t && (tt, t) in yk) || continue
            iszero(obmac(x.ob_dcc, r, t, p, cur)) && continue
            dl = glead(gv(ncap_delif, (r, t, p)).v)
            s = GZERO
            for (_, _, _, ke, k, ll) in get(sumiii_of, (r, t, p), NO6)
                ((ke,) in x.k_eoh && (k,) in x.k && (allyear, ll) in yk) || continue
                s = s + obmac(x.ob_dcc, r, k, p, cur) * max(0, min(ord[allyear] + 1, ord[ll] + dl) - max(ord[year], ord[ll]))
            end
            addterm!(lhs, s * gv(obj_crfd, (r, t, p, cur)) / gv(x.obj_diviii, (r, t, p)), tm, "VAR_NCAP", r, t, p; at=t)
        end
    end
    # L106-111 (INVTAX: OBJ_ITAX, +CST_ANNC) and L113-118 (INVSUB: OBJ_ISUB, -CST_ANNC)
    function invtaxsub!(lhs, ob, name, sgn, r, year, tt, allyear, cur)
        if (r, year, allyear, cur, "INVTAXSUB") in rt_ian
            return annual!(lhs, name, sgn, r, tt, cur)
        end
        for (_, t, p, age, ke, jot) in get(x.sumii_of_r, (r,), NO6)
            ((t,) in x.t && (ke,) in x.k_eoh && (tt, t) in yk) || continue
            iszero(obmac(ob, r, t, p, cur)) && continue
            oa = aord[age]
            s = GZERO
            for (_, _, ll, k) in get(x.invspred_of, (ke, jot), NO4)
                ((k,) in x.k && (allyear, ll) in yk && oa + min(ord[ll] - ord[year], 0) >= 1) || continue
                s = s + obmac(ob, r, k, p, cur) * (min(ord[allyear] + 1, ord[ll] + oa) - max(ord[year], ord[ll]))
            end
            addterm!(lhs, s * gv(obj_crf, (r, t, p, cur)) / gv(x.obj_divi, (r, t, p)), tm, "VAR_NCAP", r, t, p; at=t)
        end
    end
    # L121-132 (FOM), L135-146 (FOMTAX), L149-160 (FOMSUB): `ob` with the shape class `cls`;
    # `cond` is the condition $OBJ_FTX(R,T,P,CUR) / $OBJ_FSB(R,T,P,CUR) of the tax and subsidy terms
    function fixed!(lhs, ob, cls, cond, r, year, tt, allyear, cur)
        for (ll, _, t, p, jot, life) in get(x.sumiv_of_r, (r,), NO6)                              # shaped or not
            ((t,) in x.t && (tt, t) in yk) || continue
            (cond && iszero(obmac(ob, r, t, p, cur))) && continue
            ol = aord[life]
            ol + min(ord[ll] + aord[jot] - ord[year] - 1, 0) >= 1 || continue                     # SPAN(LIFE+MIN(..))
            s = GZERO
            for (_, _, k, jot2) in get(invstep_of, (ll, jot), NO4)
                (jot2 == jot && (k,) in x.k && (allyear, k) in yk) || continue
                s = s + obmac(ob, r, k, p, cur) *
                        max(0.0, min(yval(allyear) + 1, yval(k) + ol) - max(yval(year), yval(k)))
            end
            addterm!(lhs, s / gv(x.obj_diviv, (r, t, p)), tm, "VAR_NCAP", r, t, p; at=t)
        end
        for (_, t, p, _, j, jj) in get(shape_of_rcls, (r, cls), NO6)                              # shaped
            ((t,) in x.t && (tt, t) in yk) || continue
            (cond && iszero(obmac(ob, r, t, p, cur))) && continue
            s = GZERO
            for (k, _, _, _, jot, life) in get(sumiv_of_rtp, (r, t, p), NO6)
                (k,) in x.k || continue
                ol = aord[life]
                for (_, _, ll, jot2) in get(invstep_of, (k, jot), NO4)
                    (jot2 == jot && (allyear, ll) in yk && ol + min(ord[ll] - ord[year], 0) >= 1) || continue
                    a = GZERO
                    for (_, age) in get(x.opyear_of_life, (life,), no2)
                        oa = aord[age]
                        (ord[ll] + oa > ord[year] && ord[ll] + oa < ord[allyear] + 2) || continue
                        y = lead(ll, oa - 1)
                        a = a + (gv(x.shape, (j, age)) * (y === nothing ? GZERO : gv(x.multi, (jj, y))) - 1)
                    end
                    s = s + a * obmac(ob, r, ll, p, cur)
                end
            end
            addterm!(lhs, s / gv(x.obj_diviv, (r, t, p)), tm, "VAR_NCAP", r, t, p; at=t)
        end
    end
    # L164-167 (COMTAX: 'TAX', added) and L169-172 (COMSUB: 'SUB', subtracted); every period T
    function commodity!(lhs, ctype, sgn, r, year, allyear, cur)
        for t in tvec
            pw = pulse(t, year, allyear)
            isempty(pw) && continue
            for (set_of, par, var) in ((combal_of_rt, obj_comnt, "VAR_COMNET"), (comprd_of_rt, obj_compd, "VAR_COMPRD"))
                for (_, _, c, s) in get(set_of, (r, t), NO4)
                    (c,) in x.com || continue
                    w = GZERO
                    for (y, wy) in pw
                        w = w + wy * gv(par, (r, y, c, s, ctype, cur))
                    end
                    addterm!(lhs, sgn > 0 ? w : -w, tm, var, r, t, c, s; at=t)   # %VART%_COMNET/COMPRD(R,T,C,S %SWS%) (L165-171)
                end
            end
        end
    end
    # L175-190 (FLOTAX: MAX(0,OBJ_FTAX)) and L192-207 (FLOSUB: MAX(0,-OBJ_FTAX))
    function flow!(lhs, ctype, sgn, r, year, tt, allyear, cur)
        pulses = Dict{String,Vector{Tuple{String,GNum}}}()
        for (_, t, p, c, s) in get(varf_of_r, (r,), NO5)
            ((t,) in x.t && (tt, t) in yk && gv(M, (t,)).v + gv(lagt, (t,)).v > yval(year)) || continue
            (r, p, c, cur, ctype) in obj_vflo || continue
            pw = get!(() -> pulse(t, year, allyear), pulses, t)
            w = GZERO
            for (_, ts) in get(ts_ann_of_s, (s,), no2), (y, wy) in pw
                f = obmac(ob_ftax, r, y, p, c, ts, cur)
                w = w + wy * gmax(GZERO, sgn > 0 ? f : -f)
            end
            iszero(w) && continue
            for (_, v, _, _) in get(vint_of_rtp, (r, t, p), NO4)
                (v,) in x.v || continue
                if !((r, p) in rp_ire)
                    cal_nored!(lhs, tm, w, r, v, t, p, c, s; at=t)  # %SWTD%(%SWSW% ...): SUM(SW_TSW(SOW,T,WW),..), %SOW% as ,WW (L83, L179, L196);                                    # %cal_red% C COM S P T
                else
                    for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), NO4)
                        ire_or_act!(lhs, w, r, v, t, p, c, s, ie)
                    end
                    for (_, _, com, ie) in get(ire_of_rp, (r, p), NO4), io in io_set
                        fs = (r, t, p, com, s, ie, c, io)
                        ((r, t, p, com, s) in rtpcs_varf && haskey(ire_flosum, fs)) || continue
                        ire_or_act!(lhs, w * gv(ire_flosum, fs), r, v, t, p, com, s, ie)
                    end
                end
            end
        end
    end

    rows = NTuple{6,String}[]
    for (r, year, allyear, cat, cur, bd) in reg_cumcst.keys                                       # L81
        (bd == "UP" && (r,) in reg && haskey(ord, year) && haskey(ord, allyear)) || continue
        for (tt, _) in get(superyr_of, (allyear,), no2)
            (tt,) in x.t && push!(rows, (r, year, tt, allyear, cat, cur))
        end
    end
    gams_sort!(rows, tm.data)
    n = 0
    for (r, year, tt, allyear, cat, cur) in rows
        for sow in sw_rows(tm, tt)   # %SOW% with the local %SWT%, SW_T(TT,SOW) (L78, L81)
            set_sow!(tm, sow)
            lhs = JuMP.AffExpr(0.0)
            if cat == "INV"
                inv!(lhs, r, year, tt, allyear, cur)
            elseif cat == "INVTAX"
                invtaxsub!(lhs, x.ob_itax, "INVTAX", 1, r, year, tt, allyear, cur)
            elseif cat == "INVSUB"
                invtaxsub!(lhs, x.ob_isub, "INVSUB", -1, r, year, tt, allyear, cur)
            elseif cat == "FOM"
                fixed!(lhs, x.ob_fom, "1", false, r, year, tt, allyear, cur)
            elseif cat == "FOMTAX"
                fixed!(lhs, x.ob_ftx, "2", true, r, year, tt, allyear, cur)
            elseif cat == "FOMSUB"
                fixed!(lhs, x.ob_fsb, "3", true, r, year, tt, allyear, cur)
            elseif cat == "COMTAX"
                commodity!(lhs, "TAX", 1, r, year, allyear, cur)
            elseif cat == "COMSUB"
                commodity!(lhs, "SUB", -1, r, year, allyear, cur)
            elseif cat == "FLOTAX"
                flow!(lhs, "TAX", 1, r, year, tt, allyear, cur)
            elseif cat == "FLOSUB"
                flow!(lhs, "SUB", -1, r, year, tt, allyear, cur)
            end
            for (_, agg, ctype) in get(gmap_of, (cat,), no3)                                          # L210
                addterm!(lhs, GNum(ctype == "SUB" ? -1.0 : 1.0), tm, "VAR_CUMCST", r, year, allyear, agg, cur)
            end
            rhs = addterm!(JuMP.AffExpr(0.0), GNum(1.0), tm, "VAR_CUMCST", r, year, allyear, cat, cur)  # L213
            gconstraint!(tm, eqtag(tm, "EQ_BNDCST"), sowkey(tm, (r, year, tt, allyear, cat, cur)), "E", lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
