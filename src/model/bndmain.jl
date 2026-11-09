# Variable bounds: bndmain.mod and the bnd_*.mod files it includes.
#
# GAMS: bndmain.mod L15-87, bnd_act.mod L13-24, bnd_flo.mod L12-39,
# bnd_stg.mod L12-27, bnd_set.mod L20-25, bnd_cum.mod L12-40, v4.9.7 (maindrv.mod L92 includes
# bndmain.mod with %2 = 0, after eqmain.mod and before pp_qack.mod).
#
# GAMS keeps bounds as attributes of variable records, independent of
# whether a column is referenced by any equation; only referenced columns
# reach the matrix. They are kept the same way here: `bndmain(tm)` returns a
# `BoundTable` of (lower, upper) per variable record, checked against the
# variable records of the pre-solve dump (layer 1), and `apply_bounds!(tm)`
# copies them onto the JuMP columns the equations created (layer 2).
#
# Semantics relied on (docs/discrepancies.md):
# - `x.LO(..) $= p(..)` assigns where p is nonzero or EPS; an EPS bound is 0
#   (G10). `.FX` sets both bounds.
# - An assignment whose right-hand side or condition refers to the symbol
#   being assigned sees the values from before the statement (G11).
# - The "reset any existing bounds" statements (bnd_act.mod L13-14,
#   bnd_flo.mod L12-13, bnd_set.mod L20-21, bndmain.mod L15 $CLEAR) restore
#   the declared defaults. No earlier statement of a standard run sets these
#   bounds, so here every record starts at its default: 0/+INF for a
#   POSITIVE VARIABLE, -INF/+INF for a free one (mod_vars.mod).
#
# Parameters bndmain changes. bndmain.mod L44-45 (NCAP_BND), L51 (CAP_BND),
# bnd_flo.mod L16 (FLO_BND) and bnd_cum.mod L12-20 (FLO_CUM) modify their
# input parameters before taking bounds from them. They are translated and
# applied to local copies. Built from the pre-solve dump, the input already
# holds the modified values; each modification is idempotent, and the tests
# check FLO_CUM from the coef/ dump (before bndmain) against the pre-solve
# dump. bnd_flo.mod L22-23 (marks for EQ_FLOBND under the '%DFLBL%' year) do
# not affect bounds and belong with eqflobnd.mod.
#
# Sets: bndmain runs before pp_qack.mod, which then removes RTPCS_VARF
# members (RPC_CONLY, L47) and RTP members (NO_RVP, L54). Built from the
# pre-solve dump, those members are already gone. Bounds on them can only
# concern columns no equation references (docs/discrepancies.md U5).
#
# Not translated yet; data or switches that need them raise UnportedError:
# elastic demand (bnd_elas.mod), cumulative
# cost bounds (bnd_cum.mod L44-48), MACRO (bnd_macro.tm),
# STAGES, dynamic timeslices (dynslite.vda, NORTS), VDA trade bounds
# (bnd_ire.vda, PREMILE), DSC semi-continuous capacity (mod_vars.dsc L18-19,
# NCAP_SEMI), damage (eqdamage.mod L141-156), MACRO/MICRO demand
# (pp_micro.mod L88-91, RD_NLP), POWERFLO (powerflo.vda), load points
# (spoint.mod L83-85) and %R_T% variants (REG_FIXT, STEPPED; maindrv.mod
# L40-41).

"""
    BoundTable

Variable bounds as GAMS keeps them: `(lower, upper)` per variable record,
by family (upper case) and index tuple. Records not in the table have the
declared default.
"""
struct BoundTable
    recs::Dict{String,Dict{Tuple,Tuple{Float64,Float64}}}
end
BoundTable() = BoundTable(Dict{String,Dict{Tuple,Tuple{Float64,Float64}}}())

"The declared default bounds of variable family `name`: (0, Inf) if POSITIVE, else (-Inf, Inf)."
function default_bounds(tm::TimesModel, name::AbstractString)
    spec = varfamily(tm.vars, name).spec
    return spec.positive ? (0.0, Inf) : (-Inf, Inf)
end

"The bounds of one variable record."
bounds(bt::BoundTable, tm::TimesModel, name::AbstractString, key::Tuple) =
    get(get(bt.recs, uppercase(name), Dict{Tuple,Tuple{Float64,Float64}}()), key, default_bounds(tm, name))

function _setbound!(bt::BoundTable, tm, name, key::Tuple, which::Symbol, v::GNum)
    fam = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, uppercase(name))
    lo, up = get(fam, key, default_bounds(tm, name))
    x = v.v                                     # EPS is a zero bound (G10)
    which === :lo ? (lo = x) : which === :up ? (up = x) : (lo = up = x)
    fam[key] = (lo, up)
    return bt
end

"`name.LO(key) = v`, `.UP`, `.FX` for `which` = :lo, :up, :fx."
setbound!(bt::BoundTable, tm::TimesModel, name::AbstractString, key::Tuple, which::Symbol, v::GNum) =
    _setbound!(bt, tm, name, key, which, v)

"`name.<which>(key) \$= v`: assigned only where `v` is nonzero or EPS (G10)."
setbound_if!(bt::BoundTable, tm::TimesModel, name::AbstractString, key::Tuple, which::Symbol, v::GNum) =
    iszero(v) ? bt : _setbound!(bt, tm, name, key, which, v)

const BD_WHICH = (("LO", :lo), ("UP", :up), ("FX", :fx))   # bnd_set.mod L23-25 order

function bounds_unported(tm::TimesModel)
    d = tm.data
    yes(name) = uppercase(gswitch(tm, name, "")) == "YES"
    notempty_set(name, N) = !isempty(gset_opt(d, name, N))
    notempty_par(name, N) = !isempty(gparam_opt(d, name, N))
    (yes("TIMESED") || yes("MICRO")) && throw(UnportedError("bnd_elas.mod (elastic demand steps)"))
    yes("MACRO") && throw(UnportedError("bnd_macro.tm (MACRO)"))
    yes("STAGES") && throw(UnportedError("stochastic bounds (STAGES)"))
    for sw in ("SPOINT", "LPOINT", "FIXBOH", "STEPPED")
        haskey(tm.switches, sw) && throw(UnportedError("bounds under $sw (spoint.mod L63-87 / maindrv.mod L40)"))
    end
    haskey(tm.switches, "RPOINT") && uppercase(tm.switches["RPOINT"]) != "NO" &&
        throw(UnportedError("bounds under RPOINT (spoint.mod)"))
    notempty_par("REG_CUMCST", 6) && throw(UnportedError("bnd_cum.mod L44-48 (cumulative cost bounds)"))
    notempty_par("NORTS", 3) && throw(UnportedError("dynslite.vda BOUNDS (dynamic timeslices)"))
    notempty_set("PREMILE", 1) && throw(UnportedError("bnd_ire.vda (VDA fixed trade before PREMILE)"))
    notempty_par("NCAP_SEMI", 3) && throw(UnportedError("mod_vars.dsc L18-19 (semi-continuous capacity)"))
    notempty_par("DAM_COST", 4) && throw(UnportedError("eqdamage.mod L141-156 (damage step bounds)"))
    notempty_par("RD_NLP", 2) && throw(UnportedError("pp_micro.mod L88-91 (VAR_DEM bounds)"))
    notempty_par("COM_CSTBAL", 6) && throw(UnportedError("powerflo.vda (COM_CSTBAL)"))
    notempty_par("REG_FIXT", 1) && throw(UnportedError("%R_T% = RT_PP(R,T) (REG_FIXT, maindrv.mod L41)"))
    return nothing
end

"A parameter as a mutable GAMS value table (EPS kept), for the parameters bndmain changes."
gtable(p::GamsParam{N}) where {N} = Dict{NTuple{N,String},GNum}(k => gv(p, k) for k in p.keys)

"Assign `v` to `tab[k]` as GAMS does: a zero removes the record."
gassign!(tab::Dict, k, v::GNum) = (iszero(v) ? delete!(tab, k) : (tab[k] = v); tab)

"SMIN(BDNEQ, X(...,BDNEQ)) of a bound table at `key...`, over BDNEQ = LO, UP (setglobs.gms L157)."
function smin_bdneq(tab::Dict, key::Tuple)
    lo, up = get(tab, (key..., "LO"), GZERO), get(tab, (key..., "UP"), GZERO)
    return up.v < lo.v ? up : lo
end

"""
    bnd_act!(bt, tm)

    VAR_ACT.LO(RTP_VINTYR(R,T,T,P),S)\$(PRC_TS(R,P,S) * (NOT PRC_VINT(R,P))) \$= ACT_BND(R,T,P,S,'LO');
    VAR_ACT.UP(...) \$= ACT_BND(R,T,P,S,'UP');  VAR_ACT.FX(RTP_VINTYR(%R_T%,T,P),S)\$(...) \$= ACT_BND(R,T,P,S,'FX');
    VAR_ACT.UP(RTP_VINTYR(R,V,T,P),S)\$(PRC_TS(R,P,S) * PRC_VINT(R,P)\$RTPS_OFF(R,T,P,S)) = EPS;

GAMS: bnd_act.mod L13-24, v4.9.7 (%R_T% = R,T, maindrv.mod L39).
"""
function bnd_act!(bt::BoundTable, tm::TimesModel)
    act_bnd = gparam(tm, "ACT_BND")
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))
    prc_vint = gset(tm, "PRC_VINT")
    rtps_off = gset(tm, "RTPS_OFF")
    t_set, v_set = gset(tm, "MILESTONYR"), gset(tm, "MODLYEAR")
    for (r, v, t, p) in gset(tm, "RTP_VINTYR")
        ((v,) in v_set && (t,) in t_set) || continue
        for (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[])
            key = (r, v, t, p, s)
            if v == t && !((r, p) in prc_vint)                                  # L20-22
                for (bd, which) in BD_WHICH
                    setbound_if!(bt, tm, "VAR_ACT", key, which, gv(act_bnd, (r, t, p, s, bd)))
                end
            end
            (r, p) in prc_vint && (r, t, p, s) in rtps_off &&                   # L24
                setbound!(bt, tm, "VAR_ACT", key, :up, GEPS)
        end
    end
    return bt
end

"""
    bnd_flo!(bt, tm)

    FLO_BND(R,T,P,C,S,'LO')\$((NOT RPC_EMIS(R,P,C))\$(FLO_BND(R,T,P,C,S,'LO')=0)\$RP_FLO(R,P)) = 0;
    LOOP((RTPC(R,T,P,C),S,BD)\$FLO_BND(RTPC,S,BD), TRACKPC(RP_FLO(R,P),C) = YES);
    TRACKPC(PRC_VINT(R,P),C) = NO; TRACKPC(RPC_FFUNC(R,P,C)) = NO; TRACKPC(RPC_EMIS(R,P,C)) = NO;
    TRACKPC(RPC_ACT(R,P,C)) = NO;
    VAR_FLO.LO(RTP_VINTYR(R,T,T,P),C,S)\$((RTPCS_VARF(R,T,P,C,S)*TRACKPC(R,P,C))\$FLO_BND(R,T,P,C,S,'LO')) = FLO_BND(R,T,P,C,S,'LO');
    (.UP, .FX alike)

Under %REDUCE% YES (L34-39) the bounds of a flow that the activity replaces
(RPC_ACT, processes without vintages) go to VAR_ACT, divided by PRC_ACTFLO.

GAMS: bnd_flo.mod L12-39, v4.9.7. L22-23 mark FLO_BND entries under the
'%DFLBL%' year for eqflobnd.mod and do not affect bounds (file header).
"""
function bnd_flo!(bt::BoundTable, tm::TimesModel)
    flo_bnd = gtable(gparam(tm, "FLO_BND"))
    t_set, v_set, com = gset(tm, "MILESTONYR"), gset(tm, "MODLYEAR"), gset(tm, "COM")
    rpc_emis, rp_flo = gset(tm, "RPC_EMIS"), gset(tm, "RP_FLO")
    for (k, x) in collect(flo_bnd)                                              # L16
        (r, t, p, c, s, bd) = k
        bd == "LO" && (t,) in t_set && (c,) in com && x.v == 0 && !((r, p, c) in rpc_emis) && (r, p) in rp_flo &&
            gassign!(flo_bnd, k, GZERO)
    end
    trackpc = Set{NTuple{3,String}}()                                           # L17-24
    rtpc = gset(tm, "RTPC")
    for ((r, t, p, c, s, bd), _) in flo_bnd
        ((t,) in t_set && (c,) in com && (r, t, p, c) in rtpc && bd in ("LO", "UP", "FX") && (r, p) in rp_flo) &&
            push!(trackpc, (r, p, c))
    end
    prc_vint, rpc_ffunc, rpc_act = gset(tm, "PRC_VINT"), gset(tm, "RPC_FFUNC"), gset(tm, "RPC_ACT")
    filter!(k -> !((k[1], k[2]) in prc_vint || k in rpc_ffunc || k in rpc_emis || k in rpc_act), trackpc)
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    vint_tt = Set((r, t, p) for (r, v, t, p) in gset(tm, "RTP_VINTYR") if v == t && (t,) in t_set && (v,) in v_set)
    for ((r, t, p, c, s, bd), x) in sort!(collect(flo_bnd); by=first)           # L27-29
        which = bd == "LO" ? :lo : bd == "UP" ? :up : bd == "FX" ? :fx : continue
        ((r, t, p) in vint_tt && (c,) in com && (r, t, p, c, s) in rtpcs_varf && (r, p, c) in trackpc) || continue
        setbound!(bt, tm, "VAR_FLO", (r, t, t, p, c, s), which, x)
    end
    tm.reduce || return bt                                                      # L34: $IF NOT '%REDUCE%' == 'YES' $EXIT
    # L37-39: LOOP(RTPCS_VARF(R,T,P,C,S)$(((NOT PRC_VINT(R,P))*RPC_ACT(R,P,C))$FLO_BND(R,T,P,C,S,'LO')),
    #   VAR_ACT.LO(R,T,T,P,S) = MAX(VAR_ACT.LO(R,T,T,P,S),FLO_BND(R,T,P,C,S,'LO')/PRC_ACTFLO(R,T,P,C)));
    #   .UP with MIN; .FX(R,T,T,P,S) = FLO_BND(R,T,P,C,S,'FX')/PRC_ACTFLO(R,T,P,C)   (each a loop of its own)
    actflo = gparam(tm, "PRC_ACTFLO")
    varf = [k for k in rtpcs_varf.keys if !((k[1], k[3]) in prc_vint) && (k[1], k[3], k[4]) in rpc_act]
    for (bd, which) in (("LO", :lo), ("UP", :up), ("FX", :fx))
        for (r, t, p, c, s) in varf
            x = get(flo_bnd, (r, t, p, c, s, bd), nothing)
            x === nothing && continue
            y = x / gv(actflo, (r, t, p, c))
            key = (r, t, t, p, s)
            lo, up = bounds(bt, tm, "VAR_ACT", key)
            which === :lo && (y = gmax(GNum(lo), y))
            which === :up && (y = gmin(GNum(up), y))
            setbound!(bt, tm, "VAR_ACT", key, which, y)
        end
    end
    return bt
end

"""
    bnd_stg!(bt, tm, var, io, lo)

bnd_stg.mod as bndmain.mod L36-37 includes it, `bnd_stg.mod SIN IN 0` and
`bnd_stg.mod SOUT OUT -INF` (%1 = `var` without the VAR_ prefix, %2 = `io`,
%3 = `lo`):

    VAR_%1.LO(R,V,T,P,C,S)\$PRC_MAP(R,'STG',P) = 0;  VAR_%1.UP(R,V,T,P,C,S)\$PRC_MAP(R,'STG',P) = INF;
    VAR_%1.LO(RTP_VINTYR(R,V,T,P),'ACT',S)\$((RPS_STG(R,P,S)->0)\$RP_STS(R,P)) = %3;
    TRACKP(RP(R,P))\$((NOT PRC_VINT(R,P))\$PRC_MAP(R,'STG',P)) = YES;
    STG%2_BND(R,T,P,C,S,BD)\$((NOT TOP(R,P,C,'%2'))\$RP_STG(R,P)) = 0;
    VAR_%1.LO(RTP_VINTYR(R,T,T,P),C,S)\$(RPCS_VAR(R,P,C,S)\$TRACKP(R,P)) \$= STG%2_BND(R,T,P,C,S,'LO');
    (.UP, .FX alike)

The resets restore the declared defaults (VAR_SIN and VAR_SOUT are positive,
mod_vars.mod), which no earlier statement changes, so they set nothing here.
`(RPS_STG->0)` is `NOT RPS_STG`: the STS balancer output VAR_SOUT(...,'ACT',S)
is free below at every timeslice outside the storage's own (S = ALL_TS),
and VAR_SIN's 0 is its default. The STG%2_BND clearing changes the bound
parameter that EQ(l)_STGIN/STGOUT also read at the SOLVE; the pre-solve dump
already holds the cleared values, so it is applied to a local copy here.
%STAGES% (L20, L26) is refused with the bounds.

GAMS: bnd_stg.mod L12-27 with bndmain.mod L36-37, v4.9.7.
"""
function bnd_stg!(bt::BoundTable, tm::TimesModel, var::String, io::String, lo::GNum)
    rp_sts, rps_stg = gset(tm, "RP_STS"), gset(tm, "RPS_STG")
    t_set, v_set = gset(tm, "MILESTONYR"), gset(tm, "MODLYEAR")
    rtp_vintyr = gset(tm, "RTP_VINTYR")
    if !isempty(rp_sts)                                                         # L14
        all_ts = [k[1] for k in gset(tm, "ALL_TS").keys]
        for (r, v, t, p) in rtp_vintyr
            ((r, p) in rp_sts && (v,) in v_set && (t,) in t_set) || continue
            for s in all_ts
                (r, p, s) in rps_stg && continue
                setbound!(bt, tm, var, (r, v, t, p, "ACT", s), :lo, lo)
            end
        end
    end
    prc_map, prc_vint, rp = gset(tm, "PRC_MAP"), gset(tm, "PRC_VINT"), gset(tm, "RP")
    trackp = Set((r, p) for (r, m, p) in prc_map if m == "STG" && (r, p) in rp && !((r, p) in prc_vint))   # L17
    isempty(trackp) && return bt
    bnd = gtable(gparam(tm, "STG$(io)_BND"))
    top, rp_stg = gset(tm, "TOP"), gset(tm, "RP_STG")
    for k in collect(keys(bnd))                                                 # L18
        (r, t, p, c, s, b) = k
        (!((r, p, c, io) in top) && (r, p) in rp_stg) && gassign!(bnd, k, GZERO)
    end
    rpcs_var = gset(tm, "RPCS_VAR")
    vint_tt = Set((r, t, p) for (r, v, t, p) in rtp_vintyr if v == t && (t,) in t_set)
    for (bd, which) in BD_WHICH                                                 # L22-24
        for ((r, t, p, c, s, b), x) in sort!(collect(bnd); by=first)
            b == bd || continue
            ((r, t, p) in vint_tt && (r, p, c, s) in rpcs_var && (r, p) in trackp) || continue
            setbound_if!(bt, tm, var, (r, t, t, p, c, s), which, x)
        end
    end
    return bt
end

"""
    bnd_ncap_cap!(bt, tm)

    NCAP_BND(RTP_OFF,'UP') = EPS;
    NCAP_BND(RTP(R,T,P),'LO')\$(NCAP_BND(RTP,'UP')\$NCAP_BND(RTP,'LO')) = SMIN(BDNEQ,NCAP_BND(RTP,BDNEQ));
    VAR_NCAP.LO(R,T,P)\$RP(R,P) \$= NCAP_BND(R,T,P,'LO');  (.UP, .FX alike; bnd_set.mod L23-25)
    CAP_BND(RTP(RTP_VARP),'LO')\$CAP_BND(RTP,'UP') = SMIN(BDNEQ,CAP_BND(RTP,BDNEQ));
    VAR_CAP.LO(RTP(R,T,P)) \$= CAP_BND(R,T,P,'LO');       (.UP, .FX alike)

GAMS: bndmain.mod L44-46 and L51-52 with bnd_set.mod L20-25, v4.9.7.
"""
function bnd_ncap_cap!(bt::BoundTable, tm::TimesModel)
    t_set, rtp, rp = gset(tm, "MILESTONYR"), gset(tm, "RTP"), gset(tm, "RP")
    ncap = gtable(gparam(tm, "NCAP_BND"))
    for (r, y, p) in gset(tm, "RTP_OFF")                                        # L44
        gassign!(ncap, (r, y, p, "UP"), GEPS)
    end
    old = copy(ncap)                                                            # L45 (G11)
    for (r, t, p) in rtp
        (t,) in t_set || continue
        (haskey(old, (r, t, p, "UP")) && haskey(old, (r, t, p, "LO"))) || continue
        gassign!(ncap, (r, t, p, "LO"), smin_bdneq(old, (r, t, p)))
    end
    for ((r, t, p, bd), x) in sort!(collect(ncap); by=first)                     # L46
        which = bd == "LO" ? :lo : bd == "UP" ? :up : bd == "FX" ? :fx : continue
        ((t,) in t_set && (r, p) in rp) && setbound_if!(bt, tm, "VAR_NCAP", (r, t, p), which, x)
    end
    cap = gtable(gparam(tm, "CAP_BND"))
    old = copy(cap)                                                             # L51
    for (r, t, p) in gset(tm, "RTP_VARP")
        ((r, t, p) in rtp && haskey(old, (r, t, p, "UP"))) || continue
        gassign!(cap, (r, t, p, "LO"), smin_bdneq(old, (r, t, p)))
    end
    for ((r, t, p, bd), x) in sort!(collect(cap); by=first)                      # L52
        which = bd == "LO" ? :lo : bd == "UP" ? :up : bd == "FX" ? :fx : continue
        ((t,) in t_set && (r, t, p) in rtp) && setbound_if!(bt, tm, "VAR_CAP", (r, t, p), which, x)
    end
    return bt
end

"""
    bnd_com!(bt, tm)

    VAR_COMNET.LO(RTCS_VARC(R,T,C,S)) \$= COM_BNDNET(R,T,C,S,'LO');  (.UP, .FX; and VAR_COMPRD from COM_BNDPRD)
    VAR_COMPRD.FX(RTCS_VARC(R,T,C,S))\$((NOT RHS_COMPRD(R,T,C,S))\$RCS_COMPRD(R,T,C,S,'FX')) = EPS;

GAMS: bndmain.mod L57-59 with bnd_set.mod L20-25, v4.9.7.
"""
function bnd_com!(bt::BoundTable, tm::TimesModel)
    t_set, varc = gset(tm, "MILESTONYR"), gset(tm, "RTCS_VARC")
    for (var, par) in (("VAR_COMNET", "COM_BNDNET"), ("VAR_COMPRD", "COM_BNDPRD"))
        p = gparam(tm, par)
        for (r, t, c, s, bd) in sort(p.keys)
            which = bd == "LO" ? :lo : bd == "UP" ? :up : bd == "FX" ? :fx : continue
            ((t,) in t_set && (r, t, c, s) in varc) && setbound_if!(bt, tm, var, (r, t, c, s), which, gv(p, (r, t, c, s, bd)))
        end
    end
    rhs_comprd = gset(tm, "RHS_COMPRD")
    for (r, t, c, s, l) in gset(tm, "RCS_COMPRD")
        (l == "FX" && (t,) in t_set && (r, t, c, s) in varc && !((r, t, c, s) in rhs_comprd)) &&
            setbound!(bt, tm, "VAR_COMPRD", (r, t, c, s), :fx, GEPS)
    end
    return bt
end

"""
    bnd_cum_flo(tm) -> Dict

FLO_CUM after the changes bnd_cum.mod L12-20 make before it sets bounds:

    FLO_CUM(R,P,C,YEAR,LL,BD)\$((FLO_CUM(R,P,C,YEAR,LL,BD) LT 0)\$FLO_CUM(R,P,C,YEAR,LL,BD)) = 0;
    FLO_CUM(R,P,C,YEAR,'EOH','N') \$= FLO_CUM(R,P,C,YEAR,'%EOTIME%','N');
    FLO_CUM(RPC_CUMFLO(R,P,C,YEAR,LL),'N') = 0;
    FLO_CUM(R,P,C,YEAR,LL,BD)\$FLO_CUM(R,P,C,YEAR,LL,'FX') = FLO_CUM(R,P,C,YEAR,LL,'FX')\$BDNEQ(BD);
    LOOP((SAMEAS(J,'1'),MIYR_L), OPTION CLEAR=UNCD7;
      UNCD7(RPC_CUMFLO(R,P,C,YEAR,'%EOTIME%'),J+(FLO_CUM(R,P,C,YEAR,'EOH','N')-1),'') = YES;
      LOOP(UNCD7(R,P,C,YEAR,LL,JJ,''), FLO_CUM(R,P,C,YEAR,LL,'N') = MIN(0,ABS(MULTI(JJ,MIYR_L))-1)\$MULTI(JJ,MIYR_L)));

YEAR and LL are ALLYEAR, BD is BND_TYPE (LO, FX, UP; initsys.mod L71);
%EOTIME% is 2200 unless the run sets it (initsys.mod L36). GAMS: bnd_cum.mod
L12-20, v4.9.7.
"""
function bnd_cum_flo(tm::TimesModel, flo_cum::GamsParam{6}=gparam(tm, "FLO_CUM"))
    tab = gtable(flo_cum)
    allyear = gset(tm, "ALLYEAR")
    yrs(y, ll) = (y,) in allyear && (ll,) in allyear
    eotime = gswitch(tm, "EOTIME", "2200")
    for (k, x) in collect(tab)                                                  # L12
        (_, _, _, y, ll, bd) = k
        (yrs(y, ll) && bd in ("LO", "FX", "UP") && x.v < 0) && gassign!(tab, k, GZERO)
    end
    for (k, x) in collect(tab)                                                  # L13
        (r, p, c, y, ll, bd) = k
        ((y,) in allyear && ll == eotime && bd == "N") && gassign!(tab, (r, p, c, y, "EOH", "N"), x)
    end
    rpc_cumflo = gset(tm, "RPC_CUMFLO")
    for (r, p, c, y, ll) in rpc_cumflo                                          # L14
        gassign!(tab, (r, p, c, y, ll, "N"), GZERO)
    end
    old = copy(tab)                                                             # L16 (G11)
    for ((r, p, c, y, ll, bd), x) in old
        (bd == "FX" && yrs(y, ll)) || continue
        for b in ("LO", "FX", "UP")
            gassign!(tab, (r, p, c, y, ll, b), b == "FX" ? GZERO : x)
        end
    end
    j = [k[1] for k in gset(tm, "J").keys]                                      # L19-20
    j1 = findfirst(==("1"), j)                    # SAMEAS(J,'1'); J+n leads from there
    multi = gparam(tm, "MULTI")
    for (miyr_l,) in gset(tm, "MIYR_L")
        uncd7 = Tuple{NTuple{5,String},String}[]
        for (r, p, c, y, ll) in rpc_cumflo
            ll == eotime || continue
            n = get(tab, (r, p, c, y, "EOH", "N"), GZERO).v
            isinteger(n) || throw(ArgumentError("FLO_CUM$((r, p, c, y, "EOH", "N")) = $n is not an integer lead (bnd_cum.mod L19)"))
            i = j1 === nothing ? 0 : j1 + Int(n) - 1
            1 <= i <= length(j) && push!(uncd7, ((r, p, c, y, ll), j[i]))
        end
        for ((r, p, c, y, ll), jj) in uncd7
            m = gv(multi, (jj, miyr_l))
            gassign!(tab, (r, p, c, y, ll, "N"), gif(min(0.0, abs(m.v) - 1), !iszero(m)))
        end
    end
    return tab
end

"""
    bnd_cum_com(tm, com_cum=COM_CUM, rc_cumcom=RC_CUMCOM) -> (Dict, Set)

COM_CUM and RC_CUMCOM after the changes bnd_cum.mod L27-38 make, for each
COM_VAR (%1, bndmain.mod L64 passes the set COM_VAR = NET, PRD):

    COM_CUM(R,%1,YEAR,'0',C,'N') \$= COM_CUM(R,%1,YEAR,'%EOTIME%',C,'N');
    COM_CUM(RC_CUMCOM(R,%1,YEAR,LL,C),'N') = 0;
    COM_CUM(R,%1,YEAR,LL,C,BD)\$COM_CUM(R,%1,YEAR,LL,C,'FX') = COM_CUM(R,%1,YEAR,LL,C,'FX')\$BDNEQ(BD);
    COM_CUM(RC_CUMCOM(R,%1,LL,YEAR,C),BD)\$(YEARVAL(LL)>MIYR_VL) = EPS;
    RC_CUMCOM(R,%1,LL,YEAR,C)\$(YEARVAL(LL)>MIYR_VL) = NO;
    LOOP((SAMEAS(J,'1'),MIYR_L), OPTION CLEAR=UNCD7;
      UNCD7(RC_CUMCOM(R,%1,YEAR,'%EOTIME%',C),J+(COM_CUM(R,%1,YEAR,'0',C,'N')-1),'') = YES;
      LOOP(UNCD7(R,%1,YEAR,LL,C,JJ,''), COM_CUM(R,%1,YEAR,LL,C,'N') = MIN(0,ABS(MULTI(JJ,MIYR_L))-1)\$MULTI(JJ,MIYR_L)));
    COM_CUM(RC_CUMCOM(R,%1,YEAR,LL,C),L('LO'))\$(NOT COM_CUM(RC_CUMCOM,L)) =
      -INF\$SUM((RTC(R,T,C),ANNUAL(S)),MIN(0,COM_BNDPRD(RTC,S,L)\$DIAG(%1,'PRD')+COM_BNDNET(RTC,S,L)\$DIAG(%1,'NET')+1-1));

A range starting after the horizon gets EPS bounds and leaves RC_CUMCOM (so
no EQ_CUM row); a range with no lower bound gets -INF when an annual
COM_BNDNET/BNDPRD lower bound of the commodity is negative in some period
(`x+1-1` is 0 for EPS, G6). YEAR and LL are ALLYEAR, BD is BND_TYPE (LO, FX,
UP), %EOTIME% is 2200 unless the run sets it (initsys.mod L36). The STAGES
form (%SW1%/%SW2%) is refused with the bounds.

GAMS: bnd_cum.mod L27-38, v4.9.7.
"""
function bnd_cum_com(tm::TimesModel, com_cum::GamsParam{6}=gparam(tm, "COM_CUM"),
                     rc_cumcom_in=gset(tm, "RC_CUMCOM"))
    tab = gtable(com_cum)
    rc_cumcom = Set{NTuple{5,String}}(rc_cumcom_in.keys)
    allyear = gset(tm, "ALLYEAR")
    yearval = gparam(tm, "YEARVAL")
    eotime = gswitch(tm, "EOTIME", "2200")
    miyr_vl = gv(gparam(tm, "MIYR_VL"), ()).v
    for kind in ("NET", "PRD")                                                  # COM_VAR
        for (k, x) in collect(tab)                                              # L27
            (r, kk, y, ll, c, bd) = k
            (kk == kind && (y,) in allyear && ll == eotime && bd == "N") && gassign!(tab, (r, kind, y, "0", c, "N"), x)
        end
        for (r, kk, y, ll, c) in rc_cumcom                                      # L28
            kk == kind && gassign!(tab, (r, kind, y, ll, c, "N"), GZERO)
        end
        old = copy(tab)                                                         # L30 (G11)
        for ((r, kk, y, ll, c, bd), x) in old
            (kk == kind && bd == "FX" && (y,) in allyear && (ll,) in allyear) || continue
            for b in ("LO", "FX", "UP")
                gassign!(tab, (r, kind, y, ll, c, b), b == "FX" ? GZERO : x)
            end
        end
        for key in collect(rc_cumcom)                                           # L31
            (r, kk, ll, y, c) = key
            (kk == kind && gv(yearval, (ll,)).v > miyr_vl) || continue
            for b in ("LO", "FX", "UP")
                gassign!(tab, (r, kind, ll, y, c, b), GEPS)
            end
            delete!(rc_cumcom, key)
        end
        j = [k[1] for k in gset(tm, "J").keys]                                  # L34-35
        j1 = findfirst(==("1"), j)
        multi = gparam(tm, "MULTI")
        for (miyr_l,) in gset(tm, "MIYR_L")
            uncd7 = Tuple{NTuple{5,String},String}[]
            for (r, kk, y, ll, c) in rc_cumcom
                (kk == kind && ll == eotime) || continue
                n = get(tab, (r, kind, y, "0", c, "N"), GZERO).v
                isinteger(n) || throw(ArgumentError("COM_CUM$((r, kind, y, "0", c, "N")) = $n is not an integer lead (bnd_cum.mod L34)"))
                i = j1 === nothing ? 0 : j1 + Int(n) - 1
                1 <= i <= length(j) && push!(uncd7, ((r, kind, y, ll, c), j[i]))
            end
            for ((r, kk, y, ll, c), jj) in uncd7
                m = gv(multi, (jj, miyr_l))
                gassign!(tab, (r, kk, y, ll, c, "N"), gif(min(0.0, abs(m.v) - 1), !iszero(m)))
            end
        end
        bnd = gparam(tm, kind == "PRD" ? "COM_BNDPRD" : "COM_BNDNET")            # L38
        rtc_of_rc = get!(() -> indexby(gset(tm, "RTC"), (1, 3)), tm.cache, "RTC/rc")
        milestonyr = gset(tm, "MILESTONYR")
        for (r, kk, y, ll, c) in rc_cumcom
            kk == kind || continue
            haskey(tab, (r, kind, y, ll, c, "LO")) && continue
            sm = GZERO
            for (_, t, _) in get(rtc_of_rc, (r, c), NTuple{3,String}[])
                (t,) in milestonyr || continue
                v = gv(bnd, (r, t, c, "ANNUAL", "LO"))
                sm = sm + gmin(GZERO, v + 1 - 1)
            end
            gassign!(tab, (r, kind, y, ll, c, "LO"), gif(GNum(-Inf), !iszero(sm)))
        end
    end
    return tab, rc_cumcom
end

"""
    bnd_cum!(bt, tm)

    VAR_CUMFLO.LO(R,P,C,YEAR,LL)\$FLO_CUM(R,P,C,YEAR,LL,'LO') = FLO_CUM(R,P,C,YEAR,LL,'LO')*(1/%CUFSCAL%)*(FLO_CUM(R,P,C,YEAR,LL,'N')+1);
    VAR_CUMFLO.UP(R,P,C,YEAR,LL)\$FLO_CUM(R,P,C,YEAR,LL,'UP') = FLO_CUM(R,P,C,YEAR,LL,'UP')*(1/%CUFSCAL%)*(FLO_CUM(R,P,C,YEAR,LL,'N')+1);
    VAR_CUMCOM.LO(R,C,%1,YEAR,LL)\$COM_CUM(R,%1,YEAR,LL,C,'LO') = COM_CUM(R,%1,YEAR,LL,C,'LO')*(1/%CUCSCAL%)*(COM_CUM(R,%1,YEAR,LL,C,'N')+1);
    VAR_CUMCOM.UP(R,C,%1,YEAR,LL)\$COM_CUM(R,%1,YEAR,LL,C,'UP') = COM_CUM(R,%1,YEAR,LL,C,'UP')*(1/%CUCSCAL%)*(COM_CUM(R,%1,YEAR,LL,C,'N')+1);

with FLO_CUM from [`bnd_cum_flo`](@ref) and COM_CUM from
[`bnd_cum_com`](@ref); %CUFSCAL% is 10 and %CUCSCAL% 1000 unless the run
sets them (eqmain.mod L16-17). GAMS: bnd_cum.mod L23-24 and L39-40, v4.9.7
(included with %1 = COM_VAR since %2 = 0, bndmain.mod L64).
"""
function bnd_cum!(bt::BoundTable, tm::TimesModel)
    tab = bnd_cum_flo(tm)
    allyear = gset(tm, "ALLYEAR")
    scal = GNum(1 / parse(Float64, gswitch(tm, "CUFSCAL", "10")))
    for ((r, p, c, y, ll, bd), x) in sort!(collect(tab); by=first)
        (bd in ("LO", "UP") && (y,) in allyear && (ll,) in allyear) || continue
        n = get(tab, (r, p, c, y, ll, "N"), GZERO)
        setbound!(bt, tm, "VAR_CUMFLO", (r, p, c, y, ll), bd == "LO" ? :lo : :up, x * scal * (n + 1))
    end
    ctab, _ = bnd_cum_com(tm)                                                   # L39-40
    cscal = GNum(1 / parse(Float64, gswitch(tm, "CUCSCAL", "1000")))
    for ((r, kind, y, ll, c, bd), x) in sort!(collect(ctab); by=first)
        (bd in ("LO", "UP") && kind in ("NET", "PRD") && (y,) in allyear && (ll,) in allyear) || continue
        n = get(ctab, (r, kind, y, ll, c, "N"), GZERO)
        setbound!(bt, tm, "VAR_CUMCOM", (r, c, kind, y, ll), bd == "LO" ? :lo : :up, x * cscal * (n + 1))
    end
    return bt
end

"""
    bnd_ucw!(bt, tm)

The bounds of the user-constraint slack variables when VAR_UC is YES
(bndmain.mod L69), from bnd_ucw.mod's six includes of bnd_ucv.mod:

    UC_T_EACH(UC_T_SUCC) = YES;
    VAR_UCRTS.LO(UC_N,R,TT,S)\$UC_T_EACH(R,UC_N,TT) = -INF;  VAR_UCRTS.UP(UC_N,R,TT,S) = INF;
    VAR_UCRTS.LO(UC_N,R,TT,S)\$(UC_ON(R,UC_N)*UC_T_EACH(R,UC_N,TT)) \$= UC_RHSRTS(R,UC_N,TT,S,'LO');
    VAR_UCRTS.UP(...)\$(...) \$= UC_RHSRTS(R,UC_N,TT,S,'UP');  VAR_UCRTS.FX(...)\$(...) \$= UC_RHSRTS(R,UC_N,TT,S,'FX');
    UC_RHSRTS(R,UC_N,TT,S,'UP')\$((NOT UC_RHSRTS(R,UC_N,TT,S,'UP'))\$UC_RHSRTS(R,UC_N,TT,S,'N')) = INF;
    (and the same for VAR_UC/UC_RHS, VAR_UCR/UC_RHSR, VAR_UCT/UC_RHST, VAR_UCRT/UC_RHSRT,
     VAR_UCTS/UC_RHSTS, those without R inside LOOP(R, ...))
    UC_T_EACH(UC_T_SUCC) = NO;

The VAR_UC* variables are free (mod_vars.mod), so the -INF/+INF resets
(bnd_ucv.mod L6-7) give the defaults. The last line raises UC_RHS* 'UP' to
INF where only 'N' is given; the pre-solve dump already holds that, and it
sets no bound. TT = MILESTONYR, R = REG.

GAMS: bnd_ucw.mod L2-12 with bnd_ucv.mod L2-18, v4.9.7 (STAGES parts refused
with the bounds).
"""
function bnd_ucw!(bt::BoundTable, tm::TimesModel)
    var_uc(tm) || return bt                                    # bndmain.mod L69
    reg, milestonyr = gset(tm, "REG"), gset(tm, "MILESTONYR")
    uc_on = gset(tm, "UC_ON")
    t_each = union(Set(gset(tm, "UC_T_EACH").keys), Set(gset(tm, "UC_T_SUCC").keys))   # bnd_ucw.mod L5
    regs = [k[1] for k in reg.keys]
    inT(t) = (t,) in milestonyr
    on(r, n) = (r, n) in uc_on
    on_t(r, n, t) = on(r, n) && (r, n, t) in t_each
    # (variable, parameter, key -> (row key, region or nothing, period or nothing))
    fams = (("VAR_UC", "UC_RHS", k -> ((k[1],), nothing, nothing)),
            ("VAR_UCR", "UC_RHSR", k -> ((k[2], k[1]), k[1], nothing)),
            ("VAR_UCT", "UC_RHST", k -> ((k[1], k[2]), nothing, k[2])),
            ("VAR_UCRT", "UC_RHSRT", k -> ((k[2], k[1], k[3]), k[1], k[3])),
            ("VAR_UCTS", "UC_RHSTS", k -> ((k[1], k[2], k[3]), nothing, k[2])),
            ("VAR_UCRTS", "UC_RHSRTS", k -> ((k[2], k[1], k[3], k[4]), k[1], k[3])))
    for (var, par, split) in fams
        p = gparam(tm, par)
        n_of(k) = var in ("VAR_UC", "VAR_UCT", "VAR_UCTS") ? k[1] : k[2]
        for (bd, which) in BD_WHICH                            # bnd_ucv.mod L11-13
            for k in p.keys
                k[end] == bd || continue
                key, r, t = split(k)
                n = n_of(k)
                t === nothing || inT(t) || continue
                ok = if r === nothing                          # LOOP(R, ...) over every region
                    any(rr -> t === nothing ? on(rr, n) : on_t(rr, n, t), regs)
                else
                    (r,) in reg && (t === nothing ? on(r, n) : on_t(r, n, t))
                end
                ok && setbound_if!(bt, tm, var, key, which, gv(p, k))
            end
        end
    end
    return bt
end

"""
    bnd_obj!(bt, tm)

    VAR_OBJ.LO(R,OBV(UC_N),CUR)\$UC_RHS(UC_N,'N') = -INF;
    VAR_OBJ.LO(R,OBV(UC_N),CUR) \$= UC_RHS(UC_N,'LO');
    VAR_OBJ.UP(R,OBV(UC_N),CUR) \$= UC_RHS(UC_N,'UP');
    (the same three with UC_RHSR(R,UC_N,...))

GAMS: bndmain.mod L74-79, v4.9.7 (L73 clears UC_TS_SUM, which no bound uses).
"""
function bnd_obj!(bt::BoundTable, tm::TimesModel)
    obv, uc_n = gset(tm, "OBV"), gset(tm, "UC_N")
    regs, curs = [k[1] for k in gset(tm, "REG").keys], [k[1] for k in gset(tm, "CUR").keys]
    uc_rhs, uc_rhsr = gparam(tm, "UC_RHS"), gparam(tm, "UC_RHSR")
    for (o,) in obv
        (o,) in uc_n || continue
        for r in regs, cur in curs
            key = (r, o, cur)
            haskey(uc_rhs, (o, "N")) && setbound!(bt, tm, "VAR_OBJ", key, :lo, GNum(-Inf))
            setbound_if!(bt, tm, "VAR_OBJ", key, :lo, gv(uc_rhs, (o, "LO")))
            setbound_if!(bt, tm, "VAR_OBJ", key, :up, gv(uc_rhs, (o, "UP")))
        end
        for r in regs, cur in curs
            key = (r, o, cur)
            haskey(uc_rhsr, (r, o, "N")) && setbound!(bt, tm, "VAR_OBJ", key, :lo, GNum(-Inf))
            setbound_if!(bt, tm, "VAR_OBJ", key, :lo, gv(uc_rhsr, (r, o, "LO")))
            setbound_if!(bt, tm, "VAR_OBJ", key, :up, gv(uc_rhsr, (r, o, "UP")))
        end
    end
    return bt
end

"""
    bndmain(tm) -> BoundTable

All variable bounds a standard run sets before the SOLVE, in bndmain.mod
order: bnd_act, bnd_flo, bnd_stg, NCAP and CAP, COMNET and COMPRD, bnd_cum, the
user-constraint slacks, the objective components. Cached on `tm`.

GAMS: bndmain.mod L15-87, v4.9.7.
"""
function bndmain(tm::TimesModel)
    get!(tm.cache, "BOUNDS") do
        bounds_unported(tm)
        bt = BoundTable()
        ret_bounds!(bt, tm)       # mod_vars.mod L94: prepret.dsc DECL (early retirement), before bndmain
        bnd_powerflo!(bt, tm)     # mod_vars.mod L95: powerflo.vda DECL L223 (reference phase angles)
        bnd_act!(bt, tm)          # L26
        bnd_flo!(bt, tm)          # L31
        bnd_stg!(bt, tm, "VAR_SIN", "IN", GNum(0.0))       # L36
        bnd_stg!(bt, tm, "VAR_SOUT", "OUT", GNum(-Inf))    # L37
        bnd_ncap_cap!(bt, tm)     # L44-52
        bnd_com!(bt, tm)          # L57-59
        bnd_cum!(bt, tm)          # L64
        bnd_ucw!(bt, tm)          # L69
        bnd_obj!(bt, tm)          # L73-79
        bt
    end::BoundTable
end

"""
    apply_bounds!(tm) -> Int

Give every column the equations created its GAMS bounds from
[`bndmain`](@ref) (the declared default where no bound was set). Returns the
number of columns with non-default bounds.
"""
function apply_bounds!(tm::TimesModel)
    bt = bndmain(tm)
    n = 0
    for name in tm.vars.order
        f = tm.vars.families[name]
        isempty(f.keys) && continue
        dflt = default_bounds(tm, name)
        recs = get(bt.recs, name, Dict{Tuple,Tuple{Float64,Float64}}())
        for k in f.keys
            lo, up = get(recs, k, dflt)
            (lo, up) == dflt || (n += 1)
            x = f.refs[k]
            if isinf(lo) && lo < 0
                JuMP.has_lower_bound(x) && JuMP.delete_lower_bound(x)
            else
                JuMP.set_lower_bound(x, lo)
            end
            if isinf(up) && up > 0
                JuMP.has_upper_bound(x) && JuMP.delete_upper_bound(x)
            else
                JuMP.set_upper_bound(x, up)
            end
        end
    end
    return n
end
