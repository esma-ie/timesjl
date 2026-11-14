# EQE_CAPACT / EQL_CAPACT / EQG_CAPACT: capacity utilisation (activity
# against available capacity).
#
# GAMS: eqcapact.mod L15-52, v4.9.7, included three times from eqmain.mod
# L64-66 as
#   $BATINCLUDE eqcapact.mod E FX %MX%
#   $BATINCLUDE eqcapact.mod L UP %MX%
#   $BATINCLUDE eqcapact.mod G LO
# so %1 = E/L/G (the equation type, giving EQE_/EQL_/EQG_CAPACT), %2 =
# FX/UP/LO (the bound type the row enforces) and %3 = %MX%.
#
# Macro expansions:
# - %EQ% -> EQ, %VAR%/%VARM%/%VARV% -> VAR, %SWT%/%SOW%/%SWS% -> ''
#   (setglobs.gms L348, SW_NOTAGS).
# - %MX% -> '': setglobs.gms is included with X1='1' (maindrv.mod L23), which
#   only checks that the user set none of MX, RCAPSUB, RCAPSBM, and then
#   re-runs itself with X1='' (setglobs.gms L374 -> L341), setting them all
#   to ''; maindrv.mod L30 then re-empties MX (readbprice.mod L20-23 only uses
#   MX to carry a MACRO switch). So COEF_AF%3 is COEF_AF in all three
#   variants. %RCAPSBM% (L37) and %RCAPSUB% (L45) are set by prepret.dsc
#   L87-88 when early retirement is on: the -VAR_SCAP term (`rcapsub!`, M1.3
#   change 20b-2; docs/discrepancies.md D1, withdrawn).
# - %R_V_T% -> 'R,V,T' (maindrv.mod L39).
# - %PASS% (L15-16) becomes `*(NOT RPS_CAFLAC(R,P,S,'%2'))` when RPS_CAFLAC is
#   DEFINED. With VDA it is (init_ext.vda L23 declares it, ppm_ext.vda L133
#   assigns it with OPTION, and GAMS counts an OPTION assignment as
#   defining: confirmed on GAMS 54.6.0). Without VDA it is not declared.
#   Filtering on RPS_CAFLAC membership (empty when undeclared) covers both.
# - %VALIDATE% is not YES (it is a MARKAL-validation switch no test model
#   sets), so the L34/L39-40 VALIDATE branch is not translated; TimesModel has
#   no VALIDATE switch until run options arrive (M1.5).
#
# AFS (L18-20). GAMS fills AFS while executing the L include; the three
# equation definitions are generated later, at SOLVE, from AFS as it stands
# then. Between the two, other files may remove AFS entries:
#   coef_csv.mod L74 (when PRC_SIMV is DEFINED; eqmain.mod L67),
#   equ_ext.vda L79 (VDA: NCAP_AFCS(R,T,P,'ACT',S)),
#   eqactups.vda L11 (VDA dispatching: the entries that go to AFUPS, for
#     processes with RP_UPL(R,P,'FX'); they get EQ_CAPLOAD rows instead),
#   equ_ext.abs L24 (ABS extension, out of Phase 1 scope).
# coef_csv.mod L74, equ_ext.vda L79 and eqactups.vda L11 are translated (afs_solve;
# the entries coef_csv.mod takes out are AFSV, afsv_solve, the rows of EQ(l)_CAPVAC
# in eqcapvac.jl). equ_ext.abs L24 needs the ABS extension, which generate! refuses
# by its switch. AFS cannot be checked against a dump directly
# (solsetv.v3 L203 clears it after the solve); the generated rows check it.
#
# Storage (L28, L50 for RP_STG processes): the storage level VAR_ACT of the
# PRC_TS slices TS related to S (RS_FR(R,TS,S)), times the number of storage
# cycles over S, RS_FR(R,TS,S)*EXP(PRC_SC(R,P))/RS_STGPRD(R,TS), against the
# capacity without the G_YRFR factor (POWER(G_YRFR,0) = 1, G4). VAR_STS is
# the coef_ext.vda L31 macro under VDA (GAMS counts a macro as DEFINED, so
# mod_vars.mod L96's zero parameter is never declared, G2): a sum of
# VAR_UDP over RP_STL(R,P,TSL,'%2') entries, which exist only with
# %STSFLX% = YES (coef_ext.vda L32), refused (eqstgtss.jl).
#
# Coefficients are computed as GNum (GAMS EPS arithmetic) and emitted with
# addterm!, which reproduces GAMS's rule for matrix entries: a term and its
# column exist when the coefficient is nonzero or EPS, not for an exact zero
# (docs/discrepancies.md G5-G6).

"Equation variants of eqcapact.mod as included from eqmain.mod L64-66: (%1, %2)."
const CAPACT_VARIANTS = (("E", "FX"), ("L", "UP"), ("G", "LO"))

"""
    afs_capact(tm) -> GamsSet{5}

AFS(R,T,P,S,BD): the (process, period, timeslice, bound type) combinations
with an availability factor, as built by eqcapact.mod L18-20, v4.9.7:

    SET AFS(R,T,P,S,BD) //;
    LOOP(V,AFS(RTP_VARA(R,T,P),S,BD)\$COEF_AF(R,V,T,P,S,BD)=YES); AFS(RTPS_OFF,BD) = NO;

V is MODLYEAR (setglobs.gms L147), so a member exists when some model
vintage has a present (nonzero or EPS) COEF_AF. Members are in GAMS order.
Later AFS changes by other files are not applied here (see the file
header); `eq_capact!` refuses data that would trigger them.
"""
function afs_capact(tm::TimesModel)
    modlyear = gset(tm, "MODLYEAR")       # V: ALIAS(MODLYEAR,V), setglobs.gms L147
    milestonyr = gset(tm, "MILESTONYR")   # T: ALIAS(MILESTONYR,T,TT), initmty.mod L94
    rtp_vara = gset(tm, "RTP_VARA")
    rtps_off = gset(tm, "RTPS_OFF")
    coef_af = gparam(tm, "COEF_AF")

    found = Set{NTuple{5,String}}()
    for (r, v, t, p, s, bd) in coef_af.keys
        (v,) in modlyear || continue
        (t,) in milestonyr || continue          # T controls RTP_VARA(R,T,P) in the assignment
        (r, t, p) in rtp_vara || continue
        (r, t, p, s) in rtps_off && continue
        push!(found, (r, t, p, s, bd))
    end
    keys = gams_sort!(collect(found), tm.data)
    return GamsSet{5}("AFS", keys, Set(keys))
end

"""
    capact_unported_afs_changes(tm)

Throw an `UnportedError` when the data would make another GAMS file remove
AFS entries before the CAPACT rows are generated (eqcapact.mod header in
eqcapact.jl lists them); otherwise return nothing. No data does so now:
coef_csv.mod L74, equ_ext.vda L79 and eqactups.vda L11 are translated
(`afs_solve`), and equ_ext.abs L24 is behind the ABS switch, which
`generate!` refuses.
"""
function capact_unported_afs_changes(tm::TimesModel)
    return nothing
end

"""
    afs_solve(tm) -> GamsSet{5}

AFS as it stands when the SOLVE generates the EQ(l)_CAPACT and EQ(l)_CAFLAC
rows: [`afs_capact`](@ref) (eqcapact.mod L18-20) after coef_csv.mod L74,
when PRC_SIMV is DEFINED (eqmain.mod L67),

    AFSV(AFS(R,T,P,S,BD))\$=PRC_SIMV(R,P); AFS(AFSV)=NO;

and after the VDA statements

    AFS(RTP(R,T,P),S,BDUPX)\$NCAP_AFCS(RTP,'ACT',S) = NO;
    AFUPS(R,T,P,S)\$(...) \$= AFS(R,T,P,S,'UP')\$RP_UPL(R,P,'FX'); AFS(AFUPS,BD)=NO;

of equ_ext.vda L79 and eqactups.vda L11, v4.9.7 (BDUPX = {UP, FX},
setglobs.gms L155; L11: `afups_from_afs`, eqactups.jl). AFS is rebuilt here
from the COEF_AF of the pre-solve state, which holds the entries
eqactups.vda L14 adds; each of those is in AFUPS, so L11 on the rebuilt set
removes the same entries. Note that
the period T stands in NCAP_AFCS's vintage position. NCAP_AFCS exists only
with VDA (initmty.vda L26). RTP is read from the pre-solve dump: the only
later change to it, pp_qack.mod L54 `RTP(NO_RVP) = NO`, removes nothing
without PRC_SIMV, because ppmain.mod L552 clears NO_RVP; with PRC_SIMV
(L590) NO_RVP holds entries of the simulated processes only, and those
have left AFS. Cached per model.
"""
function afs_solve(tm::TimesModel)
    return get!(tm.cache, "AFS/solve") do
        afs = afs_capact(tm)
        if simv_defined(tm)                                     # coef_csv.mod L74: AFS(AFSV)=NO
            simv = gset_opt(tm.data, "PRC_SIMV", 2)
            keys = [k for k in afs.keys if !((k[1], k[3]) in simv)]
            afs = GamsSet{5}("AFS", keys, Set(keys))
        end
        afcs = gparam_opt(tm.data, "NCAP_AFCS", 5)
        act = Set((r, v, p, s) for (r, v, p, cg, s) in afcs.keys if uppercase(cg) == "ACT")
        keys = afs.keys
        if !isempty(act)
            rtp = gset(tm, "RTP")
            keys = [k for k in keys
                    if !(k[5] in ("UP", "FX") && (k[1], k[2], k[3]) in rtp && (k[1], k[2], k[3], k[4]) in act)]
        end
        # eqactups.vda L11: the entries that go to AFUPS leave AFS
        afups = afups_from_afs(keys, tm.data)
        isempty(afups) || (keys = [k for k in keys if !((k[1], k[2], k[3], k[4]) in afups)])
        keys === afs.keys && return afs
        return GamsSet{5}("AFS", keys, Set(keys))
    end::GamsSet{5}
end

"""
    afsv_solve(tm) -> GamsSet{5}

AFSV(R,T,P,S,BD), the domain of EQ(l)_CAPVAC: the [`afs_capact`](@ref) entries
of the processes in PRC_SIMV, which coef_csv.mod L74 moves out of AFS (before
equ_ext.vda L79, which acts on AFS only):

    AFSV(AFS(R,T,P,S,BD))\$=PRC_SIMV(R,P); AFS(AFSV)=NO;

PRC_SIMV is the set after coef_csv.mod L27. Cached per model.

GAMS: coef_csv.mod L74, v4.9.7.
"""
function afsv_solve(tm::TimesModel)
    return get!(tm.cache, "AFSV/solve") do
        simv = gset_opt(tm.data, "PRC_SIMV", 2)
        keys = [k for k in afs_capact(tm).keys if (k[1], k[3]) in simv]
        return GamsSet{5}("AFSV", keys, Set(keys))
    end::GamsSet{5}
end

"""
    eq_capact!(tm::TimesModel) -> Int

Generate every EQE_CAPACT, EQL_CAPACT and EQG_CAPACT row (eqmain.mod L64-66)
from `tm.data`, creating the VAR_ACT and VAR_NCAP columns they reference.
Returns the number of rows generated.

GAMS: eqcapact.mod L15-52, v4.9.7.
"""
function eq_capact!(tm::TimesModel)
    capact_unported_afs_changes(tm)
    afs = afs_solve(tm)
    n = 0
    for (eqtype, bd) in CAPACT_VARIANTS
        n += eq_capact!(tm, eqtype, bd, afs)
    end
    return n
end

"""
    eq_capact!(tm, eqtype, bd, afs) -> Int

One include of eqcapact.mod: `eqtype` is %1 (E, L or G), `bd` is %2 (FX, UP
or LO).

    EQ%1_CAPACT(RTP_VINTYR(R,V,T,P),S)\$(AFS(R,T,P,S,'%2') * (NOT RPS_CAFLAC(R,P,S,'%2'))) ..
      SUM(PRC_TS(R,P,TS)\$TS_MAP(R,S,TS), VAR_ACT(R,V,T,P,TS))\$(NOT RP_STG(R,P))
      + SUM(PRC_TS(R,P,TS)\$RS_FR(R,TS,S),
            (VAR_ACT(R,V,T,P,TS) + VAR_STS(R,V,T,P,TS,'%2')) * RS_FR(R,TS,S)*EXP(PRC_SC(R,P))/RS_STGPRD(R,TS))\$RP_STG(R,P)
      =%1=
      ( (SUM(MODLYEAR\$COEF_CPT(R,MODLYEAR,T,P),
             COEF_CPT(R,MODLYEAR,T,P) * COEF_AF(R,MODLYEAR,T,P,S,'%2') *
             (VAR_NCAP(R,MODLYEAR,P)\$T(MODLYEAR) + NCAP_PASTI(R,MODLYEAR,P)\$PASTYEAR(MODLYEAR))
            ) * PRC_CAPACT(R,P))\$(NOT PRC_VINT(R,P)) +
        (COEF_AF(R,V,T,P,S,'%2') * COEF_CPT(R,V,T,P) * PRC_CAPACT(R,P) *
         (VAR_NCAP(R,V,P)\$T(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)))\$PRC_VINT(R,P)
      ) * POWER(G_YRFR(R,S), 1-1\$RP_STG(R,P));

GAMS: eqcapact.mod L22-52, v4.9.7 (the VALIDATE branch L34/L39-40 and
VAR_STS with %STSFLX% are not translated; see the file header).
"""
function eq_capact!(tm::TimesModel, eqtype::AbstractString, bd::AbstractString, afs::GamsSet{5})
    name = "EQ$(eqtype)_CAPACT"

    rtp_vintyr = gset(tm, "RTP_VINTYR")
    rps_caflac = gset_opt(tm.data, "RPS_CAFLAC", 4)
    prc_ts = gset(tm, "PRC_TS")
    ts_map = gset(tm, "TS_MAP")
    rp_stg = gset(tm, "RP_STG")
    prc_vint = gset(tm, "PRC_VINT")
    milestonyr = gset(tm, "MILESTONYR")   # T: ALIAS(MILESTONYR,T,TT), initmty.mod L94
    modlyear = gset(tm, "MODLYEAR")
    pastyear = gset(tm, "PASTYEAR")
    coef_cpt = gparam(tm, "COEF_CPT")
    coef_af = gparam(tm, "COEF_AF")
    prc_capact = gparam(tm, "PRC_CAPACT")
    g_yrfr = gparam(tm, "G_YRFR")
    ncap_pasti = gparam(tm, "NCAP_PASTI")
    rs_fr = gparam(tm, "RS_FR")
    prc_sc = gparam(tm, "PRC_SC")
    rs_stgprd = gparam(tm, "RS_STGPRD")
    stl_bd = Set((k[1], k[2], k[4]) for k in gset(tm, "RP_STL"))   # (r,p,bd) with an RP_STL entry

    # Precomputed incidence maps: no filtering over dense domains in the row loop.
    s_of_rtpbd = indexby(afs, (1, 2, 3, 5))      # (r,t,p,bd) -> AFS members, GAMS order
    ts_of_rp = indexby(prc_ts, (1, 2))           # (r,p) -> PRC_TS members
    # SUM(MODLYEAR$COEF_CPT(R,MODLYEAR,T,P), ...): vintages k per (r,t,p).
    k_of_rtp = Dict{NTuple{3,String},Vector{String}}()
    for (r, k, t, p) in coef_cpt.keys
        (k,) in modlyear || continue
        push!(get!(() -> String[], k_of_rtp, (r, t, p)), k)
    end

    # One capacity term, coefficient `c`: VAR_NCAP(r,k,p)$T(k) + NCAP_PASTI(r,k,p)$PASTYEAR(k)
    # with %RCAPSBM% (L37) or %RCAPSUB% (L45), k controlled in both (prepret.jl).
    function add_capacity!(rhs, r, k, t, p, c::GNum)
        (k,) in milestonyr && addterm!(rhs, c, tm, "VAR_NCAP", r, k, p)
        (k,) in pastyear && addconst!(rhs, c * gv(ncap_pasti, (r, k, p)))
        rcapsub!(rhs, c, tm, r, k, t, p)
        return rhs
    end

    n = 0
    for (r, v, t, p) in rtp_vintyr
        # The domain RTP_VINTYR(R,V,T,P) is controlled by V (MODLYEAR) and T (MILESTONYR).
        ((v,) in modlyear && (t,) in milestonyr) || continue
        for (_, _, _, s, _) in get(s_of_rtpbd, (r, t, p, bd), NTuple{5,String}[])
            (r, p, s, bd) in rps_caflac && continue
            stg = (r, p) in rp_stg

            lhs = JuMP.AffExpr(0.0)
            if !stg
                # L25: activity in the timeslices at or below S.
                for (_, _, ts) in get(ts_of_rp, (r, p), NTuple{3,String}[])
                    (r, s, ts) in ts_map || continue
                    addterm!(lhs, GNum(1.0), tm, "VAR_ACT", r, v, t, p, ts)
                end
            else
                # L28: storage level times the storage cycles of TS within S.
                (r, p, bd) in stl_bd && throw(UnportedError(
                    "eqcapact.mod L28 VAR_STS(R,V,T,P,TS,'$bd') of ($r, $p): RP_STL with %STSFLX% (coef_ext.vda L31-32)"))
                cyc = gexp(gv(prc_sc, (r, p)))
                for (_, _, ts) in get(ts_of_rp, (r, p), NTuple{3,String}[])
                    haskey(rs_fr, (r, ts, s)) || continue
                    addterm!(lhs, gv(rs_fr, (r, ts, s)) * cyc / gv(rs_stgprd, (r, ts)), tm, "VAR_ACT", r, v, t, p, ts)
                end
            end

            # RHS, L32-50, times POWER(G_YRFR(R,S),1-1$RP_STG(R,P)).
            capact = gv(prc_capact, (r, p))
            yrfr = gpower(gv(g_yrfr, (r, s)), stg ? 0 : 1)
            rhs = JuMP.AffExpr(0.0)
            if !((r, p) in prc_vint)
                for k in get(k_of_rtp, (r, t, p), String[])
                    c = gv(coef_cpt, (r, k, t, p)) * gv(coef_af, (r, k, t, p, s, bd)) * capact * yrfr
                    add_capacity!(rhs, r, k, t, p, c)
                end
            else
                c = gv(coef_af, (r, v, t, p, s, bd)) * gv(coef_cpt, (r, v, t, p)) * capact * yrfr
                add_capacity!(rhs, r, v, t, p, c)
            end

            gconstraint!(tm, name, (r, v, t, p, s), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
