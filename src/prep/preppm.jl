# M1.3 (6a): preppm.mod L1-212, the interpolation of user data, included at
# ppmain.mod L248. L213-217 (the extensions' prep_ext, then the prep
# checkpoint) are M1.3 (6b).
#
# GAMS: preppm.mod L1-212 with prepxtra.mod SAVE (L79-86), curex.gms (curex.jl),
# prepret.dsc PREP (prepret.jl), fillvint.gms L14-20, filparam.gms,
# prepparm.gms and fillparm.gms (interp.jl), v4.9.7.
#
# Index sets: R is REG, P is PRC, C is COM, S and TS are ALL_TS, BD is
# BND_TYPE, LL is ALLYEAR, T is MILESTONYR, V is MODLYEAR (setglobs.gms
# L147); `LL--ORD(LL)` is '0', the last ALLYEAR element (G31). %DFLBL% is '0'
# (initmty.mod L367), %RESET% is 0 (L9), %DEF_IEBD% is 10 unless the run sets
# it (L55). `OPTION a <= b` matches positions left to right by domain (G26).
# $IF DEFINED is decided at compile time from the DD data (G35, G40).
#
# Refused: %INTEXT_ONLY% YES (L10, L218: prepxtra.mod XTIE and POST) and
# %PREP_ANS% YES (L12-13); the curex.gms paths `curex_unported` lists;
# %RETIRE% other than YES (prepret.jl). Currency conversion (L27-28) is
# curex.jl (M1.3 change 26). L11 (%DATAGDX% YES, every suite run) runs prepxtra.mod SAVE:
# it sets the scratch Z to the length of "%GDXPATH%%RUN_NAME%" plus 16 (CARD
# of a string, G41) and renames the data GDX file with a shell command, which
# has no data effect and is not translated.

"The preppm.mod L1-212 paths this model would take that are not translated."
function preppm_unported(tm)
    out = String[]
    yes(n) = uppercase(gswitch(tm, n, "")) == "YES"
    yes("INTEXT_ONLY") && push!(out, "preppm.mod L10 (INTEXT_ONLY YES: prepxtra.mod)")
    yes("PREP_ANS") && push!(out, "preppm.mod L12-13 (PREP_ANS YES)")
    append!(out, curex_unported(tm))
    append!(out, prepret_unported(tm))
    return out
end

"""
    preppm_symbols(tm) -> Vector{String}

The symbols preppm.mod L1-212 settles that nothing later in the init -> prep
segment changes (for the layer-1 check at the prep checkpoint), read on the
state after `preppm!`: every parameter it interpolates and every set it
writes, except NCAP_TLIFE and NCAP_ILED (prep_ext.vda L66-67 and L82 change
them), NCAP_BND when it has 'N' records (prep_ext.vda L80-83), RTP and RVP
with %POWERFLO% YES (powerflo.vda), and the scratch (UNCD7, MY_ARRAY, MY_FIL2,
TRACKP and the scalars), which prep_ext.vda uses again. PRC_CAP when
NCAP_OLIFE has data (prepret.dsc L29 clears it); INT_DEFAULT with G_NOINTERP
(prepparm.gms L25). With currency conversion, what `curex_symbols` lists.
"""
function preppm_symbols(tm)
    d = tm.data
    out = ["MODLYEAR", "DATAYEAR", "DM_YEAR", "FIL2", "MY_FIL", "OBJ_VFLO", "RPC_CUR", "IE_DEFAULT", "PRC_YMIN", "PASTSUM",
           "PRC_SIMV", "PRC_VINT", "G_RFRIR", "UC_TIME", "RCAP_BND", "PRC_RCAP", "RCAP_BLK", "RCAP_OCAP", "NCAP_OLIFE", "RTP_VARP"]
    append!(out, filter(n -> !(n in ("NCAP_TLIFE", "NCAP_ILED", "NCAP_BND")), PREPPM_PARAMS))
    any(k -> k[4] == "N", gparam_opt(d, "NCAP_BND", 4).keys) || push!(out, "NCAP_BND")
    uppercase(gswitch(tm, "POWERFLO", "")) == "YES" || append!(out, ["RTP", "RVP"])
    hasdata(tm, "NCAP_OLIFE", 3) && push!(out, "PRC_CAP")
    iszero(gscalar(tm, "G_NOINTERP")) || push!(out, "INT_DEFAULT")
    append!(out, curex_symbols(tm))
    return unique!(out)
end

"The parameters the macro calls of preppm.mod L76-211 interpolate."
const PREPPM_PARAMS = [
    "NCAP_COST", "NCAP_DCOST", "NCAP_DLAGC", "NCAP_FOM", "NCAP_FSUB", "NCAP_FTAX", "NCAP_ISUB", "NCAP_ITAX", "NCAP_VALU",
    "NCAP_ISPCT", "OBJ_COMNT", "OBJ_COMPD", "ACT_COST", "FLO_COST", "FLO_DELIV", "FLO_SUB", "FLO_TAX", "IRE_PRICE", "DAM_COST",
    "NCAP_AF", "NCAP_AFA", "NCAP_AFS", "NCAP_BPME", "NCAP_CDME", "NCAP_CEH", "NCAP_CHPR", "NCAP_CLED", "NCAP_CLAG", "NCAP_COM",
    "NCAP_DELIF", "NCAP_DLAG", "NCAP_DLIFE", "NCAP_DRATE", "NCAP_FDR", "NCAP_ELIFE", "NCAP_ICOM", "NCAP_ILED", "NCAP_OCOM",
    "NCAP_PKCNT", "NCAP_TLIFE", "COM_AGG", "COM_ELAST", "COM_FR", "COM_IE", "COM_PKFLX", "COM_PKRSV", "COM_PROJ", "COM_VOC",
    "ACT_CSTUP", "ACT_CSTSD", "ACT_CSTRMP", "ACT_TIME", "FLO_FUNC", "FLO_PKCOI", "FLO_SUM", "PRC_ACTFLO", "FLO_MARK", "PRC_MARK",
    "IRE_FLO", "IRE_FLOSUM", "STG_CHRG", "STG_EFF", "STG_LOSS", "STG_SIFT", "UC_ACT", "UC_CAP", "UC_COM", "UC_FLO", "UC_IRE",
    "UC_NCAP", "UC_UCN", "CAP_BND", "NCAP_BND", "COM_BNDNET", "COM_BNDPRD", "ACT_BND", "FLO_BND", "FLO_BDLVL", "FLO_FR",
    "FLO_SHAR", "IRE_BND", "IRE_XBND", "STGIN_BND", "STGOUT_BND", "UC_RHSRT", "UC_RHSRTS", "UC_RHST", "UC_RHSTS", "REG_BNDCST"]

"The UNCD7 padding as a GAMS call writes it (`\",'0','0'\"`) as labels."
pd(s::AbstractString) = String[strip(x, ['\'', ' ']) for x in split(s, ',')[2:end]]

"""
    preppm!(tm) -> tm

preppm.mod L1-212 on the state after `ppmain_rtp!`: the year sets of the
interpolation, the merging of special attributes into generic ones, the
retirement and vintaging preparations, and the interpolation and
extrapolation of every user parameter by its option.

GAMS: preppm.mod L1-212, v4.9.7.
"""
function preppm!(tm)
    u = preppm_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    ax = YearAxis(tm)
    yv(y) = ax.yearval[y]
    dfl = "0"
    # labels the block writes that a dump holds only when some record uses them (G36)
    foreach(l -> register_uel!(tm.data, l), ("", dfl, "COST", "TAX", "SUB", "PRD", "NET", "COMPRD", "COMCON", "COMNET", "N"))
    reg = Set(k[1] for k in gset(tm, "REG").keys)
    com = Set(k[1] for k in gset(tm, "COM").keys)
    ts = Set(k[1] for k in gset(tm, "ALL_TS").keys)

    # --- L9-13: %INTEXT_ONLY%, %DATAGDX%, %PREP_ANS% ---------------------------------
    # L11: prepxtra.mod SAVE, L81: Z=CARD("%GDXPATH%%RUN_NAME%")+16
    z_save = uppercase(gswitch(tm, "DATAGDX", "")) == "YES" ?
             GNum(length(gswitch(tm, "GDXPATH", "") * gswitch(tm, "RUN_NAME", "")) + 16.0) : nothing

    # --- L17-25: the years of the interpolation ---------------------------------------
    tset = [k[1] for k in gset(tm, "MILESTONYR").keys]
    pastyear = gset(tm, "PASTYEAR").members
    # L17: MODLYEAR(LL) = MILESTONYR(LL)+PASTYEAR(LL)
    modlyear = Set{Tuple{String}}([(t,) for t in tset])
    union!(modlyear, pastyear)
    gput!(tm, "MODLYEAR", modlyear)
    # L18-19: DATAYEAR(PASTYEAR) = YES; DATAYEAR('%DFLBL%') = YES
    datayear = union!(gmembers(tm, "DATAYEAR", 1), pastyear)
    push!(datayear, (dfl,))
    gput!(tm, "DATAYEAR", datayear)
    # L21-22: DM_YEAR(MILESTONYR) = YES; DM_YEAR(DATAYEAR) = (YEARVAL(DATAYEAR)>0)
    dm_year = gmembers(tm, "DM_YEAR", 1)
    foreach(t -> push!(dm_year, (t,)), tset)
    for k in datayear
        yv(k[1]) > 0 ? push!(dm_year, k) : delete!(dm_year, k)
    end
    gput!(tm, "DM_YEAR", dm_year)
    # L24: LOOP(T,FIL2(DM_YEAR)$((YEARVAL(DM_YEAR) >= B(T)) * (YEARVAL(DM_YEAR) <= E(T))) = YEARVAL(T))
    B, E = gvalues(tm, "B", 1), gvalues(tm, "E", 1)
    fil2 = gvalues(tm, "FIL2", 1)
    for t in tset, (y,) in dm_year
        (gv(B, (t,)).v <= yv(y) <= gv(E, (t,)).v) && gassign!(fil2, (y,), GNum(yv(t)))
    end
    gput!(tm, "FIL2", fil2)
    # L25: MY_FIL(DM_YEAR)$(FIL2(DM_YEAR)*(NOT T(DM_YEAR))) = YES
    my_fil = gmembers(tm, "MY_FIL", 1)
    tmem = Set(tset)
    for (y,) in dm_year
        (!iszero(gv(fil2, (y,))) && !(y in tmem)) && push!(my_fil, (y,))
    end
    gput!(tm, "MY_FIL", my_fil)

    # --- L27-28: currency conversion (curex.gms) ----------------------------------------
    curex!(tm)

    # --- L31-32: special case user attributes merged into the generic case ----------
    rpc, rc = gset(tm, "RPC").members, gset(tm, "RC").members
    bd = Set(k[1] for k in gset(tm, "BND_TYPE").keys)
    # L31: FLO_MARK(R,LL,P,C,BD)$((NOT RPC(R,P,C))$RC(R,C)$FLO_MARK(R,LL,P,C,BD)) = 0
    flo_mark = gvalues(tm, "FLO_MARK", 5)
    filter!(((k, _),) -> !(k[4] in com && k[5] in bd && (k[1], k[4]) in rc && !((k[1], k[3], k[4]) in rpc)), flo_mark)
    gput!(tm, "FLO_MARK", flo_mark)
    # L32: PRC_MARK(R,LL,P,P,C,BD)$((RPC(R,P,C)->(FLO_MARK(R,'0',P,C,BD)>1))$RC(R,C)$PRC_MARK(R,LL,P,P,C,BD)) = 0
    prc_mark = gvalues(tm, "PRC_MARK", 6)
    filter!(prc_mark) do (k, _)
        (k[3] == k[4] && k[5] in com && k[6] in bd && (k[1], k[5]) in rc) || return true
        imp = !((k[1], k[3], k[5]) in rpc) || gv(flo_mark, (k[1], dfl, k[3], k[5], k[6])).v > 1
        return !imp
    end
    gput!(tm, "PRC_MARK", prc_mark)

    # --- L34-39: commodity costs by year ------------------------------------------------
    for (dst, srcs) in (("OBJ_COMNT", ("COM_CSTNET", "COM_TAXNET", "COM_SUBNET")), ("OBJ_COMPD", ("COM_CSTPRD", "COM_TAXPRD", "COM_SUBPRD")))
        obj = gvalues(tm, dst, 6)
        # OBJ_COMxx(R,DATAYEAR,C,S,'COST'|'TAX'|'SUB',CUR) $= COM_xxx(R,DATAYEAR,C,S,CUR) (*(-1) for SUB)
        for (src, ct) in zip(srcs, ("COST", "TAX", "SUB"))
            for (k, x) in gparam_opt(tm.data, src, 5).values
                (k[1] in reg && (k[2],) in datayear && k[3] in com && k[4] in ts) || continue
                gassign!(obj, (k[1], k[2], k[3], k[4], ct, k[5]), ct == "SUB" ? (x == 0 ? GEPS : GNum(x)) * GNum(-1.0) :
                                                                          (x == 0 ? GEPS : GNum(x)))
            end
        end
        gput!(tm, dst, obj)
    end

    # --- L41-45: UC_COMxxx merged into UC_COM -----------------------------------------
    uc_com = gvalues(tm, "UC_COM", 8)
    uc_attr = gset_opt(tm.data, "UC_ATTR", 5).members
    netattr(k, g) = (k[3], k[1], k[2], g, "NET") in uc_attr      # UC_ATTR(R,UC_N,SIDE,g,'NET')
    ucsrc(n) = [(k, x == 0 ? GEPS : GNum(x)) for (k, x) in gparam_opt(tm.data, n, 6).values
                if k[3] in reg && (k[4],) in datayear && k[5] in com && k[6] in ts]
    ucput!(k, cv, g, x) = gassign!(uc_com, (k[1], cv, k[2], k[3], k[4], k[5], k[6], g), x)
    # L41-42: UC_COM(UC_N,'PRD',SIDE,R,DATAYEAR,C,S,'COMPRD'|'COMCON')$(NOT UC_ATTR(R,UC_N,SIDE,..,'NET')) $= UC_COMPRD|UC_COMCON(...)
    foreach(((k, x),) -> netattr(k, "COMPRD") || ucput!(k, "PRD", "COMPRD", x), ucsrc("UC_COMPRD"))
    foreach(((k, x),) -> netattr(k, "COMCON") || ucput!(k, "PRD", "COMCON", x), ucsrc("UC_COMCON"))
    # L43: UC_COM(UC_N,'NET',SIDE,R,DATAYEAR,C,S,'COMPRD')$UC_ATTR(R,UC_N,SIDE,'COMPRD','NET') $= UC_COMPRD(...)
    foreach(((k, x),) -> netattr(k, "COMPRD") && ucput!(k, "NET", "COMPRD", x), ucsrc("UC_COMPRD"))
    # L44: UC_COM(UC_N,'NET',SIDE,R,DATAYEAR,C,S,'COMCON')$UC_COMCON(...) = UC_COMCON(...)*(-1)
    foreach(((k, x),) -> ucput!(k, "NET", "COMCON", x * GNum(-1.0)), ucsrc("UC_COMCON"))
    # L45: UC_COM(UC_N,'NET',SIDE,R,DATAYEAR,C,S,'COMNET') $= UC_COMNET(...)
    foreach(((k, x),) -> ucput!(k, "NET", "COMNET", x), ucsrc("UC_COMNET"))
    gput!(tm, "UC_COM", uc_com)

    # --- L47-52: flags for flow taxes and subsidies ------------------------------------
    # L49: OPTION RPC_CUR <= FLO_TAX; OBJ_VFLO(RPC_CUR,'TAX') = YES
    #   FLO_TAX(REG,ALLYEAR,PRC,COM,TS,CUR) onto RPC_CUR(REG,PRC,COM,CUR): positions 1, 3, 4, 6
    flo_tax, flo_sub = gvalues(tm, "FLO_TAX", 6), gvalues(tm, "FLO_SUB", 6)
    obj_vflo = gmembers(tm, "OBJ_VFLO", 5)
    foreach(k -> push!(obj_vflo, (k..., "TAX")), project(keys(flo_tax), (1, 3, 4, 6)))
    # L50: OPTION RPC_CUR <= FLO_SUB; OBJ_VFLO(RPC_CUR,'SUB') $= OBJ_VFLO(RPC_CUR,'TAX')
    rpc_cur = project(keys(flo_sub), (1, 3, 4, 6))
    foreach(k -> (k..., "TAX") in obj_vflo && push!(obj_vflo, (k..., "SUB")), rpc_cur)
    gput!(tm, "RPC_CUR", rpc_cur)
    gput!(tm, "OBJ_VFLO", obj_vflo)
    # L51-52: FLO_TAX|FLO_SUB(R,LL--ORD(LL),P,C,S,CUR)$((NOT ..(R,'%DFLBL%',P,C,S,CUR))$..(R,LL,P,C,S,CUR)$OBJ_VFLO(R,P,C,CUR,'SUB')) = 3
    for f in (flo_tax, flo_sub)
        add = Set{NTuple{6,String}}()
        for k in keys(f)
            (k[1] in reg && k[4] in com && k[5] in ts && (k[1], k[3], k[4], k[6], "SUB") in obj_vflo) || continue
            o = (k[1], dfl, k[3], k[4], k[5], k[6])
            haskey(f, o) || push!(add, o)
        end
        foreach(o -> (f[o] = 3.0), add)
    end
    gput!(tm, "FLO_TAX", flo_tax)
    gput!(tm, "FLO_SUB", flo_sub)

    # --- L55-57: defaults, retirements -------------------------------------------------
    # L56: IE_DEFAULT(INT_DEFAULT) = 3
    ie_default = gvalues(tm, "IE_DEFAULT", 1)
    foreach(k -> (ie_default[k] = 3.0), gset_opt(tm.data, "INT_DEFAULT", 1).keys)
    gput!(tm, "IE_DEFAULT", ie_default)
    st = InterpState(tm)
    z_save === nothing || (st.Z = z_save)
    # L57: $IF SET RETIRE $BATINCLUDE prepret.dsc PREP PRC_RCAP RCAP_BND
    prepret_prep!(st)

    # --- L60-61: vintaging -----------------------------------------------------------------
    fillvint_init!(tm, ax)
    rtp, rvp = gset(tm, "RTP").members, gmembers(tm, "RVP", 3)
    # L61: RVP(RTP(R,V,P))$PRC_VINT(R,P) = YES
    vint = gset(tm, "PRC_VINT").members
    foreach(k -> ((k[2],) in modlyear && (k[1], k[3]) in vint) && push!(rvp, k), rtp)
    gput!(tm, "RVP", rvp)

    # --- L76-211: the interpolation of the user parameters ------------------------------
    V = [k[1] for k in gset(tm, "MODLYEAR").keys]
    T = tset
    PM = [k[1] for k in gset(tm, "PASTMILE").keys]
    one = k -> true
    rtpk = k -> (k[1], k[2], k[3]) in rtp                       # 'RTP(R,V,P)', 'RTP(R,T,P)' on (R,year,P,...)
    rvpk = k -> (k[1], k[2], k[3]) in rvp                       # 'RVP(R,V,P)'
    rtpu = k -> (k[3], k[4], k[5]) in rtp                       # 'RTP(R,T,P)' on (UC_N,SIDE,R,year,P,...)
    ge0 = (d, k) -> d >= 0                                      # 'GE 0'
    M = gvalues(tm, "M", 1)
    miyr_v1 = gscalar(tm, "MIYR_V1")
    P1, P0, PE = GNum(1.0), GZERO, GEPS                          # %7: 1, 0, EPS
    # L77: $BATINCLUDE filparam G_RFRIR 'R,' '' ",'0','0','0','0','0'" YEAR V
    filparam!(st, "G_RFRIR", "R,", "", pd(",'0','0','0','0','0'"), ax.years, V)
    # Capacity related cost attributes (L81-90)
    prepparm!(st, "NCAP_COST", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_DCOST", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_DLAGC", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_FOM", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_FSUB", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_FTAX", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_ISUB", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_ITAX", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_VALU", "R", "P,C,CUR", pd(",'0','0','0'"), V, rtpk, P0)
    prepparm!(st, "NCAP_ISPCT", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, P0)
    # Commodity related cost attributes (L94-95)
    prepparm!(st, "OBJ_COMNT", "R", "C,TS,COSTYPE,CUR", pd(",'0','0'"), T, one, P0)
    prepparm!(st, "OBJ_COMPD", "R", "C,TS,COSTYPE,CUR", pd(",'0','0'"), T, one, P0)
    # Flow related cost attributes (L99-105)
    prepparm!(st, "ACT_COST", "R", "P,CUR", pd(",'0','0','0','0'"), V, rtpk, P0)
    prepparm!(st, "FLO_COST", "R", "P,C,TS,CUR", pd(",'0','0'"), V, rtpk, P0)
    prepparm!(st, "FLO_DELIV", "R", "P,C,TS,CUR", pd(",'0','0'"), V, rtpk, P0)
    prepparm!(st, "FLO_SUB", "R", "P,C,TS,CUR", pd(",'0','0'"), V, rtpk, P0)
    prepparm!(st, "FLO_TAX", "R", "P,C,TS,CUR", pd(",'0','0'"), V, rtpk, P0)
    prepparm!(st, "IRE_PRICE", "R", "P,C,TS,ALL_REG,IE,CUR", pd(""), V, rtpk, P0)
    # L105: $IF DEFINED DAM_COST $BATINCLUDE prepparm DAM_COST R 'C,CUR' ",'0','0','0'" T 1 EPS 3
    hasdata(tm, "DAM_COST", 4) && prepparm!(st, "DAM_COST", "R", "C,CUR", pd(",'0','0','0'"), T, one, PE; iebd=3)
    # Capacity related attributes (L111-131)
    fillparm!(st, "NCAP_AF", "R", "P,TS,BD", pd(",'0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_AFA", "R", "P,BD", pd(",'0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_AFS", "R", "P,TS,BD", pd(",'0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_BPME", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_CDME", "R", "P", pd(",'0','0','0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "NCAP_CEH", "R", "P", pd(",'0','0','0','0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "NCAP_CHPR", "R", "P,BD", pd(",'0','0','0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "NCAP_CLED", "R", "P,C", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_CLAG", "R", "P,C,IO", pd(",'0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_COM", "R", "P,C,IO", pd(",'0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_DELIF", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_DLAG", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_DLIFE", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_DRATE", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_FDR", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_ELIFE", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_ICOM", "R", "P,C", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_ILED", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    fillparm!(st, "NCAP_OCOM", "R", "P,C", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_PKCNT", "R", "P,TS", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "NCAP_TLIFE", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0; cache=true)
    # Commodity related attributes (L135-142)
    fillparm!(st, "COM_AGG", "R", "C,COM", pd(",'0','0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_ELAST", "R", "C,TS,L", pd(",'0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_FR", "R", "C,TS", pd(",'0','0','0','0'"), T, one, ge0; cache=true)
    fillparm!(st, "COM_IE", "R", "C,TS", pd(",'0','0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_PKFLX", "R", "C,TS", pd(",'0','0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_PKRSV", "R", "C", pd(",'0','0','0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_PROJ", "R", "C", pd(",'0','0','0','0','0'"), T, one, ge0)
    fillparm!(st, "COM_VOC", "R", "C,BD", pd(",'0','0','0','0'"), T, one, ge0)
    # Flow related attributes & inter-regional exchange (L146-157)
    fillparm!(st, "ACT_CSTUP", "R", "P,TSL,CUR", pd(",'0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "ACT_CSTSD", "R", "P,UPT,BD,CUR", pd(",'0','0'"), V, rtpk, ge0)
    fillparm!(st, "ACT_CSTRMP", "R", "P,BD,CUR", pd(",'0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "ACT_TIME", "R", "P,LIM", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "FLO_FUNC", "R", "P,CG1,CG2,TS", pd(",'0','0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "FLO_PKCOI", "R", "P,C,TS", pd(",'0','0','0'"), V, rvpk, ge0)
    fillparm!(st, "FLO_SUM", "R", "P,CG1,C,CG2,TS", pd(",'0'"), V, rvpk, ge0; cache=true)
    fillparm!(st, "PRC_ACTFLO", "R", "P,CG", pd(",'0','0','0','0'"), V, rtpk, ge0; cache=true)
    prepparm!(st, "FLO_MARK", "R", "P,C,BD", pd(",'0','0'"), T, one, P1; iebd=3, cache=true)
    prepparm!(st, "PRC_MARK", "R", "P,ITEM,C,BD", pd(",'0'"), T, one, P1; iebd=11, cache=true)
    # L156: IRE_FLO ... V '(RVP(R,V,P) OR RTP(REG,V,P))' on (R,V,P,C,REG,COM,TS)
    fillparm!(st, "IRE_FLO", "R", "P,C,REG,COM,TS", pd(",'0'"), V, k -> rvpk(k) || (k[5], k[2], k[3]) in rtp, ge0)
    fillparm!(st, "IRE_FLOSUM", "R", "P,C,TS,IE,COM,IO", pd(""), V, rvpk, ge0)
    # Storage attributes (L161-164); L161: STG_CHRG ... V '(M(V) GE MIYR_V1-1)'
    fillparm!(st, "STG_CHRG", "R", "P,S", pd(",'0','0','0','0'"), V, k -> gv(M, (k[2],)).v >= miyr_v1 - 1, ge0)
    fillparm!(st, "STG_EFF", "R", "P", pd(",'0','0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "STG_LOSS", "R", "P,S", pd(",'0','0','0','0'"), V, rtpk, ge0)
    fillparm!(st, "STG_SIFT", "R", "P,C,S", pd(",'0','0','0'"), T, rtpk, ge0)
    # User constraints (L168-175)
    fillparm!(st, "UC_ACT", "UC_N,SIDE,R", "P,TS", pd(",'0','0'"), T, rtpu, ge0)
    fillparm!(st, "UC_CAP", "UC_N,SIDE,R", "P", pd(",'0','0','0'"), T, one, ge0)
    fillparm!(st, "UC_COM", "UC_N,COM_VAR,SIDE,R", "C,TS,UC_GRPTYPE", pd(""), T, one, ge0)
    fillparm!(st, "UC_FLO", "UC_N,SIDE,R", "P,C,TS", pd(",'0'"), T, one, ge0; cache=true)
    fillparm!(st, "UC_IRE", "UC_N,SIDE,R", "P,C,TS,IE", pd(""), T, rtpu, ge0)
    fillparm!(st, "UC_NCAP", "UC_N,SIDE,R", "P", pd(",'0','0','0'"), T, rtpu, ge0)
    fillparm!(st, "UC_UCN", "UC_N,SIDE,R", "UCN", pd(",'0','0','0'"), T, one, ge0)
    # L175: $BATINCLUDE filparam UC_TIME 'UC_N,R,' '' ",'0','0','0'" DATAYEAR T '' '' '' "YEAR,"
    filparam!(st, "UC_TIME", "UC_N,R,", "", pd(",'0','0','0'"), [y for y in ax.years if (y,) in datayear], T; year_in_uncd7=true)
    # Non-regular capacity and commodity related attributes (L181-184)
    prepparm!(st, "CAP_BND", "R", "P,BD", pd(",'0','0','0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "NCAP_BND", "R", "P,BD", pd(",'0','0','0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "COM_BNDNET", "R", "C,TS,BD", pd(",'0','0'"), T, one, P1)
    prepparm!(st, "COM_BNDPRD", "R", "C,TS,BD", pd(",'0','0'"), T, one, P1)
    # Flow related attributes & inter-regional exchange (L188-194)
    prepparm!(st, "ACT_BND", "R", "P,TS,BD", pd(",'0','0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "FLO_BND", "R", "P,CG,TS,BD", pd(",'0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "FLO_BDLVL", "R", "P,CG,S,BD", pd(",'0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "FLO_FR", "R", "P,C,TS,LIM", pd(",'0'"), T, rtpk, P1; cache=true)
    prepparm!(st, "FLO_SHAR", "R", "P,C,CG,TS,BD", pd(""), V, rvpk, P1; cache=true, arg10="+")
    prepparm!(st, "IRE_BND", "R", "C,TS,ALL_REG,IE,BD", pd(""), T, one, P1)
    prepparm!(st, "IRE_XBND", "ALL_REG", "C,TS,IE,BD", pd(",'0'"), T, one, P1)
    # Storage attributes (L198-199)
    prepparm!(st, "STGIN_BND", "R", "P,C,S,BD", pd(",'0'"), T, rtpk, P1)
    prepparm!(st, "STGOUT_BND", "R", "P,C,S,BD", pd(",'0'"), T, rtpk, P1)
    # User constraints (L203-207)
    prepparm!(st, "UC_RHSRT", "ALL_R,UC_N", "LIM", pd(",'0','0','0'"), T, one, P1; cache=true)
    prepparm!(st, "UC_RHSRTS", "ALL_R,UC_N", "TS,L", pd(",'0','0'"), T, one, P1; cache=true)
    prepparm!(st, "UC_RHST", "UC_N", "LIM", pd(",'0','0','0','0'"), T, one, P1)
    prepparm!(st, "UC_RHSTS", "UC_N", "TS,LIM", pd(",'0','0','0'"), T, one, P1)
    prepparm!(st, "REG_BNDCST", "R", "COSTAGG,CUR,BD", pd(",'0','0'"), T, one, P1)
    # L211: $BATINCLUDE prepparm FLO_SHAR R 'P,C,CG,TS,BD' "" PASTMILE 'RVP(R,PASTMILE,P)' 1 3 X_RPCGSB -ABS
    prepparm!(st, "FLO_SHAR", "R", "P,C,CG,TS,BD", pd(""), PM, rvpk, P1; iebd=3, cache=true, arg10="-ABS")

    put_interp_scratch!(st)
    return tm
end

"""
    fillvint_init!(tm, ax) -> tm

fillvint.gms without arguments (preppm.mod L60): PRC_YMIN and PASTSUM
cleared; with %VINTOPT% 2 every vintaged process but storage simulated
(PRC_SIMV), and PRC_SIMV is vintaged; every vintaged process gets the
modelyear one LEAD before each milestone in RVP (a lag on ALLYEAR, rounded,
G29); and with PRC_SIMV, RTP takes the RVP records of the simulated
processes. `\$IF DEFINED PRC_SIMV` holds with PRC_SIMV data or %VINTOPT% 2
(L15 is then compiled, G1).

GAMS: fillvint.gms L14-20, v4.9.7.
"""
function fillvint_init!(tm, ax)
    # L14: OPTION CLEAR=PRC_YMIN,CLEAR=PASTSUM
    gput!(tm, "PRC_YMIN", Dict{NTuple{2,String},Float64}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    vint = gmembers(tm, "PRC_VINT", 2)
    simv = gmembers(tm, "PRC_SIMV", 2)
    vintopt2 = strip(gswitch(tm, "VINTOPT", "")) == "2"
    simv_def = vintopt2 || !isempty(simv)
    stg = Set((k[1], k[3]) for k in gset(tm, "PRC_MAP").keys if k[2] == "STG")
    # L15: $IF %VINTOPT%==2 PRC_SIMV(PRC_VINT(R,P)) = NOT PRC_MAP(R,'STG',P)
    if vintopt2
        for k in vint
            k in stg ? delete!(simv, k) : push!(simv, k)
        end
    end
    if simv_def
        # L16: PRC_SIMV(R,P)$PRC_MAP(R,'STG',P) = NO; PRC_VINT(PRC_SIMV) = YES
        setdiff!(simv, stg)
        union!(vint, simv)
        gput!(tm, "PRC_SIMV", simv)
        gput!(tm, "PRC_VINT", vint)
    end
    # L18: LOOP(T(LL),RVP(R,V(LL-LEAD(T)),P)$((NOT RVP(R,V,P))$RVP(R,T,P)$PRC_VINT(R,P)) = YES)
    rvp = gmembers(tm, "RVP", 3)
    LEAD = gvalues(tm, "LEAD", 1)
    modl = gset(tm, "MODLYEAR").members
    byt = Dict{String,Vector{NTuple{3,String}}}()
    foreach(k -> push!(get!(byt, k[2], NTuple{3,String}[]), k), rvp)
    for (t,) in gset(tm, "MILESTONYR").keys
        v = lead(ax, t, -glead(gv(LEAD, (t,)).v))
        (v === nothing || !((v,) in modl)) && continue
        for k in get(byt, t, NTuple{3,String}[])
            (k[1], k[3]) in vint && push!(rvp, (k[1], v, k[3]))
        end
    end
    gput!(tm, "RVP", rvp)
    # L19: $IF DEFINED PRC_SIMV RTP(RVP(R,V,P)) $=PRC_SIMV(R,P)
    if simv_def
        rtp = gmembers(tm, "RTP", 3)
        foreach(k -> (k[1], k[3]) in simv && push!(rtp, k), rvp)
        gput!(tm, "RTP", rtp)
    end
    return tm
end

# M1.3 (7a): preppm.mod L218-252, after the prep checkpoint (prep_ext.vda,
# L217): the SHAPE and multiplier indexes (preshape.gms), PRC_MARK from
# FLO_MARK and the final DATAYEAR. L218 (%INTEXT_ONLY% YES: prepxtra.mod XTIE)
# is refused at L10 (`preppm_unported`); L245-251 run only with %VINTOPT% 1,
# refused here (fillvint.gms with its four-argument calls).

"The preppm.mod L218-252 paths this model would take that are not translated."
function preppm_shape_unported(tm)
    out = String[]
    uppercase(gswitch(tm, "INTEXT_ONLY", "")) == "YES" && push!(out, "preppm.mod L218 (INTEXT_ONLY YES: prepxtra.mod XTIE)")
    strip(gswitch(tm, "VINTOPT", "")) == "1" && push!(out, "preppm.mod L245-251 (VINTOPT 1: fillvint.gms)")
    return out
end

"""
    preppm_shape_symbols(tm) -> Vector{String}

The symbols preppm.mod L218-252 settles that nothing later in the prep ->
prelv segment changes (for the layer-1 check at the prelv checkpoint): the
twelve preshape parameters, PRC_MARK, DATAYEAR and the preshape.gms scratch
but Z and F (ppmain.mod L335 assigns them). UNCD7 and RXX are left out:
pp_lvlfc.mod (pp_prelv.vda L101) and ppmain.mod L335 clear them again.
MY_F is left out with %POWERFLO% YES: powerflo.vda L80 (pp_prelv.vda L114)
assigns it again.
"""
function preppm_shape_symbols(tm)
    out = vcat(PRESHAPE_PARAMS, ["PRC_MARK", "DATAYEAR", "MY_ARRAY", "DFUNC", "LAST_VAL", "FIRST_VAL", "MY_FYEAR"])
    uppercase(gswitch(tm, "POWERFLO", "")) == "YES" || push!(out, "MY_F")
    return out
end

"The parameters of the preshape.gms calls, preppm.mod L222-233."
const PRESHAPE_PARAMS = ["NCAP_AFX", "NCAP_AFSX", "NCAP_AFM", "NCAP_FOMX", "NCAP_FSUBX", "NCAP_FTAXX", "FLO_FUNCX",
                         "COM_ELASTX", "NCAP_FOMM", "NCAP_FSUBM", "NCAP_FTAXM", "NCAP_CPX"]

"""
    preppm_shape!(tm) -> tm

preppm.mod L218-252 on the state at the prep checkpoint: the SHAPE and
multiplier indexes carried over the model years by their options
(preshape.gms), UNCD7 cleared, PRC_MARK from FLO_MARK on the milestones, and
DATAYEAR with the milestones and without '0'.

GAMS: preppm.mod L218-252, preshape.gms L17-48, v4.9.7.
"""
function preppm_shape!(tm)
    u = preppm_shape_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    st = InterpState(tm)
    V = [k[1] for k in gset(tm, "MODLYEAR").keys]
    T = [k[1] for k in gset(tm, "MILESTONYR").keys]
    rtp = gset(tm, "RTP").members
    rtpk = k -> (k[1], k[2], k[3]) in rtp                       # 'RTP(R,V,P)' on (R,V,P,...)
    one = k -> true
    # L222-233: $BATINCLUDE preshape <name> R <post> <pad> V|T RXX|UNCD7 <cond> [15]
    preshape!(st, "NCAP_AFX", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_AFSX", "R", "P,BD", pd(",'0','0','0'"), V, "UNCD7", rtpk)
    preshape!(st, "NCAP_AFM", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_FOMX", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_FSUBX", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_FTAXX", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "FLO_FUNCX", "R", "P,CG1,CG2", pd(",'0','0'"), V, "UNCD7", rtpk)
    preshape!(st, "COM_ELASTX", "R", "C,BD", pd(",'0','0','0'"), T, "UNCD7", one; def=15)
    preshape!(st, "NCAP_FOMM", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_FSUBM", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_FTAXM", "R", "P", String[], V, "RXX", rtpk)
    preshape!(st, "NCAP_CPX", "R", "P", String[], V, "RXX", rtpk)
    # L236: OPTION CLEAR = UNCD7
    st.uncd7 = Set{NTuple{7,String}}()
    put_interp_scratch!(st)
    # L237: PRC_MARK(R,T,P,P,C,BD) $= FLO_MARK(R,T,P,C,BD)
    reg, com = gset(tm, "REG").members, gset(tm, "COM").members
    bd, prc = gset(tm, "BND_TYPE").members, gset(tm, "PRC").members
    tmem = Set(T)
    flo_mark = gvalues(tm, "FLO_MARK", 5)
    prc_mark = gvalues(tm, "PRC_MARK", 6)
    for k in keys(flo_mark)
        ((k[1],) in reg && k[2] in tmem && (k[3],) in prc && (k[4],) in com && (k[5],) in bd) || continue
        gassign!(prc_mark, (k[1], k[2], k[3], k[3], k[4], k[5]), gv(flo_mark, k))   # EPS stays EPS (G24)
    end
    gput!(tm, "PRC_MARK", prc_mark)
    # L241-242: DATAYEAR(MILESTONYR) = YES; DATAYEAR('%DFLBL%') = NO
    datayear = gmembers(tm, "DATAYEAR", 1)
    foreach(t -> push!(datayear, (t,)), T)
    delete!(datayear, ("0",))
    gput!(tm, "DATAYEAR", datayear)
    return tm
end
