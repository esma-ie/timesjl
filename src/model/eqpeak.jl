# EQ_PEAK: commodity peaking constraint. For each peak commodity group and
# peak timeslice, capacity (and flow) contributions de-rated by the reserve
# margin must cover consumption plus flexibility.
#
# GAMS: eqpeak.mod L15-87, v4.9.7, included from eqmain.mod L159 as
# `$BATINCLUDE eqpeak.mod mod`; declared eqdeclr.mod L116
# (R,ALLYEAR,COM_GRP,S), type =G=. Its includes, with the arguments passed:
#   L31  cal_ire.mod  IMP OUT IE '*NCAP_PKCNT(R,V,P,S)' -
#   L32  cal_ire.mod  EXP IN IE '*(-NCAP_PKCNT(R,V,P,S)/COM_IE(R,T,C,S))$(COM_IE(R,T,C,S)>0)' - PRC_PKNO( )
#   L41  cal_stgn.mod OUT IN '*STG_EFF(R,V,P)' '' "(NOT PRC_NSTTS(R,P,TS))" '*(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C))$RPC_PKF(R,P,C)'
#   L44  cal_fflo.mod OUT O '*(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C))' '$RPC_PKF(R,P,C)'
#   L65  cal_fflo.mod IN I '*FLO_PKCOI(R,T,P,C,TS)'
#   L68  cal_ire.mod  EXP IN IE '*FLO_PKCOI(R,T,P,C,TS)' -
#   L72  cal_cap.mod  IN I '1$(NOT PRC_PKNO(R,P))*' (capacity flows; refused)
#   L75  cal_stgn.mod IN OUT '' 'STG_EFF(R,V,P)*(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C))*' "((NOT PRC_MAP(R,'NST',P))+PRC_NSTTS(R,P,TS))" "$RPC_PKF(R,P,C)"
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV% -> VAR, %SOW%/%SWT%/%SWS% -> ''
# (setglobs.gms L348); %R_T% -> 'R,T' (maindrv.mod L39); RTS(SL) -> SL
# (timslice.mod L39; NORTS refused, see eqptrans.jl); %RCAPSUB% is the -VAR_SCAP
# term of early retirement (prepret.dsc L87, `rcapsub!`; M1.3 change 20b-2); COM_FR%MX% -> COM_FR (the $SET MX of
# cal_ire.mod L16 is scoped to that include). Index sets: T = MILESTONYR
# (initmty.mod L94), V = MODLYEAR (setglobs.gms L147), SL = ALL_TS
# (initmty.mod L89), CG2 = COM_GRP (initsys.mod L96).
#
# GAMS semantics used (docs/discrepancies.md): SUM(COM(CG2),x(COM)) with CG2
# controlled is x(CG2) when CG2 is a commodity, else 0 (G14); MAX treats EPS
# as 0 (G14); `**` is gpow (G13); `(x/y)$(y>0)` is not evaluated when the
# condition is false (G14).
#
# Not translated yet; data that needs them raises UnportedError:
# - capacity-related flows, cal_cap.mod L72 (NCAP_COM, RPC_CAPFLO);
# - blending, L78 (BLE_OPR);
# - elastic demand, L85 under %TIMESED% (COM_ELAST); VAR_DEM, L82 (RD_NLP);
# - the IER extraction-condensing CHP adjustment, L49 (%PEAKCHP%);
# - %IREAUXBAL% in cal_ire.mod L30 other than from powerflo.vda DECL (its IREAUX
#   terms, L31, are `ireaux!`: M1.3 change 27b-2). (REDUCE YES goes through cal_fflo_red!, M1.3 change 17b.)
# The sets read (COM_PKTS, RPC_PKC, RPC_PKF, COEF_VNT, RTPCS_VARF, ...) come
# from the pre-solve dump; pp_lvlpk.mod and pp_reduce.red L185 fill them.

function peak_unported(tm::TimesModel)
    d = tm.data
    nonempty_set(name, N) = !isempty(gset_opt(d, name, N))
    nonempty_par(name, N) = !isempty(gparam_opt(d, name, N))
    (nonempty_par("NCAP_COM", 5) || nonempty_set("RPC_CAPFLO", 4)) &&
        throw(UnportedError("eqpeak.mod L72 capacity-related flows, cal_cap.mod (NCAP_COM / RPC_CAPFLO)"))
    nonempty_set("BLE_OPR", 3) && throw(UnportedError("eqpeak.mod L78 blending (BLE_OPR)"))
    nonempty_par("COM_ELAST", 5) && throw(UnportedError("eqpeak.mod L85 elastic demand under %TIMESED% (COM_ELAST)"))
    nonempty_par("RD_NLP", 2) && throw(UnportedError("eqpeak.mod L82 non-linear demand VAR_DEM (RD_NLP)"))
    haskey(tm.switches, "PEAKCHP") && throw(UnportedError("eqpeak.mod L49 %PEAKCHP% (IER extension, prep_ext.ier L21)"))
    # %IREAUXBAL% comes from powerflo.vda DECL (L221) under %POWERFLO% (`ireaux!`); set any other way, refused
    haskey(tm.switches, "IREAUXBAL") && !powerflo_on(tm) && throw(UnportedError("cal_ire.mod L30 under %IREAUXBAL% without %POWERFLO%"))
    return nothing
end

"""
    eq_peak!(tm::TimesModel) -> Int

Generate every EQ_PEAK row from `tm.data`. Returns the number of rows.

    EQ_PEAK(R,T,CG2,SL)\$(SUM(COM_GMAP(R,CG2,C)\$RTC(R,T,C),1)\$COM_PKTS(R,CG2,SL)) ..
      SUM((COM_GMAP(R,CG2,C),COM_TS(R,C,S))\$RS_FR(R,SL,S),
        RS_FR(R,SL,S) * (1/(1+MAX(SUM(COM(CG2),COM_PKRSV(R,T,COM)),COM_PKRSV(R,T,C)))) * COM_IE(R,T,C,S) *
        ( SUM(RPC_PKC(R,P,C), G_YRFR(R,S) * PRC_CAPACT(R,P) *
              SUM(V\$COEF_VNT(R,T,P,V), COEF_VNT(R,T,P,V)*PRC_ACTFLO(R,V,P,C)*NCAP_PKCNT(R,V,P,S)*
                  (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)))) +
          [cal_ire IMP OUT IE, *NCAP_PKCNT(R,V,P,S)] +
          [cal_ire EXP IN IE over PRC_PKNO, *(-NCAP_PKCNT(R,V,P,S)/COM_IE(R,T,C,S))\$(COM_IE(R,T,C,S)>0)] +
          ( [cal_stgn OUT IN, *(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C))\$RPC_PKF(R,P,C)] +
            [cal_fflo OUT, *(NCAP_PKCNT(R,V,P,S)**RPC_PKF(R,P,C)), \$RPC_PKF(R,P,C)] + 0)))
      =G=
      SUM((COM_GMAP(R,CG2,C),COM_TS(R,C,S))\$RS_FR(R,SL,S),
        RS_FR(R,SL,S) * (1+MAX(SUM(COM(CG2),COM_PKFLX(R,T,COM,SL)),COM_PKFLX(R,T,C,S))) *
        ( [cal_fflo IN, *FLO_PKCOI(R,T,P,C,TS)] + [cal_ire EXP IN IE, *FLO_PKCOI(R,T,P,C,TS)] +
          [cal_cap IN] + [cal_stgn IN OUT, STG_EFF*(NCAP_PKCNT**RPC_PKF)*, \$RPC_PKF(R,P,C)] + [blending] +
          ((COM_PROJ(R,T,C)\$(NOT RD_NLP(R,C)) + SUM(RD_AGG(R,COM), RD_SHAR(R,T,COM,C)*VAR_COMPRD(R,T,COM,'ANNUAL')))
           * COM_FR(R,T,C,S))\$DEM(R,C) + 0));

Inside the cal_* terms the commodity is C and the balance timeslice is S
(the inner summation indices), as eqpeak.mod passes them.

GAMS: eqpeak.mod L15-87, v4.9.7.
"""
function eq_peak!(tm::TimesModel)
    com_pkts = gset(tm, "COM_PKTS")
    isempty(com_pkts) && return 0
    peak_unported(tm)
    name = "EQ_PEAK"

    reg = gset(tm, "REG")
    milestonyr = gset(tm, "MILESTONYR")     # T: ALIAS(MILESTONYR,T,TT), initmty.mod L94
    modlyear = gset(tm, "MODLYEAR")         # V: ALIAS(MODLYEAR,V), setglobs.gms L147
    pastyear = gset(tm, "PASTYEAR")
    com = gset(tm, "COM")
    rtc = gset(tm, "RTC")
    dem = gset(tm, "DEM")
    prc_pkno = gset(tm, "PRC_PKNO")
    rs_fr = gparam(tm, "RS_FR")
    com_ie = gparam(tm, "COM_IE")
    com_pkrsv = gparam(tm, "COM_PKRSV")
    com_pkflx = gparam(tm, "COM_PKFLX")
    g_yrfr = gparam(tm, "G_YRFR")
    prc_capact = gparam(tm, "PRC_CAPACT")
    coef_vnt = gparam(tm, "COEF_VNT")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    ncap_pkcnt = gparam(tm, "NCAP_PKCNT")
    ncap_pasti = gparam(tm, "NCAP_PASTI")
    rpc_pkf = gparam(tm, "RPC_PKF")
    flo_pkcoi = gparam(tm, "FLO_PKCOI")
    com_proj = gparam(tm, "COM_PROJ")
    com_fr = gparam(tm, "COM_FR")
    rd_nlp = gparam(tm, "RD_NLP")
    rd_shar = gparam(tm, "RD_SHAR")
    stg_eff = gparam(tm, "STG_EFF")
    nstts, prc_map = gset(tm, "PRC_NSTTS"), gset(tm, "PRC_MAP")
    one = GNum(1.0)

    # Precomputed incidence maps.
    gmap_of_rcg = indexby(gset(tm, "COM_GMAP"), (1, 2))   # (r,cg) -> COM_GMAP(r,cg,c)
    ts_of_rc = indexby(gset(tm, "COM_TS"), (1, 2))        # (r,c) -> COM_TS(r,c,s)
    pkc_of_rc = indexby(gset(tm, "RPC_PKC"), (1, 3))      # (r,c) -> RPC_PKC(r,p,c)
    agg_of_r = indexby(gset(tm, "RD_AGG"), (1,))          # r -> RD_AGG(r,com)
    # SUM(V$COEF_VNT(R,T,P,V), ...): vintages per (r,t,p), V in MODLYEAR.
    v_of_rtp = Dict{NTuple{3,String},Vector{String}}()
    for (r, t, p, v) in coef_vnt.keys
        (v,) in modlyear || continue
        push!(get!(() -> String[], v_of_rtp, (r, t, p)), v)
    end
    no3 = NTuple{3,String}[]
    no2 = NTuple{2,String}[]

    # SUM(COM(CG2), x(COM)): x(CG2) when CG2 is a commodity, else 0 (G14).
    grp(p, k) = (k[3],) in com ? gv(p, k) : GZERO

    # The domain, in GAMS order (R, T, CG2, SL).
    rows = NTuple{4,String}[]
    for (r, cg2, sl) in com_pkts, (t,) in milestonyr
        (r,) in reg || continue
        any(k -> (r, t, k[3]) in rtc, get(gmap_of_rcg, (r, cg2), no3)) || continue
        push!(rows, (r, t, cg2, sl))
    end
    gams_sort!(rows, tm.data)

    n = 0
    for (r, t, cg2, sl) in rows
        lhs = JuMP.AffExpr(0.0)
        rhs = JuMP.AffExpr(0.0)
        for (_, _, c) in get(gmap_of_rcg, (r, cg2), no3), (_, _, s) in get(ts_of_rc, (r, c), no3)
            haskey(rs_fr, (r, sl, s)) || continue
            fr = gv(rs_fr, (r, sl, s))
            ie = gv(com_ie, (r, t, c, s))

            # ---- LHS (L17-50) -------------------------------------------------
            rsv = GNum(1.0) / (1 + gmax(grp(com_pkrsv, (r, t, cg2)), gv(com_pkrsv, (r, t, c))))
            out = fr * rsv * ie
            # Capacity contribution (L22-25).
            for (_, p, _) in get(pkc_of_rc, (r, c), no3)
                base = gv(g_yrfr, (r, s)) * gv(prc_capact, (r, p))
                for v in get(v_of_rtp, (r, t, p), String[])
                    k = out * (base * (gv(coef_vnt, (r, t, p, v)) * gv(prc_actflo, (r, v, p, c)) *
                                       gv(ncap_pkcnt, (r, v, p, s))))
                    (v,) in milestonyr && addterm!(lhs, k, tm, "VAR_NCAP", r, v, p)
                    (v,) in pastyear && addconst!(lhs, k * gv(ncap_pasti, (r, v, p)))
                    rcapsub!(lhs, k, tm, r, v, t, p)                  # %RCAPSUB% (prepret.jl)
                end
            end
            pkcnt = (p, v, ts) -> gv(ncap_pkcnt, (r, v, p, s))
            # Net imports (L31-32): imports times NCAP_PKCNT, minus exports of PRC_PKNO processes.
            cal_ire!(lhs, tm, out, "IMP", "OUT", r, t, c, s; pk=pkcnt)
            ireaux!(lhs, tm, -out, r, t, c, s)                     # L31: cal_ire.mod L30, IREAUXOUT- (%MX% = '-')
            ie_pos = ie.v > 0                              # COM_IE(R,T,C,S)>0 (EPS compares as 0, G12)
            exp_pk = (p, v, ts) -> ie_pos ? (-gv(ncap_pkcnt, (r, v, p, s))) / ie : GZERO
            cal_ire!(lhs, tm, out, "EXP", "IN", r, t, c, s; pk=exp_pk, pfilter=p -> (r, p) in prc_pkno)
            # Storage (L41): output * STG_EFF (net of the input with RPC_STGN), * NCAP_PKCNT**RPC_PKF.
            pkf = (p, v) -> gif(gpow(gv(ncap_pkcnt, (r, v, p, s)), gv(rpc_pkf, (r, p, c))), haskey(rpc_pkf, (r, p, c)))
            cal_stgn!(lhs, tm, out, "OUT", r, t, c, s; cond=(p, ts) -> !((r, p, ts) in nstts),
                      f3=(p, v) -> gv(stg_eff, (r, v, p)), f4=(p, v) -> one, f6=pkf)
            # Flow-based contribution (L44).
            cal_fflo!(lhs, tm, out, "OUT", r, t, c, s;
                      pk=(p, v, ts) -> gpow(gv(ncap_pkcnt, (r, v, p, s)), gv(rpc_pkf, (r, p, c))),
                      pcond=p -> haskey(rpc_pkf, (r, p, c)))

            # ---- RHS (L54-87) -------------------------------------------------
            flx = fr * (1 + gmax(grp(com_pkflx, (r, t, cg2, sl)), gv(com_pkflx, (r, t, c, s))))
            pkcoi = (p, v, ts) -> gv(flo_pkcoi, (r, t, p, c, ts))
            cal_fflo!(rhs, tm, flx, "IN", r, t, c, s; pk=pkcoi)          # L65
            cal_ire!(rhs, tm, flx, "EXP", "IN", r, t, c, s; pk=pkcoi)    # L68
            # Storage input (L75), net of STG_EFF * NCAP_PKCNT**RPC_PKF * output with RPC_STGN.
            cal_stgn!(rhs, tm, flx, "IN", r, t, c, s;
                      cond=(p, ts) -> !((r, "NST", p) in prc_map) || (r, p, ts) in nstts,
                      f3=(p, v) -> one,
                      f4=(p, v) -> gv(stg_eff, (r, v, p)) * gpow(gv(ncap_pkcnt, (r, v, p, s)), gv(rpc_pkf, (r, p, c))),
                      f6=(p, v) -> gif(one, haskey(rpc_pkf, (r, p, c))))
            # Demand projection (L82).
            if (r, c) in dem
                cfr = gv(com_fr, (r, t, c, s))
                haskey(rd_nlp, (r, c)) || addconst!(rhs, flx * (gv(com_proj, (r, t, c)) * cfr))
                for (_, cm) in get(agg_of_r, (r,), no2)
                    addterm!(rhs, flx * (gv(rd_shar, (r, t, cm, c)) * cfr), tm, "VAR_COMPRD", r, t, cm, "ANNUAL")
                end
            end
        end
        gconstraint!(tm, name, (r, t, cg2, sl), "G", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
