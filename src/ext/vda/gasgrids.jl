# M1.3 (61): gasgrids.vda, the gas grids of the VDA power-flow extension (%POWERFLO% YES, set by
# init_ext.vda L135 when GG_KGF has data), in the LP formulation: the main block (powerflo.vda L183),
# DECL (powerflo.vda L249) and MODEL (powerflo.vda L360).
#
# GAMS (v4.9.7): gasgrids.vda L8-95 (main block), L97-139 (DECL), L141-205 (MODEL).
#
# Refused (`gasgrids_unported`): pressure points given as data (GG_PP), which set %SOLMIP% YES
# (L30) and take the MIP path of the pressure-point generation (L73-75), and any run with %SOLMIP%
# YES, where VAR_GG_Y is binary (L106) and GG_M1 is 1 (L62).

"The gasgrids.vda paths this model would take that are not translated."
function gasgrids_unported(tm)
    out = String[]
    hasdata(tm, "GG_KGF", 4) || return out
    hasdata(tm, "GG_PP", 6) && push!(out, "gasgrids.vda L30, L73-75 (GG_PP has data: pressure points, a MIP)")
    uppercase(strip(gswitch(tm, "SOLMIP", ""), ['\'', '"'])) == "YES" &&
        push!(out, "gasgrids.vda L62, L106 (gas grids with %SOLMIP% YES: binary VAR_GG_Y)")
    return out
end

"`OMG(J) /1*51/` and `GG_O(J) /1*%GG_WN%/` (%GG_WN% 19), gasgrids.vda L19, L21."
const GG_WN = 19

"""
    gasgrids_main!(tm) -> tm

gasgrids.vda's main block, included at the end of powerflo.vda's main block (L183) when GG_KGF
has data: the gas-grid nodes (TRACKC: the nodes of NRG_GMAP 'GAS' with a density GG_DENS), the
pipelines (GG_TOP, GG_LINK, GG_EDGE, GG_ARC, GG_RTC, GG_RTPC), the Weymouth and linepack
constants synchronised between the two ends of a pipeline (L46-51), the pressure bounds made
consistent (L53-54), the compression factors (L56-57, L84), the stepped Weymouth linearization
generated from the pressure bounds (GG_PPM, GG_PPW: L66-81, the LP branch of L76-78), the
auxiliary flow of the importing end (IRE_FLOSUM, L89), GG_WINK and the big-M estimates GG_MM.

L35 (`LOOP(GR_GRID(J,TRACKC), GG_DENS(R,C)\$((NOT GG_DENS(R,C))\$GR_GRID(J,R,C)) =
GG_DENS(TRACKC))`) assigns each node its own density: TRACKC in the loop domain stands for its
indices R and C, which the statement then reads as controlled, so it changes nothing. The scratch
CNT, F, Z, DFUNC, MY_F and DONE are left as the loop of L66-78 leaves them.

GAMS: gasgrids.vda L8-95, v4.9.7.
"""
function gasgrids_main!(tm)
    hasdata(tm, "GG_KGF", 4) || return tm                                  # L8: $IFE NOT CARD(GG_KGF) $EXIT
    u = gasgrids_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    d = tm.data
    S(n, k) = gset_opt(d, n, k).members
    Sk(n, k) = gset_opt(d, n, k).keys
    sorted(x) = gams_sort!(collect(x), d)
    T = [k[1] for k in Sk("MILESTONYR", 1)]
    flow = gparam(tm, "GR_FLOW").values
    # L32: OPTION GG_WTX < GG_PP (no GG_PP data: refused)
    wtx = Set{NTuple{3,String}}()
    # L33: TRACKC(R,C) $= SUM(NRG_GMAP(R,'GAS',C),GG_DENS(R,C))   (TRACKC empty since powerflo.vda L182)
    dens = gvalues(tm, "GG_DENS", 2)
    # L35: no change (see the docstring); L36: OPTION TRACKC < GG_DENS
    trackc = Set{NTuple{2,String}}(keys(dens))
    # L38: GG_RTC(RC_GRID(R,T,C)) $= TRACKC(R,C)
    gg_rtc = Set{NTuple{3,String}}(k for k in Sk("RC_GRID", 3) if (k[1], k[3]) in trackc)
    # L39: TRACKP(RP_IRE(R,P))$SUM(TRACKC(R,C)$GR_FLOW(R,P,C),1) = YES
    trackp = gmembers(tm, "TRACKP", 2)
    rp_ire = S("RP_IRE", 2)
    for k in keys(flow)
        ((k[1], k[2]) in rp_ire && (k[1], k[3]) in trackc) && push!(trackp, (k[1], k[2]))
    end
    # L40: GG_RTPC(RTP(R,T,P),C)$(GG_RTC(R,T,C)$GR_FLOW(R,P,C)) = YES
    rtp = S("RTP", 3)
    flow_c = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> push!(get!(() -> String[], flow_c, (k[1], k[2])), k[3]), keys(flow))
    gg_rtpc = Set{NTuple{4,String}}()
    for (r, t, p) in rtp, c in get(flow_c, (r, p), String[])
        (r, t, c) in gg_rtc && push!(gg_rtpc, (r, t, p, c))
    end
    # L41: GG_ARC(GR_ARC(TRACKC(R,C),RC)) = YES
    gg_arc = Set{NTuple{4,String}}(k for k in Sk("GR_ARC", 4) if (k[1], k[2]) in trackc)
    # L42: GG_TOP(TOP_IRE(TRACKC(R,C),RC,P))$TRACKP(R,P) = YES
    top = Set{NTuple{5,String}}(k for k in Sk("TOP_IRE", 5) if (k[1], k[2]) in trackc && (k[1], k[5]) in trackp)
    # L43: OPTION GG_LINK <= GG_TOP (GG_LINK(R,P,C,REG,COM) = GG_TOP(R,C,REG,COM,P)), CLEAR=GG_TOP, GG_EDGE <= GG_LINK
    gg_link = Set{NTuple{5,String}}((k[1], k[5], k[2], k[3], k[4]) for k in top)
    gg_edge = Set{NTuple{3,String}}((k[1], k[2], k[4]) for k in gg_link)
    # L44: GG_TOP(GR_TOP(TRACKC(R,C),RC,P)) = YES
    gg_top = Set{NTuple{5,String}}(k for k in Sk("GR_TOP", 5) if (k[1], k[2]) in trackc)
    # L46-51: the constants of both ends of each pipeline
    kgf, klp = gvalues(tm, "GG_KGF", 4), gvalues(tm, "GG_KLP", 4)
    put!(p, k, x) = x == 0 ? delete!(p, k) : (p[k] = x)
    act = [k[1] for k in Sk("ACTCG", 1)]
    for (r, c, reg, com, p) in sorted(gg_top), t in T
        # L47-48: GG_KGF of each end where it has none, from the other end
        a, b = (r, t, p, c), (reg, t, p, com)
        (get(kgf, a, 0.0) == 0 && get(kgf, b, 0.0) != 0) && put!(kgf, a, kgf[b])
        (get(kgf, b, 0.0) == 0 && get(kgf, a, 0.0) != 0) && put!(kgf, b, kgf[a])
        # L49: GG_KLP(R,T,P,C)$((NOT GG_KLP(R,T,P,C))$GG_KLP(REG,T,P,COM)) = GG_KLP(REG,T,P,COM)
        (get(klp, a, 0.0) == 0 && get(klp, b, 0.0) != 0) && put!(klp, a, klp[b])
        # L50: GG_KLP(R,T,P,COM2(ACTCG))$(NOT GG_KLP(R,T,P,COM2)) = GG_KLP(REG,T,P,COM2)
        for ac in act
            get(klp, (r, t, p, ac), 0.0) == 0 && put!(klp, (r, t, p, ac), get(klp, (reg, t, p, ac), 0.0))
        end
        # L51: GG_KLP(REG,T,P,COM) = 0; IF(NOT SAMEAS(R,REG),GG_KLP(REG,T,P,COM2) = 0)
        delete!(klp, b)
        r == reg || filter!(((k, _),) -> !(k[1] == reg && k[2] == t && k[3] == p), klp)
    end
    # L53-54: an upper pressure bound below the lower takes the lower; then a lower above the upper takes the upper
    prbd = gvalues(tm, "GG_PRBD", 4)
    for (r, t, c) in gg_rtc
        lo, up = get(prbd, (r, t, c, "LO"), 0.0), get(prbd, (r, t, c, "UP"), 0.0)
        (up < lo && lo != 0) && (prbd[(r, t, c, "UP")] = lo)
    end
    for (r, t, c) in gg_rtc
        lo, up = get(prbd, (r, t, c, "LO"), 0.0), get(prbd, (r, t, c, "UP"), 0.0)
        (lo > up && up != 0) && (prbd[(r, t, c, "LO")] = up)
    end
    pb(r, t, c, l) = get(prbd, (r, t, c, l), 0.0)
    # L56-57: GG_GAMMA 1 at the importing ends and where below 1+1/128
    gamma = gvalues(tm, "GG_GAMMA", 4)
    rpc_ire = S("RPC_IRE", 4)
    for k in gg_rtpc
        (k[1], k[3], k[4], "EXP") in rpc_ire || (gamma[k] = 1.0)
    end
    for k in gg_rtpc
        get(gamma, k, 0.0) < 1 + 1 / 128 && (gamma[k] = 1.0)
    end
    gm(r, t, p, c) = get(gamma, (r, t, p, c), 0.0)
    # L59: TRACKPC: the pipelines that link two nodes both ways
    trackpc = Set{NTuple{3,String}}((k[1], k[2], k[3]) for k in gg_link if (k[4], k[2], k[5], k[1], k[3]) in gg_link)
    # L61: GG_WTX(TRACKPC) = NO (GG_WTX is empty); L65: GG_WTX(TRACKPC)$... = YES (none, GG_WTX empty)
    # L66-78: the pressure points of the stepped Weymouth linearization, from the pressure bounds (LP branch)
    js = [k[1] for k in Sk("J", 1)]
    jord = Dict(j => i for (i, j) in enumerate(js))
    gg_o = [j for j in js if 1 <= jord[j] <= GG_WN]                       # GG_O(J) /1*19/: '1'..'19' in J's order
    ppm = gvalues(tm, "GG_PPM", 7)
    cnt, F, Z, dfunc, my_f, done = (Float64(gscalar(tm, n)) for n in ("CNT", "F", "Z", "DFUNC", "MY_F", "DONE"))
    links_of = Dict{NTuple{3,String},Vector{NTuple{2,String}}}()
    for k in sorted(gg_link)
        push!(get!(() -> NTuple{2,String}[], links_of, (k[1], k[2], k[3])), (k[4], k[5]))
    end
    gg_m1 = 0.0
    for (r, t, p, c) in sorted(gg_rtpc), (reg, com) in get(links_of, (r, p, c), NTuple{2,String}[])
        # L67: CNT = ROUND(MAX(0,GG_PP(R,'0',P,C,'N','1'),GG_PP(REG,'0',P,COM,'N','1')))   (no GG_PP: 0)
        cnt = 0.0
        # L68: F=Z; DFUNC=GG_WTX(R,P,C)$CNT
        F = Z
        dfunc = ((r, p, c) in wtx && cnt != 0) ? 1.0 : 0.0
        # L69-71: IF(DFUNC->CNT, ...)
        if dfunc == 0 || cnt != 0
            cnt = min(50.0, cnt)
            F = pb(r, t, c, "UP") * max(1.0, gm(r, t, p, c))
            Z = max(F * 0.1, pb(reg, t, com, "LO"))
        end
        # L72-78: IF(F>Z, IF(DFUNC, ... (pressure points: refused) ELSE ...))
        if F > Z
            cnt = Float64(length(gg_o))
            my_f, dfunc = 1.283, 0.233
            done = (1 - Z / F) * dfunc / (cnt / 2 * (cnt - 1))
            cnt = cnt - 1 + gg_m1 / 2
            Z = (1 - Z / F) * (1 - dfunc) / (my_f^cnt)
            for j in gg_o
                o = jord[j]
                put!(ppm, (r, t, p, c, reg, com, j), F * (1 - Z * my_f^(o - 1) - o / 2 * (o - 1) * done))
            end
        end
    end
    # L79: GG_PP(R,LL,P,C,'N',OMG) = 0 (none); OPTION GG_WTX < GG_PP (empty), OMG < GG_PP (empty)
    gput!(tm, "OMG", Set{Tuple{String}}())
    # L80: GG_PPM(GG_RTPC(R,T,P,C),R,C,GG_O(J))$(NOT GG_WTX(R,P,C)) = GG_PRBD(R,T,C,'UP')*MAX(1,GG_GAMMA(R,T,P,C))
    for (r, t, p, c) in gg_rtpc, j in gg_o
        put!(ppm, (r, t, p, c, r, c, j), pb(r, t, c, "UP") * max(1.0, gm(r, t, p, c)))
    end
    # L81: GG_PPW(GG_RTPC(R,T,P,C),RC,GG_O(J))$((NOT GG_WTX(R,P,C))$GG_PPM(R,T,P,C,RC,J)) =
    #   SQRT(POWER(GG_PPM(R,T,P,C,R,C,J),2)-POWER(GG_PPM(R,T,P,C,RC,J),2))
    ppw = gvalues(tm, "GG_PPW", 7)
    ogo = Set(gg_o)
    for (k, x) in collect(ppm)
        ((k[1], k[2], k[3], k[4]) in gg_rtpc && k[7] in ogo && x != 0) || continue
        put!(ppw, k, sqrt(get(ppm, (k[1], k[2], k[3], k[4], k[1], k[4], k[7]), 0.0)^2 - x^2))
    end
    # L84: GG_GAMMA(GG_RTPC(R,T,P,C))$(GG_GAMMA(R,T,P,C)<1+1/128) = 0
    for k in gg_rtpc
        get(gamma, k, 0.0) < 1 + 1 / 128 && delete!(gamma, k)
    end
    # L86: GG_RTPC(R,T,P,C)$(NOT GG_KGF(R,T,P,C)) = NO
    filter!(k -> haskey(kgf, k), gg_rtpc)                                  # (a stored 0 is EPS: true)
    # L87: GG_KLP(RTPC(R,T,P,C))$(NOT GG_RTPC(RTPC)) = 0
    rtpc = S("RTPC", 4)
    filter!(((k, _),) -> !(k in rtpc && !(k in gg_rtpc)), klp)
    # L88: LOOP(GG_LINK(GG_WTX(R,P,C),REG,COM), ...): GG_WTX is empty
    # L89: IRE_FLOSUM(GG_RTPC(R,T,P,C),ANNUAL,IE,C,'IN')$(NOT RPC_IRE(R,P,C,IE)) $= RPC_IRE(R,P,C,'IMP')
    flosum = gvalues(tm, "IRE_FLOSUM", 8)
    annual = Sk("ANNUAL", 1)[1][1]
    for (r, t, p, c) in gg_rtpc
        (r, p, c, "IMP") in rpc_ire || continue
        for ie in ("IMP", "EXP")
            (r, p, c, ie) in rpc_ire || (flosum[(r, t, p, c, annual, ie, c, "IN")] = 1.0)
        end
    end
    # L90: GG_WINK(GG_LINK(R,P,C,RC))$(NOT GG_WTX(R,P,C)) = YES
    gg_wink = gmembers(tm, "GG_WINK", 5)
    union!(gg_wink, gg_link)
    # L92: GG_MM(GG_RTPC(R,T,P,C)) = MAX(60,GG_PRBD(R,T,C,'UP'))*MAX(1,GG_GAMMA(R,T,P,C))*GG_KGF(R,T,P,C)
    mm = gvalues(tm, "GG_MM", 4)
    for (r, t, p, c) in gg_rtpc
        put!(mm, (r, t, p, c), max(60.0, pb(r, t, c, "UP")) * max(1.0, gm(r, t, p, c)) * get(kgf, (r, t, p, c), 0.0))
    end
    # L93: GG_PPW(...,R,C,'1')$GG_WTX(R,P,C) = ...: GG_WTX is empty
    # L94: GG_KGF(GG_RTPC)$(NOT SUM((RC,J)$GG_PPW(GG_RTPC,RC,J),1)) = 0
    withppw = Set((k[1], k[2], k[3], k[4]) for k in keys(ppw))
    foreach(k -> (k in withppw) || delete!(kgf, k), gg_rtpc)
    for (n, v) in (("GG_DENS", dens), ("GG_RTC", gg_rtc), ("GG_RTPC", gg_rtpc), ("GG_ARC", gg_arc), ("GG_LINK", gg_link),
                   ("GG_EDGE", gg_edge), ("GG_TOP", gg_top), ("GG_KGF", kgf), ("GG_KLP", klp), ("GG_PRBD", prbd),
                   ("GG_GAMMA", gamma), ("GG_WTX", wtx), ("GG_PPM", ppm), ("GG_PPW", ppw), ("IRE_FLOSUM", flosum),
                   ("GG_WINK", gg_wink), ("GG_MM", mm))
        gput!(tm, n, v)
    end
    gput_scalar!(tm, "GG_M1", gg_m1)
    # L95: OPTION CLEAR=TRACKC, CLEAR=TRACKPC, CLEAR=TRACKP
    gput!(tm, "TRACKC", Set{NTuple{2,String}}()); gput!(tm, "TRACKPC", Set{NTuple{3,String}}())
    gput!(tm, "TRACKP", Set{NTuple{2,String}}())
    for (n, x) in (("CNT", cnt), ("F", F), ("Z", Z), ("DFUNC", dfunc), ("MY_F", my_f), ("DONE", done))
        gput_scalar!(tm, n, x)
    end
    return tm
end

# --- DECL (powerflo.vda L249): variables, the EQ_IRE rows deleted, bounds ------------------------------

"""
The variables gasgrids.vda DECL declares (L99-108), all positive in the LP formulation
(VAR_GG_Y is binary with %SOLMIP% YES, refused).
"""
const GASGRID_VARS = VariableSpec[
    VariableSpec("VAR_GG_PR", ["R", "T", "C", "S"], true, "Nodal pressures (gasgrids.vda L100)", 95),
    VariableSpec("VAR_GG_MF", ["R", "T", "P", "C", "R", "C", "S"], true, "Mass flows of gases (gasgrids.vda L101)", 95),
    VariableSpec("VAR_GG_PDIF", ["R", "T", "P", "C", "R", "C", "S"], true, "Pressure differences over pipeline (gasgrids.vda L102)", 95),
    VariableSpec("VAR_GG_PADD", ["R", "T", "P", "C", "S"], true, "Pressure boost due to compressor at input node (gasgrids.vda L103)", 95),
    VariableSpec("VAR_GG_STEP", ["R", "T", "P", "C", "S", "J"], true, "Alternate step variables (gasgrids.vda L104)", 95),
    VariableSpec("VAR_GG_Y", ["R", "T", "P", "C", "S"], true, "Flow direction indicator (gasgrids.vda L106-108)", 95),
]

"Declare gasgrids.vda's variables in the model's variable store (once)."
function gasgrids_vars!(tm)
    for spec in GASGRID_VARS
        n = uppercase(spec.name)
        haskey(tm.vars.families, n) && continue
        tm.vars.families[n] = VarFamily(spec)
        push!(tm.vars.order, n)
    end
    return tm
end

"""
    gasgrids_decl!(tm) -> tm

gasgrids.vda DECL (powerflo.vda L249) on the state after the coefficient stage: the variables
(`gasgrids_vars!`) and the EQ_IRE rows deleted at the far end of each pipeline with linepack:

    OPTION TRACKPC < GG_KLP; TRACKPC(R,P,C)\$(NOT GR_FLOW(R,P,C)) = NO
    LOOP(GG_LINK(TRACKPC(R,P,C),REG,COM),RPC_EQIRE(REG,P,COM,IE) = NO);

The bounds of L115-126 are set where the columns are made (`bnd_gasgrids!`); TRACKPC is
cleared again (L127).

GAMS: gasgrids.vda L98-127, v4.9.7.
"""
function gasgrids_decl!(tm)
    hasdata(tm, "GG_KGF", 4) || return tm                                  # L8
    gasgrids_vars!(tm)
    d = tm.data
    flow = gparam(tm, "GR_FLOW").values
    # L111-112: the (R,P,C) of GG_KLP (positions 1, 3 and 4) with a GR_FLOW
    trackpc = Set((k[1], k[3], k[4]) for k in keys(gparam_opt(d, "GG_KLP", 4).values) if haskey(flow, (k[1], k[3], k[4])))
    # L113
    far = Set((k[4], k[2], k[5]) for k in gset_opt(d, "GG_LINK", 5).keys if (k[1], k[2], k[3]) in trackpc)
    eqire = gmembers(tm, "RPC_EQIRE", 4)
    filter!(k -> !((k[1], k[2], k[3]) in far), eqire)
    gput!(tm, "RPC_EQIRE", eqire)
    gput!(tm, "TRACKPC", Set{NTuple{3,String}}())                          # L127: OPTION CLEAR=TRACKPC
    return tm
end

"""
    bnd_gasgrids!(bt, tm) -> bt

The bounds of gasgrids.vda DECL, on the columns the gas-grid rows made:

    LOOP(GG_TOP(R,C,REG,COM,P),
      VAR_GG_PR.LO(GG_RTC(R,T,C),S)\$PRC_TS(R,P,S) = GG_PRBD(R,T,C,'LO');
      VAR_GG_PR.UP(GG_RTC(R,T,C),S)\$PRC_TS(R,P,S) = GG_PRBD(R,T,C,'UP');
      VAR_GG_PR.LO(RTC(REG,T,COM),S)\$PRC_TS(R,P,S) = GG_PRBD(RTC,'LO');
      VAR_GG_PR.UP(RTC(REG,T,COM),S)\$PRC_TS(R,P,S) = GG_PRBD(RTC,'UP'));
    VAR_GG_PADD.LO(RTP(r,t,p),COM(%PGPRIM%),S)\$(PRC_TS(R,P,S)\$GG_KLP(r,t,p,COM)) =
      SUM(RPC_IRE(TRACKPC(R,P,C),'EXP'),MIN((GG_PRBD(R,T,C,'UP')*MAX(1,GG_GAMMA(R,T,P,C))+GG_PRBD(R,T,C,'LO'))/2*
          GG_KLP(R,T,P,C),GG_KLP(r,t,p,COM)) * GG_DENS(R,C) * RS_STGPRD(R,S));
    VAR_GG_PDIF.FX(GG_RTPC(REG,T,P,COM),R,C,S)\$((NOT GG_LINK(REG,P,COM,R,C))\$GG_LINK(R,P,C,REG,COM)\$PRC_TS(REG,P,S)) = 0;
    VAR_GG_STEP.UP(RTPCS_VARF(GG_RTPC(R,T,P,C),S),GG_O)\$SUM(GG_LINK(R,P,C,RC)\$GG_PPW(R,T,P,C,RC,GG_O),1) = EXP(1);
    VAR_GG_Y.UP(RTPCS_VARF(GG_RTPC,S)) = 1;

A pressure bound with no GG_PRBD is 0. TRACKPC in L121 is L111-112's (pipelines with linepack).

GAMS: gasgrids.vda L115-126, v4.9.7.
"""
function bnd_gasgrids!(bt, tm)
    haskey(tm.vars.families, "VAR_GG_PR") || return bt
    d = tm.data
    S(n, k) = gset_opt(d, n, k).members
    rec(name) = get!(() -> Dict{Tuple,Tuple{Float64,Float64}}(), bt.recs, name)
    cols(name) = haskey(tm.vars.families, name) ? tm.vars.families[name].keys : ()
    prbd = gparam(tm, "GG_PRBD").values
    pb(r, t, c, l) = get(prbd, (r, t, c, l), 0.0)
    prc_ts = S("PRC_TS", 3)
    # L115-119, in GG_TOP order (a later pipeline overwrites)
    pr = rec("VAR_GG_PR")
    prcols = Dict{NTuple{2,String},Vector{Tuple}}()
    foreach(k -> push!(get!(() -> Tuple[], prcols, (k[1], k[3])), k), cols("VAR_GG_PR"))
    gg_rtc, rtc = S("GG_RTC", 3), S("RTC", 3)
    for (r, c, reg, com, p) in gams_sort!(collect(gset_opt(d, "GG_TOP", 5).keys), d)
        for (n, cc, ok) in ((r, c, k -> (k[1], k[2], k[3]) in gg_rtc), (reg, com, k -> (k[1], k[2], k[3]) in rtc))
            for k in get(prcols, (n, cc), Tuple[])
                (ok(k) && (r, p, k[4]) in prc_ts) || continue
                pr[k] = (pb(k[1], k[2], k[3], "LO"), pb(k[1], k[2], k[3], "UP"))
            end
        end
    end
    # L120-121: VAR_GG_PADD.LO of %PGPRIM% ('ACT'), the linepack
    klp, gamma, dens = gparam(tm, "GG_KLP").values, gparam(tm, "GG_GAMMA").values, gparam(tm, "GG_DENS").values
    stgprd = gparam(tm, "RS_STGPRD")
    flow = gparam(tm, "GR_FLOW").values
    trackpc = Set((k[1], k[3], k[4]) for k in keys(klp) if haskey(flow, (k[1], k[3], k[4])))
    rpc_ire, rtp = S("RPC_IRE", 4), S("RTP", 3)
    padd = rec("VAR_GG_PADD")
    for k in cols("VAR_GG_PADD")
        (r, t, p, com, s) = k
        (com == "ACT" && (r, t, p) in rtp && (r, p, s) in prc_ts && haskey(klp, (r, t, p, com))) || continue
        kc = klp[(r, t, p, com)]
        x = 0.0
        for (r2, p2, c) in trackpc
            (r2 == r && p2 == p && (r, p, c, "EXP") in rpc_ire) || continue
            x += min((pb(r, t, c, "UP") * max(1.0, get(gamma, (r, t, p, c), 0.0)) + pb(r, t, c, "LO")) / 2 * get(klp, (r, t, p, c), 0.0), kc) *
                 get(dens, (r, c), 0.0) * Float64(gv(stgprd, (r, s)))
        end
        padd[k] = (x, last(get(padd, k, (0.0, Inf))))
    end
    # L124: VAR_GG_PDIF.FX at the far end of a one-way pipeline
    link = gset_opt(d, "GG_LINK", 5).members
    rtpc = S("GG_RTPC", 4)
    pdif = rec("VAR_GG_PDIF")
    for k in cols("VAR_GG_PDIF")
        (reg, t, p, com, r, c, s) = k
        ((reg, t, p, com) in rtpc && !((reg, p, com, r, c) in link) && (r, p, c, reg, com) in link && (reg, p, s) in prc_ts) || continue
        pdif[k] = (0.0, 0.0)
    end
    # L125: VAR_GG_STEP.UP = EXP(1) where a link of the pipeline end has the Weymouth point
    ppw = gparam(tm, "GG_PPW").values
    varf = S("RTPCS_VARF", 5)
    withppw = Set((k[1], k[2], k[3], k[4], k[7]) for k in keys(ppw) if (k[1], k[3], k[4], k[5], k[6]) in link)
    step = rec("VAR_GG_STEP")
    for k in cols("VAR_GG_STEP")
        (r, t, p, c, s, j) = k
        ((r, t, p, c) in rtpc && (r, t, p, c, s) in varf && (r, t, p, c, j) in withppw) || continue
        step[k] = (first(get(step, k, (0.0, Inf))), exp(1))
    end
    # L126: VAR_GG_Y.UP(RTPCS_VARF(GG_RTPC,S)) = 1
    y = rec("VAR_GG_Y")
    for k in cols("VAR_GG_Y")
        ((k[1], k[2], k[3], k[4]) in rtpc && k in varf) && (y[k] = (first(get(y, k, (0.0, Inf))), 1.0))
    end
    return bt
end

# --- MODEL (powerflo.vda L360): the gas-grid rows ----------------------------------------------------

"""
    gg_context(tm) -> NamedTuple

The gas-grid sets and parameters the rows read, with their incidence maps, built once per model.
"""
function gg_context(tm)
    get!(tm.cache, "GG_CONTEXT") do
        d = tm.data
        S(n, k) = gset_opt(d, n, k)
        P(n, k) = gparam_opt(d, n, k)
        link = S("GG_LINK", 5)
        links_of = Dict{NTuple{3,String},Vector{NTuple{2,String}}}()
        for k in gams_sort!(collect(link.keys), d)
            push!(get!(() -> NTuple{2,String}[], links_of, (k[1], k[2], k[3])), (k[4], k[5]))
        end
        ts_of = Dict{NTuple{2,String},Vector{String}}()
        foreach(k -> push!(get!(() -> String[], ts_of, (k[1], k[2])), k[3]), S("PRC_TS", 3).keys)
        ppw = P("GG_PPW", 7)
        ppw_j = Dict{NTuple{6,String},Vector{String}}()
        for k in gams_sort!(collect(keys(ppw.values)), d)
            push!(get!(() -> String[], ppw_j, k[1:6]), k[7])
        end
        (rtpc=gams_sort!(collect(S("GG_RTPC", 4).keys), d), link=link.members, links_of, ts_of,
         top=S("GG_TOP", 5).members, arc=S("GG_ARC", 4).members, wink=S("GG_WINK", 5).members,
         edge=S("GG_EDGE", 3).members, kgf=P("GG_KGF", 4), klp=P("GG_KLP", 4), gamma=P("GG_GAMMA", 4),
         dens=P("GG_DENS", 2), mm=P("GG_MM", 4), prbd=P("GG_PRBD", 4), ppm=P("GG_PPM", 7), ppw, ppw_j,
         g_yrfr=gparam(tm, "G_YRFR"), stgprd=gparam(tm, "RS_STGPRD"),
         prev=Dict((r, s) => sl for (r, s, sl) in gset(tm, "RS_PREV").keys),
         jord=Dict(k[1] => i for (i, k) in enumerate(gset(tm, "J").keys)),
         gg_vi=[k[1] for k in gset(tm, "J").keys if k[1] in ("1", "2", "99")],         # GG_VI(J) /1,2,99/ (L21)
         gg_o=Set(k[1] for (i, k) in enumerate(gset(tm, "J").keys) if i <= GG_WN),     # GG_O(J) /1*19/
         vint_of=indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4)),           # (r,t,p) -> RTP_VINTYR(r,v,t,p)
         rpc_ire=S("RPC_IRE", 4).members, ire_of=indexby(gset(tm, "RPC_IRE"), (1, 2, 3)),
         aire=S("RPC_AIRE", 3).members, actflo=gparam(tm, "PRC_ACTFLO"), rpc_pg=S("RPC_PG", 3).members,
         com_gmap=S("COM_GMAP", 3).members, top_ire=indexby(gset(tm, "TOP_IRE"), (1, 3, 5)))   # (r,reg,p) -> TOP_IRE
    end
end

"VAR_IRE(R,V,T,P,C,S,IE), or VAR_ACT*PRC_ACTFLO for a process with RPC_AIRE, times `k`."
function gg_ire!(expr, x, tm, k::GNum, r, v, t, p, c, s, ie)
    if (r, p, c) in x.aire
        addterm!(expr, k * gv(x.actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, s)
    else
        addterm!(expr, k, tm, "VAR_IRE", r, v, t, p, c, s, ie)
    end
end

"VAR_GG_PRIO(r,t,p,c,s): VAR_GG_PR(r,t,c,s) + VAR_GG_PADD(r,t,p,c,s)\$GG_GAMMA(r,t,p,c) (gasgrids.vda L146), times `k`."
function gg_prio!(expr, x, tm, k::GNum, r, t, p, c, s)
    addterm!(expr, k, tm, "VAR_GG_PR", r, t, c, s)
    haskey(x.gamma.values, (r, t, p, c)) && addterm!(expr, k, tm, "VAR_GG_PADD", r, t, p, c, s)
end

"VAR_GG_PRU(r,t,p,c,s): VAR_GG_PDIF(r,t,p,c,r,'ACT',s) (gasgrids.vda L144), times `k`."
gg_pru!(expr, tm, k::GNum, r, t, p, c, s) = addterm!(expr, k, tm, "VAR_GG_PDIF", r, t, p, c, r, "ACT", s)

"""
VAR_GG_WSLAC(r,t,p,c,reg,com,s) (gasgrids.vda L148), times `k`:

    sum(com2(actcg)\$GG_KGF(r,t,p,c),var_gg_pdif(r,t,p,com2,r,c,s)+8/11*var_gg_pdif(reg,t,p,com2,reg,com,s)\$gg_wink(reg,p,com,r,c)\$(GG_M1->0))

GG_M1 is 0 in the LP formulation, so GG_M1->0 holds.
"""
function gg_wslac!(expr, x, tm, k::GNum, r, t, p, c, reg, com, s)
    haskey(x.kgf.values, (r, t, p, c)) || return expr
    addterm!(expr, k, tm, "VAR_GG_PDIF", r, t, p, "ACT", r, c, s)
    (reg, p, com, r, c) in x.wink && addterm!(expr, k * (GNum(8.0) / GNum(11.0)), tm, "VAR_GG_PDIF", reg, t, p, "ACT", reg, com, s)
    return expr
end

"""
The flow-direction term of VAR_GG_Y2 and VAR_GG_PDMAX (gasgrids.vda L145, L150), times `k`:

    (VAR_GG_Y(R,T,P,C,S)\$GG_TOP(R,C,REG,COM,P) + (1-VAR_GG_Y(REG,T,P,COM,S))\$GG_TOP(REG,COM,R,C,P))
"""
function gg_y2!(expr, x, tm, k::GNum, r, t, p, c, reg, com, s)
    (r, c, reg, com, p) in x.top && addterm!(expr, k, tm, "VAR_GG_Y", r, t, p, c, s)
    if (reg, com, r, c, p) in x.top
        addconst!(expr, k)
        addterm!(expr, -k, tm, "VAR_GG_Y", reg, t, p, com, s)
    end
    return expr
end

"""
The constant of VAR_GG_PDMAX(r,t,p,c,reg,com,ts,z) (gasgrids.vda L150) before its direction term:
MAX(POWER(GG_PRBD(R,T,C,'UP')*MAX(1,GG_GAMMA(R,T,P,C)),Z)-POWER(GG_PRBD(REG,T,COM,'LO'),Z),0).
"""
function gg_pdmax(x, r, t, p, c, reg, com, z::Int)
    up = gv(x.prbd, (r, t, c, "UP")) * gmax(GNum(1.0), gv(x.gamma, (r, t, p, c)))
    return gmax(gpower(up, z) - gpower(gv(x.prbd, (reg, t, com, "LO")), z), GZERO)
end

"""
    eq_gg!(tm) -> Int

The gas-grid rows of gasgrids.vda MODEL (powerflo.vda L360) for one-way pipelines, the LP
formulation (GG_M1 0, no GG_WTX):

    EQ_GG_MFLO(GG_RTPC(R,T,P,C),RC(REG,COM1),S)\$(PRC_TS(R,P,S)\$GG_LINK(R,P,C,RC))..
      VAR_GG_MF(R,T,P,C,RC,S)*GG_DENS(R,C)*G_YRFR(R,S)*8760 =E=
      SUM(TOP_IRE(R,COM,REG,COM2,P)\$(GG_EDGE(R,P,R)->((RPC_PG(R,P,COM2) XOR RPC_PG(R,P,C)) OR COM_GMAP(R,C,COM)\$COM_GMAP(RC,COM2))),
        SUM(RTP_VINTYR(R,V,T,P),VAR_IRE(R,V,T,P,COM,S,'EXP')/2) + SUM(RTP_VINTYR(REG,V,T,P),VAR_IRE(REG,V,T,P,COM2,S,'IMP')/2))
    EQ_GG_GAMA(GG_RTPC(R,T,P,C),REG,COM,S)\$(PRC_TS(R,P,S)\$GG_LINK(R,P,C,REG,COM)\$GG_GAMMA(R,T,P,C))..
      VAR_GG_PADD(R,T,P,C,S) =L= (GG_GAMMA(R,T,P,C)-1)*VAR_GG_PR(R,T,C,S)
    EQ_GG_MBND(GG_RTPC(R,T,P,C),RC(REG,COM),LNX(L),S)\$(PRC_TS(R,P,S)\$(GG_LINK(REG,P,COM,R,C)\$BD(L)+IPS(L)\$(GG_M1->GG_WTX(R,P,C)))\$GG_LINK(R,P,C,RC))..
      VAR_GG_MF(R,T,P,C,REG,COM,S) =L= (GG_MM(R,T,P,C)*(VAR_GG_PRIO(R,T,P,C,S)-VAR_GG_PRIO(REG,T,P,COM,S)))\$GG_TOP(R,C,RC,P)
    EQ_GG_HLIP(GG_RTPC(R,T,P,C),REG,COM,S)\$(PRC_TS(R,P,S)\$GG_KLP(R,T,P,C)\$GG_LINK(R,P,C,REG,COM)\$GG_ARC(R,C,REG,COM))..
      VAR_GG_HLIP(R,T,P,S) =E= VAR_GG_HLIP(R,T,P,S--RS_STG(R,S)) +
        SUM((RTP_VINTYR(R,V,T,P),RPC_IRE(R,P,C,IE)),VAR_IRE(R,V,T,P,C,S,IE)*(2\$XPT(IE)-1)) +
        SUM((RTP_VINTYR(REG,V,T,P),RPC_IRE(REG,P,COM,IE)),VAR_IRE(REG,V,T,P,COM,S,IE)*(2\$XPT(IE)-1))
    EQ_GG_HLEV(GG_RTPC(R,T,P,C),REG,COM,S)\$(PRC_TS(R,P,S)\$GG_LINK(R,P,C,REG,COM)\$GG_ARC(R,C,REG,COM))..
      VAR_GG_HLIP(R,T,P,S) =E= GG_KLP(R,T,P,C)*GG_DENS(R,C)*RS_STGPRD(R,S)*(VAR_GG_PRIO(R,T,P,C,S)+VAR_GG_PRIO(REG,T,P,COM,S))/2
    EQ_GG_PRIO(GG_RTPC(R,T,P,C),RC(REG,COM),LNX(L),S)\$(PRC_TS(R,P,S)\$GG_WINK(R,P,C,RC)\$GG_ARC(R,C,RC))..
      VAR_GG_PRU(R,T,P,C,S)+VAR_GG_PRU(REG,T,P,COM,S)-VAR_GG_PDIF(REG,T,P,COM,R,C,S)\$IPS(L)-VAR_GG_PDIF(R,T,P,C,REG,COM,S)\$BD(L)
      =E= VAR_GG_PRIO(R,T,P,C,S)\$IPS(L)+VAR_GG_PRIO(REG,T,P,COM,S)\$BD(L)-VAR_GG_PDIF(R,T,P,C,R,C,S)
    EQ_GG_WEYMST(GG_RTPC(R,T,P,C),RC(REG,COM),BD(L),S)\$(PRC_TS(R,P,S)\$GG_WINK(R,P,C,RC))..
      (VAR_GG_MF(R,T,P,C,REG,COM,S)+VAR_GG_WSLAC(R,T,P,C,REG,COM,S))\$LNX(L) +
      (VAR_GG_PDIF(R,T,P,C,REG,COM,S)\$BDLOX(BD)+VAR_GG_PRU(R,T,P,C,S)\$BDUPX(BD))\$BDNEQ(BD) =E=
      (GG_KGF(R,T,P,C)*SUM(J\$GG_PPW(R,T,P,C,RC,J),VAR_GG_STEP(R,T,P,C,S,J)*GG_PPW(R,T,P,C,RC,J)))\$LNX(L) +
      (SUM(J\$GG_PPW(R,T,P,C,RC,J),VAR_GG_STEP(R,T,P,C,S,J)*(GG_PPM(R,T,P,C,R,C,J)-GG_PPM(R,T,P,C,RC,J)))\$BDLOX(BD) +
       SUM(J\$GG_PPW(R,T,P,C,RC,J),VAR_GG_STEP(R,T,P,C,S,J)*GG_PPM(R,T,P,C,R,C,J))\$BDUPX(BD))\$BDNEQ(BD)

VAR_GG_HLIP(r,t,p,s) is VAR_GG_PADD(r,t,p,%PGPRIM%,s) (L147). VAR_IRE is replaced by VAR_ACT times
PRC_ACTFLO for a process with RPC_AIRE. S--RS_STG(R,S) is read from RS_PREV, as in EQ_STGTSS.
LNX is {N, FX}, IPS(L) is L = N, BD(L) is L in {LO, FX, UP}, BDLOX {LO, FX}, BDUPX {UP, FX}, BDNEQ
{LO, UP}. The rows of two-way pipelines (EQ_GG_PDIF1, EQ_GG_PDIF2, EQ_GG_STEP, the FX rows of
EQ_GG_MBND with VAR_GG_Y, the second term of VAR_GG_WSLAC) came with M1.3 change 62.
EQ_GG_WEYMTX needs GG_WTX, from pressure points given as data (refused). Returns the number of
rows.

GAMS: gasgrids.vda L141-205, v4.9.7.
"""
function eq_gg!(tm)
    (powerflo_on(tm) && !isempty(gset_opt(tm.data, "GG_RTPC", 4).keys)) || return 0
    gasgrids_vars!(tm)                   # declared here too: a model built from the pre-solve state has no DECL step
    u = gasgrids_model_unported(tm)
    isempty(u) || throw(UnportedError(join(u, "; ")))
    x = gg_context(tm)
    one = GNum(1.0)
    no2, no4 = NTuple{2,String}[], NTuple{4,String}[]
    tx = eq_periods(tm)
    n = 0
    put(name, key, sense, lhs, rhs) = (gconstraint!(tm, name, key, sense, lhs, rhs) === nothing || (n += 1))
    off = rts_off(tm)                    # RTS(S): S+NORTS(R,T,S) with dynamic timeslices (M1.3 change 67)
    for (r, t, p, c) in x.rtpc
        (t,) in tx || continue
        for (reg, com) in get(x.links_of, (r, p, c), no2), s in get(x.ts_of, (r, p), String[])
            off(r, t, s) && continue     # RTS(S) of every EQ_GG_* row, L154-200 (M1.3 change 67)
            # EQ_GG_MFLO
            lhs = JuMP.AffExpr(0.0)
            addterm!(lhs, gv(x.dens, (r, c)) * gv(x.g_yrfr, (r, s)) * GNum(8760.0), tm, "VAR_GG_MF", r, t, p, c, reg, com, s)
            rhs = JuMP.AffExpr(0.0)
            intra = (r, p, r) in x.edge
            for (_, c1, _, c2, _) in get(x.top_ire, (r, reg, p), NTuple{5,String}[])
                ok = !intra || ((((r, p, c2) in x.rpc_pg) != ((r, p, c) in x.rpc_pg)) ||
                                ((r, c, c1) in x.com_gmap && (reg, com, c2) in x.com_gmap))
                ok || continue
                foreach(k -> gg_ire!(rhs, x, tm, GNum(0.5), r, k[2], t, p, c1, s, "EXP"), get(x.vint_of, (r, t, p), no4))
                foreach(k -> gg_ire!(rhs, x, tm, GNum(0.5), reg, k[2], t, p, c2, s, "IMP"), get(x.vint_of, (reg, t, p), no4))
            end
            put("EQ_GG_MFLO", (r, t, p, c, reg, com, s), "E", lhs, rhs)
            # EQ_GG_GAMA
            g = gv(x.gamma, (r, t, p, c))
            if !iszero(g)
                lhs = JuMP.AffExpr(0.0); addterm!(lhs, one, tm, "VAR_GG_PADD", r, t, p, c, s)
                rhs = JuMP.AffExpr(0.0); addterm!(rhs, g - one, tm, "VAR_GG_PR", r, t, c, s)
                put("EQ_GG_GAMA", (r, t, p, c, reg, com, s), "L", lhs, rhs)
            end
            # EQ_GG_MBND: L = 'N' (IPS; GG_M1->GG_WTX is true with GG_M1 0), and L = 'FX' (BD) for a two-way link
            twoway = (reg, p, com, r, c) in x.link
            for l in (twoway ? ("N", "FX") : ("N",))
                lhs = JuMP.AffExpr(0.0); addterm!(lhs, one, tm, "VAR_GG_MF", r, t, p, c, reg, com, s)
                (reg, p, com, r, c) in x.wink && gg_wslac!(lhs, x, tm, one, r, t, p, c, reg, com, s)
                rhs = JuMP.AffExpr(0.0)
                mm = gv(x.mm, (r, t, p, c))
                if l == "N"
                    if (r, c, reg, com, p) in x.top
                        gg_prio!(rhs, x, tm, mm, r, t, p, c, s)
                        gg_prio!(rhs, x, tm, -mm, reg, t, p, com, s)
                        twoway && addterm!(rhs, mm, tm, "VAR_GG_PDIF", reg, t, p, com, r, c, s)
                    end
                    (reg, com, r, c, p) in x.top && addterm!(rhs, mm, tm, "VAR_GG_PDIF", r, t, p, c, reg, com, s)
                else
                    # (GG_KGF(r,t,p,c)*SQRT(VAR_GG_PDMAX(R,T,P,C,REG,COM,S,2)))$BD(L): the macro closes the SQRT
                    #   before its direction term, which multiplies it
                    gg_y2!(rhs, x, tm, gv(x.kgf, (r, t, p, c)) * GNum(sqrt(gg_pdmax(x, r, t, p, c, reg, com, 2).v)),
                           r, t, p, c, reg, com, s)
                end
                put("EQ_GG_MBND", (r, t, p, c, reg, com, l, s), "L", lhs, rhs)
            end
            if twoway
                # EQ_GG_PDIF1(GG_RTPC(R,T,P,C),RC(REG,COM),GG_VI(J),S), J in /1, 2, 99/ (GG_WTX is empty)
                for j in x.gg_vi
                    lhs = JuMP.AffExpr(0.0)
                    if !(j in x.gg_o)                                         # $(NOT GG_O(J))
                        addterm!(lhs, one, tm, "VAR_GG_PDIF", r, t, p, c, reg, com, s)
                        gg_y2!(lhs, x, tm, -gg_pdmax(x, r, t, p, c, reg, com, 1), r, t, p, c, reg, com, s)
                    elseif x.jord[j] == 1                                     # ORD(J)=1
                        gg_pru!(lhs, tm, one, r, t, p, c, s)
                        gg_y2!(lhs, x, tm, -gv(x.prbd, (r, t, c, "UP")), r, t, p, c, reg, com, s)
                    elseif x.jord[j] == 2                                     # ORD(J)=2
                        gg_pru!(lhs, tm, one, r, t, p, c, s)
                        gg_prio!(lhs, x, tm, -one, r, t, p, c, s)
                        lo = gv(x.prbd, (r, t, c, "LO"))
                        addconst!(lhs, lo)                                    # +GG_PRBD(R,T,C,'LO')*(1-VAR_GG_Y2)
                        gg_y2!(lhs, x, tm, -lo, r, t, p, c, reg, com, s)
                    end
                    put("EQ_GG_PDIF1", (r, t, p, c, reg, com, j, s), "L", lhs, JuMP.AffExpr(0.0))
                end
                # EQ_GG_PDIF2(GG_RTPC(R,T,P,C),REG,COM,S)$(GG_LINK(REG,P,COM,R,C)$PRC_TS(R,P,S)$GG_TOP(R,C,REG,COM,P))
                if (r, c, reg, com, p) in x.top
                    lhs = JuMP.AffExpr(0.0); addterm!(lhs, one, tm, "VAR_GG_PDIF", reg, t, p, com, r, c, s)
                    rhs = JuMP.AffExpr(0.0)
                    gg_prio!(rhs, x, tm, one, reg, t, p, com, s)
                    gg_prio!(rhs, x, tm, -one, r, t, p, c, s)
                    addterm!(rhs, one, tm, "VAR_GG_PDIF", r, t, p, c, reg, com, s)
                    put("EQ_GG_PDIF2", (r, t, p, c, reg, com, s), "E", lhs, rhs)
                end
            end
            # EQ_GG_HLIP and EQ_GG_HLEV
            if (r, c, reg, com) in x.arc
                hl = JuMP.AffExpr(0.0); addterm!(hl, one, tm, "VAR_GG_PADD", r, t, p, "ACT", s)
                if haskey(x.klp.values, (r, t, p, c))
                    rhs = JuMP.AffExpr(0.0)
                    addterm!(rhs, one, tm, "VAR_GG_PADD", r, t, p, "ACT", get(x.prev, (r, s), s))
                    for (rr, cc) in ((r, c), (reg, com)), (_, _, _, ie) in get(x.ire_of, (rr, p, cc), no4), k in get(x.vint_of, (rr, t, p), no4)
                        gg_ire!(rhs, x, tm, GNum(ie == "EXP" ? 1.0 : -1.0), rr, k[2], t, p, cc, s, ie)
                    end
                    put("EQ_GG_HLIP", (r, t, p, c, reg, com, s), "E", hl, rhs)
                end
                hl = JuMP.AffExpr(0.0); addterm!(hl, one, tm, "VAR_GG_PADD", r, t, p, "ACT", s)
                f = gv(x.klp, (r, t, p, c)) * gv(x.dens, (r, c)) * gv(x.stgprd, (r, s))
                rhs = JuMP.AffExpr(0.0)
                gg_prio!(rhs, x, tm, f / GNum(2.0), r, t, p, c, s)
                gg_prio!(rhs, x, tm, f / GNum(2.0), reg, t, p, com, s)
                put("EQ_GG_HLEV", (r, t, p, c, reg, com, s), "E", hl, rhs)
            end
            (r, p, c, reg, com) in x.wink || continue
            # EQ_GG_STEP(GG_RTPC(R,T,P,C),RC(REG,COM),S)$((GG_M1->0)$PRC_TS(R,P,S)$GG_WINK(REG,P,COM,R,C)$GG_WINK(R,P,C,RC)$GG_ARC(R,C,RC))
            if (reg, p, com, r, c) in x.wink && (r, c, reg, com) in x.arc
                lhs = JuMP.AffExpr(0.0)
                foreach(j -> addterm!(lhs, one, tm, "VAR_GG_STEP", r, t, p, c, s, j), get(x.ppw_j, (r, t, p, c, reg, com), String[]))
                foreach(j -> addterm!(lhs, one, tm, "VAR_GG_STEP", reg, t, p, com, s, j), get(x.ppw_j, (reg, t, p, com, r, c), String[]))
                put("EQ_GG_STEP", (r, t, p, c, reg, com, s), "L", lhs, JuMP.AffExpr(1.0))
            end
            # EQ_GG_PRIO, L in LNX = (N, FX)
            if (r, c, reg, com) in x.arc
                for l in ("N", "FX")
                    lhs = JuMP.AffExpr(0.0)
                    gg_pru!(lhs, tm, one, r, t, p, c, s); gg_pru!(lhs, tm, one, reg, t, p, com, s)
                    l == "N" ? addterm!(lhs, -one, tm, "VAR_GG_PDIF", reg, t, p, com, r, c, s) :
                               addterm!(lhs, -one, tm, "VAR_GG_PDIF", r, t, p, c, reg, com, s)
                    rhs = JuMP.AffExpr(0.0)
                    l == "N" ? gg_prio!(rhs, x, tm, one, r, t, p, c, s) : gg_prio!(rhs, x, tm, one, reg, t, p, com, s)
                    addterm!(rhs, -one, tm, "VAR_GG_PDIF", r, t, p, c, r, c, s)
                    put("EQ_GG_PRIO", (r, t, p, c, reg, com, l, s), "E", lhs, rhs)
                end
            end
            # EQ_GG_WEYMST, L in BD = (LO, FX, UP), in the order of BD (LO, FX, UP)
            js = get(x.ppw_j, (r, t, p, c, reg, com), String[])
            for l in ("LO", "FX", "UP")
                lhs, rhs = JuMP.AffExpr(0.0), JuMP.AffExpr(0.0)
                if l == "FX"                                                   # LNX(L)
                    addterm!(lhs, one, tm, "VAR_GG_MF", r, t, p, c, reg, com, s)
                    gg_wslac!(lhs, x, tm, one, r, t, p, c, reg, com, s)
                    kg = gv(x.kgf, (r, t, p, c))
                    foreach(j -> addterm!(rhs, kg * gv(x.ppw, (r, t, p, c, reg, com, j)), tm, "VAR_GG_STEP", r, t, p, c, s, j), js)
                elseif l == "LO"                                               # BDNEQ, BDLOX
                    addterm!(lhs, one, tm, "VAR_GG_PDIF", r, t, p, c, reg, com, s)
                    foreach(j -> addterm!(rhs, gv(x.ppm, (r, t, p, c, r, c, j)) - gv(x.ppm, (r, t, p, c, reg, com, j)),
                                          tm, "VAR_GG_STEP", r, t, p, c, s, j), js)
                else                                                           # BDNEQ, BDUPX
                    gg_pru!(lhs, tm, one, r, t, p, c, s)
                    foreach(j -> addterm!(rhs, gv(x.ppm, (r, t, p, c, r, c, j)), tm, "VAR_GG_STEP", r, t, p, c, s, j), js)
                end
                put("EQ_GG_WEYMST", (r, t, p, c, reg, com, l, s), "E", lhs, rhs)
            end
        end
    end
    return n
end

"""
    gasgrids_model_unported(tm) -> Vector{String}

The gas-grid paths of the model not translated: those of `gasgrids_unported` (pressure points as
data, %SOLMIP% YES). Two-way pipelines are translated since M1.3 change 62.
"""
gasgrids_model_unported(tm) = gasgrids_unported(tm)
