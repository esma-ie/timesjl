# M1.3 change 50: costs on the components of a commodity's balance, COM_CSTBAL (VDA, powerflo.vda
# labels CSTBAL and OBJBAL). Both labels are included whenever COM_CSTBAL is DEFINED, with or without
# a power-flow grid (%POWERFLO%): CSTBAL from coef_ext.vda L80 (after eqashar.vda, L79), OBJBAL from
# equ_ext.vda L100 (after ucbet.vda, L99), and mod_ext.vda L42-43 put EQ_OBJBAL in the model.
#
# CSTBAL (L372-395) levels COM_CSTBAL to the commodity timeslices (pp_lvlfc.mod with %11 = N: only the
# records flagged at year '0' are moved, the others stay at their own timeslice) and turns it into
# OBJ_COMBAL(R,T,C,S,ITEM,CUR), the cost per unit of each component at each commodity timeslice, a
# value at S itself plus one at ANNUAL (TS_ANN, coef_obj.mod L16-18):
# - for a commodity with data that is not a grid node allocation (TRACKC): 'PRD' (PRD+CON+OUT) on
#   the production VAR_COMPRD, which L387 adds to RHS_COMPRD (fixed, RCS_COMPRD 'FX'), and 'IMP'
#   (IMP+NTX-PRD) and 'EXP' (EXP-NTX-CON) on the trade flows;
# - for a grid node (RC_GRID, powerflo.vda main block): 'GEN' (PRD+CON), 'NTX' (NTX+CON), 'IMP' and
#   'EXP' as given, and 'NPG' (net positive generation), whose data also adds the node to the group
#   'FIN' (GR_ALLMAP, GR_ALGMAP).
# OBJBAL (L398-434) sums the costs, weighted by OBJ_LINT over the periods, into VAR_OBJ(R,'OBJBAL',CUR),
# which EQ_OBJ counts through OBV (L374 adds OBJBAL to OBV at compile time, so every dump has it).
#
# Not translated: the stochastic indexes (%STAGES%, refused for the whole model).

"""
    cstbal_prep!(tm) -> tm

powerflo.vda CSTBAL (coef_ext.vda L80, `\$IF DEFINED COM_CSTBAL`), nothing without COM_CSTBAL data:

    \$IF NOT DEFINED RC_GRID OPTION CLEAR=RC_GRID,...,CLEAR=GR_ENDC;                              (L379)
    \$BATINCLUDE pp_lvlfc.mod COM_CSTBAL C COM_TS ',ITEM,CUR' ",'0','0'" ALL_TS T RTC(R,T,C) '' '' N   (L381)
    OPTION TRACKC < COM_CSTBAL;                                                                 (L382)
    TRACKC(R,C)\$SUM(GR_ALLMAP(R,C,COM),1)=NO;                                                   (L383)
    OBJ_COMBAL(RTCS_VARC(RTC(R,T,C),TS),'PRD',CUR)\$TRACKC(R,C) = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,'PRD',CUR)+COM_CSTBAL(RTC,S,'CON',CUR)+COM_CSTBAL(RTC,S,'OUT',CUR));
    OBJ_COMBAL(RTCS_VARC(RTC(R,T,C),TS),'IMP',CUR)\$TRACKC(R,C) = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,'IMP',CUR)+COM_CSTBAL(RTC,S,'NTX',CUR)-COM_CSTBAL(RTC,S,'PRD',CUR));
    OBJ_COMBAL(RTCS_VARC(RTC(R,T,C),TS),'EXP',CUR)\$TRACKC(R,C) = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,'EXP',CUR)-COM_CSTBAL(RTC,S,'NTX',CUR)-COM_CSTBAL(RTC,S,'CON',CUR));
    LOOP(RDCUR(R,CUR),RHS_COMPRD(RTCS_VARC(R,T,C,S))\$OBJ_COMBAL(R,T,C,S,'PRD',CUR)=YES); RCS_COMPRD(RHS_COMPRD(R,T,C,S),'FX')\$TRACKC(R,C) = YES;
    OBJ_COMBAL(RTCS_VARC(RTC(RC_GRID),TS),'GEN',CUR) = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,'PRD',CUR)+COM_CSTBAL(RTC,S,'CON',CUR));
    OBJ_COMBAL(RTCS_VARC(RTC(RC_GRID),TS),'NTX',CUR) = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,'NTX',CUR)+COM_CSTBAL(RTC,S,'CON',CUR));
    OBJ_COMBAL(RTCS_VARC(RTC(RC_GRID),TS),IE,CUR)    = SUM(TS_ANN(TS,S),COM_CSTBAL(RTC,S,IE,CUR));
    OPTION CLEAR=UNCD7; UNCD7(R,T--ORD(T),C,S--ORD(S),CUR,'','')\$RC_GRID(R,T,C) \$= COM_CSTBAL(R,T,C,S,'NPG',CUR);
    LOOP(UNCD7(R,TT,C,SL,CUR,'',''), GR_ALLMAP(R,'FIN',C) = YES; GR_ALGMAP(R,CG('FIN'),CG) = YES;
      OBJ_COMBAL(RC_GRID(R,T,C),TS,'NPG',CUR) \$= SUM(TS_ANN(TS,S),COM_CSTBAL(R,T,C,S,'NPG',CUR)));
    OPTION CLEAR=TRACKC;                                                                        (L395)

The three plain assignments of each block run over every CUR (an exact zero stores nothing and
removes what an earlier line put there, G11). `T--ORD(T)` and `S--ORD(S)` lag each element
circularly by its own position, which lands on the last element of T and of ALL_TS (G31), so UNCD7
holds one entry per grid node and currency with NPG data. `GR_ALLMAP(R,CG('FIN'),CG)`: the second CG
is the one the first fixes, so the entry is (R,'FIN','FIN').

GAMS: powerflo.vda L372-395, coef_ext.vda L80, v4.9.7.
"""
function cstbal_prep!(tm::TimesModel)
    hasdata(tm, "COM_CSTBAL", 6) || return tm
    d = tm.data
    # Labels the code names itself, which the dump it starts from may not hold (G36)
    foreach(l -> register_uel!(d, l), ("PRD", "IMP", "EXP", "GEN", "NTX", "NPG", "FIN", "FX", ""))
    tr = TsTree(tm)
    tlist = [k[1] for k in gset(tm, "MILESTONYR").keys]
    tset = Set(tlist)
    rtc = gset(tm, "RTC")
    comts = indexby(gset(tm, "COM_TS"), (1, 2))                         # (r,c) -> COM_TS(r,c,s)
    targets(k) = [x[3] for x in get(comts, (k[1], k[3]), NTuple{3,String}[])]
    # L381: the levelling, %7 = T (the milestone years), %8 = RTC(R,T,C), %11 = N
    _, ts_array = pp_lvlfc!(tm, tr, "COM_CSTBAL", 6; sp=4, years=tset, keyok=k -> true, targets,
                            qual=k -> (k[1], k[2], k[3]) in rtc, p11="N")
    ts_array === nothing || gput!(tm, "TS_ARRAY", Dict{Tuple{String},Float64}((s,) => v for (s, v) in ts_array))
    cst = gvalues(tm, "COM_CSTBAL", 6)
    cv(r, t, c, s, item, cur) = gv(cst, (r, t, c, s, item, cur))
    # L382-383: TRACKC
    allmap = gset_opt(d, "GR_ALLMAP", 3)
    in_allmap = Set((k[1], k[2]) for k in allmap.keys)                  # SUM(GR_ALLMAP(R,C,COM),1)
    trackc = Set((k[1], k[3]) for k in keys(cst) if !((k[1], k[3]) in in_allmap))
    curs = [k[1] for k in gset(tm, "CUR").keys]
    # SUM(TS_ANN(TS,S), f(S)): f(TS), plus f('ANNUAL') when TS is not ANNUAL
    tsann(f, ts) = ts == "ANNUAL" ? f("ANNUAL") : f(ts) + f("ANNUAL")
    obj = Dict{NTuple{6,String},Float64}()
    varc = gset(tm, "RTCS_VARC")
    # L384-386
    for (r, t, c, ts) in varc
        ((r, t, c) in rtc && (r, c) in trackc) || continue
        for cur in curs
            gassign!(obj, (r, t, c, ts, "PRD", cur), tsann(s -> cv(r, t, c, s, "PRD", cur) + cv(r, t, c, s, "CON", cur) + cv(r, t, c, s, "OUT", cur), ts))
            gassign!(obj, (r, t, c, ts, "IMP", cur), tsann(s -> cv(r, t, c, s, "IMP", cur) + cv(r, t, c, s, "NTX", cur) - cv(r, t, c, s, "PRD", cur), ts))
            gassign!(obj, (r, t, c, ts, "EXP", cur), tsann(s -> cv(r, t, c, s, "EXP", cur) - cv(r, t, c, s, "NTX", cur) - cv(r, t, c, s, "CON", cur), ts))
        end
    end
    # L387: RHS_COMPRD and RCS_COMPRD
    rhs_comprd = gmembers(tm, "RHS_COMPRD", 4)
    for (r, cur) in gset(tm, "RDCUR").keys, (rr, t, c, s) in varc
        rr == r && haskey(obj, (r, t, c, s, "PRD", cur)) && push!(rhs_comprd, (r, t, c, s))
    end
    gput!(tm, "RHS_COMPRD", rhs_comprd)
    rcs_comprd = gmembers(tm, "RCS_COMPRD", 5)
    foreach(k -> (k[1], k[3]) in trackc && push!(rcs_comprd, (k..., "FX")), rhs_comprd)
    gput!(tm, "RCS_COMPRD", rcs_comprd)
    # L388-390: the grid nodes
    rc_grid = gset_opt(d, "RC_GRID", 3)
    for (r, t, c, ts) in varc
        ((r, t, c) in rc_grid && (r, t, c) in rtc) || continue
        for cur in curs
            gassign!(obj, (r, t, c, ts, "GEN", cur), tsann(s -> cv(r, t, c, s, "PRD", cur) + cv(r, t, c, s, "CON", cur), ts))
            gassign!(obj, (r, t, c, ts, "NTX", cur), tsann(s -> cv(r, t, c, s, "NTX", cur) + cv(r, t, c, s, "CON", cur), ts))
            for ie in ("IMP", "EXP")
                gassign!(obj, (r, t, c, ts, ie, cur), tsann(s -> cv(r, t, c, s, ie, cur), ts))
            end
        end
    end
    # L392-394: UNCD7 and the NPG costs of the grid nodes
    lastt, lasts = tlist[end], last(tr.all_ts)
    uncd7 = Set{NTuple{7,String}}()
    for (k, v) in cst
        (k[5] == "NPG" && (k[1], k[2], k[3]) in rc_grid && (k[2] in tset)) || continue
        push!(uncd7, (k[1], lastt, k[3], lasts, k[6], "", ""))
    end
    if !isempty(uncd7)
        allm, algm = gmembers(tm, "GR_ALLMAP", 3), gmembers(tm, "GR_ALGMAP", 3)
        grid_of_rc = indexby(rc_grid, (1, 3))                           # (r,c) -> RC_GRID(r,t,c)
        for (r, _, c, _, cur, _, _) in gams_sort!(collect(uncd7), d)
            push!(allm, (r, "FIN", c)); push!(algm, (r, "FIN", "FIN"))
            for (_, t, _) in get(grid_of_rc, (r, c), NTuple{3,String}[]), ts in tr.all_ts
                x = tsann(s -> cv(r, t, c, s, "NPG", cur), ts)
                iszero(x) || gassign!(obj, (r, t, c, ts, "NPG", cur), x)       # \$=
            end
        end
        gput!(tm, "GR_ALLMAP", allm); gput!(tm, "GR_ALGMAP", algm)
    end
    gput!(tm, "UNCD7", uncd7)
    gput!(tm, "OBJ_COMBAL", obj)
    gput!(tm, "TRACKC", Set{NTuple{2,String}}())                         # L395
    return tm
end

"""
    eq_objbal!(tm) -> Int

EQ_OBJBAL (powerflo.vda OBJBAL, equ_ext.vda L100; mod_ext.vda L42-43), one row for each RDCUR(R,CUR),
nothing without COM_CSTBAL data. With %TPULSE% = `TT\$OBJ_LINT(R,T,TT,CUR),OBJ_LINT(R,T,TT,CUR)` (L399):

    EQ_OBJBAL(RDCUR(R,CUR))..
      VAR_OBJ(R,'OBJBAL',CUR) =E=
      SUM(RHS_COMPRD(R,T,C,S),VAR_COMPRD(R,T,C,S) * SUM(%TPULSE% * OBJ_COMBAL(R,TT,C,S,'PRD',CUR))) +
      SUM(RTCS_VARC(RC_GRID(R,T,C),S)\$OBJ_COMBAL(R,T,C,S,'GEN',CUR),
        (SUM(GR_ALGMAP(R,CG,COM)\$GR_ALLMAP(R,C,COM),VAR_GRIDIO(R,T,COM,C,S,'OUT') + VAR_GRIDIO(R,T,COM,C,S,'IN')\$GR_ALGMAP(R,COM,COM))+
         SUM((GR_PRCMAP(RP_STD(R,P),COM,ITEM),GR_ENDC(R,NRG_GRID,COM)), GR_GENMAP(R,P,ITEM)*GR_GENFR(R,T,C,ITEM) *
           SUM((RTP_VINTYR(R,V,T,P),RTPCS_VARF(R,T,P,COM,TS))\$RS_FR(R,S,TS), [cal_red COM COM1 TS P T] * RS_FR(R,S,TS)))) *
        SUM(%TPULSE% * OBJ_COMBAL(R,TT,C,S,'GEN',CUR))) +
      SUM(RTCS_VARC(RC_GRID(R,T,C),S)\$OBJ_COMBAL(R,T,C,S,'NTX',CUR),
        SUM(GR_DEMMAP(R,C,COM),VAR_GRIDIO(R,T,COM,C,S,'IN')\$GR_ALGMAP(R,'NRG',COM) - VAR_GRIDIO(R,T,COM,C,S,'OUT')) *
        SUM(%TPULSE% * OBJ_COMBAL(R,TT,C,S,'NTX',CUR))) +
      SUM(RTCS_VARC(RC_GRID(R,T,C),S)\$OBJ_COMBAL(R,T,C,S,'NPG',CUR),
        VAR_GRIDIO(R,T,C,C,S,'OUT') * SUM(%TPULSE% * MAX(0,OBJ_COMBAL(R,TT,C,S,'NPG',CUR)))) +
      SUM((RTPCS_VARF(R,T,P,C,S),RPC_IRE(R,P,C,IE))\$OBJ_COMBAL(R,T,C,S,IE,CUR),
        SUM(RTP_VINTYR(R,V,T,P),
          (VAR_IRE(R,V,T,P,C,S,IE)\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))) *
        SUM(%TPULSE% * OBJ_COMBAL(R,TT,C,S,IE,CUR)));

The GEN sums count a term once for each CG of GR_ALGMAP(R,CG,COM) and each NRG_GRID of GR_ENDC, as
the GAMS sums are written. The `\$OBJ_COMBAL(R,T,...)` conditions read period T, the weights the
periods TT. Returns the number of rows.

GAMS: powerflo.vda L398-434, equ_ext.vda L100, mod_ext.vda L42-43, v4.9.7.
"""
function eq_objbal!(tm::TimesModel)
    hasdata(tm, "COM_CSTBAL", 6) || return 0
    d = tm.data
    obj = gparam(tm, "OBJ_COMBAL")
    lint = gparam(tm, "OBJ_LINT")
    lint_of = indexby(lint, (1, 2, 4))                                  # (r,t,cur) -> OBJ_LINT(r,t,tt,cur)
    no4 = NTuple{4,String}[]
    # SUM(%TPULSE% * f(OBJ_COMBAL(R,TT,C,S,item,CUR)))
    function wsum(r, t, c, s, item, cur; f=identity)
        w = GZERO
        for (_, _, tt, _) in get(lint_of, (r, t, cur), no4)
            w = w + gv(lint, (r, t, tt, cur)) * f(gv(obj, (r, tt, c, s, item, cur)))
        end
        return w
    end
    has(r, t, c, s, item, cur) = haskey(obj.values, (r, t, c, s, item, cur))
    rc_grid = gset_opt(d, "RC_GRID", 3)
    grid = !isempty(rc_grid)
    grid && powerflo_vars!(tm)
    x = grid ? gralloc_context(tm) : nothing
    varc_of = indexby(gset(tm, "RTCS_VARC"), (1, 2, 3))                  # (r,t,c) -> RTCS_VARC(r,t,c,s)
    vint_of = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))                 # (r,t,p) -> RTP_VINTYR(r,v,t,p)
    varf_of = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))              # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    varf_of_r = indexby(gset(tm, "RTPCS_VARF"), (1,))                    # r -> RTPCS_VARF(r,t,p,c,s)
    ire_of = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))                     # (r,p,c) -> RPC_IRE(r,p,c,ie)
    comprd_of_r = indexby(gset(tm, "RHS_COMPRD"), (1,))                  # r -> RHS_COMPRD(r,t,c,s)
    grid_of_r = indexby(rc_grid, (1,))                                   # r -> RC_GRID(r,t,c)
    rs_fr, rp_std = gparam(tm, "RS_FR"), gset(tm, "RP_STD")
    one = GNum(1.0)
    n = 0
    for (r, cur) in gset(tm, "RDCUR").keys
        lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
        addterm!(lhs, one, tm, "VAR_OBJ", r, "OBJBAL", cur)                                  # L405
        for (_, t, c, s) in get(comprd_of_r, (r,), no4)                                       # L410
            addterm!(rhs, wsum(r, t, c, s, "PRD", cur), tm, "VAR_COMPRD", r, t, c, s)
        end
        if grid
            for (_, t, c) in get(grid_of_r, (r,), NTuple{3,String}[]), (_, _, _, s) in get(varc_of, (r, t, c), no4)
                if has(r, t, c, s, "GEN", cur)                                                 # L411-416
                    w = wsum(r, t, c, s, "GEN", cur)
                    for (rr, cg, com) in x.algmap                                              # SUM(GR_ALGMAP(R,CG,COM)$GR_ALLMAP(R,C,COM), ...)
                        (rr == r && (r, c, com) in x.allmap) || continue
                        addterm!(rhs, w, tm, "VAR_GRIDIO", r, t, com, c, s, "OUT")
                        (r, com, com) in x.algmap && addterm!(rhs, w, tm, "VAR_GRIDIO", r, t, com, c, s, "IN")
                    end
                    for (_, p, com, item) in get(x.prcmap_of_r, (r,), no4)
                        (r, p) in rp_std || continue
                        k0 = gv(x.genmap, (r, p, item)) * gv(x.genfr, (r, t, c, item))
                        for (rr, ng, cc) in x.endc
                            (rr == r && cc == com) || continue                                # GR_ENDC(R,NRG_GRID,COM)
                            for (_, v, _, _) in get(vint_of, (r, t, p), no4), (_, _, _, _, ts) in get(varf_of, (r, t, p, com), NTuple{5,String}[])
                                haskey(rs_fr, (r, s, ts)) || continue
                                cal_nored!(rhs, tm, k0 * gv(rs_fr, (r, s, ts)) * w, r, v, t, p, com, ts)
                            end
                        end
                    end
                end
                if has(r, t, c, s, "NTX", cur)                                                 # L419-421
                    w = wsum(r, t, c, s, "NTX", cur)
                    for (_, _, com) in get(x.dem_by_12, (r, c), NTuple{3,String}[])
                        (r, "NRG", com) in x.algmap && addterm!(rhs, w, tm, "VAR_GRIDIO", r, t, com, c, s, "IN")
                        addterm!(rhs, -w, tm, "VAR_GRIDIO", r, t, com, c, s, "OUT")
                    end
                end
                if has(r, t, c, s, "NPG", cur)                                                 # L424-425
                    addterm!(rhs, wsum(r, t, c, s, "NPG", cur; f=v -> gmax(GZERO, v)), tm, "VAR_GRIDIO", r, t, c, c, s, "OUT")
                end
            end
        end
        for (_, t, p, c, s) in get(varf_of_r, (r,), NTuple{5,String}[])                       # L428-431
            for (_, _, _, ie) in get(ire_of, (r, p, c), no4)
                has(r, t, c, s, ie, cur) || continue
                w = wsum(r, t, c, s, ie, cur)
                for (_, v, _, _) in get(vint_of, (r, t, p), no4)
                    gr_trade!(rhs, tm, w, r, v, t, p, c, s, ie)
                end
            end
        end
        gconstraint!(tm, "EQ_OBJBAL", (r, cur, "1"), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
