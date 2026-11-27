# The flow term of a process/commodity/timeslice inside equations: the
# `$BATINCLUDE %cal_red% ...` that eqptrans.mod, eqcombal.mod and others use.
#
# %cal_red% is chosen in pp_reduce.red: cal_nored.red by default (L13) and
# cal_red.red only when REDUCE is YES (L58-59). With REDUCE NO the
# reduction is skipped (L15), so RPC_EMIS and FS_EMIT stay empty and the
# expression is the flow variable itself; with REDUCE neither YES nor NO the
# emission substitution of cal_nored.red applies to what pp_reduce.red
# computed. Under REDUCE YES cal_red.red replaces flows by activities
# (`cal_red!`, M1.3 change 17b); `cal_nored!` hands over to it.

"""
    cal_nored!(expr, tm, coef, r, v, t, p, c, ts; mode="") -> expr

Add `coef` times the flow of commodity `c` in timeslice `ts` of process `p`
(period `t`, vintage `v`) to `expr`, as cal_nored.red expands it:

    ( VAR_FLO(R,%VNT%,%5,%4,%1,%3)\$(NOT RPC_EMIS(R,%4,%1))
      + SUM((FS_EMIT(R,%4,%1,CG3,COM2),ALL_TS)\$(RS_FR(R,%3,ALL_TS)*RTPCS_VARF(R,%5,%4,COM2,ALL_TS)),
            VAR_FLO(R,%VNT%,%5,%4,COM2,ALL_TS) * COEF_PTRAN(R,%VNT%,%4,CG3,COM2,%1,ALL_TS)%SHP3% *
            RS_FR(R,%3,ALL_TS)*(1+RTCS_FR(R,%5,COM2,%3,ALL_TS))
      )\$RPC_EMIS(R,%4,%1) )

with %1 = c, %3 = ts, %4 = p, %5 = t and `mode` = %7:
- `""` (general case): %VNT% = V (here `v`) and %SHP3% =
  `*(1+RTP_FFCX(R,V,T,P,CG3,C)\$PRC_VINT(R,P))` [`*(1+RTP_FFCS(R,V,P,CG3,C))`];
- `"V"`: as above without `\$PRC_VINT(R,P)`;
- `"T"`: %VNT% = %5 (pass `v = t`) and only the RTP_FFCS factor.
The RTP_FFCS factor exists only when RTP_FFCS is DEFINED (L18).
%8/%9 (a SUM over vintages wrapped around the whole term, used only by
cal_fflo.mod) are not supported here.

The SOW tags (sow_tags.jl): each variable is `%VAR%_FLO%6(... %SOW%)`
(cal_nored.red L23, L27; cal_red.red L29-56), the row's own SOW. `at` is for
the callers whose file sets %SOW% again around the include: eqcumflo.mod L16
and L26 sum the term over SW_TSW(SOW,T,WW) with %SOW% as `,WW`, which is what
`at = t` reads (`addterm!`).

GAMS: cal_nored.red L15-30, v4.9.7 (macro defaults from setglobs.gms
L348-353: %VAR% -> VAR, %SOW% -> '', %SHFF% -> 1+RTP_FFC).
"""
function cal_nored!(expr::JuMP.AffExpr, tm::TimesModel, coef::GNum,
                    r::String, v::String, t::String, p::String, c::String, ts::String;
                    mode::AbstractString="", at::Union{Nothing,AbstractString}=nothing)
    tm.reduce && return cal_red!(expr, tm, coef, r, v, t, p, c, ts; mode, at)    # %cal_red% is cal_red.red (pp_reduce.red L58-59)
    mode in ("", "T", "V") || throw(ArgumentError("cal_nored mode (%7) must be '', T or V, got $mode"))
    iszero(coef) && return expr
    vnt = mode == "T" ? t : v

    # RPC_EMIS(R,P,C) has three indices (the assertion gives the membership test its type: `gset`
    # returns an abstract `GamsSet`, and this function runs once per flow term; Phase 2, change 3)
    rpc_emis = gset(tm, "RPC_EMIS")::GamsSet{3}
    if !((r, p, c) in rpc_emis)
        return addterm!(expr, coef, tm, "VAR_FLO", r, vnt, t, p, c, ts; at)
    end

    # Emission flow = flow variable * emission factor (cal_nored.red L26-28).
    fs_emit_by_rpc = get!(() -> indexby(gset(tm, "FS_EMIT"), (1, 2, 3)), tm.cache, "FS_EMIT/rpc")
    rs_fr = gparam(tm, "RS_FR")
    rs_fr_by_rs = get!(() -> indexby(rs_fr, (1, 2)), tm.cache, "RS_FR/rs")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    coef_ptran = gparam(tm, "COEF_PTRAN")
    rtcs_fr = gparam(tm, "RTCS_FR")
    rtp_ffcx = gparam(tm, "RTP_FFCX")
    rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5)
    prc_vint = gset(tm, "PRC_VINT")
    for (_, _, _, cg3, com2) in get(fs_emit_by_rpc, (r, p, c), NO5)
        for (_, _, all_ts) in get(rs_fr_by_rs, (r, ts), NO3)
            # $(RS_FR(R,%3,ALL_TS)*RTPCS_VARF(R,%5,%4,COM2,ALL_TS)): RS_FR present, VARF member.
            (r, t, p, com2, all_ts) in rtpcs_varf || continue
            shp3 = GNum(1.0)
            if mode != "T"
                ffcx = gv(rtp_ffcx, (r, v, t, p, cg3, c))
                shp3 = 1 + (mode == "V" ? ffcx : gif(ffcx, (r, p) in prc_vint))
            end
            shp3 = shp3 * (1 + gv(rtp_ffcs, (r, vnt, p, cg3, c)))
            k = coef * (gv(coef_ptran, (r, vnt, p, cg3, com2, c, all_ts)) * shp3 *
                        gv(rs_fr, (r, ts, all_ts)) * (1 + gv(rtcs_fr, (r, t, com2, ts, all_ts))))
            addterm!(expr, k, tm, "VAR_FLO", r, vnt, t, p, com2, all_ts; at)
        end
    end
    return expr
end

"""
    cal_red!(expr, tm, coef, r, v, t, p, c, ts; mode="") -> expr

Add `coef` times the flow of commodity `c` in timeslice `ts` of process `p`
(period `t`, vintage `v`) to `expr`, as cal_red.red expands it under
%REDUCE% YES (pp_reduce.red L58-59), with %1 = c, %2 = COM, %3 = ts,
%4 = p, %5 = t, %6 = '' and `mode` = %7:

    ( ( VAR_FLO(R,%VNT%,%5,%4,%1,%3)\$(NOT RPC_EMIS(R,%4,%1))
        + SUM((FS_EMIT(R,%4,%1,CG1,COM2),ALL_TS)\$(RTPCS_VARF(R,%5,%4,COM2,ALL_TS)\$RS_FR(R,%3,ALL_TS)),
            ( VAR_FLO(R,%VNT%,%5,%4,COM2,ALL_TS)\$(NOT RPC_ACT(R,%4,COM2)+RPC_FFUNC(R,%4,COM2))
              + (VAR_ACT(R,%VNT%,%5,%4,ALL_TS)*PRC_ACTFLO(R,%VNT%,%4,COM2))\$RPC_ACT(R,%4,COM2)
              + SUM((RPC_ACT(R,%4,%2),PRC_TS2(R,%4,S2))\$RS_FR(R,ALL_TS,S2),
                    (VAR_ACT(R,%VNT%,%5,%4,S2) * ACT_FLO(R,%VNT%,%4,COM2,ALL_TS)%SHP1%) *
                    RS_FR(R,ALL_TS,S2)*(1+RTCS_FR(R,%5,%2,ALL_TS,S2)))\$RPC_FFUNC(R,%4,COM2)
            ) * COEF_PTRAN(R,%VNT%,%4,CG1,COM2,%1,ALL_TS)%SHP3% * RS_FR(R,%3,ALL_TS)*(1+RTCS_FR(R,%5,COM2,%3,ALL_TS))
        )\$RPC_EMIS(R,%4,%1)
      )\$(NOT RPC_ACT(R,%4,%1)+RPC_FFUNC(R,%4,%1))
      + (VAR_ACT(R,%VNT%,%5,%4,%3)*PRC_ACTFLO(R,%VNT%,%4,%1))\$RPC_ACT(R,%4,%1)
      + SUM((RPC_ACT(R,%4,%2),PRC_TS2(R,%4,S2))\$RS_FR(R,%3,S2),
            (VAR_ACT(R,%VNT%,%5,%4,S2) * ACT_FLO(R,%VNT%,%4,%1,%3)%SHP2%) *
            RS_FR(R,%3,S2)*(1+RTCS_FR(R,%5,%2,%3,S2)))\$RPC_FFUNC(R,%4,%1) )

`NOT a + b` is `NOT (a + b)` (G37). %2 = COM is an alias of COM, so the
SUM over RPC_ACT(R,%4,%2) skips its ACTCG members (pp_reduce.red L87; G27).
%SHP1%, %SHP2%, %SHP3% are the shape factors of (%PGPRIM%,COM2),
(%PGPRIM%,%1) and (CG1,%1): for `mode` "" (general case) %VNT% = V and
`*(1+RTP_FFCX(R,V,T,P,CG,C)\$PRC_VINT(R,P))`, for "V" the same without the
`\$PRC_VINT`, for "T" %VNT% = %5 and no RTP_FFCX factor; each times
`(1+RTP_FFCS(R,%VNT%,P,CG,C))` when RTP_FFCS is DEFINED (L18-21). %8, %9 and
%10 (cal_fflo.mod's SUM over the vintages and multiplier) wrap every term
alike, so the caller sums over the vintages and passes the multiplier in
`coef`.

`at` is passed to `addterm!` for every variable (see `cal_nored!`):
`%VAR%_FLO%6(... %SOW%)` and `%VAR%_ACT%6(... %SOW%)`, cal_red.red L29, L36,
L39, L43, L52 and L56.

GAMS: cal_red.red L15-56, v4.9.7 (macro defaults from setglobs.gms
L348-353: %VAR% -> VAR, %SOW% -> '', %SHFF% -> 1+RTP_FFC).
"""
function cal_red!(expr::JuMP.AffExpr, tm::TimesModel, coef::GNum,
                  r::String, v::String, t::String, p::String, c::String, ts::String;
                  mode::AbstractString="", at::Union{Nothing,AbstractString}=nothing)
    mode in ("", "T", "V") || throw(ArgumentError("cal_red mode (%7) must be '', T or V, got $mode"))
    iszero(coef) && return expr
    return cal_red!(expr, tm, cal_red_context(tm), coef, r, v, t, p, c, ts, mode, at)
end

"The sets, parameters and incidence maps `cal_red!` reads, built once per model (untyped out of `tm.cache`)."
function cal_red_context(tm::TimesModel)
    get!(tm.cache, "CAL_RED") do
        pg = uppercase(strip(gswitch(tm, "PGPRIM", "'ACT'"), ['\'', '"']))      # initmty.mod L138
        cgk = gset(tm, "COM_GRP").keys
        i = findfirst(k -> uppercase(k[1]) == pg, cgk)
        com = Set(k[1] for k in gset(tm, "COM").keys)
        act_of = Dict{NTuple{2,String},Vector{String}}()                         # RPC_ACT(R,P,COM), COM a commodity
        foreach(k -> k[3] in com && push!(get!(() -> String[], act_of, (k[1], k[2])), k[3]), gset(tm, "RPC_ACT").keys)
        (; pgl = i === nothing ? pg : cgk[i][1],
           rpc_act = gset(tm, "RPC_ACT"), rpc_ffunc = gset(tm, "RPC_FFUNC"), rpc_emis = gset(tm, "RPC_EMIS"),
           act_of, ts2_of = indexby(gset(tm, "PRC_TS2"), (1, 2)),
           fs_emit_of = indexby(gset(tm, "FS_EMIT"), (1, 2, 3)),
           rs_fr = gparam(tm, "RS_FR"), rs_fr_of = indexby(gparam(tm, "RS_FR"), (1, 2)),
           rtpcs_varf = gset(tm, "RTPCS_VARF"), coef_ptran = gparam(tm, "COEF_PTRAN"), rtcs_fr = gparam(tm, "RTCS_FR"),
           prc_actflo = gparam(tm, "PRC_ACTFLO"), act_flo = gparam(tm, "ACT_FLO"),
           rtp_ffcx = gparam(tm, "RTP_FFCX"), rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5), prc_vint = gset(tm, "PRC_VINT"))
    end
end

# `cal_red!` with the context `x` as a typed argument (a function barrier, as for `combal_context`:
# Julia compiles this method for the context's concrete type; Phase 2, change 3), after the outer
# method's checks. GAMS: cal_red.red L15-56, v4.9.7.
function cal_red!(expr::JuMP.AffExpr, tm::TimesModel, x::NamedTuple, coef::GNum,
                  r::String, v::String, t::String, p::String, c::String, ts::String,
                  mode::AbstractString, at::Union{Nothing,AbstractString})
    vnt = mode == "T" ? t : v
    shp(cg, cc) = (mode == "T" ? GNum(1.0) :
                   1 + (mode == "V" ? gv(x.rtp_ffcx, (r, v, t, p, cg, cc)) : gif(gv(x.rtp_ffcx, (r, v, t, p, cg, cc)), (r, p) in x.prc_vint))) *
                  (1 + gv(x.rtp_ffcs, (r, vnt, p, cg, cc)))
    # SUM((RPC_ACT(R,P,%2),PRC_TS2(R,P,S2))$RS_FR(R,tsx,S2), VAR_ACT(S2) * af * RS_FR(R,tsx,S2)*(1+RTCS_FR(R,T,%2,tsx,S2)))
    function ffunc!(w::GNum, af::GNum, tsx::String)
        for com in get(x.act_of, (r, p), NO_LABELS), (_, _, s2) in get(x.ts2_of, (r, p), NO3)
            haskey(x.rs_fr.values, (r, tsx, s2)) || continue
            k = w * (af * gv(x.rs_fr, (r, tsx, s2)) * (1 + gv(x.rtcs_fr, (r, t, com, tsx, s2))))
            addterm!(expr, k, tm, "VAR_ACT", r, vnt, t, p, s2; at)
        end
    end
    act, ffn = (r, p, c) in x.rpc_act, (r, p, c) in x.rpc_ffunc
    if !(act || ffn)
        if !((r, p, c) in x.rpc_emis)
            addterm!(expr, coef, tm, "VAR_FLO", r, vnt, t, p, c, ts; at)
        else
            # Emission flow = source flow (itself perhaps substituted) * emission factor (L29-42).
            for (_, _, _, cg1, com2) in get(x.fs_emit_of, (r, p, c), NO5)
                for (_, _, all_ts) in get(x.rs_fr_of, (r, ts), NO3)
                    (r, t, p, com2, all_ts) in x.rtpcs_varf || continue
                    w = coef * (gv(x.coef_ptran, (r, vnt, p, cg1, com2, c, all_ts)) * shp(cg1, c) *
                                gv(x.rs_fr, (r, ts, all_ts)) * (1 + gv(x.rtcs_fr, (r, t, com2, ts, all_ts))))
                    a2, f2 = (r, p, com2) in x.rpc_act, (r, p, com2) in x.rpc_ffunc
                    (a2 || f2) || addterm!(expr, w, tm, "VAR_FLO", r, vnt, t, p, com2, all_ts; at)
                    a2 && addterm!(expr, w * gv(x.prc_actflo, (r, vnt, p, com2)), tm, "VAR_ACT", r, vnt, t, p, all_ts; at)
                    f2 && ffunc!(w, gv(x.act_flo, (r, vnt, p, com2, all_ts)) * shp(x.pgl, com2), all_ts)
                end
            end
        end
    end
    # Flow variable equals activity variable (L46-47), or a function of it (L49-54).
    act && addterm!(expr, coef * gv(x.prc_actflo, (r, vnt, p, c)), tm, "VAR_ACT", r, vnt, t, p, ts; at)
    ffn && ffunc!(coef, gv(x.act_flo, (r, vnt, p, c, ts)) * shp(x.pgl, c), ts)
    return expr
end
