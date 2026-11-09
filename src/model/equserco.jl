# User constraints (the EQ(l)_UC* families) with VAR_UC = YES: eqmain.mod
# L195-232, equcwrap.mod, equserco.mod and the uc_*.mod term files.
#
# GAMS: eqmain.mod L208-226 (the generation maps UC_TMAP, UC_RHSMAP, UC_UT,
# UC_UTS, UC_RTSUC) and L229 (`$BATINCLUDE equcwrap.mod E BD '' SUM(BD$ ,1)
# NOT`); equcwrap.mod L13-42; equserco.mod L23-120; uc_flo.mod, uc_ncap.mod,
# uc_cap.mod, uc_act.mod, uc_com.mod, uc_ire.mod and uc_pasti.mod, v4.9.7.
#
# With VAR_UC = YES only the first equcwrap include runs (equcwrap.mod L13:
# `$IF NOT YES==YES $EXIT` does not exit; the FX/LO/UP includes at eqmain.mod
# L230-232 do). Every row is then `LHS =E= VAR_UC*(...) [+ UC_TIME term]`
# and the right-hand-side bounds sit on the VAR_UC* slack variables
# (bnd_ucw.mod, `bnd_ucw!` in bndmain.jl). VAR_UC is YES when the run sets
# it, or when UC_TIME or UC_UCN has data (eqmain.mod L197); unset it is not
# YES. (initmty.mod L447-448 also force it under STEPPED, refused with the
# bounds, and under a GAMS licence of level 2.)
#
# Translated: the four non-dynamic families whose equserco %8 is 0, with
# HS = 'LHS' (equserco.mod L28) and the terms of uc_flo, uc_ncap, uc_cap,
# uc_act, uc_com (PRD and NET) and uc_ire:
#   equcwrap L26  EQE_UCT(UC_N,T)        region sum, timeslice sum
#   equcwrap L28  EQE_UCRT(R,T,UC_N)     timeslice sum
#   equcwrap L30  EQE_UCTS(UC_N,T,S)     region sum
#   equcwrap L32  EQE_UCRTS(R,T,UC_N,S)  no sum
# and the four dynamic (UC_T_SUCC) families whose %8 is 1, in the LHS
# direction (equserco.mod L52-78: terms at T on the LHS, at T+1 on the RHS,
# through UC_TMAP 'N'; `uc_dyn!`) or, when UC_DYNDIR has an 'RHS' entry, in
# the RHS direction (L80-106: terms at T on the LHS, at T-1 on the RHS, or
# at the periods the CUMSUM, CUM+ and SYNC attributes pick through UC_TMAP,
# less the past investments of uc_pasti.mod in the first period;
# `uc_dyn_rhs!`, M1.3 change 21), with the GROWTH attribute:
#   equcwrap L34  EQE_UCSU(UC_N,T)       region sum, timeslice sum
#   equcwrap L36  EQE_UCRSU(R,T,UC_N)    timeslice sum
#   equcwrap L38  EQE_UCRSUS(R,T,UC_N,S) no sum
#   equcwrap L40  EQE_UCSUS(UC_N,T,S)    region sum
# and the two multi-period families whose %8 is 2 (period sums over
# UC_T_SUM with the FPD factor of cumulative constraints, plus UC_CUMFLO and
# UC_CUMCOM terms; `uc_several_lhs!`):
#   equcwrap L22  EQE_UC(UC_N)           region, period and timeslice sums
#   equcwrap L24  EQE_UCR(R,UC_N)        period and timeslice sums
# and the timeslice-level family whose %8 is S (equserco.mod L30: HS = SIDE),
# for user constraints whose UC_ATTR names a timeslice level (UC_DS):
#   equcwrap L42  EQE_UCRS(R,T,UC_N,TSL,S) the LHS side at S, the RHS side
#                                           at the previous slice RS_PREV
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV%/%SWFLO% -> VAR, %SOW%/%SWT%/
# %SWS%/%SWD% -> '' (setglobs.gms L348); %R_T% -> 'R,T' (maindrv.mod L39);
# RTS(S) -> S; the STAGES lines of equcwrap.mod L16-17 and equserco.mod L55
# drop out (%SWTD%, the dynamic families' %5, is then unused); %cal_red% is
# cal_nored.red (cal_red.jl).
#
# Not translated; data that needs them raises UnportedError:
# - VAR_UC not YES (the typed FX/LO/UP includes, eqmain.mod L230-232);
# - nested constraints (equserco.mod L76, L99: UC_GMAP_U/UC_UCN) and the
#   climate terms of the RHS direction (L101, uc_cli.mod; %CLI% is refused
#   by the generation driver);
# - the UC_ATTR attributes ANNUL (with INVCOST, INVTAX, INVSUB: CST_ANNC of
#   eqbndcst.mod, uc_ncap.mod L39) and ONLINE (uc_cap.mod L36-42); the
#   others are translated (`UC_ATTR_REFUSED`; PERIOD, NEWFLO, PERDISC, EFF,
#   CAPACT, BUILDUP and COST/DELIV/TAX/SUB in M1.3 change 22);
# - capacity-related flows in uc_flo.mod L35-49 (UC_CAPFLO, cal_caps.mod).
# Read from the pre-solve dump (computed elsewhere): UC_RHS*, UC_ON,
# UC_R_*/UC_T_*/UC_TS_* maps, UC_GMAP_*/UC_MAP_*, UC_ATTR, UC_DYNDIR, LAGT,
# UC_SIGN, RHS_COMBAL/RHS_COMPRD, RTP_OFF (eqmain.mod L199-202 add to it;
# read after those changes), LEAD, M, B, MIYR_1, RTP_CPTYR, COEF_CPT,
# NCAP_PASTI.

"VAR_UC as eqmain.mod L197 leaves it: the run's value, or YES if UC_TIME/UC_UCN has data."
function var_uc(tm::TimesModel)
    uppercase(gswitch(tm, "VAR_UC", "")) == "YES" && return true
    return !isempty(gparam_opt(tm.data, "UC_TIME", 3)) || !isempty(gparam_opt(tm.data, "UC_UCN", 5))
end

_gset_from(name::String, keys::Vector{NTuple{N,String}}, d::DumpData) where {N} =
    (k = unique(keys); gams_sort!(k, d); GamsSet{N}(name, k, Set(k)))

"""
    uc_setup(tm) -> NamedTuple (rhsmap, ut, uts, rtsuc)

The user-constraint generation maps eqmain.mod computes before the UC
equations, with VAR_UC = YES (%UCBD% = %TMP% = %TAKE% = ''):

    IF(CARD(UC_RHSRT), OPTION R_UCT < UC_RHSRT, R_UC < UC_TS_SUM;
      UC_RHSTMP(R_UCT(R_UC(R,UC_N),T),ANNUAL,'SEVERAL')\$UC_T_EACH(R,UC_N,T) = YES;
      UC_RHSTMP(R_UCT(R_UC(R,UC_N),T),ANNUAL,'DYNAMIC')\$UC_T_SUCC(R,UC_N,T) = YES);
    IF(CARD(UC_RHSRTS), OPTION RUCTS < UC_RHSRTS;
      UC_RHSTMP(RUCTS(UC_T_EACH(UC_R_EACH(R,UC_N),T),S),'EACH')\$UC_TS_EACH(R,UC_N,S) = YES;
      UC_RHSTMP(RUCTS(UC_T_SUCC(UC_R_EACH(R,UC_N),T),S),'SUCC')\$UC_TS_EACH(R,UC_N,S) = YES;
      UC_RHSTMP(RUCTS(UC_T_EACH(UC_R_EACH(R,UC_N),T),S),UC_NUMBER(TSL))\$(TS_GROUP(R,TSL,S)\$UC_DS(R,UC_N,TSL)) = YES);
    OPTION UC_RTSUC < UC_T_SUCC, UC_RHSMAP < UC_RHSTMP, UC_UT < UC_RHST, UC_UTS < UC_RHSTS;

`OPTION a < b` projects b onto a, matching indices by their domain sets:
UC_RHSMAP(REG,T,UC_N,UC_NUMBER,S) from UC_RHSTMP(REG,UC_N,T,S,UC_NUMBER),
UC_RTSUC(ALL_R,ALLYEAR,UC_N) from UC_T_SUCC(ALL_R,UC_N,ALLYEAR). R ranges
over REG and T over MILESTONYR. The UC_DS line (L224) gives the RS family
its rows: one per slice S of the level TSL named in UC_DS, with UC_NUMBER =
TSL (setglobs.gms L121: UC_NUMBER holds the level names). ppmain.mod L1114
removes UC_TS_EACH for those constraints, so the EACH lines skip them.

GAMS: eqmain.mod L208-226, v4.9.7.
"""
function uc_setup(tm::TimesModel)
    get!(tm.cache, "UC_SETUP") do
        d = tm.data
        reg, milestonyr = gset(tm, "REG"), gset(tm, "MILESTONYR")
        uc_rhsrt, uc_rhsrts = gparam(tm, "UC_RHSRT"), gparam(tm, "UC_RHSRTS")
        t_each, t_succ = gset(tm, "UC_T_EACH"), gset(tm, "UC_T_SUCC")
        r_each, ts_each, ts_sum = gset(tm, "UC_R_EACH"), gset(tm, "UC_TS_EACH"), gset(tm, "UC_TS_SUM")
        uc_ds = gset_opt(d, "UC_DS", 3)
        tsl_of_rn = indexby(uc_ds, (1, 2))                            # (r,n) -> UC_DS(r,n,tsl)
        ts_group = gset(tm, "TS_GROUP")
        tmp = NTuple{5,String}[]                                      # UC_RHSTMP(REG,UC_N,T,S,UC_NUMBER)
        if !isempty(uc_rhsrt)                                         # L216-220
            r_uc = Set((k[1], k[2]) for k in ts_sum)                  # R_UC < UC_TS_SUM
            for (r, n, t) in unique((k[1], k[2], k[3]) for k in uc_rhsrt.keys)   # R_UCT < UC_RHSRT
                ((r,) in reg && (t,) in milestonyr && (r, n) in r_uc) || continue
                (r, n, t) in t_each && push!(tmp, (r, n, t, "ANNUAL", "SEVERAL"))
                (r, n, t) in t_succ && push!(tmp, (r, n, t, "ANNUAL", "DYNAMIC"))
            end
        end
        if !isempty(uc_rhsrts)                                        # L221-225
            for (r, n, t, s) in unique((k[1], k[2], k[3], k[4]) for k in uc_rhsrts.keys)   # RUCTS < UC_RHSRTS
                ((r,) in reg && (t,) in milestonyr && (r, n) in r_each && (r, n, s) in ts_each) || continue
                (r, n, t) in t_each && push!(tmp, (r, n, t, s, "EACH"))
                (r, n, t) in t_succ && push!(tmp, (r, n, t, s, "SUCC"))
            end
            # L224: UC_RHSTMP(RUCTS(UC_T_EACH(UC_R_EACH(R,UC_N),T),S),UC_NUMBER(TSL))
            #         $(TS_GROUP(R,TSL,S)$UC_DS(R,UC_N,TSL)) = YES;
            for (r, n, t, s) in unique((k[1], k[2], k[3], k[4]) for k in uc_rhsrts.keys)
                ((r,) in reg && (t,) in milestonyr && (r, n) in r_each && (r, n, t) in t_each) || continue
                for (_, _, tsl) in get(tsl_of_rn, (r, n), _NO3)
                    (r, tsl, s) in ts_group && push!(tmp, (r, n, t, s, tsl))
                end
            end
        end
        rhsmap = _gset_from("UC_RHSMAP", [(r, t, n, num, s) for (r, n, t, s, num) in tmp], d)
        ut = _gset_from("UC_UT", [(k[1], k[2]) for k in gparam(tm, "UC_RHST").keys], d)
        uts = _gset_from("UC_UTS", [(k[1], k[2], k[3]) for k in gparam(tm, "UC_RHSTS").keys], d)
        rtsuc = _gset_from("UC_RTSUC", [(k[1], k[3], k[2]) for k in t_succ], d)
        (; rhsmap, ut, uts, rtsuc)
    end
end

"""
UC_ATTR attributes refused (UC_NAME, initsys.mod L120-129): ANNUL and the
names UC_MAPCOST maps to it (INVCOST, INVTAX, INVSUB), which read CST_ANNC
of eqbndcst.mod (uc_ncap.mod L39; eqbndcst.mod is not translated), and
ONLINE (uc_cap.mod L36-42, the VDA RS family's VAR_UPS terms). Every other
name is translated: GROWTH and PERDISC; the UC_DYNT types N, CUMSUM, CUM+
and SYNC, which pick UC_TMAP entries in the RHS direction (equserco.mod L83;
M1.3 change 21); PERIOD, NEWFLO, EFF, CAPACT, BUILDUP and the cost
attributes COST, DELIV, TAX and SUB (the uc_*.mod factors; change 22); NET
and the old cost names FLO_COST ... NCAP_ISUB, which act only in
preprocessing (preppm.mod L41-43, ppmain.mod L1157); CAPFLO, whose only
effect is UC_CAPFLO (refused on its own); YES, set only under %CLI%
(refused by the generation driver).
"""
const UC_ATTR_REFUSED = ("ANNUL", "INVCOST", "INVTAX", "INVSUB", "ONLINE")

function uc_unported(tm::TimesModel, setup)
    var_uc(tm) || throw(UnportedError("user constraints with VAR_UC not YES (eqmain.mod L230-232, equcwrap.mod L13)"))
    d = tm.data
    # Dynamic families (equcwrap L34-40): nested UCs.
    isempty(gset_opt(d, "UC_GMAP_U", 3)) ||
        throw(UnportedError("equserco.mod L76/L99: nested user constraints (UC_GMAP_U, UC_UCN)"))
    let k = findfirst(k -> k[5] in UC_ATTR_REFUSED, gset(tm, "UC_ATTR").keys)
        k === nothing || throw(UnportedError("uc_ncap.mod L39, uc_cap.mod L36-42: user-constraint attribute " *
                                             "$(gset(tm, "UC_ATTR").keys[k]) (ANNUL needs eqbndcst.mod's CST_ANNC, ONLINE the VDA VAR_UPS terms)"))
    end
    isempty(gset(tm, "UC_CAPFLO")) ||
        throw(UnportedError("uc_flo.mod L35-49: capacity-related flows in user constraints (UC_CAPFLO, cal_caps.mod)"))
    return nothing
end

"""
    uc_context(tm) -> NamedTuple

Sets, parameters and incidence maps the uc_*.mod terms read, built once.
"""
function uc_context(tm::TimesModel)
    get!(tm.cache, "UC_CONTEXT") do
        rtp_vintyr = gset(tm, "RTP_VINTYR")
        attr = gset(tm, "UC_ATTR")
        (modlyear = gset(tm, "MODLYEAR"),                                      # V: setglobs.gms L147
         milestonyr = gset(tm, "MILESTONYR"),
         rs_fr = gparam(tm, "RS_FR"),
         rtcs_fr = gparam(tm, "RTCS_FR"),
         rs_below = gset(tm, "RS_BELOW"),
         vint_of_rtp = indexby(rtp_vintyr, (1, 3, 4)),                         # (r,t,p) -> RTP_VINTYR(r,v,t,p)
         varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4)),        # (r,t,p,c) -> (r,t,p,c,ts)
         rtp = gset(tm, "RTP"),
         rtp_off = gset(tm, "RTP_OFF"),
         rtp_vara = gset(tm, "RTP_VARA"),
         rpc_aire = gset(tm, "RPC_AIRE"),
         prc_actflo = gparam(tm, "PRC_ACTFLO"),
         prc_capact = gparam(tm, "PRC_CAPACT"),
         com_ie = gparam(tm, "COM_IE"),
         ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2)),                      # (r,p) -> PRC_TS(r,p,ts)
         mapflo_of_nr = indexby(gset(tm, "UC_MAP_FLO"), (1, 2, 3)),           # (n,side,r) -> (n,side,r,p,c)
         gmapp_of_rnk = indexby(gset(tm, "UC_GMAP_P"), (1, 2, 3)),            # (r,n,grp) -> (r,n,grp,p)
         gmapc_of_rnk = indexby(gset(tm, "UC_GMAP_C"), (1, 2, 3)),            # (r,n,var) -> (r,n,var,c,grptype)
         mapire_of_nr = indexby(gset(tm, "UC_MAP_IRE"), (1, 2)),              # (n,r) -> (n,r,p,c,ie)
         rhs_combal_of_rtc = indexby(gset(tm, "RHS_COMBAL"), (1, 2, 3)),      # (r,t,c) -> (r,t,c,ts)
         rhs_comprd_of_rtc = indexby(gset(tm, "RHS_COMPRD"), (1, 2, 3)),
         uc_attr = attr,
         # (r,n,side,grp) -> the UC_COST attributes of the group, in set order
         cost_of_rnsg = indexby(_gset_from("UC_ATTR/cost", [k for k in attr.keys if k[5] in UC_COST], tm.data),
                                (1, 2, 3, 4)),
         uc_dt = gset(tm, "UC_DT"),
         fpd = gparam(tm, "FPD"),
         lead = gparam(tm, "LEAD"),
         coef_pvt = gparam(tm, "COEF_PVT"),
         coef_rpti = gparam(tm, "COEF_RPTI"),
         rvpt = gset(tm, "RVPT"),                                              # eqmain.mod L199-201
         rvpt_to = indexby(gset(tm, "RVPT"), (1, 3, 4)),                      # (r,p,t) -> RVPT(r,v,p,t)
         rvpt_from = indexby(gset(tm, "RVPT"), (1, 2, 3)),                    # (r,v,p) -> RVPT(r,v,p,t)
         rdcur_of_r = indexby(gset(tm, "RDCUR"), (1,)),                       # r -> RDCUR(r,cur)
         tsann_of_ts = indexby(gset(tm, "TS_ANN"), (1,)),                     # ts -> TS_ANN(ts,sl)
         ob_fcos = gparam(tm, "OB_FCOS"),                                      # OBJ_FCOST(r,y,p,c,s,m) = OB_FCOS(r,p,c,s,m,y)
         ob_fdel = gparam(tm, "OB_FDEL"),
         ob_ftax = gparam(tm, "OB_FTAX"),
         ob_act = gparam(tm, "OB_ACT"),                                        # OBJ_ACOST(r,y,p,m) = OB_ACT(r,p,m,y)
         ob_icost = gparam(tm, "OB_ICOST"),                                    # OBJ_ICOST(r,y,p,m) = OB_ICOST(r,p,m,y)
         ob_itax = gparam(tm, "OB_ITAX"),
         ob_isub = gparam(tm, "OB_ISUB"),
         obj_compd = gparam(tm, "OBJ_COMPD"),                                  # (r,t,c,ts,costype,cur)
         obj_comnt = gparam(tm, "OBJ_COMNT"),
         uc_sign = gparam(tm, "UC_SIGN"),                                      # initsys.mod L116
         uc_flo = gparam(tm, "UC_FLO"),
         uc_act = gparam(tm, "UC_ACT"),
         uc_ncap = gparam(tm, "UC_NCAP"),
         uc_cap = gparam(tm, "UC_CAP"),
         uc_com = gparam(tm, "UC_COM"),
         uc_ire = gparam(tm, "UC_IRE"))
    end
end

const _NO2 = NTuple{2,String}[]
const _NO3 = NTuple{3,String}[]
const _NO4 = NTuple{4,String}[]
const _NO5 = NTuple{5,String}[]

"UC_COST (initsys.mod L131-132)."
const UC_COST = ("COST", "DELIV", "TAX", "SUB", "ANNUL")

"Whether UC_ATTR(R,UC_N,SIDE,grp,attr) is set."
_uc_has(x, r, n, side, grp, attr) = (r, n, side, grp, attr) in x.uc_attr

"Timeslice weight of the flow-type UC terms: `PROD(RS_BELOW(R,TS,S),RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS)))`."
_uc_tsw(x, r, t, c, s, ts) =
    (r, ts, s) in x.rs_below ? gv(x.rs_fr, (r, s, ts)) * (1 + gv(x.rtcs_fr, (r, t, c, s, ts))) : GNum(1.0)

"""
    _uc_growth(x, r, n, side, grp, coef, lagt) -> GNum

The GROWTH factor of a dynamic term (the `\$IF %6==1` lines of the uc_*.mod
files, with %8 = LAGT(T) of the row):

    PROD(UC_ATTR(R,UC_N,SIDE,grp,'GROWTH'), POWER(ABS(coef), LAGT(T)*UC_SIGN(SIDE)-1))

1 when `lagt` is `nothing` (a non-dynamic term, where those lines are not
compiled) or the attribute is absent.
"""
function _uc_growth(x, r, n, side, grp, coef::GNum, lagt)
    lagt === nothing && return GNum(1.0)
    (r, n, side, grp, "GROWTH") in x.uc_attr || return GNum(1.0)
    return gpower(abs(coef), lagt * gv(x.uc_sign, (side,)) - 1)
end

"""
    _uc_perdisc(x, r, n, grp, t) -> GNum

The period factor of a several-period term (the `\$IF %6==2` lines of
uc_flo.mod L22, uc_act.mod L22, uc_com.mod L25, uc_ire.mod L21):

    (1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS',grp,'PERDISC')-1)\$UC_DT(R,UC_N))

FPD(T) for a cumulative constraint (UC_DT), its present value with
PERDISC, and 1 otherwise; evaluated as written.
"""
function _uc_perdisc(x, r, n, grp, t)
    (r, n) in x.uc_dt || return GNum(1.0)
    fpd = gv(x.fpd, (t,))
    y = fpd + gif(gv(x.coef_pvt, (r, t)) - fpd, _uc_has(x, r, n, "LHS", grp, "PERDISC"))
    return 1 + (y - 1)
end

"""
    _uc_perds(x, r, n, side, grp, v, t, p) -> GNum

The PERIOD and NEWFLO factor of the flow, activity and trade terms
(uc_flo.mod L38-39, uc_act.mod L37-38, uc_ire.mod L38-39):

    PROD(UC_ATTR(R,UC_N,SIDE,grp,UC_PERDS), FPD(T) *
         PROD(UC_NEWFLO(UC_PERDS), 1\$(SAMEAS(V,T)+RVPT(R,V,P,T))/FPD(T)))

UC_PERDS = {PERIOD, NEWFLO}, UC_NEWFLO = {NEWFLO} (initsys.mod L147-148):
PERIOD gives FPD(T); NEWFLO gives FPD(T)*(1/FPD(T)) for the vintage of the
period (or one commissioned in it, RVPT) and 0 for the others.
"""
function _uc_perds(x, r, n, side, grp, v, t, p)
    f = GNum(1.0)
    _uc_has(x, r, n, side, grp, "PERIOD") && (f = f * gv(x.fpd, (t,)))
    if _uc_has(x, r, n, side, grp, "NEWFLO")
        fpd = gv(x.fpd, (t,))
        f = f * (fpd * (gif(GNum(1.0), v == t || (r, v, p, t) in x.rvpt) / fpd))
    end
    return f
end

"""
    _uc_fcost(x, r, n, side, grp, t, p, c, ts) -> GNum

The cost factor of the flow and trade terms (uc_flo.mod L41-46, uc_ire.mod
L41-46), 1 unless the group has a UC_COST attribute:

    PROD(REG(R)\$SUM(UC_ATTR(R,UC_N,SIDE,grp,UC_COST),1),
      SUM((RDCUR(R,CUR),TS_ANN(TS,SL)),
        OBJ_FCOST(R,T,P,C,SL,CUR)\$UC_ATTR(...'COST') + OBJ_FDELV(R,T,P,C,SL,CUR)\$UC_ATTR(...'DELIV')
        + MIN(0,OBJ_FTAX(R,T,P,C,SL,CUR))\$UC_ATTR(...'SUB') + MAX(0,OBJ_FTAX(R,T,P,C,SL,CUR))\$UC_ATTR(...'TAX')))

OBJ_FCOST/FDELV/FTAX(r,y,p,c,s,m) are OB_FCOS/FDEL/FTAX(r,p,c,s,m,y)
(coef_obj.mod L166-168).
"""
function _uc_fcost(x, r, n, side, grp, t, p, c, ts)
    isempty(get(x.cost_of_rnsg, (r, n, side, grp), _NO5)) && return GNum(1.0)
    cost, deliv = _uc_has(x, r, n, side, grp, "COST"), _uc_has(x, r, n, side, grp, "DELIV")
    sub, tax = _uc_has(x, r, n, side, grp, "SUB"), _uc_has(x, r, n, side, grp, "TAX")
    f = GZERO
    for (_, cur) in get(x.rdcur_of_r, (r,), _NO2), (_, sl) in get(x.tsann_of_ts, (ts,), _NO2)
        ftax = gv(x.ob_ftax, (r, p, c, sl, cur, t))
        f = f + (gif(gv(x.ob_fcos, (r, p, c, sl, cur, t)), cost) + gif(gv(x.ob_fdel, (r, p, c, sl, cur, t)), deliv) +
                 gif(gmin(GZERO, ftax), sub) + gif(gmax(GZERO, ftax), tax))
    end
    return f
end

# Every term function below takes the term's period `t` (%4: T, or TT in the
# dynamic blocks; the period of the variables) and, as keywords, the side
# (%5: 'LHS', or SIDE), a factor `k0` that multiplies the whole term (the
# dynamic blocks' UC_SIGN(SIDE), the RS family's 1/G_YRFR), `lagt`, the
# GROWTH exponent's period length of a dynamic term (%6 = 1: LAGT(T) in the
# LHS direction, -LEAD(T) in the RHS direction) or `nothing`, `tc`, the
# period of the UC_* coefficient (%7: T, TT, or LL in the RHS direction; `t`
# by default), and `several`, true for the several-period families (%6 = 2:
# the period factor `_uc_perdisc`).

"""
    uc_flo!(expr, tm, n, r, t, s; side="LHS", k0=1, lagt=nothing, tc=t, several=false) -> expr

    [(1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS','FLO','PERDISC')-1)\$UC_DT(R,UC_N)) *, %6 = 2]
    SUM((RTP_VINTYR(R,V,T,P),RTPCS_VARF(R,T,P,C,TS))\$(UC_MAP_FLO(UC_N,SIDE,R,P,C)\$RS_FR(R,S,TS)),
        [cal_red C COM TS P T] * UC_FLO(UC_N,SIDE,R,TC,P,C,TS) *
        PROD(ANNUAL,1)*PROD(RS_BELOW(R,TS,S),RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))) *
        [GROWTH factor, dynamic only] * [PERIOD/NEWFLO factor] * [cost factor])

GAMS: uc_flo.mod L4-59, v4.9.7 (L35-49 UC_CAPFLO refused).
"""
function uc_flo!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String, s::String;
                 side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    several && (k0 = k0 * _uc_perdisc(x, r, n, "FLO", t))
    for (_, _, _, p, c) in get(x.mapflo_of_nr, (n, side, r), _NO5)
        for (_, v, _, _) in get(x.vint_of_rtp, (r, t, p), _NO4)
            (v,) in x.modlyear || continue
            for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), _NO5)
                haskey(x.rs_fr, (r, s, ts)) || continue
                coef = gv(x.uc_flo, (n, side, r, tc, p, c, ts))
                k = k0 * coef * _uc_tsw(x, r, t, c, s, ts) * _uc_growth(x, r, n, side, "FLO", coef, lagt) *
                    _uc_perds(x, r, n, side, "FLO", v, t, p) * _uc_fcost(x, r, n, side, "FLO", t, p, c, ts)
                cal_nored!(expr, tm, k, r, v, t, p, c, ts)
            end
        end
    end
    return expr
end

"""
    uc_ncap!(expr, tm, n, r, t; side="LHS", k0=1, lagt=nothing, tc=t) -> expr

    SUM(UC_GMAP_P(R,UC_N,'NCAP',P)\$RTP(R,T,P), UC_NCAP(UC_N,SIDE,R,TC,P) *
        (VAR_NCAP(R,T,P)\$(NOT RTP_OFF(R,T,P)) +
         (SUM(RVPT(R,V,P,T),VAR_NCAP(R,V,P)) + VAR_NCAP(R,T,P) *
          (COEF_RPTI(R,T,P)-PROD(RVPT(R,T,P,MILESTONYR),2)))\$UC_ATTR(R,UC_N,SIDE,'NCAP','PERIOD')) *
        [GROWTH factor, dynamic only] *
        PROD(UC_ATTR(R,UC_N,SIDE,'NCAP','BUILDUP'),1/LEAD(T)) *
        PROD(L('N'),PROD(REG(R)\$SUM(UC_ATTR(R,UC_N,SIDE,'NCAP',UC_COST),1),
          SUM(RDCUR(R,CUR), [ANNUL: CST_ANNC, refused] + OBJ_ICOST(R,T,P,CUR)\$UC_ATTR(...'COST')
              + OBJ_ITAX(R,T,P,CUR)\$UC_ATTR(...'TAX') - OBJ_ISUB(R,T,P,CUR)\$UC_ATTR(...'SUB')))))

`PROD(RVPT(R,T,P,MILESTONYR),2)` is 2 when the period's investment is
commissioned in a period (RVPT, eqmain.mod L199-201) and 1 otherwise.
OBJ_ICOST/ITAX/ISUB(r,y,p,m) are OB_ICOST/ITAX/ISUB(r,p,m,y) (coef_obj.mod
L157-159).

GAMS: uc_ncap.mod L3-50, v4.9.7.
"""
function uc_ncap!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String;
                  side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    period = _uc_has(x, r, n, side, "NCAP", "PERIOD")
    buildup = _uc_has(x, r, n, side, "NCAP", "BUILDUP")
    hascost = !isempty(get(x.cost_of_rnsg, (r, n, side, "NCAP"), _NO5))
    cost, tax, sub = (_uc_has(x, r, n, side, "NCAP", a) for a in ("COST", "TAX", "SUB"))
    for (_, _, _, p) in get(x.gmapp_of_rnk, (r, n, "NCAP"), _NO4)
        (r, t, p) in x.rtp || continue
        coef = gv(x.uc_ncap, (n, side, r, tc, p))
        k = k0 * coef * _uc_growth(x, r, n, side, "NCAP", coef, lagt)
        buildup && (k = k * (1 / gv(x.lead, (t,))))
        if hascost
            f = GZERO
            for (_, cur) in get(x.rdcur_of_r, (r,), _NO2)
                f = f + (gif(gv(x.ob_icost, (r, p, cur, t)), cost) + gif(gv(x.ob_itax, (r, p, cur, t)), tax) -
                         gif(gv(x.ob_isub, (r, p, cur, t)), sub))
            end
            k = k * f
        end
        (r, t, p) in x.rtp_off || addterm!(expr, k, tm, "VAR_NCAP", r, t, p)
        if period
            for (_, v, _, _) in get(x.rvpt_to, (r, p, t), _NO4)
                addterm!(expr, k, tm, "VAR_NCAP", r, v, p)
            end
            nrvpt = count(kk -> (kk[4],) in x.milestonyr, get(x.rvpt_from, (r, t, p), _NO4))
            addterm!(expr, k * (gv(x.coef_rpti, (r, t, p)) - GNum(2.0^nrvpt)), tm, "VAR_NCAP", r, t, p)
        end
    end
    return expr
end

"""
    uc_cap!(expr, tm, n, r, t; side="LHS", k0=1, lagt=nothing, tc=t) -> expr

    SUM(RTP(R,T,P)\$UC_GMAP_P(R,UC_N,'CAP',P),
        VAR_CAP(R,T,P) * UC_CAP(UC_N,SIDE,R,TC,P) *
        [GROWTH factor, dynamic only] *
        PROD(UC_ATTR(R,UC_N,SIDE,'CAP','CAPACT'),PRC_CAPACT(R,P)) * PROD(L('N'),1))

GAMS: uc_cap.mod L3-34, v4.9.7 (L36-50, VDA ONLINE and ABS reserves, only
for the RS family: ONLINE and ABS are refused).
"""
function uc_cap!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String;
                 side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    capact = _uc_has(x, r, n, side, "CAP", "CAPACT")
    for (_, _, _, p) in get(x.gmapp_of_rnk, (r, n, "CAP"), _NO4)
        (r, t, p) in x.rtp || continue
        coef = gv(x.uc_cap, (n, side, r, tc, p))
        k = k0 * coef * _uc_growth(x, r, n, side, "CAP", coef, lagt)
        capact && (k = k * gv(x.prc_capact, (r, p)))
        addterm!(expr, k, tm, "VAR_CAP", r, t, p)
    end
    return expr
end

"""
    uc_act!(expr, tm, n, r, t, s; side="LHS", k0=1, lagt=nothing, tc=t, several=false) -> expr

    [(1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS','ACT','PERDISC')-1)\$UC_DT(R,UC_N)) *, %6 = 2]
    SUM(RTP_VINTYR(R,V,T,P)\$UC_GMAP_P(R,UC_N,'ACT',P),
        SUM(PRC_TS(R,P,TS)\$(RS_FR(R,S,TS)*RTP_VARA(R,T,P)),
            VAR_ACT(R,V,T,P,TS)*UC_ACT(UC_N,SIDE,R,TC,P,TS)*PROD(ANNUAL,RS_FR(R,S,TS)) *
            [GROWTH factor, dynamic only] * [PERIOD/NEWFLO factor]) *
        PROD(UC_ATTR(R,UC_N,SIDE,'ACT','COST'),SUM(RDCUR(R,CUR),OBJ_ACOST(R,T,P,CUR))))

OBJ_ACOST(r,y,p,m) is OB_ACT(r,p,m,y) (coef_obj.mod L165).
GAMS: uc_act.mod L4-52, v4.9.7.
"""
function uc_act!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String, s::String;
                 side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    several && (k0 = k0 * _uc_perdisc(x, r, n, "ACT", t))
    cost = _uc_has(x, r, n, side, "ACT", "COST")
    for (_, _, _, p) in get(x.gmapp_of_rnk, (r, n, "ACT"), _NO4)
        (r, t, p) in x.rtp_vara || continue
        fc = GNum(1.0)
        if cost
            fc = GZERO
            for (_, cur) in get(x.rdcur_of_r, (r,), _NO2)
                fc = fc + gv(x.ob_act, (r, p, cur, t))
            end
        end
        for (_, v, _, _) in get(x.vint_of_rtp, (r, t, p), _NO4)
            (v,) in x.modlyear || continue
            for (_, _, ts) in get(x.ts_of_rp, (r, p), _NO3)
                haskey(x.rs_fr, (r, s, ts)) || continue
                coef = gv(x.uc_act, (n, side, r, tc, p, ts))
                k = k0 * coef * gv(x.rs_fr, (r, s, ts)) * _uc_growth(x, r, n, side, "ACT", coef, lagt) *
                    _uc_perds(x, r, n, side, "ACT", v, t, p) * fc
                addterm!(expr, k, tm, "VAR_ACT", r, v, t, p, ts)
            end
        end
    end
    return expr
end

"""
    uc_com!(expr, tm, n, r, t, s, kind; side="LHS", k0=1, lagt=nothing, tc=t, several=false) -> expr

`kind` = "NET" (equserco.mod L44/L72: `uc_com ... BAL NET NT`) or "PRD"
(L42/L70: `PRD PRD PD`):

    SUM(UC_GMAP_C(R,UC_N,'%9',C,UC_GRPTYPE),
      [(1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS',UC_GRPTYPE,'PERDISC')-1)\$UC_DT(R,UC_N)) *, %6 = 2]
        SUM(RHS_COM%8(R,T,C,TS)\$RS_FR(R,S,TS),
            UC_COM(UC_N,'%9',SIDE,R,TC,C,TS,UC_GRPTYPE) * VAR_COM%9(R,T,C,TS) *
            (1+(1/COM_IE(R,T,C,TS)-1)\$(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,'EFF') XOR DIAG(UC_GRPTYPE,'COM%9'))) *
            PROD(ANNUAL,1)*PROD(RS_BELOW(R,TS,S),RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))) *
            [GROWTH factor on UC_GRPTYPE, dynamic only] *
            PROD(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,'PERIOD'),FPD(T)) *
            PROD(REG(R)\$SUM(UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_COST),1),
              SUM((UC_ATTR(R,UC_N,SIDE,UC_GRPTYPE,UC_COST),RDCUR(R,CUR)), OBJ_COM%10(R,T,C,TS,UC_COST,CUR)))))

DIAG is GAMS's built-in label comparison (docs/discrepancies.md G15), so a
term whose group type is COMNET (COMPRD) is divided by COM_IE unless EFF is
set, and one of another group type only when EFF is set. %10 is PD for PRD
and NT for NET (OBJ_COMPD, OBJ_COMNT).

GAMS: uc_com.mod L4-47, v4.9.7.
"""
function uc_com!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String, s::String, kind::String;
                 side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    kind in ("NET", "PRD") || throw(ArgumentError("uc_com kind must be NET or PRD, got $kind"))
    rhs_of = kind == "NET" ? x.rhs_combal_of_rtc : x.rhs_comprd_of_rtc
    obj_com = kind == "NET" ? x.obj_comnt : x.obj_compd
    var = "VAR_COM" * kind
    for (_, _, _, c, grptype) in get(x.gmapc_of_rnk, (r, n, kind), _NO5)
        kg = several ? k0 * _uc_perdisc(x, r, n, grptype, t) : k0
        ie_div = _uc_has(x, r, n, side, grptype, "EFF") ⊻ (grptype == "COM" * kind)
        period = _uc_has(x, r, n, side, grptype, "PERIOD")
        costs = get(x.cost_of_rnsg, (r, n, side, grptype), _NO5)
        for (_, _, _, ts) in get(rhs_of, (r, t, c), _NO4)
            haskey(x.rs_fr, (r, s, ts)) || continue
            f = ie_div ? 1 + (GNum(1.0) / gv(x.com_ie, (r, t, c, ts)) - 1) : GNum(1.0)
            coef = gv(x.uc_com, (n, kind, side, r, tc, c, ts, grptype))
            k = kg * coef * f * _uc_tsw(x, r, t, c, s, ts) * _uc_growth(x, r, n, side, grptype, coef, lagt)
            period && (k = k * gv(x.fpd, (t,)))
            if !isempty(costs)
                fc = GZERO
                for (_, _, _, _, ucc) in costs, (_, cur) in get(x.rdcur_of_r, (r,), _NO2)
                    fc = fc + gv(obj_com, (r, t, c, ts, ucc, cur))
                end
                k = k * fc
            end
            addterm!(expr, k, tm, var, r, t, c, ts)
        end
    end
    return expr
end

"""
    uc_ire!(expr, tm, n, r, t, s; side="LHS", k0=1, lagt=nothing, tc=t, several=false) -> expr

    [(1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS','IRE','PERDISC')-1)\$UC_DT(R,UC_N)) *, %6 = 2]
    SUM((RTP_VINTYR(R,V,T,P),UC_MAP_IRE(UC_N,R,P,C,IE),RTPCS_VARF(R,T,P,C,TS))\$RS_FR(R,S,TS),
        (VAR_IRE(R,V,T,P,C,TS,IE)\$(NOT RPC_AIRE(R,P,C))+(VAR_ACT(R,V,T,P,TS)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))
        * UC_IRE(UC_N,SIDE,R,TC,P,C,TS,IE) *
        PROD(ANNUAL,1)*PROD(RS_BELOW(R,TS,S),RS_FR(R,S,TS)*(1+RTCS_FR(R,T,C,S,TS))) *
        [GROWTH factor, dynamic only] * [PERIOD/NEWFLO factor] * [cost factor, as uc_flo])

UC_MAP_IRE has no side index: the same exchanges enter both sides.
GAMS: uc_ire.mod L4-57, v4.9.7.
"""
function uc_ire!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String, s::String;
                 side::String="LHS", k0::GNum=GNum(1.0), lagt=nothing, tc::String=t, several::Bool=false)
    x = uc_context(tm)
    several && (k0 = k0 * _uc_perdisc(x, r, n, "IRE", t))
    for (_, _, p, c, ie) in get(x.mapire_of_nr, (n, r), _NO5)
        for (_, v, _, _) in get(x.vint_of_rtp, (r, t, p), _NO4)
            (v,) in x.modlyear || continue
            for (_, _, _, _, ts) in get(x.varf_of_rtpc, (r, t, p, c), _NO5)
                haskey(x.rs_fr, (r, s, ts)) || continue
                coef = gv(x.uc_ire, (n, side, r, tc, p, c, ts, ie))
                k = k0 * coef * _uc_tsw(x, r, t, c, s, ts) * _uc_growth(x, r, n, side, "IRE", coef, lagt) *
                    _uc_perds(x, r, n, side, "IRE", v, t, p) * _uc_fcost(x, r, n, side, "IRE", t, p, c, ts)
                if !((r, p, c) in x.rpc_aire)
                    addterm!(expr, k, tm, "VAR_IRE", r, v, t, p, c, ts, ie)
                else
                    addterm!(expr, gv(x.prc_actflo, (r, v, p, c)) * k, tm, "VAR_ACT", r, v, t, p, ts)
                end
            end
        end
    end
    return expr
end

"""
    uc_lhs!(expr, tm, n, regions, t, ts_of) -> expr

The non-dynamic left-hand side, equserco.mod L34-46 with HS = 'LHS':
uc_flo + uc_ncap + uc_cap + uc_act + uc_com PRD + uc_com NET + uc_ire, each
summed over `regions` (%4%7) and, for the timeslice terms, over `ts_of(r)`
(%6); the period is the row's (%5 is a bracket in all four families).
"""
function uc_lhs!(expr::JuMP.AffExpr, tm::TimesModel, n::String, regions, t::String, ts_of)
    for r in regions, s in ts_of(r)
        uc_flo!(expr, tm, n, r, t, s)
    end
    for r in regions
        uc_ncap!(expr, tm, n, r, t)
    end
    for r in regions
        uc_cap!(expr, tm, n, r, t)
    end
    for r in regions, s in ts_of(r)
        uc_act!(expr, tm, n, r, t, s)
    end
    for kind in ("PRD", "NET"), r in regions, s in ts_of(r)
        uc_com!(expr, tm, n, r, t, s, kind)
    end
    for r in regions, s in ts_of(r)
        uc_ire!(expr, tm, n, r, t, s)
    end
    return expr
end

"""
    uc_tmap_n(tm) -> Dict{String,Vector{Tuple{String,String}}}

The 'N' part of UC_TMAP (eqmain.mod L211-212), keyed for the LHS-direction
sum `SUM(UC_TMAP(TT,T,T,SIDE,'N'), ...)` of equserco.mod L60: row period T
-> the (TT, SIDE) pairs.

    UC_TMAP(T,TT(T-DIAG(SIDE,'RHS')),TT,SIDE,'N') = YES;

so UC_TMAP(T,T,T,'LHS','N') for every T and UC_TMAP(T+1,T,T,'RHS','N') for
every T but the last (a non-circular lag): the LHS terms are at T, the RHS
terms at T+1. T is MILESTONYR in GAMS order.
"""
function uc_tmap_n(tm::TimesModel)
    get!(tm.cache, "UC_TMAP_N") do
        ts = [k[1] for k in gset(tm, "MILESTONYR").keys]
        out = Dict{String,Vector{Tuple{String,String}}}()
        for (i, t) in enumerate(ts)
            pairs = [(t, "LHS")]
            i < length(ts) && push!(pairs, (ts[i+1], "RHS"))
            out[t] = pairs
        end
        out
    end
end

"""
    uc_dyn!(expr, tm, n, regions, t, ts_of) -> expr

The dynamic body in the LHS direction, equserco.mod L56-78 (%8 = 1):

    ( SUM(UC_TMAP(TT,T,T,SIDE,'N'), UC_SIGN(SIDE) * [uc_flo, uc_ncap, uc_cap, uc_act,
          uc_com PRD, uc_com NET, uc_ire at period TT and side SIDE, GROWTH exponent LAGT(T)])
      + [nested UCN terms, refused] )\$(NOT SUM(UC_DYNDIR(R,UC_N,'RHS'),1))

summed over `regions` (%4%7) and the timeslice terms over `ts_of(r)` (%6).
The caller takes this block or [`uc_dyn_rhs!`](@ref), by the UC_DYNDIR
condition (`uc_rhsdir`).
"""
function uc_dyn!(expr::JuMP.AffExpr, tm::TimesModel, n::String, regions, t::String, ts_of)
    x = uc_context(tm)
    lagt = gv(gparam(tm, "LAGT"), (t,))
    pairs = uc_tmap_n(tm)[t]
    kw(tt, side) = (; side, k0=gv(x.uc_sign, (side,)), lagt)
    for r in regions, (tt, side) in pairs, s in ts_of(r)
        uc_flo!(expr, tm, n, r, tt, s; kw(tt, side)...)
    end
    for r in regions, (tt, side) in pairs
        uc_ncap!(expr, tm, n, r, tt; kw(tt, side)...)
    end
    for r in regions, (tt, side) in pairs
        uc_cap!(expr, tm, n, r, tt; kw(tt, side)...)
    end
    for r in regions, (tt, side) in pairs, s in ts_of(r)
        uc_act!(expr, tm, n, r, tt, s; kw(tt, side)...)
    end
    for kind in ("PRD", "NET"), r in regions, (tt, side) in pairs, s in ts_of(r)
        uc_com!(expr, tm, n, r, tt, s, kind; kw(tt, side)...)
    end
    for r in regions, (tt, side) in pairs, s in ts_of(r)
        uc_ire!(expr, tm, n, r, tt, s; kw(tt, side)...)
    end
    return expr
end

"""
    uc_tmap(tm) -> GamsSet{5}

UC_TMAP(YEAR,YEAR,T,SIDE,UC_DYNT), the period maps of the dynamic user
constraints, eqmain.mod L211-215:

    UC_TMAP(T,TT(T-DIAG(SIDE,'RHS')),TT,SIDE,'N') = YES;
    UC_TMAP(T,TT(T-DIAG(SIDE,'RHS')),MILESTONYR,SIDE,'CUMSUM')\$(ORD(T) > ORD(MILESTONYR)+DIAG(SIDE,'RHS')) = YES;
    UC_TMAP(T,T,T,'RHS','SYNC') = YES;
    UC_TMAP(T,T,TT,'RHS','CUM+')\$UC_TMAP(T,T,TT,'LHS','CUMSUM') = YES;

With T the i-th milestone year and T-1 the one before it (a lag on
MILESTONYR, not circular): (T,T,T,'LHS','N'); (T,T-1,T-1,'RHS','N') for
i > 1; (T,T,M,'LHS','CUMSUM') for every milestone M before T;
(T,T-1,M,'RHS','CUMSUM') for every M before T-1; (T,T,T,'RHS','SYNC'); and
(T,T,M,'RHS','CUM+') for every M before T. DIAG is GAMS's label comparison
(docs/discrepancies.md G15). In the RHS direction (equserco.mod L83) the
first index is the row's period, the second (LL) the period of the
coefficients and the third (TT) that of the variables. The set is in the
presolve dump; `test_equserco_dyn.jl` checks this one against it.
"""
function uc_tmap(tm::TimesModel)
    get!(tm.cache, "UC_TMAP") do
        ts = [k[1] for k in gset(tm, "MILESTONYR").keys]
        out = NTuple{5,String}[]
        for (i, t) in enumerate(ts)
            push!(out, (t, t, t, "LHS", "N"))                                  # L212, SIDE = LHS
            i > 1 && push!(out, (t, ts[i-1], ts[i-1], "RHS", "N"))             # L212, SIDE = RHS
            for j in 1:i-1
                push!(out, (t, t, ts[j], "LHS", "CUMSUM"))                     # L213: ORD(T) > ORD(M)
                j < i - 1 && push!(out, (t, ts[i-1], ts[j], "RHS", "CUMSUM"))  # L213: ORD(T) > ORD(M)+1
                push!(out, (t, t, ts[j], "RHS", "CUM+"))                       # L215
            end
            push!(out, (t, t, t, "RHS", "SYNC"))                               # L214
        end
        _gset_from("UC_TMAP", out, tm.data)
    end
end

"UC_TMAP keyed by its first index (the row's period): T -> (LL, TT, SIDE, UC_DYNT), in set order."
uc_tmap_of_t(tm::TimesModel) =
    get!(tm.cache, "UC_TMAP/t") do
        out = Dict{String,Vector{NTuple{4,String}}}()
        for (t, ll, tt, side, dynt) in uc_tmap(tm)
            push!(get!(() -> NTuple{4,String}[], out, t), (ll, tt, side, dynt))
        end
        out
    end::Dict{String,Vector{NTuple{4,String}}}

"""
    uc_rhsdir(tm, n[, r]) -> Bool

The condition that picks a dynamic constraint's direction, equserco.mod L78
and L106: `SUM(UC_DYNDIR(R,UC_N,'RHS'),1)`, with R the row's region (the
UCRSU and UCRSUS families) or, when the row has no region index (UCSU and
UCSUS), any region (the SUM then controls R).
"""
function uc_rhsdir(tm::TimesModel, n::String, r=nothing)
    dyn = get!(tm.cache, "UC_DYNDIR/RHS") do
        Set((k[1], k[2]) for k in gset(tm, "UC_DYNDIR") if k[3] == "RHS")
    end::Set{Tuple{String,String}}
    r === nothing && return any(k -> k[2] == n, dyn)
    return (r, n) in dyn
end

"""
    uc_dyn_rhs!(expr, tm, n, regions, t, ts_of) -> expr

The dynamic body in the RHS direction, equserco.mod L80-106 (%8 = 1):

    ( SUM(UC_TMAP(T,LL,TT,SIDE,UC_DYNT)\$(LIM(UC_DYNT) xor UC_ATTR(R,UC_N,SIDE,grp,UC_DYNT)), UC_SIGN(SIDE)*
          [uc_flo, uc_ncap, uc_cap, uc_act, uc_com PRD, uc_com NET, uc_ire: the variables at TT,
           the coefficients at LL, side SIDE, GROWTH exponent -LEAD(T)*UC_SIGN(SIDE)-1])
      + [nested UCN terms, refused] + [uc_cli.mod, %CLI% refused]
      - [uc_pasti.mod] )\$SUM(UC_DYNDIR(R,UC_N,'RHS'),1)

grp is the name each include passes to the TSUM macro: FLO, NCAP, CAP, ACT,
COMPRD, COMNET and IRE (for uc_com it is not the term's UC_GRPTYPE). LIM =
{LO, FX, UP, N} (initsys.mod L70) and UC_DYNT = {N, CUMSUM, CUM+, SYNC}
(L142), so an 'N' entry of UC_TMAP is taken unless the group has the
attribute N, and a CUMSUM, CUM+ or SYNC entry only when it has that
attribute (ppmain.mod L1160-1168 set them). Each term is summed over
`regions` (%4%7, which also controls the R of the UC_ATTR test), then the
UC_TMAP entries, then, for the timeslice terms, `ts_of(r)` (%6).

GAMS: equserco.mod L80-106 with uc_flo.mod, uc_ncap.mod, uc_cap.mod,
uc_act.mod, uc_com.mod, uc_ire.mod (%6 = 1) and uc_pasti.mod, v4.9.7.
"""
function uc_dyn_rhs!(expr::JuMP.AffExpr, tm::TimesModel, n::String, regions, t::String, ts_of)
    x = uc_context(tm)
    mlead = -gv(gparam(tm, "LEAD"), (t,))
    entries = get(uc_tmap_of_t(tm), t, _NO4)
    take(r, grp) = [(ll, tt, side) for (ll, tt, side, dynt) in entries
                    if (dynt == "N") ⊻ ((r, n, side, grp, dynt) in x.uc_attr)]
    kw(ll, side) = (; side, k0=gv(x.uc_sign, (side,)), lagt=mlead, tc=ll)
    for r in regions, (ll, tt, side) in take(r, "FLO"), s in ts_of(r)
        uc_flo!(expr, tm, n, r, tt, s; kw(ll, side)...)
    end
    for r in regions, (ll, tt, side) in take(r, "NCAP")
        uc_ncap!(expr, tm, n, r, tt; kw(ll, side)...)
    end
    for r in regions, (ll, tt, side) in take(r, "CAP")
        uc_cap!(expr, tm, n, r, tt; kw(ll, side)...)
    end
    for r in regions, (ll, tt, side) in take(r, "ACT"), s in ts_of(r)
        uc_act!(expr, tm, n, r, tt, s; kw(ll, side)...)
    end
    for (kind, grp) in (("PRD", "COMPRD"), ("NET", "COMNET")), r in regions, (ll, tt, side) in take(r, grp), s in ts_of(r)
        uc_com!(expr, tm, n, r, tt, s, kind; kw(ll, side)...)
    end
    for r in regions, (ll, tt, side) in take(r, "IRE"), s in ts_of(r)
        uc_ire!(expr, tm, n, r, tt, s; kw(ll, side)...)
    end
    return uc_pasti!(expr, tm, n, regions, t)
end

"""
    uc_pasti!(expr, tm, n, regions, t) -> expr

The past investments' capacity, subtracted in the RHS direction
(equserco.mod L103-104: `- uc_pasti.mod %4%7 MIYR_1 T 'RHS'`):

    - %4%7 SUM(RTP(R,T,P)\$UC_GMAP_P(R,UC_N,'CAP',P),
              SUM(RTP_CPTYR(R,PASTYEAR,T,P),COEF_CPT(R,PASTYEAR,T,P)*NCAP_PASTI(R,PASTYEAR,P)) *
              UC_CAP(UC_N,'RHS',R,T,P) *
              PROD(SIDE('RHS'),PROD(UC_ATTR(R,UC_N,SIDE,'CAP','GROWTH'),
                   POWER(ABS(UC_CAP(UC_N,'RHS',R,T,P)),M(T)-B(T))))) )\$SUM(MIYR_1(T),1)

a constant, only in the first period's rows: the capacity the past
investments leave in the first period stands for the RHS capacity of the
period before it. GAMS moves it to the right-hand side.

GAMS: uc_pasti.mod L16-32, v4.9.7.
"""
function uc_pasti!(expr::JuMP.AffExpr, tm::TimesModel, n::String, regions, t::String)
    (t,) in gset(tm, "MIYR_1") || return expr
    x = uc_context(tm)
    y = get!(tm.cache, "UC_PASTI") do
        (cptyr = indexby(gset(tm, "RTP_CPTYR"), (1, 3, 4)),                  # (r,t,p) -> RTP_CPTYR(r,v,t,p)
         pastyear = gset(tm, "PASTYEAR"),
         coef_cpt = gparam(tm, "COEF_CPT"),
         ncap_pasti = gparam(tm, "NCAP_PASTI"),
         m = gparam(tm, "M"),
         b = gparam(tm, "B"))
    end
    for r in regions
        for (_, _, _, p) in get(x.gmapp_of_rnk, (r, n, "CAP"), _NO4)
            (r, t, p) in x.rtp || continue
            pasti = GNum(0.0)
            for (_, v, _, _) in get(y.cptyr, (r, t, p), _NO4)
                (v,) in y.pastyear || continue
                pasti += gv(y.coef_cpt, (r, v, t, p)) * gv(y.ncap_pasti, (r, v, p))
            end
            coef = gv(x.uc_cap, (n, "RHS", r, t, p))
            g = (r, n, "RHS", "CAP", "GROWTH") in x.uc_attr ?
                gpower(abs(coef), gv(y.m, (t,)) - gv(y.b, (t,))) : GNum(1.0)
            addconst!(expr, -(pasti * coef * g))
        end
    end
    return expr
end

"""
    uc_several_lhs!(expr, tm, n, regions, ts_of) -> expr

The left-hand side of the UC and UCR families (equcwrap.mod L22/L24, %8 = 2,
HS = 'LHS'): each term summed over `regions` (%4%7), over the periods of
UC_T_SUM(R,UC_N,T) (%5 = `SUM(UC_T_SUM(R,UC_N,T),`) and, for the timeslice
terms, over `ts_of(r)` (%6). The flow, activity, commodity and trade terms
are multiplied by the period factor of the `\$IF %6==2` lines

    (1+(FPD(T)+(COEF_PVT(R,T)-FPD(T))\$UC_ATTR(R,UC_N,'LHS',grp,'PERDISC')-1)\$UC_DT(R,UC_N))

(`_uc_perdisc`: FPD(T) for a cumulative constraint, UC_DT, ppmain.mod
L1150, its present value COEF_PVT with PERDISC, 1 otherwise); the capacity
terms are not. Then the cumulative terms:

    + SUM((%7RPC_CUMFLO(R,P,C,ALLYEAR,LL))\$UC_CUMFLO(UC_N,R,P,C,ALLYEAR,LL),
          UC_CUMFLO(UC_N,R,P,C,ALLYEAR,LL)*VAR_CUMFLO(R,P,C,ALLYEAR,LL)*%CUFSCAL%)
    + SUM((%7COM_VAR,C,YEAR,LL)\$UC_CUMCOM(UC_N,R,COM_VAR,C,YEAR,LL),
          UC_CUMCOM(UC_N,R,COM_VAR,C,YEAR,LL)*VAR_CUMCOM(R,C,COM_VAR,YEAR,LL)*%CUCSCAL%)

The cumulative-commodity term needs no RC_CUMCOM entry (a range dropped by
bnd_cum.mod L31 keeps its column). T is MILESTONYR (G8).

GAMS: equserco.mod L34-49 with uc_flo.mod L22/L77, uc_act.mod L22,
uc_com.mod L25, uc_ire.mod L21, v4.9.7.
"""
function uc_several_lhs!(expr::JuMP.AffExpr, tm::TimesModel, n::String, regions, ts_of)
    x = uc_context(tm)
    milestonyr = gset(tm, "MILESTONYR")
    tsum_of_rn = get!(() -> indexby(gset(tm, "UC_T_SUM"), (1, 2)), tm.cache, "UC_T_SUM/rn")
    periods(r) = [k[3] for k in get(tsum_of_rn, (r, n), _NO3) if (k[3],) in milestonyr]
    for r in regions, t in periods(r), s in ts_of(r)
        uc_flo!(expr, tm, n, r, t, s; several=true)
    end
    for r in regions, t in periods(r)
        uc_ncap!(expr, tm, n, r, t)
    end
    for r in regions, t in periods(r)
        uc_cap!(expr, tm, n, r, t)
    end
    for r in regions, t in periods(r), s in ts_of(r)
        uc_act!(expr, tm, n, r, t, s; several=true)
    end
    for kind in ("PRD", "NET"), r in regions, t in periods(r), s in ts_of(r)
        uc_com!(expr, tm, n, r, t, s, kind; several=true)
    end
    for r in regions, t in periods(r), s in ts_of(r)
        uc_ire!(expr, tm, n, r, t, s; several=true)
    end
    # Cumulative flows (uc_flo.mod L77) and commodities (equserco.mod L49).
    cufscal = parse(Float64, gswitch(tm, "CUFSCAL", "10"))
    cucscal = parse(Float64, gswitch(tm, "CUCSCAL", "1000"))
    cumflo = gparam(tm, "UC_CUMFLO")
    cumflo_of_nr = get!(() -> indexby(cumflo, (1, 2)), tm.cache, "UC_CUMFLO/nr")
    rpc_cumflo = gset(tm, "RPC_CUMFLO")
    cumcom = gparam(tm, "UC_CUMCOM")
    cumcom_of_nr = get!(() -> indexby(cumcom, (1, 2)), tm.cache, "UC_CUMCOM/nr")
    for r in regions
        for k in get(cumflo_of_nr, (n, r), NTuple{6,String}[])
            (_, _, p, c, y1, y2) = k
            (r, p, c, y1, y2) in rpc_cumflo || continue
            addterm!(expr, gv(cumflo, k) * cufscal, tm, "VAR_CUMFLO", r, p, c, y1, y2)
        end
    end
    for r in regions
        for k in get(cumcom_of_nr, (n, r), NTuple{6,String}[])
            (_, _, cv, c, y1, y2) = k
            addterm!(expr, gv(cumcom, k) * cucscal, tm, "VAR_CUMCOM", r, c, cv, y1, y2)
        end
    end
    return expr
end

"""
    uc_rs_pairs(tm, r, n, tsl, sl) -> Vector{Tuple{String,String}}

The (SIDE, S) pairs of the RS family's %5 sum, equcwrap.mod L42:

    SUM((UC_TSL(R,UC_N,SIDE,TSL),G_UDS(SL,SIDE,S))\$(RHS(SIDE)->RS_PREV(R,SL,S)), UC_SIGN(SIDE)* ...

G_UDS(S,'LHS',S) for every slice and G_UDS(S,'RHS',TS) for the previous
slice RS_PREV (ppmain.mod L1178-1179), so the LHS side is taken at the row's
slice SL and the RHS side at its predecessor in the cycle. RHS = {'RHS'}
(setglobs.gms L120).
"""
function uc_rs_pairs(tm::TimesModel, r::String, n::String, tsl::String, sl::String)
    x = get!(tm.cache, "UC_RS") do
        (sides = indexby(gset(tm, "UC_TSL"), (1, 2, 4)),          # (r,n,tsl) -> UC_TSL(r,n,side,tsl)
         uds = indexby(gset(tm, "G_UDS"), (1, 2)),                # (sl,side) -> G_UDS(sl,side,s)
         rs_prev = gset(tm, "RS_PREV"))
    end
    out = Tuple{String,String}[]
    for (_, _, side, _) in get(x.sides, (r, n, tsl), _NO4)
        for (_, _, s) in get(x.uds, (sl, side), _NO3)
            (side == "RHS" && !((r, sl, s) in x.rs_prev)) && continue
            push!(out, (side, s))
        end
    end
    return out
end

"""
    uc_rs_lhs!(expr, tm, n, r, t, pairs) -> expr

The RS family's left-hand side, equserco.mod L34-46 with %4%7 = '(', %5 =
the (SIDE, S) sum of [`uc_rs_pairs`](@ref), %6 = '(' and %8 = S (HS = SIDE):
each uc_*.mod term at period T, side SIDE and slice S, times UC_SIGN(SIDE).
The flow-type files (uc_flo L5, uc_act L15, uc_com L14, uc_ire L15) add the
factor `1/G_YRFR(R,S)` for %6 = S; uc_ncap and uc_cap have none. uc_cap.mod
L15-27 (VDA ONLINE and ABS reserve terms, compiled for %VDA%%5 = YESS) give
nothing: ONLINE is a UC_ATTR attribute (refused with the others) and ABS is
refused by the generation driver.

GAMS: equcwrap.mod L42 with equserco.mod L23-46, uc_flo.mod L5, uc_act.mod
L15, uc_com.mod L14, uc_ire.mod L15, uc_cap.mod L15-27, v4.9.7.
"""
function uc_rs_lhs!(expr::JuMP.AffExpr, tm::TimesModel, n::String, r::String, t::String, pairs)
    x = uc_context(tm)
    g_yrfr = gparam(tm, "G_YRFR")
    sgn(side) = gv(x.uc_sign, (side,))
    per_s(side, s) = sgn(side) * (GNum(1.0) / gv(g_yrfr, (r, s)))
    for (side, s) in pairs
        uc_flo!(expr, tm, n, r, t, s; side, k0=per_s(side, s))
    end
    for (side, _) in pairs
        uc_ncap!(expr, tm, n, r, t; side, k0=sgn(side))
    end
    for (side, _) in pairs
        uc_cap!(expr, tm, n, r, t; side, k0=sgn(side))
    end
    for (side, s) in pairs
        uc_act!(expr, tm, n, r, t, s; side, k0=per_s(side, s))
    end
    for kind in ("PRD", "NET"), (side, s) in pairs
        uc_com!(expr, tm, n, r, t, s, kind; side, k0=per_s(side, s))
    end
    for (side, s) in pairs
        uc_ire!(expr, tm, n, r, t, s; side, k0=per_s(side, s))
    end
    return expr
end

"""
    eq_uc!(tm::TimesModel) -> Int

Generate the EQE_UC, EQE_UCR, EQE_UCT, EQE_UCRT, EQE_UCTS and EQE_UCRTS rows
(VAR_UC = YES):

    EQE_UC(UC_N)\$(SUM(BD\$UC_RHS(UC_N,BD),1)\$(SUM(UC_TS_SUM(UC_R_SUM(R,UC_N),S),1)\$SUM(UC_T_SUM(R,UC_N,T),1))) ..
        [several-period LHS summed over UC_R_SUM(R,UC_N)] =E= VAR_UC(UC_N) +
        SUM((UC_R_SUM(R,UC_N),V(T))\$UC_TIME(UC_N,R,T), SUM(UC_T_SUM(R,UC_N,T), UC_TIME(UC_N,R,T)*FPD(T)));
    EQE_UCR(UC_R_EACH(R,UC_N))\$(SUM(BD\$UC_RHSR(R,UC_N,BD),1)\$(SUM(UC_TS_SUM(R,UC_N,S),1)\$SUM(UC_T_SUM(R,UC_N,T),1))) ..
        [several-period LHS at R] =E= VAR_UCR(UC_N,R) + [the UC_TIME term at R];

whose left-hand side is [`uc_several_lhs!`](@ref) (a SUM over a
multi-dimensional set controls all its free indices: the UC_T_SUM test of
EQE_UC holds for any region);

    EQE_UCRTS(R,T,UC_N,S)\$UC_RHSMAP(R,T,UC_N,'EACH',S) ..
        [LHS at (R,T,S)] =E= VAR_UCRTS(UC_N,R,T,S) + SUM((V(T))\$UC_TIME(UC_N,R,T), (UC_TIME(UC_N,R,T)*FPD(T)));
    EQE_UCRT(R,T,UC_N)\$UC_RHSMAP(R,T,UC_N,'SEVERAL','ANNUAL') ..
        [LHS at R,T summed over UC_TS_SUM(R,UC_N,S)] =E= VAR_UCRT(UC_N,R,T) + [same UC_TIME term];
    EQE_UCTS(UC_N,T,S)\$(SUM(UC_T_EACH(UC_R_SUM(R,UC_N),T)\$UC_TS_EACH(R,UC_N,S),1)\$UC_UTS(UC_N,T,S)) ..
        [LHS summed over UC_R_SUM(R,UC_N)] =E= VAR_UCTS(UC_N,T,S) + SUM((UC_R_SUM(R,UC_N),V(T))\$UC_TIME(UC_N,R,T), (...));
    EQE_UCT(UC_N,T)\$(SUM(UC_T_EACH(UC_R_SUM(R,UC_N),T)\$SUM(UC_TS_SUM(R,UC_N,S),1),1)\$UC_UT(UC_N,T)) ..
        [LHS summed over UC_R_SUM(R,UC_N) and UC_TS_SUM(R,UC_N,S)] =E= VAR_UCT(UC_N,T) + [region-summed UC_TIME term];

the timeslice-level rows (UC_DS), whose left-hand side is [`uc_rs_lhs!`](@ref):

    EQE_UCRS(R,T,UC_N,TSL(UC_NUMBER),SL)\$(UC_RHSMAP(R,T,UC_N,UC_NUMBER,SL)\$UC_DS(R,UC_N,TSL)) ..
        [RS LHS] =E= VAR_UCRTS(UC_N,R,T,SL) +
        SUM((V(T))\$UC_TIME(UC_N,R,T), SUM((UC_TSL(...),G_UDS(...))\$(...), UC_SIGN(SIDE)*UC_TIME(UC_N,R,T)*FPD(T)));

and the dynamic rows (UC_T_SUCC), whose left-hand side is [`uc_dyn!`](@ref):

    EQE_UCRSUS(UC_RTSUC(R,T,UC_N),S)\$UC_RHSMAP(R,T,UC_N,'SUCC',S) ..
        [dynamic LHS at (R,T,S)] =E= VAR_UCRTS(UC_N,R,T,S) +
        SUM((V(T))\$UC_TIME(UC_N,R,T), UC_TIME(UC_N,R,T)*(LEAD(T)\$UC_DYNDIR(R,UC_N,'RHS')+LAGT(T)\$(NOT UC_DYNDIR(R,UC_N,'RHS'))));
    EQE_UCRSU(UC_RTSUC(R,T,UC_N))\$UC_RHSMAP(R,T,UC_N,'DYNAMIC','ANNUAL') ..
        [summed over UC_TS_SUM(R,UC_N,S)] =E= VAR_UCRT(UC_N,R,T) + [same UC_TIME term];
    EQE_UCSUS(UC_N,T,S)\$(SUM(UC_T_SUCC(UC_R_SUM(R,UC_N),T)\$UC_TS_EACH(R,UC_N,S),1)\$UC_UTS(UC_N,T,S)) ..
        [summed over UC_R_SUM(R,UC_N)] =E= VAR_UCTS(UC_N,T,S) + [region-summed UC_TIME term];
    EQE_UCSU(UC_N,T)\$(SUM(UC_T_SUCC(UC_R_SUM(R,UC_N),T)\$SUM(UC_TS_SUM(R,UC_N,S),1),1)\$UC_UT(UC_N,T)) ..
        [summed over UC_R_SUM(R,UC_N) and UC_TS_SUM(R,UC_N,S)] =E= VAR_UCT(UC_N,T) + [region-summed UC_TIME term];

`V(T)` with T controlled is a membership test (docs/discrepancies.md G14).
Returns the number of rows.

GAMS: equcwrap.mod L22-42 with equserco.mod L23-78, L108-120, v4.9.7.
"""
function eq_uc!(tm::TimesModel)
    setup = uc_setup(tm)
    has_rhs = !isempty(setup.rhsmap) || !isempty(setup.ut) || !isempty(setup.uts) ||
              !isempty(gparam(tm, "UC_RHS")) || !isempty(gparam(tm, "UC_RHSR"))
    has_rhs || return 0
    uc_unported(tm, setup)

    milestonyr, modlyear = gset(tm, "MILESTONYR"), gset(tm, "MODLYEAR")
    r_sum, t_each = gset(tm, "UC_R_SUM"), gset(tm, "UC_T_EACH")
    ts_each = gset(tm, "UC_TS_EACH")
    uc_time, fpd = gparam_opt(tm.data, "UC_TIME", 3), gparam(tm, "FPD")
    regs_of_n = Dict{String,Vector{String}}()
    for (r, n) in r_sum
        (r,) in gset(tm, "REG") && push!(get!(() -> String[], regs_of_n, n), r)
    end
    tssum_of_rn = indexby(gset(tm, "UC_TS_SUM"), (1, 2))      # (r,n) -> UC_TS_SUM(r,n,s)
    tssum(r, n) = [k[3] for k in get(tssum_of_rn, (r, n), _NO3)]

    # SUM((%7V(T))$UC_TIME(UC_N,R,T), %5 UC_TIME(UC_N,R,T)*FPD(T))) over `regions`.
    function add_time!(rhs, n, regions, t)
        (t,) in modlyear || return rhs
        for r in regions
            haskey(uc_time, (n, r, t)) && addconst!(rhs, gv(uc_time, (n, r, t)) * gv(fpd, (t,)))
        end
        return rhs
    end

    # L118, %8 = 1: SUM((%7V(T))$UC_TIME(UC_N,R,T), UC_TIME(UC_N,R,T)*(LEAD(T)$UC_DYNDIR(R,UC_N,'RHS')
    #                                      +LAGT(T)$(NOT UC_DYNDIR(R,UC_N,'RHS')))).
    lead, lagt = gparam(tm, "LEAD"), gparam(tm, "LAGT")
    dyndir = gset(tm, "UC_DYNDIR")
    function add_time_dyn!(rhs, n, regions, t)
        (t,) in modlyear || return rhs
        for r in regions
            haskey(uc_time, (n, r, t)) || continue
            rhsdir = (r, n, "RHS") in dyndir
            addconst!(rhs, gv(uc_time, (n, r, t)) * (gif(gv(lead, (t,)), rhsdir) + gif(gv(lagt, (t,)), !rhsdir)))
        end
        return rhs
    end
    t_succ, rtsuc = gset(tm, "UC_T_SUCC"), setup.rtsuc
    # The dynamic body (equserco.mod L56-106): the LHS direction (L56-78) or the RHS
    # direction (L80-106), each under its UC_DYNDIR condition; `r` is the row's region
    # or `nothing` for the region-summed families.
    dyn!(expr, n, r, regions, t, ts_of) = uc_rhsdir(tm, n, r) ?
        uc_dyn_rhs!(expr, tm, n, regions, t, ts_of) : uc_dyn!(expr, tm, n, regions, t, ts_of)

    n_rows = 0
    # EQE_UC(UC_N), equcwrap L22, %8 = 2: SUM(BD$UC_RHS(UC_N,BD),1) and some
    # UC_TS_SUM(UC_R_SUM(R,UC_N),S) and some UC_T_SUM(R,UC_N,T).
    tsum_of_n = indexby(gset(tm, "UC_T_SUM"), (2,))                # n -> UC_T_SUM(r,n,t)
    tsum_of_rn = indexby(gset(tm, "UC_T_SUM"), (1, 2))             # (r,n) -> UC_T_SUM(r,n,t)
    bds = ("LO", "UP", "FX")                                       # BD (initsys.mod)
    uc_rhs, uc_rhsr = gparam(tm, "UC_RHS"), gparam(tm, "UC_RHSR")
    # SUM((%7V(T))$UC_TIME(UC_N,R,T), SUM(UC_T_SUM(R,UC_N,T), UC_TIME(UC_N,R,T)*FPD(T))): the
    # inner SUM over an already-controlled T is a condition (G18).
    function add_time_several!(rhs, n, regions)
        for r in regions, (_, _, t) in get(tsum_of_rn, (r, n), _NO3)
            ((t,) in milestonyr && (t,) in modlyear && haskey(uc_time, (n, r, t))) || continue
            addconst!(rhs, gv(uc_time, (n, r, t)) * gv(fpd, (t,)))
        end
        return rhs
    end
    uc_n_order = [k[1] for k in gset(tm, "UC_N").keys]
    for n in uc_n_order
        any(bd -> haskey(uc_rhs, (n, bd)), bds) || continue
        regs = get(regs_of_n, n, String[])
        any(r -> !isempty(tssum(r, n)), regs) || continue
        isempty(get(tsum_of_n, (n,), _NO3)) && continue
        lhs = uc_several_lhs!(JuMP.AffExpr(0.0), tm, n, regs, r -> tssum(r, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UC", n)
        add_time_several!(rhs, n, regs)
        gconstraint!(tm, "EQE_UC", (n,), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCR(R,UC_N), equcwrap L24, %8 = 2, over UC_R_EACH(R,UC_N).
    for (r, n) in gset(tm, "UC_R_EACH")
        (r,) in gset(tm, "REG") || continue
        any(bd -> haskey(uc_rhsr, (r, n, bd)), bds) || continue
        (!isempty(tssum(r, n)) && !isempty(get(tsum_of_rn, (r, n), _NO3))) || continue
        lhs = uc_several_lhs!(JuMP.AffExpr(0.0), tm, n, (r,), rr -> tssum(rr, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCR", n, r)
        add_time_several!(rhs, n, (r,))
        gconstraint!(tm, "EQE_UCR", (r, n), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCT(UC_N,T), equcwrap L26.
    for (n, t) in setup.ut
        (t,) in milestonyr || continue
        regs = get(regs_of_n, n, String[])
        any(r -> (r, n, t) in t_each && !isempty(tssum(r, n)), regs) || continue
        lhs = uc_lhs!(JuMP.AffExpr(0.0), tm, n, regs, t, r -> tssum(r, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCT", n, t)
        add_time!(rhs, n, regs, t)
        gconstraint!(tm, "EQE_UCT", (n, t), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCRT(R,T,UC_N), equcwrap L28.
    for (r, t, n, num, s) in setup.rhsmap
        (num == "SEVERAL" && s == "ANNUAL") || continue
        lhs = uc_lhs!(JuMP.AffExpr(0.0), tm, n, (r,), t, rr -> tssum(rr, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCRT", n, r, t)
        add_time!(rhs, n, (r,), t)
        gconstraint!(tm, "EQE_UCRT", (r, t, n), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCTS(UC_N,T,S), equcwrap L30.
    for (n, t, s) in setup.uts
        (t,) in milestonyr || continue
        regs = get(regs_of_n, n, String[])
        any(r -> (r, n, t) in t_each && (r, n, s) in ts_each, regs) || continue
        lhs = uc_lhs!(JuMP.AffExpr(0.0), tm, n, regs, t, _ -> (s,))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCTS", n, t, s)
        add_time!(rhs, n, regs, t)
        gconstraint!(tm, "EQE_UCTS", (n, t, s), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCRTS(R,T,UC_N,S), equcwrap L32.
    for (r, t, n, num, s) in setup.rhsmap
        num == "EACH" || continue
        lhs = uc_lhs!(JuMP.AffExpr(0.0), tm, n, (r,), t, _ -> (s,))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCRTS", n, r, t, s)
        add_time!(rhs, n, (r,), t)
        gconstraint!(tm, "EQE_UCRTS", (r, t, n, s), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCRS(R,T,UC_N,TSL,SL), equcwrap L42.
    uc_ds = gset_opt(tm.data, "UC_DS", 3)
    for (r, t, n, tsl, sl) in setup.rhsmap
        (r, n, tsl) in uc_ds || continue
        pairs = uc_rs_pairs(tm, r, n, tsl, sl)
        lhs = uc_rs_lhs!(JuMP.AffExpr(0.0), tm, n, r, t, pairs)
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCRTS", n, r, t, sl)
        if (t,) in modlyear && haskey(uc_time, (n, r, t))      # L117 with %5 = the (SIDE, S) sum
            for (side, _) in pairs
                addconst!(rhs, gv(gparam(tm, "UC_SIGN"), (side,)) * (gv(uc_time, (n, r, t)) * gv(fpd, (t,))))
            end
        end
        gconstraint!(tm, "EQE_UCRS", (r, t, n, tsl, sl), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCSU(UC_N,T), equcwrap L34.
    for (n, t) in setup.ut
        (t,) in milestonyr || continue
        regs = get(regs_of_n, n, String[])
        any(r -> (r, n, t) in t_succ && !isempty(tssum(r, n)), regs) || continue
        lhs = dyn!(JuMP.AffExpr(0.0), n, nothing, regs, t, r -> tssum(r, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCT", n, t)
        add_time_dyn!(rhs, n, regs, t)
        gconstraint!(tm, "EQE_UCSU", (n, t), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCRSU(R,T,UC_N), equcwrap L36.
    for (r, t, n, num, s) in setup.rhsmap
        (num == "DYNAMIC" && s == "ANNUAL" && (r, t, n) in rtsuc) || continue
        lhs = dyn!(JuMP.AffExpr(0.0), n, r, (r,), t, rr -> tssum(rr, n))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCRT", n, r, t)
        add_time_dyn!(rhs, n, (r,), t)
        gconstraint!(tm, "EQE_UCRSU", (r, t, n), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCRSUS(R,T,UC_N,S), equcwrap L38.
    for (r, t, n, num, s) in setup.rhsmap
        (num == "SUCC" && (r, t, n) in rtsuc) || continue
        lhs = dyn!(JuMP.AffExpr(0.0), n, r, (r,), t, _ -> (s,))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCRTS", n, r, t, s)
        add_time_dyn!(rhs, n, (r,), t)
        gconstraint!(tm, "EQE_UCRSUS", (r, t, n, s), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    # EQE_UCSUS(UC_N,T,S), equcwrap L40.
    for (n, t, s) in setup.uts
        (t,) in milestonyr || continue
        regs = get(regs_of_n, n, String[])
        any(r -> (r, n, t) in t_succ && (r, n, s) in ts_each, regs) || continue
        lhs = dyn!(JuMP.AffExpr(0.0), n, nothing, regs, t, _ -> (s,))
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_UCTS", n, t, s)
        add_time_dyn!(rhs, n, regs, t)
        gconstraint!(tm, "EQE_UCSUS", (n, t, s), "E", lhs, rhs) === nothing || (n_rows += 1)
    end
    return n_rows
end
