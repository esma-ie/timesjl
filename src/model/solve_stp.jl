# M1.5 part 1, change 2: the stepped (myopic) solve of solve.stp. This file
# holds the partition of the horizon into steps and the data each step
# prepares before its model is generated.
#
# GAMS source (TIMES v4.9.7 @ d9a6a25):
#   solve.stp L9-26       control checks; the symbols solve.stp declares
#   solve.stp L43-57      the first partition: YR_V1, SUBT, BACKWARD, FORWARD, RT_PP, NO_RT
#   clearsol.stp L8-10    RVT, FIL (included at solve.stp L60)
#   solve.stp L69-107     FX bounds copied to LO and UP, UC_RN, R_UC, RTP_VARP, RTP_CAPYR, VAR_CAP.L,
#                         STP_UCT, STP_DIV
#   solve.stp L111-196    one step: the partition, the end of the horizon, coef_alt.lin STP, OBJ_LIFE,
#                         eqobsalv.mod STP, RVPRL, the period sets of the user constraints, the relaxed
#                         right-hand sides (UC_BND), bnd_ucw.mod
#   solve.stp L217, L222-227   NO_RVP, FIL, bnd_cum.mod
#   solve.stp L288-289    PAR_CUMFLOM, PAR_UCR
#   solve.stp L295-319    after the SOLVE: PRESOL, the marginals restored, the next SUBT, the saved
#                         data restored, bndmain.mod with its second argument 1
#
# Not in this file: the variable bounds of a step (L199-282) and the equations
# over SUBT (maindrv.mod L38-40) are change 3 of docs/m15-plan.md; the loop
# with the SOLVE is change 4.
#
# The run controls, as GAMS leaves them:
# - maindrv.mod L23 includes setglobs.gms after the data is read, and its L11
#   (`$IF NOT SET FIXBOH $KILL REG_FIXT`) removes REG_FIXT unless FIXBOH is
#   set. So without FIXBOH maindrv.mod L41 (`$IF DEFINED REG_FIXT ... SET RTPX
#   X`) leaves %RTPX% empty, solve.stp L46 is not compiled (MY_FYEAR stays 0)
#   and every statement conditioned on REG_FIXT(R) does nothing.
# - FIXBOH is refused: its levels come from a restart point (spoint.mod),
#   which is part 2 of the M1.5 plan.
# - initmty.mod L446-447 set VAR_UC to YES in a stepped run (`var_uc`), so the
#   abort of solve.stp L14 cannot be reached with TIMESTEP set.
#
# The levels and marginals GAMS statements read between two steps
# (`VAR_UCRT.L`, `VAR_CAP.L`, `VAR_CUMFLO.M`, ...) are kept in a point store
# (`StpPoint`): the stepped run starts with every level zero, the SOLVE of a
# step merges its solution into the store (OPTION SOLVEOPT=MERGE, L286;
# change 4), and the layer-1 check of a step loads GAMS's own point of the
# step before (`stp_load_point!`).

"""
    StpPoint

The levels and the marginals of the variables of a stepped run, by variable
name: for each name a `Dict` from the key tuple to the value, with the
convention of a parameter's values (an absent key is 0, a stored 0.0 is EPS).
Kept in `tm.cache["STP_POINT"]`.
"""
struct StpPoint
    level::Dict{String,Any}
    marginal::Dict{String,Any}
end
StpPoint() = StpPoint(Dict{String,Any}(), Dict{String,Any}())

"The point store of the stepped run (created empty: every level and marginal zero)."
stp_point(tm::TimesModel) = get!(() -> StpPoint(), tm.cache, "STP_POINT")::StpPoint

"`VAR_<name>.L` of the point store, as a `Dict` over `N`-tuples (see [`StpPoint`](@ref))."
stp_level(tm::TimesModel, name::AbstractString, N::Int) =
    get!(() -> Dict{NTuple{N,String},Float64}(), stp_point(tm).level, String(name))::Dict{NTuple{N,String},Float64}

"`VAR_<name>.M` of the point store, as a `Dict` over `N`-tuples (see [`StpPoint`](@ref))."
stp_marginal(tm::TimesModel, name::AbstractString, N::Int) =
    get!(() -> Dict{NTuple{N,String},Float64}(), stp_point(tm).marginal, String(name))::Dict{NTuple{N,String},Float64}

"""
The variables whose levels or marginals solve.stp reads: its data statements
(L97-98, L137, L160-171, L186-190, L288-301) the first two lines, the fixes
of the periods already solved (L200-220, L233; `stp_step_bounds!`) the rest.
"""
const STP_POINT_VARS = ("VAR_NCAP", "VAR_CAP", "VAR_UC", "VAR_UCR", "VAR_UCT", "VAR_UCTS", "VAR_UCRT", "VAR_UCRTS",
                        "VAR_CUMFLO", "VAR_CUMCOM",
                        "VAR_ACT", "VAR_FLO", "VAR_IRE", "VAR_SIN", "VAR_SOUT", "VAR_UPS", "VAR_UPT", "VAR_UDP",
                        "VAR_COMNET", "VAR_COMPRD", "VAR_SCAP", "VAR_BLND")

# One field of a variable's records as point-store values: a record is kept where the field is nonzero or EPS.
function _stp_field(r::Reference.SymbolRecords{N}, col::String) where {N}
    vals = Dict{NTuple{N,String},Float64}()
    haskey(r.values, col) || return vals
    v = r.values[col]
    sp = get(r.special, col, nothing)
    for (i, k) in enumerate(r.keys)
        if v[i] != 0
            vals[k] = v[i]
        elseif sp !== nothing && sp[i] == Reference.SV_EPS
            vals[k] = 0.0
        end
    end
    return vals
end

"""
    stp_load_point!(tm, ref::DumpData; names=STP_POINT_VARS) -> tm

Replace the levels and marginals of the variables `names` in the point store
by those of the dump `ref` (a variable the dump does not hold is left as it
is). With the dump GAMS writes after the SOLVE of step k (`steps/<k>/final`
of a stepped reference) the next step is prepared on GAMS's own point, so
that a difference in one step cannot hide in the next (docs/m15-plan.md).

GAMS: solve.stp L286 (OPTION SOLVEOPT=MERGE: the levels after the SOLVE of a
step are those of every step so far), v4.9.7.
"""
function stp_load_point!(tm::TimesModel, ref::DumpData; names=STP_POINT_VARS)
    pt = stp_point(tm)
    for name in names
        Reference.has_symbol(ref.dump, name) || continue
        r = Reference.read_symbol(ref.dump, name)
        r.info.kind === :variable || throw(ArgumentError("stp_load_point!: $name is not a variable of the dump"))
        pt.level[name] = _stp_field(r, "level")
        pt.marginal[name] = _stp_field(r, "marginal")
    end
    return tm
end

# `X(...,BD)$X(...,'FX') = X(...,'FX')$BDNEQ(BD)` (solve.stp L69-75): where an FX value is set, LO and UP
# take it and FX is removed. `ok(k)` is the domain of the controlling indices. The FX values are those
# from before the statement (docs/discrepancies.md G11); an EPS is copied as an EPS (G3).
function _stp_fx!(ok, vals::Dict{NTuple{N,String},Float64}, bd, bdneq) where {N}
    fx = [(k, x) for (k, x) in vals if k[N] == "FX" && ok(k)]
    for (k, x) in fx, b in bd
        kb = ntuple(i -> i == N ? b : k[i], N)
        b in bdneq ? (vals[kb] = x) : delete!(vals, kb)
    end
    return vals
end

"""
    stp_init!(tm) -> tm

The statements of solve.stp before its loop: the first partition of the
horizon and the data prepared once for all steps.

- L18: `SCALAR PRESOL / 1 /`.
- L43-44: `YR_V1 = 0; YR_VL = %TIMESTEP%; MY_FYEAR = 0;`
  `IF(G_OVERLAP, G_OVERLAP = MAX(EPS,G_OVERLAP); ELSE G_OVERLAP = FLOOR(YR_VL/2));`
  (a given overlap of EPS stays EPS, a zero overlap in the comparisons).
- L47-52: `F = SUM(MIYR_1(T),M(T)); REG_FIXT(R)\$(REG_FIXT(R) < F) = 0;`
  `YR_V1 = SMIN((R,T)\$(M(T) > REG_FIXT(R)),M(T)); Z = YR_V1 + YR_VL;`
  `SUBT(T)\$(M(T) < YR_V1) = NO; SUBT(T)\$(M(T) GE Z) = NO;`
- L53-57: `OPTION CLEAR=BACKWARD, CLEAR=FORWARD, RTC_NET<RHS_COMBAL, RTC_PRD<RHS_COMPRD;`
  `BACKWARD(T)\$(M(T) < YR_V1) = YES; FORWARD(T) = TT(T)-BACKWARD(T)-SUBT(T);`
  `RT_PP(R,T) = (M(T) > REG_FIXT(R)); NO_RT(R,T) = NOT RT_PP(R,T);`
- clearsol.stp L9-10 (included at L60 without an argument, so `IF(1%1,` is
  true): `RVT(R,VNT(V,T))\$RT_PP(R,T) = YES; FIL(LL)=T(LL);`
  `LOOP(R, FIL(T)\$NO_RT(R,T) = NO);` Its L11-28 set levels to zero: the point
  store starts empty, so they change nothing.
- L69-76: the FX values of CAP_BND, UC_RHS, UC_RHSR, UC_RHST, UC_RHSTS,
  UC_RHSRT, UC_RHSRTS and PRC_DYNUC are copied to LO and UP and removed,
  `X(...,BD)\$X(...,'FX') = X(...,'FX')\$BDNEQ(BD)`, so that a step can relax them.
- L78-92: UC_RN(UC_N,R) for a user constraint with a coefficient of UC_CAP,
  UC_NCAP, UC_ACT, UC_FLO, UC_IRE or UC_COM whose product with UC_SIGN(SIDE)
  is negative, and for `UC_MAP_IRE(UC_N,R,P,C,'IMP')\$COM_UNIT(R,C,'UCU')`;
  `UC_RN(UC_N,'IMPEXP') \$= SUM(UC_RN(UC_N,R),1);`
- L94: `LOOP((UC_N,SIDE,R,T,P)\$UC_CAP(UC_N,SIDE,R,T,P),R_UC(R,UC_N) = YES);`
- L96-98: `RTP_VARP(RTP(R,T,P))\$(CAP_BND(RTP,'UP')+CAP_BND(RTP,'LO')) = YES;`
  `OPTION CLEAR=RTP_CAPYR; RTP_CAPYR(RTP_CPTYR(R,V,T,P))\$(VAR_NCAP.L(R,V,P)+NCAP_PASTI(R,V,P)) = YES;`
  `VAR_CAP.L(RTP_VARP(RT_PP(R,T),P)) = SUM(RTP_CAPYR(R,V,T,P),COEF_CPT(R,V,T,P)*(VAR_NCAP.L(R,V,P)\$TT(V)+NCAP_PASTI(R,V,P)));`
- L101-107: `STP_UCT('1',UC_T_SUM) = YES; STP_UCT('2',UC_T_SUCC) = YES; STP_UCT('3',UC_T_EACH) = YES;`
  and, where ALTOBJ > 1, STP_DIV from OBJ_DIVI, OBJ_DIVIV and OBJ_DIVIII.

Refused (`UnportedError`): STAGES, SPINES or SENSIS (L10-13 and the
stochastic branches), FIXBOH (L28-39, L45; it needs a restart point), CLI
(L149, clearsol.stp L26), UC_CLI data (L91) and TM_HSX (L154: other
tolerances). REG_FIXT is emptied as setglobs.gms L11 does without FIXBOH.

Not translated, flagged: L61-66 (the start from a given solution: the
activity levels rebuilt from the flows and VAR_COMNET.L from EQG_COMBAL.L)
read levels that are all zero when the run starts from no point.

GAMS: solve.stp L9-26, L43-57, L69-107; clearsol.stp L8-10; setglobs.gms L11, v4.9.7.
"""
function stp_init!(tm::TimesModel)
    stepped(tm) || throw(ArgumentError("stp_init!: not a stepped run (TIMESTEP is not set)"))
    d = tm.data
    yes(name) = uppercase(gswitch(tm, name, "")) == "YES"
    # L10-13: $ABORT Stepped TIMES Not available with STAGES/SENSIS!; with SPINES the stochastic branches
    (yes("STAGES") || yes("SPINES") || yes("SENSIS")) &&
        throw(UnportedError("solve.stp L10-13: a stepped run with STAGES, SPINES or SENSIS"))
    haskey(tm.switches, "FIXBOH") &&
        throw(UnportedError("solve.stp L28-39, L45: FIXBOH (a run fixed to an earlier solution needs a restart point)"))
    yes("CLI") && throw(UnportedError("solve.stp L149, clearsol.stp L26: a stepped run with the climate extension"))
    isempty(gparam_opt(d, "UC_CLI", 5)) || throw(UnportedError("solve.stp L91: UC_CLI in a stepped run"))
    Reference.has_symbol(d.dump, "TM_HSX") && throw(UnportedError("solve.stp L154: the tolerances under TM_HSX"))
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    nz(x::GNum) = x.v != 0 || x.eps
    T = [k[1] for k in S("MILESTONYR", 1).keys]
    R = [k[1] for k in S("REG", 1).keys]
    Tset, Rset = Set(T), Set(R)
    M = P("M", 1)
    m(t) = gv(M, (t,)).v
    tm.cache["STP_POINT"] = StpPoint()                                          # the run starts from no point
    gput_scalar!(tm, "PRESOL", 1.0)                                             # L18
    gput!(tm, "REG_FIXT", Dict{NTuple{1,String},Float64}())                     # setglobs.gms L11
    stp_bounds_init!(tm)                                                        # maindrv.mod L92: bndmain.mod with 0
    reg_fixt = Dict{NTuple{1,String},Float64}()
    fixt(r) = gv(reg_fixt, (r,)).v
    # L43
    ts = tryparse(Float64, strip(gswitch(tm, "TIMESTEP", "")))
    ts === nothing && throw(ArgumentError("TIMESTEP = $(gswitch(tm, "TIMESTEP", "")): not a number (initmty.mod L443)"))
    yr_vl = ts
    gput_scalar!(tm, "YR_VL", yr_vl)
    gput_scalar!(tm, "MY_FYEAR", 0.0)
    # L44
    g = gv(P("G_OVERLAP", 0), ())
    gput_scalar!(tm, "G_OVERLAP", nz(g) ? gmax(GEPS, g) : GNum(floor(yr_vl / 2)))
    # L47-52
    f = sum((m(t) for (t,) in S("MIYR_1", 1).keys if t in Tset); init=0.0)
    gput_scalar!(tm, "F", f)
    yr_v1 = minimum((m(t) for r in R for t in T if m(t) > fixt(r)); init=Inf)
    z = yr_v1 + yr_vl
    gput_scalar!(tm, "YR_V1", yr_v1)
    gput_scalar!(tm, "Z", z)
    subt = filter(k -> !(m(k[1]) < yr_v1) && !(m(k[1]) >= z), gmembers(tm, "SUBT", 1))
    gput!(tm, "SUBT", subt)
    # L53: RTC_NET<RHS_COMBAL, RTC_PRD<RHS_COMPRD
    gput!(tm, "RTC_NET", Set((k[1], k[2], k[3]) for k in S("RHS_COMBAL", 4).keys))
    gput!(tm, "RTC_PRD", Set((k[1], k[2], k[3]) for k in S("RHS_COMPRD", 4).keys))
    # L54-57
    backward = Set((t,) for t in T if m(t) < yr_v1)
    gput!(tm, "BACKWARD", backward)
    gput!(tm, "FORWARD", Set((t,) for t in T if !((t,) in backward) && !((t,) in subt)))
    rt_pp = Set((r, t) for r in R for t in T if m(t) > fixt(r))
    gput!(tm, "RT_PP", rt_pp)
    no_rt = Dict{NTuple{2,String},Float64}((r, t) => 1.0 for r in R for t in T if !((r, t) in rt_pp))
    gput!(tm, "NO_RT", no_rt)
    # clearsol.stp L9-10
    V = S("MODLYEAR", 1)                                                        # ALIAS(MODLYEAR,V), setglobs.gms L147
    rvt = gmembers(tm, "RVT", 3)
    for (v, t) in S("VNT", 2).keys, r in R
        ((v,) in V && (r, t) in rt_pp) && push!(rvt, (r, v, t))
    end
    gput!(tm, "RVT", rvt)
    gput!(tm, "FIL", Set((t,) for t in T if !any(r -> haskey(no_rt, (r, t)), R)))
    # L69-75
    bd = [k[1] for k in S("BND_TYPE", 1).keys]                                  # ALIAS(BND_TYPE,BD)
    bdneq = Set(k[1] for k in S("BDNEQ", 1).keys)
    cap_bnd = _stp_fx!(k -> k[1] in Rset && k[2] in Tset, gvalues(tm, "CAP_BND", 4), bd, bdneq)
    gput!(tm, "CAP_BND", cap_bnd)
    gput!(tm, "UC_RHS", _stp_fx!(k -> true, gvalues(tm, "UC_RHS", 2), bd, bdneq))
    gput!(tm, "UC_RHSR", _stp_fx!(k -> k[1] in Rset, gvalues(tm, "UC_RHSR", 3), bd, bdneq))
    gput!(tm, "UC_RHST", _stp_fx!(k -> k[2] in Tset, gvalues(tm, "UC_RHST", 3), bd, bdneq))
    gput!(tm, "UC_RHSTS", _stp_fx!(k -> k[2] in Tset, gvalues(tm, "UC_RHSTS", 4), bd, bdneq))
    gput!(tm, "UC_RHSRT", _stp_fx!(k -> k[1] in Rset && k[3] in Tset, gvalues(tm, "UC_RHSRT", 4), bd, bdneq))
    gput!(tm, "UC_RHSRTS", _stp_fx!(k -> k[1] in Rset && k[3] in Tset, gvalues(tm, "UC_RHSRTS", 5), bd, bdneq))
    # L76: PRC_DYNUC(UC_N,SIDE,R,LL,P,UC_GRPTYPE,BD)$PRC_DYNUC(UC_N,'RHS',R,LL,P,UC_GRPTYPE,'FX') =
    #      PRC_DYNUC(UC_N,SIDE,R,LL,P,UC_GRPTYPE,'FX')$BDNEQ(BD)   (values from before the statement, G11)
    dyn = gvalues(tm, "PRC_DYNUC", 7)
    if !isempty(dyn)
        old = copy(dyn)
        sides = [k[1] for k in S("SIDE", 1).keys]
        for k in keys(old)
            (k[2] == "RHS" && k[7] == "FX" && k[3] in Rset) || continue
            for side in sides
                x = gv(old, (k[1], side, k[3], k[4], k[5], k[6], "FX"))
                for b in bd
                    gassign!(dyn, (k[1], side, k[3], k[4], k[5], k[6], b), b in bdneq ? x : GZERO)
                end
            end
        end
        gput!(tm, "PRC_DYNUC", dyn)
    end
    # L78-89: user constraints with a negative coefficient
    uc_rn = gmembers(tm, "UC_RN", 2)
    uc_sign = P("UC_SIGN", 1)
    sgn(side) = gv(uc_sign, (side,)).v
    for (name, n, iside) in (("UC_CAP", 5, 2), ("UC_NCAP", 5, 2), ("UC_ACT", 6, 2), ("UC_FLO", 7, 2), ("UC_IRE", 8, 2),
                             ("UC_COM", 8, 3))
        for (k, x) in P(name, n).values
            (k[iside+1] in Rset && k[iside+2] in Tset && x * sgn(k[iside]) < 0) && push!(uc_rn, (k[1], k[iside+1]))
        end
    end
    # L90: LOOP(UC_MAP_IRE(UC_N,R,P,C,'IMP')$COM_UNIT(R,C,'UCU'),UC_RN(UC_N,R)=YES)
    com_unit = S("COM_UNIT", 3)
    for (n, r, _, c, ie) in S("UC_MAP_IRE", 5).keys
        (ie == "IMP" && r in Rset && (r, c, "UCU") in com_unit) && push!(uc_rn, (n, r))
    end
    # L92: UC_RN(UC_N,'IMPEXP') $= SUM(UC_RN(UC_N,R),1)
    for (n, r) in collect(uc_rn)
        r in Rset && push!(uc_rn, (n, "IMPEXP"))
    end
    gput!(tm, "UC_RN", uc_rn)
    # L94
    r_uc = gmembers(tm, "R_UC", 2)
    for k in keys(P("UC_CAP", 5).values)
        (k[3] in Rset && k[4] in Tset) && push!(r_uc, (k[3], k[1]))
    end
    gput!(tm, "R_UC", r_uc)
    # L96
    rtp = S("RTP", 3)
    rtp_varp = gmembers(tm, "RTP_VARP", 3)
    for k in keys(cap_bnd)
        (k[4] == "UP" || k[4] == "LO") || continue
        key = (k[1], k[2], k[3])
        (k[2] in Tset && key in rtp && nz(gv(cap_bnd, (key..., "UP")) + gv(cap_bnd, (key..., "LO")))) && push!(rtp_varp, key)
    end
    gput!(tm, "RTP_VARP", rtp_varp)
    # L97
    ncap_l, pasti = stp_level(tm, "VAR_NCAP", 3), P("NCAP_PASTI", 3)
    rtp_capyr = Set{NTuple{4,String}}()
    for k in S("RTP_CPTYR", 4).keys
        (r, v, t, p) = k
        ((v,) in V && t in Tset && nz(gv(ncap_l, (r, v, p)) + gv(pasti, (r, v, p)))) && push!(rtp_capyr, k)
    end
    gput!(tm, "RTP_CAPYR", rtp_capyr)
    # L98
    coef_cpt = P("COEF_CPT", 4)
    capyr_of = Dict{NTuple{3,String},Vector{String}}()
    for (r, v, t, p) in rtp_capyr
        push!(get!(() -> String[], capyr_of, (r, t, p)), v)
    end
    cap_l = stp_level(tm, "VAR_CAP", 3)
    for key in rtp_varp
        (r, t, p) = key
        (r, t) in rt_pp || continue
        s = GZERO
        for v in get(capyr_of, key, String[])
            s = s + gv(coef_cpt, (r, v, t, p)) * (gif(gv(ncap_l, (r, v, p)), v in Tset) + gv(pasti, (r, v, p)))
        end
        gassign!(cap_l, key, s)
    end
    # L101-103
    stp_uct = gvalues(tm, "STP_UCT", 4)
    for (j, name) in (("1", "UC_T_SUM"), ("2", "UC_T_SUCC"), ("3", "UC_T_EACH")), k in S(name, 3).keys
        stp_uct[(j, k[1], k[2], k[3])] = 1.0
    end
    gput!(tm, "STP_UCT", stp_uct)
    # L104-107
    if gscalar(tm, "ALTOBJ") > 1
        stp_div = gvalues(tm, "STP_DIV", 4)
        for (j, name) in (("1", "OBJ_DIVI"), ("2", "OBJ_DIVIV"), ("3", "OBJ_DIVIII")), (k, x) in P(name, 3).values
            (k[1] in Rset && k[2] in Tset) && (stp_div[(j, k[1], k[2], k[3])] = x)
        end
        gput!(tm, "STP_DIV", stp_div)
    end
    return tm
end

"""
    stp_step_prep!(tm) -> tm

The data one step of a stepped run prepares before its model is generated:
the statements of the loop of solve.stp up to the SOLVE, less the variable
bounds (change 3 of docs/m15-plan.md).

- L111-115: `BACKWARD(T) = (M(T) < YR_V1); FORWARD(SUBT) = NO; NO_RT(R,T(BACKWARD)) = 1;`
  `RT_PP(R,T) = SUBT(T)\$(NOT NO_RT(R,T)); V(FORWARD) = NO;` (V is MODLYEAR.)
- L117-120: `MIYR_VL = SMAX(SUBT(T),E(T));` Y_EOH and MIYR_L for that end of
  the horizon: `Y_EOH(EOHYEARS)\$((YEARVAL(EOHYEARS) <= MIYR_VL)\$(YEARVAL(EOHYEARS) >= MINYR)) = YES;`
  `LOOP(MIYR_1(YEAR), Z=MIYR_VL-YEARVAL(YEAR); MIYR_L(YEAR+Z) = YES);`
- L124: `coef_alt.lin STP` under a non-empty %CTST% ([`coef_alt!`](@ref) with `stp`).
- L126: `OBJ_LIFE(K(LL),R,JOT,LIFE,CUR)\$OBJ_LIFE(K,R,JOT,LIFE,CUR) =`
  `SUM((OPYEAR(LIFE,AGE),Y_EOH(LL+(ORD(AGE)-1))),OBJ_DISC(R,Y_EOH,CUR))+EPS;`
- L127: `eqobsalv.mod STP EXIT` ([`eqobsalv_step!`](@ref)).
- L128: `RVPRL(R,K,P)\$RVPRL(R,K,P)=MAX(1,SMAX(RTP_CPTYR(R,VNT(K,V(T)),P),YEARVAL(V))-YEARVAL(K));`
- L132-136: RXX and UNCD1 flag the user constraints summed over periods
  that overlap the step; UC_T_SUM loses the pending periods and the
  constraints that do not overlap. L137: under PRESOL the levels of VAR_UC
  and VAR_UCR of those constraints are set to zero.
- L140-151: UC_T, and UC_T_EACH and UC_T_SUCC reduced to the periods of the
  step: `UC_T_SUCC(UC_T_SUCC(R,UC_N,T-1)) = UC_DYNDIR(R,UC_N,'RHS')+RT_PP(R,T);`
  keeps the member of a period whose next period is in the step (or a
  constraint that is dynamic on the RHS); the member of the last period has
  no next period and stays. `LOOP(BD,UC_T_SUCC(R,UC_N,T)\$UC_DYNBND(UC_N,BD) = RT_PP(R,T));`
- L155-191, once a period is fixed (`IF(CARD(BACKWARD) OR MY_FYEAR,`):
  R_UCT; UC_BND holds each right-hand side corrected by the level of its
  slack variable where the solution of the steps before violates it,
  `MAX(rhs, level-INF\$(NOT level))` for UP and `MIN(rhs, level+INF\$(NOT level))`
  for LO (an EPS level is a level: G25), then relaxed by the relative
  tolerance 3E-6 and, for a constraint in UC_RN, the absolute tolerance 1E-4
  (L173-174); UC_BND is copied back to the right-hand sides of the
  constraints of fixed regions (L176-181); PRC_DYNUC's LHS coefficient of
  the period after a fixed one is relaxed (L183-185, tolerances 3E-6 and
  1E-5); CAP_BND is relaxed to the level of the capacity (L190-191).
- L193: bnd_ucw.mod ([`bnd_ucw_data!`](@ref)). L195: `OPTION UC_RTSUC < UC_T_SUCC;`
  L196: REG_CUMCST loses its UP bounds over fixed periods.
- L217: `OPTION CLEAR=NO_RVP; NO_RVP(RTP_VARP(R,SUBT(T),P))\$SUM(RTP_CPTYR(R,BACKWARD(TT),T,P),1) = YES;`
- L222-225: `Z = SMAX(T,M(T)); Z = (Z > MIYR_VL); FIL(LL) = Z*(MIYR_VL < YEARVAL(LL));`
- L227: bnd_cum.mod ([`bnd_cum_data!`](@ref)).
- L288-289: `IF(PRESOL=0, PAR_CUMFLOM(R,P,C,YEAR,LL) \$= VAR_CUMFLO.M(R,P,C,YEAR,LL);`
  `PAR_UCR(UC_N,'IMPEXP') \$= VAR_UC.M(UC_N); PAR_UCR(UC_N,R) \$= VAR_UCR.M(UC_N,R));`

Unreached without REG_FIXT (which needs FIXBOH, refused in [`stp_init!`](@ref)):
the copy back of UC_RHSR, UC_RHSRT and UC_RHSRTS takes nothing, since L158
empties R_UCT; L186-189 (COM_CUM and FLO_CUM of a fixed region) and L223
(RPC_CUMFLO and RC_CUMCOM of a region fixed to the end) do nothing and are
not translated. L149 (CLI) is refused in `stp_init!`.

GAMS: solve.stp L111-196, L217, L222-227, L288-289, v4.9.7.
"""
function stp_step_prep!(tm::TimesModel)
    stepped(tm) || throw(ArgumentError("stp_step_prep!: not a stepped run (TIMESTEP is not set)"))
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    yax = YearAxis(tm)
    yv(y) = yax.yearval[y]
    T = [k[1] for k in S("MILESTONYR", 1).keys]
    R = [k[1] for k in S("REG", 1).keys]
    Tset, Rset = Set(T), Set(R)
    M, E = P("M", 1), P("E", 1)
    m(t) = gv(M, (t,)).v
    subt = gmembers(tm, "SUBT", 1)
    isempty(subt) && throw(ArgumentError("stp_step_prep!: no step is left (SUBT is empty; solve.stp L109)"))
    yr_v1 = gscalar(tm, "YR_V1")
    presol = gscalar(tm, "PRESOL") != 0
    reg_fixt = P("REG_FIXT", 1)
    # L111-115
    backward = Set((t,) for t in T if m(t) < yr_v1)
    forward = filter(k -> !(k in subt), gmembers(tm, "FORWARD", 1))
    no_rt = gvalues(tm, "NO_RT", 2)
    for r in R, (t,) in backward
        no_rt[(r, t)] = 1.0
    end
    rt_pp = Set((r, t) for r in R for (t,) in subt if !haskey(no_rt, (r, t)))
    V = filter(k -> !(k in forward), gmembers(tm, "MODLYEAR", 1))
    gput!(tm, "BACKWARD", backward); gput!(tm, "FORWARD", forward); gput!(tm, "NO_RT", no_rt)
    gput!(tm, "RT_PP", rt_pp); gput!(tm, "MODLYEAR", V)
    # L117-120
    miyr_vl = maximum(gv(E, k).v for k in subt)
    gput_scalar!(tm, "MIYR_VL", miyr_vl)
    minyr = gscalar(tm, "MINYR")
    y_eoh = Set((y,) for (y,) in S("EOHYEARS", 1).keys if yv(y) <= miyr_vl && yv(y) >= minyr)
    gput!(tm, "Y_EOH", y_eoh)
    miyr_l = Set{NTuple{1,String}}()
    for (y,) in S("MIYR_1", 1).keys
        z = miyr_vl - yv(y)
        gput_scalar!(tm, "Z", z)
        yy = lead(yax, y, glead(z))
        yy === nothing || push!(miyr_l, (yy,))
    end
    gput!(tm, "MIYR_L", miyr_l)
    # L124: $IF NOT '%CTST%'=='' $BATINCLUDE coef_alt.lin STP
    ctst(tm) == "" || coef_alt!(tm; stp=true)
    # L126
    K = S("EACHYEAR", 1)
    ageax = OrdAxis(tm, "AGE")
    opy_of = indexby(S("OPYEAR", 2), (1,))                                      # LIFE -> OPYEAR(LIFE,AGE)
    obj_disc = P("OBJ_DISC", 3)
    obj_life = gvalues(tm, "OBJ_LIFE", 5)
    for k in collect(keys(obj_life))
        (ll, r, _, life, cur) = k
        ((ll,) in K && r in Rset) || continue
        s = GZERO
        for (_, a) in get(opy_of, (life,), NTuple{2,String}[])
            y = lead(yax, ll, ageax.pos[a] - 1)
            (y !== nothing && (y,) in y_eoh) && (s = s + gv(obj_disc, (r, y, cur)))
        end
        gassign!(obj_life, k, s + GEPS)
    end
    gput!(tm, "OBJ_LIFE", obj_life)
    # L127: $IF %STEPPED%==YES $BATINCLUDE eqobsalv.%1 STP EXIT
    eqobsalv_step!(tm)
    # L128
    rvprl = gvalues(tm, "RVPRL", 3)
    if !isempty(rvprl)
        vnt, cptyr = S("VNT", 2), S("RTP_CPTYR", 4)
        for k in collect(keys(rvprl))
            (r, kk, p) = k
            ((kk,) in K && r in Rset) || continue
            top = maximum((yv(t) for t in T if (t,) in V && (kk, t) in vnt && (r, kk, t, p) in cptyr); init=-Inf)
            gassign!(rvprl, k, max(1.0, top - yv(kk)))
        end
        gput!(tm, "RVPRL", rvprl)
    end
    # L132-136
    uc_r_each, uc_r_sum = S("UC_R_EACH", 2), S("UC_R_SUM", 2)
    uc_t_sum = gmembers(tm, "UC_T_SUM", 3)
    rxx, uncd1 = Set{NTuple{3,String}}(), Set{NTuple{1,String}}()
    for (r, n, t) in uc_t_sum
        (r, t) in rt_pp || continue
        (r, n) in uc_r_each && push!(rxx, (r, n, r))
        (r, n) in uc_r_sum && push!(uncd1, (n,))
    end
    filter!(k -> !(k[1] in Rset && (k[3],) in forward), uc_t_sum)
    filter!(k -> !(k[1] in Rset && k[3] in Tset && !((k[2],) in uncd1) && !((k[1], k[2], k[1]) in rxx)), uc_t_sum)
    gput!(tm, "RXX", rxx); gput!(tm, "UNCD1", uncd1); gput!(tm, "UC_T_SUM", uc_t_sum)
    # L137: IF(PRESOL, VAR_UC.L(UC_N(UNCD1)) = 0; VAR_UCR.L(UC_N,R)$RXX(R,UC_N,R) = 0)
    if presol
        uc_l, ucr_l = stp_level(tm, "VAR_UC", 1), stp_level(tm, "VAR_UCR", 2)
        foreach(k -> delete!(uc_l, k), uncd1)
        foreach(k -> delete!(ucr_l, (k[2], k[1])), rxx)
    end
    # L140-148
    uc_t = Set{NTuple{2,String}}()
    uc_t_each, uc_t_succ = gmembers(tm, "UC_T_EACH", 3), gmembers(tm, "UC_T_SUCC", 3)
    uc_dyndir = S("UC_DYNDIR", 3)
    dynrhs(r, n) = (r, n, "RHS") in uc_dyndir
    for (r, n, t) in uc_t_each
        ((r, n) in uc_r_sum && (r, t) in rt_pp) && push!(uc_t, (n, t))
    end
    for (r, n, t) in uc_t_succ
        ((r, n) in uc_r_sum && (r, t) in rt_pp) && push!(uc_t, (n, t))
    end
    inrt(k) = k[1] in Rset && k[3] in Tset
    filter!(k -> !(inrt(k) && (k[1], k[2]) in uc_r_sum && !((k[2], k[3]) in uc_t)), uc_t_each)                          # L143
    filter!(k -> !(inrt(k) && (k[1], k[2]) in uc_r_sum && dynrhs(k[1], k[2]) && !((k[2], k[3]) in uc_t)), uc_t_succ)    # L144
    filter!(k -> !(inrt(k) && (k[1], k[2]) in uc_r_each && !((k[1], k[3]) in rt_pp)), uc_t_each)                        # L145
    filter!(k -> !(inrt(k) && (k[1], k[2]) in uc_r_each && dynrhs(k[1], k[2]) && !((k[1], k[3]) in rt_pp)), uc_t_succ)  # L146
    tnext = Dict(T[i] => T[i+1] for i in 1:length(T)-1)
    for k in collect(uc_t_succ)                                                 # L147 (the member is at T-1)
        (r, n, tp) = k
        (r in Rset && haskey(tnext, tp)) || continue
        (dynrhs(r, n) || (r, tnext[tp]) in rt_pp) || delete!(uc_t_succ, k)
    end
    filter!(k -> !(k[2] in Tset && !any(r -> haskey(no_rt, (r, k[2])), R)), uc_t)                                       # L148
    # L151: LOOP(BD,UC_T_SUCC(R,UC_N,T)$UC_DYNBND(UC_N,BD) = RT_PP(R,T))
    bdset = Set(k[1] for k in S("BND_TYPE", 1).keys)
    for n in unique(k[1] for k in S("UC_DYNBND", 2).keys if k[2] in bdset), r in R, t in T
        (r, t) in rt_pp ? push!(uc_t_succ, (r, n, t)) : delete!(uc_t_succ, (r, n, t))
    end
    # L153: the tolerances (TM_HSX is refused in stp_init!)
    tolr, tola, tolx = 3e-6, 1e-4, 1e-5
    # L155-191
    if !isempty(backward) || gscalar(tm, "MY_FYEAR") != 0
        uc_bnd = Dict{NTuple{6,String},Float64}()
        r_uc = S("R_UC", 2)
        r_uct = Set{NTuple{3,String}}()
        for k in Iterators.flatten((uc_t_each, uc_t_succ))                      # L156
            (inrt(k) && (k[1], k[2]) in r_uc) && push!(r_uct, k)
        end
        for (r, n, t) in r_uct                                                  # L157
            (r, n) in uc_r_sum && push!(uc_t, (n, t))
        end
        filter!(k -> haskey(reg_fixt, (k[1],)), r_uct)                          # L158
        # L160-171
        rhs = (gvalues(tm, "UC_RHS", 2), gvalues(tm, "UC_RHSR", 3), gvalues(tm, "UC_RHST", 3), gvalues(tm, "UC_RHSTS", 4),
               gvalues(tm, "UC_RHSRT", 4), gvalues(tm, "UC_RHSRTS", 5))
        lev = (stp_level(tm, "VAR_UC", 1), stp_level(tm, "VAR_UCR", 2), stp_level(tm, "VAR_UCT", 2),
               stp_level(tm, "VAR_UCTS", 3), stp_level(tm, "VAR_UCRT", 3), stp_level(tm, "VAR_UCRTS", 4))
        function ucb!(key::NTuple{6,String}, x::GNum, level::GNum)
            up = key[6] == "UP"
            l = iszero(level) ? GNum(up ? -Inf : Inf) : level                    # level -/+ INF$(NOT level), G25
            gassign!(uc_bnd, key, up ? gmax(x, l) : gmin(x, l))
        end
        for b in ("UP", "LO")
            for (k, _) in rhs[1]                                                # UC_RHS(UC_N,BD)
                k[2] == b && ucb!(("1", "IMPEXP", k[1], "0", "ANNUAL", b), gv(rhs[1], k), gv(lev[1], (k[1],)))
            end
            for (k, _) in rhs[2]                                                # UC_RHSR(R,UC_N,BD)
                (k[3] == b && k[1] in Rset) &&
                    ucb!(("2", k[1], k[2], "0", "ANNUAL", b), gv(rhs[2], k), gv(lev[2], (k[2], k[1])))
            end
            for (k, _) in rhs[3]                                                # UC_RHST(UC_N,T,BD)
                (k[3] == b && k[2] in Tset) &&
                    ucb!(("3", "IMPEXP", k[1], k[2], "ANNUAL", b), gv(rhs[3], k), gv(lev[3], (k[1], k[2])))
            end
            for (k, _) in rhs[4]                                                # UC_RHSTS(UC_N,T,S,BD)
                (k[4] == b && k[2] in Tset) &&
                    ucb!(("4", "IMPEXP", k[1], k[2], k[3], b), gv(rhs[4], k), gv(lev[4], (k[1], k[2], k[3])))
            end
            for (k, _) in rhs[5]                                                # UC_RHSRT(R,UC_N,T,BD)
                (k[4] == b && k[1] in Rset && k[3] in Tset) &&
                    ucb!(("5", k[1], k[2], k[3], "ANNUAL", b), gv(rhs[5], k), gv(lev[5], (k[2], k[1], k[3])))
            end
            for (k, _) in rhs[6]                                                # UC_RHSRTS(R,UC_N,T,S,BD)
                (k[5] == b && k[1] in Rset && k[3] in Tset) &&
                    ucb!(("6", k[1], k[2], k[3], k[4], b), gv(rhs[6], k), gv(lev[6], (k[2], k[1], k[3], k[4])))
            end
        end
        # L173-174: the relative tolerance, and the absolute one where the constraint has negative coefficients
        uc_rn = S("UC_RN", 2)
        for k in collect(keys(uc_bnd))
            x = gv(uc_bnd, k)
            ax = GNum(abs(x.v), x.eps)
            if k[6] == "UP"
                gassign!(uc_bnd, k, x + ax * GNum(tolr) + gif(tola, (k[3], k[2]) in uc_rn))
            elseif k[6] == "LO"
                gassign!(uc_bnd, k, x - ax * GNum(tolr) - gif(tola, (k[3], k[2]) in uc_rn))
            end
        end
        # L176-181: copied back to the right-hand sides ($=: where UC_BND is nonzero or EPS)
        bdneq = Set(k[1] for k in S("BDNEQ", 1).keys)
        for (k, x) in uc_bnd
            (j, ar, n, ll, s, b) = k
            b in bdneq || continue
            if j == "1"
                rhs[1][(n, b)] = x
            elseif j == "2"
                haskey(reg_fixt, (ar,)) && (rhs[2][(ar, n, b)] = x)
            elseif j == "3"
                (n, ll) in uc_t && (rhs[3][(n, ll, b)] = x)
            elseif j == "4"
                (n, ll) in uc_t && (rhs[4][(n, ll, s, b)] = x)
            elseif j == "5"
                (ar, n, ll) in r_uct && (rhs[5][(ar, n, ll, b)] = x)
            elseif j == "6"
                (ar, n, ll) in r_uct && (rhs[6][(ar, n, ll, s, b)] = x)
            end
        end
        for (name, vals) in zip(("UC_RHS", "UC_RHSR", "UC_RHST", "UC_RHSTS", "UC_RHSRT", "UC_RHSRTS"), rhs)
            gput!(tm, name, vals)
        end
        gput!(tm, "UC_BND", uc_bnd); gput!(tm, "R_UCT", r_uct)
        # L183-185: LOOP((R,T,SAMEAS(T+1,TT))$NO_RT(R,T), PRC_DYNUC(UC_N,'LHS',RTP(R,TT,P),UC_GRPTYPE,bd)
        #           $PRC_DYNUC(UC_N,'RHS',R,'0',P,UC_GRPTYPE,bd) = PRC_DYNUC(UC_N,'LHS',R,TT,P,UC_GRPTYPE,bd)*(1 +/- tol))
        dyn = gvalues(tm, "PRC_DYNUC", 7)
        if !isempty(dyn)
            rtp = S("RTP", 3)
            rhs0 = [k for k in keys(dyn) if k[2] == "RHS" && k[4] == "0" && (k[7] == "UP" || k[7] == "LO")]
            for r in R, t in T
                (haskey(no_rt, (r, t)) && haskey(tnext, t)) || continue
                tt = tnext[t]
                for k in rhs0
                    (k[3] == r && (r, tt, k[5]) in rtp) || continue
                    kl = (k[1], "LHS", r, tt, k[5], k[6], k[7])
                    gassign!(dyn, kl, gv(dyn, kl) * GNum(k[7] == "UP" ? 1 + tolr : 1 - tolx))
                end
            end
            gput!(tm, "PRC_DYNUC", dyn)
        end
        # L190-191
        cap_bnd = gvalues(tm, "CAP_BND", 4)
        if !isempty(cap_bnd)
            cap_l = stp_level(tm, "VAR_CAP", 3)
            for k in collect(keys(cap_bnd))
                (k[1] in Rset && k[2] in Tset) || continue
                x = gv(cap_bnd, k)
                if k[4] == "UP"
                    gassign!(cap_bnd, k, gmax(x, gv(cap_l, (k[1], k[2], k[3])) * GNum(1 + tolr)))
                elseif k[4] == "LO"
                    gassign!(cap_bnd, k, x * GNum(1 - tolr))
                end
            end
            gput!(tm, "CAP_BND", cap_bnd)
        end
    end
    gput!(tm, "UC_T", uc_t); gput!(tm, "UC_T_EACH", uc_t_each); gput!(tm, "UC_T_SUCC", uc_t_succ)
    # L193: $BATINCLUDE bnd_ucw.%1
    bnd_ucw_data!(tm)
    # L195: OPTION UC_RTSUC < UC_T_SUCC
    gput!(tm, "UC_RTSUC", Set((k[1], k[3], k[2]) for k in S("UC_T_SUCC", 3).keys))
    # L196: IF(CARD(REG_CUMCST),LOOP((R,T)$NO_RT(R,T),REG_CUMCST(R,YEAR,LL,COSTCAT,CUR,'UP')$SUPERYR(T,LL) = 0))
    reg_cumcst = gvalues(tm, "REG_CUMCST", 6)
    if !isempty(reg_cumcst)
        superyr = S("SUPERYR", 2)
        for k in collect(keys(reg_cumcst))
            (k[6] == "UP" && k[1] in Rset) || continue
            any(t -> haskey(no_rt, (k[1], t)) && (t, k[3]) in superyr, T) && delete!(reg_cumcst, k)
        end
        gput!(tm, "REG_CUMCST", reg_cumcst)
    end
    # L217
    cpt_of = indexby(S("RTP_CPTYR", 4), (1, 3, 4))
    no_rvp = Set{NTuple{3,String}}()
    for k in S("RTP_VARP", 3).keys
        (r, t, p) = k
        (r in Rset && (t,) in subt) || continue
        any(c -> (c[2],) in backward, get(cpt_of, k, NTuple{4,String}[])) && push!(no_rvp, k)
    end
    gput!(tm, "NO_RVP", no_rvp)
    # L222-225 (L223 acts on a region fixed to the end of the horizon: none without REG_FIXT)
    z = maximum((m(t) for t in T); init=-Inf) > miyr_vl
    gput_scalar!(tm, "Z", z ? 1.0 : 0.0)
    gput!(tm, "FIL", Set((y,) for y in yax.years if z && miyr_vl < yv(y)))
    # L227: $IFI NOT %SENSIS%==YES $BATINCLUDE bnd_cum.mod COM_VAR
    bnd_cum_data!(tm)
    # L288-289
    if !presol
        par = gvalues(tm, "PAR_CUMFLOM", 5)
        for (k, x) in stp_marginal(tm, "VAR_CUMFLO", 5)
            k[1] in Rset && (par[k] = x)
        end
        gput!(tm, "PAR_CUMFLOM", par)
        par_ucr = gvalues(tm, "PAR_UCR", 2)
        for (k, x) in stp_marginal(tm, "VAR_UC", 1)
            par_ucr[(k[1], "IMPEXP")] = x
        end
        for (k, x) in stp_marginal(tm, "VAR_UCR", 2)
            k[2] in Rset && (par_ucr[k] = x)
        end
        gput!(tm, "PAR_UCR", par_ucr)
    end
    stp_step_bounds!(tm)                                                        # L193, L199-233, L267-281: the bounds
    return tm
end

"""
    stp_next!(tm) -> tm

The statements of the loop of solve.stp after the SOLVE of a step: the
partition moves to the next step and the data the step reduced is restored.

- L295: `PRESOL = 0;`
- L299-301: a marginal of VAR_UC, VAR_UCR or VAR_CUMFLO that is zero after
  the SOLVE takes the value saved before it,
  `VAR_CUMFLO.M(R,P,C,YEAR,LL)\$(VAR_CUMFLO.M(R,P,C,YEAR,LL)=0) \$= PAR_CUMFLOM(R,P,C,YEAR,LL);`
  (an EPS marginal equals 0 in the comparison: G12).
- L303-308: `SUBT(T) = SUBT(T-1); Z = SMIN(FORWARD(T),B(T));`
  `YR_V1 = SMIN(SUBT(T)\$(M(T) GE Z-G_OVERLAP),M(T)); Z = YR_V1 + YR_VL;`
  `SUBT(T)\$(M(T) < Z) = YES; SUBT(T)\$(M(T) < YR_V1) = NO;` The shift reads
  SUBT from before the statement (G11). After the last step FORWARD is
  empty, so Z and YR_V1 are +INF (G31) and SUBT ends empty, which ends the
  loop (L109).
- L311-314: `V(T) = YES; UC_T_SUM(R,UC_N,T) \$= STP_UCT('1',R,UC_N,T);` and
  the same for UC_T_SUCC ('2') and UC_T_EACH ('3').
- L319: `bndmain.mod mod 1` ([`bnd_data!`](@ref) with `cum = false`).

L315-317 (%RTPX% and SPINES) are not compiled without FIXBOH and SPINES.

GAMS: solve.stp L295-319, v4.9.7.
"""
function stp_next!(tm::TimesModel)
    stepped(tm) || throw(ArgumentError("stp_next!: not a stepped run (TIMESTEP is not set)"))
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    T = [k[1] for k in S("MILESTONYR", 1).keys]
    Tset = Set(T)
    Rset = Set(k[1] for k in S("REG", 1).keys)
    M, B = P("M", 1), P("B", 1)
    m(t) = gv(M, (t,)).v
    gput_scalar!(tm, "PRESOL", 0.0)                                             # L295
    # L299-301
    uc_m, ucr_m = stp_marginal(tm, "VAR_UC", 1), stp_marginal(tm, "VAR_UCR", 2)
    for (k, x) in P("PAR_UCR", 2).values
        if k[2] == "IMPEXP"
            get(uc_m, (k[1],), 0.0) == 0 && (uc_m[(k[1],)] = x)
        elseif k[2] in Rset
            get(ucr_m, k, 0.0) == 0 && (ucr_m[k] = x)
        end
    end
    cum_m = stp_marginal(tm, "VAR_CUMFLO", 5)
    for (k, x) in P("PAR_CUMFLOM", 5).values
        (k[1] in Rset && get(cum_m, k, 0.0) == 0) && (cum_m[k] = x)
    end
    # L303-308
    old = gmembers(tm, "SUBT", 1)
    subt = Set((T[i],) for i in 2:length(T) if (T[i-1],) in old)
    z = minimum((gv(B, k).v for k in S("FORWARD", 1).keys); init=Inf)
    g_overlap = gscalar(tm, "G_OVERLAP")
    yr_v1 = minimum((m(t) for (t,) in subt if m(t) >= z - g_overlap); init=Inf)
    z = yr_v1 + gscalar(tm, "YR_VL")
    for t in T
        m(t) < z && push!(subt, (t,))
    end
    filter!(k -> !(m(k[1]) < yr_v1), subt)
    gput_scalar!(tm, "YR_V1", yr_v1)
    gput_scalar!(tm, "Z", z)
    gput!(tm, "SUBT", subt)
    # L311
    V = gmembers(tm, "MODLYEAR", 1)
    foreach(t -> push!(V, (t,)), T)
    gput!(tm, "MODLYEAR", V)
    # L312-314
    stp_uct = P("STP_UCT", 4)
    for (j, name) in (("1", "UC_T_SUM"), ("2", "UC_T_SUCC"), ("3", "UC_T_EACH"))
        mem = gmembers(tm, name, 3)
        for k in keys(stp_uct.values)
            (k[1] == j && k[2] in Rset && k[4] in Tset) && push!(mem, (k[2], k[3], k[4]))
        end
        gput!(tm, name, mem)
    end
    # L319: $BATINCLUDE bndmain.%1 %1 1
    bnd_data!(tm; cum=false)
    stp_bndmain!(tm)                                                            # its bound statements
    return tm
end
