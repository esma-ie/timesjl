# Elastic demand (%TIMESED% YES), the linear form: the base prices of an earlier run and the
# preprocessing of TIMES-Micro's demand aggregation (M1.3 change 69, 19 Nov 2026).
#
# GAMS: readbprice.mod L29-45 (maindrv.mod L29), pp_micro.mod L18-52 (PRE; ppmain.mod L749), v4.9.7.
# The base prices come from TIMES.jl's own Arrow folder, not a GDX file (q1, 19 Nov 2026): the
# compile step loads them (`gload_bprice!`, readbprice.mod L11-27), so they are in the input dump as
# in GAMS's.
#
# Not translated (UnportedError): the damage costs of the base run (readbprice.mod L37-45, DAM_ELAST
# with DAM_TVOC data); TIMES-Micro's nonlinear form (pp_micro.mod NLP, %MICRO% YES).

"""
    timesed(tm) -> String

The value of %TIMESED% that maindrv.mod acts on: the run's, `YES` when the run sets %MICRO% YES and
leaves %TIMESED% at its default 0 (L25), `0` under %MACRO% YES (L26; setglobs.gms L339 sets 0).
"""
function timesed(tm)
    t = strip(gswitch(tm, "TIMESED", "0"))
    m = strip(gswitch(tm, "MICRO", ""))
    uppercase(m * t) == "YES0" && (t = "YES")                   # L25: $IFI %MICRO%%TIMESED%==YES0
    uppercase(strip(gswitch(tm, "MACRO", ""))) == "YES" && (t = "0")   # L26
    return t
end

"Whether elastic demand is on: `%TIMESED%==YES`, compared case-exactly as `\$IF` does."
timesed_on(tm) = timesed(tm) == "YES"

"""
    readbprice!(tm) -> tm

The statements of readbprice.mod (maindrv.mod L28-29, when %TIMESED% is neither NO nor 0) after the
base prices are loaded: DEM, FORWARD and FIL, and COM_BPRICE from SOL_BPRICE. When no base prices
were loaded (no file: GAMS's `\$GOTO FINISH` at L19 or L22 skips these lines), nothing is done
(UNCONFIRMED: a file holding no SOL_BPRICE record takes the same path here, while GAMS would run
the statements on an empty SOL_BPRICE).

GAMS: readbprice.mod L29-45, v4.9.7.
"""
function readbprice!(tm)
    t = timesed(tm)
    (uppercase(t) == "NO" || t == "0") && return tm           # maindrv.mod L28-29
    sb = gparam_opt(tm.data, "SOL_BPRICE", 5)
    isempty(sb.keys) && return tm
    tl = [k[1] for k in gset(tm, "MILESTONYR").keys]          # T (initmty.mod L94)
    tset = Set(tl)
    # L29: OPTION DEM < COM_PROJ; L30: DEM(R,C)$COM_TMAP(R,'DEM',C) = YES
    dem = project(gparam_opt(tm.data, "COM_PROJ", 3).keys, (1, 3))
    foreach(k -> k[2] == "DEM" && push!(dem, (k[1], k[3])), gset_opt(tm.data, "COM_TMAP", 3).keys)
    # L32: OPTION FORWARD < SOL_BPRICE (FORWARD(YEAR) takes SOL_BPRICE's YEAR, G26, G45)
    fwd = project(sb.keys, (2,))
    gput!(tm, "FORWARD", fwd)
    #      FIL(T) = PROD(FORWARD(TT),ORD(TT)<ORD(T)): the periods after the last one with a base price
    pos = Dict(x => i for (i, x) in enumerate(tl))
    fpos = [pos[x] for x in tl if (x,) in fwd]
    fil = gmembers(tm, "FIL", 1)
    filter!(k -> !(k[1] in tset), fil)
    foreach(x -> all(p -> p < pos[x], fpos) && push!(fil, (x,)), tl)
    gput!(tm, "FIL", fil)
    # L33: LOOP(FIL(TT(T+1)),COM_BPRICE(R,TT,C,S,CUR) $= SOL_BPRICE(R,T,C,S,CUR))
    cbp = gvalues(tm, "COM_BPRICE", 5)
    by_t = Dict{String,Vector{NTuple{5,String}}}()
    foreach(k -> pushat!(by_t, k[2], k), sb.keys)
    for i in 1:length(tl)-1
        tt = tl[i+1]
        (tt,) in fil || continue
        for k in get(by_t, tl[i], NTuple{5,String}[])
            v = gv(sb, k)
            iszero(v) || gassign!(cbp, (k[1], tt, k[3], k[4], k[5]), v)
        end
    end
    # L34: COM_BPRICE(R,T,C,S,CUR)$DEM(R,C) $= SOL_BPRICE(R,T,C,S,CUR)
    for k in sb.keys
        (k[2] in tset && (k[1], k[3]) in dem) || continue
        v = gv(sb, k)
        iszero(v) || gassign!(cbp, k, v)
    end
    gput!(tm, "COM_BPRICE", cbp)
    gput!(tm, "DEM", Set{NTuple{2,String}}())                 # L35: OPTION CLEAR=DEM
    # L37-45 (under DAM_ELAST): damage costs from the base run's DAM_TVOC; refused when it has data
    any(k -> k[4] == "N", gparam_opt(tm.data, "DAM_TVOC", 4).keys) &&
        throw(UnportedError("readbprice.mod L37-45 (damage costs from the base run: DAM_ELAST with DAM_TVOC)"))
    return tm
end

"""
    pp_micro_pre!(tm) -> tm

TIMES-Micro's preprocessing that %TIMESED% YES runs (ppmain.mod L749, after DEM at L747): the demand
aggregation (MI_DMAS from COM_AGG, RD_AGG, the aggregate's projection and base price), the
elasticities of substitution (MI_ESUB), the reference quantities and prices (DDF_QREF, DDF_PREF),
the shares (RD_SHAR); the components' projections are moved onto their aggregate.

GAMS: pp_micro.mod L18-52, v4.9.7.
"""
function pp_micro_pre!(tm)
    tl = [k[1] for k in gset(tm, "MILESTONYR").keys]
    T(f) = foreach(f, tl)
    rcset = gset(tm, "RC").members
    agg = gvalues(tm, "COM_AGG", 4)
    sb = gparam_opt(tm.data, "SOL_BPRICE", 5)
    # L18: OPTION MI_DMAS<COM_AGG, OBJ_PVT<SOL_BPRICE. `<` pairs the two COM positions right to left (G26):
    #     COM_AGG(R,T,component,aggregate) gives MI_DMAS(R,aggregate,component) (checked with GAMS 54.6.1,
    #     19 Nov 2026); OBJ_PVT(R,YEAR,CUR) from SOL_BPRICE(R,YEAR,C,TS,CUR) (G45)
    mi = project(keys(agg), (1, 4, 3))
    objpvt = project(sb.keys, (1, 2, 5))
    # L19: RD_AGG(RC(R,C))$(DEM(RC)+COM_TMAP(R,'DEM',C))=YES
    dem = gmembers(tm, "DEM", 2)
    tmapdem = Set((k[1], k[3]) for k in gset_opt(tm.data, "COM_TMAP", 3).keys if k[2] == "DEM")
    rdagg = gmembers(tm, "RD_AGG", 2)
    foreach(rc -> (rc in dem || rc in tmapdem) && push!(rdagg, rc), rcset)
    # L20: MI_DMAS(R,C,COM)$(NOT RD_AGG(R,C)*RD_AGG(R,COM)*COM_TSL(R,C,'ANNUAL'))=NO
    tsl = gset_opt(tm.data, "COM_TSL", 3).members
    filter!(k -> (k[1], k[2]) in rdagg && (k[1], k[3]) in rdagg && (k[1], k[2], "ANNUAL") in tsl, mi)
    # L21: DDF_PREF(R,T,C)$DEM(R,C) = SUM((COM_TS(R,C,S),RDCUR(R,CUR)),SOL_BPRICE(R,T,C,S,CUR)*COM_FR(R,T,C,S))
    comts = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(comts, (k[1], k[2]), k[3]), gset(tm, "COM_TS").keys)
    rdcur = Dict{String,Vector{String}}()
    foreach(k -> pushat!(rdcur, k[1], k[2]), gset(tm, "RDCUR").keys)
    cfr = gparam_opt(tm.data, "COM_FR", 4)
    pref = gvalues(tm, "DDF_PREF", 3)
    for (r, c) in gams_sort!(collect(dem), tm.data), t in tl
        x = GZERO
        for s in get(comts, (r, c), String[]), cu in get(rdcur, r, String[])
            x += gv(sb, (r, t, c, s, cu)) * gv(cfr, (r, t, c, s))
        end
        gassign!(pref, (r, t, c), x)
    end
    # L23: MI_DMAS(R,C,COM)$SUM(RPC(RP_FLO(R,P),C),1)=NO
    rpflo = gset(tm, "RP_FLO").members
    flowc = Set((k[1], k[3]) for k in gset(tm, "RPC").keys if (k[1], k[2]) in rpflo)
    filter!(k -> !((k[1], k[2]) in flowc), mi)
    proj = gvalues(tm, "COM_PROJ", 3)
    qref = gvalues(tm, "DDF_QREF", 3)
    # L24 and L34: OPTION RD_AGG<=MI_DMAS; RD_AGG(DEM)=NO; LOOP(MI_DMAS(R,C,COM)$(NOT DEM(R,COM)),RD_AGG(R,C)=NO)
    function aggs()
        a = project(mi, (1, 2))
        setdiff!(a, dem)
        foreach(k -> (k[1], k[3]) in dem || delete!(a, (k[1], k[2])), mi)
        a
    end
    rdagg = aggs()
    mi_of = Dict{NTuple{2,String},Vector{String}}()
    for k in gams_sort!(collect(mi), tm.data)
        pushat!(mi_of, (k[1], k[2]), k[3])
    end
    # L25-35: WHILE(CARD(RD_AGG), ...)
    while !isempty(rdagg)
        union!(dem, rdagg)                                         # DEM(RD_AGG)=YES
        ra = gams_sort!(collect(rdagg), tm.data)
        for (r, c) in ra, t in tl                                  # L27
            num, den = GZERO, GZERO
            for com in get(mi_of, (r, c), String[])
                num += gv(proj, (r, t, com)) * gv(pref, (r, t, com))
                den += gv(proj, (r, t, com))
            end
            gassign!(pref, (r, t, c), num / den)
        end
        for (r, c) in ra, t in tl, com in get(mi_of, (r, c), String[])   # L28
            k = (r, t, com, c)
            iszero(gv(agg, k)) || continue
            p = gv(pref, (r, t, c))
            gassign!(agg, k, GNum(1.0) + (iszero(p) ? GZERO : gv(pref, (r, t, com)) / p - GNum(1.0)))
        end
        for (r, c) in ra, t in tl                                  # L30
            x = GZERO
            foreach(com -> (x += gv(agg, (r, t, com, c)) * gv(proj, (r, t, com))), get(mi_of, (r, c), String[]))
            gassign!(qref, (r, t, c), x)
        end
        for (r, c) in ra, t in tl                                  # L31
            x = GZERO
            foreach(com -> (x += gv(proj, (r, t, com))), get(mi_of, (r, c), String[]))
            gassign!(proj, (r, t, c), x)
        end
        for k in collect(keys(agg))                                # L32 (COM_AGG(R,T,COM,C), C an aggregate)
            ((k[1], k[4]) in rdagg && k[2] in tl) || continue
            v = gv(agg, k)
            iszero(v) || gassign!(agg, k, v * gv(proj, (k[1], k[2], k[4])) / gv(qref, (k[1], k[2], k[4])))
        end
        rdagg = aggs()                                             # L34
    end
    # L36: MI_DMAS(R,C,COM)$(NOT DEM(R,C)*DEM(R,COM))=NO
    filter!(k -> (k[1], k[2]) in dem && (k[1], k[3]) in dem, mi)
    # L37: OPTION RD_AGG<=MI_DMAS; RPCS_VAR(R,P,C,S)$RD_AGG(R,C)=NO
    rdagg = project(mi, (1, 2))
    rpcsvar = gmembers(tm, "RPCS_VAR", 4)
    filter!(k -> !((k[1], k[3]) in rdagg), rpcsvar)
    # L39: MI_ESUB(R,T,C)$RD_AGG(R,C) = ABS(COM_ELAST(R,T,C,'ANNUAL','N'))
    cel = gvalues(tm, "COM_ELAST", 5)
    esub = gvalues(tm, "MI_ESUB", 3)
    for (r, c) in gams_sort!(collect(rdagg), tm.data), t in tl
        x = gv(cel, (r, t, c, "ANNUAL", "N"))
        gassign!(esub, (r, t, c), GNum(abs(x.v), x.eps))
    end
    # L40: COM_ELAST(RTC,S,BDNEQ)$(NOT COM_ELAST(RTC,S,BDNEQ)) $= COM_ELAST(RTC,S,'FX')
    rtc = gset(tm, "RTC").members
    bdneq = [k[1] for k in gset(tm, "BDNEQ").keys]
    for k in collect(keys(cel))
        (k[5] == "FX" && (k[1], k[2], k[3]) in rtc) || continue
        v = gv(cel, k)
        iszero(v) && continue
        for b in bdneq
            haskey(cel, (k[1], k[2], k[3], k[4], b)) || gassign!(cel, (k[1], k[2], k[3], k[4], b), v)
        end
    end
    # L41: LOOP(MI_DMAS(R,COM,C),COM_ELAST(R,T,C,S,BD)$(COM_TS(R,C,S)+ANNUAL(S))=MAX(ABS(COM_ELAST(R,T,C,S,BD)),MI_ESUB(R,T,COM)))
    bd = [k[1] for k in gset(tm, "BD").keys]
    for (r, com, c) in gams_sort!(collect(mi), tm.data), t in tl
        ss = unique([get(comts, (r, c), String[]); "ANNUAL"])
        for s in ss, b in bd
            x = gv(cel, (r, t, c, s, b))
            gassign!(cel, (r, t, c, s, b), gmax(GNum(abs(x.v), x.eps), gv(esub, (r, t, com))))
        end
    end
    # L43: DDF_QREF(R,T,C) $= COM_PROJ(R,T,C)
    for (k, _) in proj
        k[2] in tl || continue
        v = gv(proj, k)
        iszero(v) || gassign!(qref, k, v)
    end
    # L44: DDF_PREF(R,T,C)$RD_AGG(R,C) = SUM(MI_DMAS(R,C,COM),DDF_QREF(R,T,COM)*DDF_PREF(R,T,COM))/DDF_QREF(R,T,C)
    mi_of = Dict{NTuple{2,String},Vector{String}}()
    foreach(k -> pushat!(mi_of, (k[1], k[2]), k[3]), gams_sort!(collect(mi), tm.data))
    for (r, c) in gams_sort!(collect(rdagg), tm.data), t in tl
        x = GZERO
        foreach(com -> (x += gv(qref, (r, t, com)) * gv(pref, (r, t, com))), get(mi_of, (r, c), String[]))
        gassign!(pref, (r, t, c), x / gv(qref, (r, t, c)))
    end
    # L45: COM_BPRICE(R,T,C,ANNUAL,CUR)$(OBJ_PVT(R,T,CUR)$RD_AGG(R,C)) = DDF_PREF(R,T,C)
    cbp = gvalues(tm, "COM_BPRICE", 5)
    for (r, t, cu) in objpvt, (rr, c) in rdagg
        rr == r && gassign!(cbp, (r, t, c, "ANNUAL", cu), gv(pref, (r, t, c)))
    end
    # L46: RD_SHAR(R,T,C,COM)$MI_DMAS(R,C,COM) = DDF_QREF(R,T,COM) / DDF_QREF(R,T,C)
    shar = gvalues(tm, "RD_SHAR", 4)
    for (r, c, com) in mi, t in tl
        gassign!(shar, (r, t, c, com), gv(qref, (r, t, com)) / gv(qref, (r, t, c)))
    end
    # L48: OPTION TRACKC < RD_SHAR (TRACKC(R,C): the components, RD_SHAR's last index, G26)
    trackc = project(keys(shar), (1, 4))
    # L49: COM_PROJ(R,T,C)$TRACKC(R,C)=0
    foreach(k -> (k[1], k[3]) in trackc && k[2] in tl && delete!(proj, k), collect(keys(proj)))
    # L50: COM_BNDNET(RTCS_VARC(R,T,C,S),'UP')$TRACKC(R,C)=EPS
    bnet = gvalues(tm, "COM_BNDNET", 5)
    foreach(k -> (k[1], k[3]) in trackc && gassign!(bnet, (k..., "UP"), GEPS), gset(tm, "RTCS_VARC").keys)
    # L51: RHS_COMPRD(R,T,C,ANNUAL)$=RD_AGG(R,C)
    rhs = gmembers(tm, "RHS_COMPRD", 4)
    foreach(((r, c),) -> foreach(t -> push!(rhs, (r, t, c, "ANNUAL")), tl), rdagg)
    # L52: OPTION CLEAR=TRACKC,CLEAR=OBJ_PVT (TRACKC and OBJ_PVT stay as they were; this file never kept them)
    gput!(tm, "MI_DMAS", mi); gput!(tm, "RD_AGG", rdagg); gput!(tm, "DEM", dem)
    gput!(tm, "DDF_PREF", pref); gput!(tm, "DDF_QREF", qref); gput!(tm, "COM_AGG", agg); gput!(tm, "COM_PROJ", proj)
    gput!(tm, "RPCS_VAR", rpcsvar); gput!(tm, "MI_ESUB", esub); gput!(tm, "COM_ELAST", cel); gput!(tm, "COM_BPRICE", cbp)
    gput!(tm, "RD_SHAR", shar); gput!(tm, "COM_BNDNET", bnet); gput!(tm, "RHS_COMPRD", rhs)
    gput!(tm, "TRACKC", Set{NTuple{2,String}}()); gput!(tm, "OBJ_PVT", Dict{NTuple{3,String},Float64}())
    return tm
end

"""
    bprice_records(tm, marginal) -> Dict{NTuple{5,String},Float64}

The base prices a run leaves for a later elastic demand run: for each demand commodity (DEM) and
balance row, the row's marginal discounted back to its period's money (1/COEF_PVT), in each of the
region's currencies (G_RCUR). `marginal(name, key)` gives the marginal of row `name` (EQG_COMBAL or
EQE_COMBAL) at `key`, or `nothing` when the model has no such row. A zero marginal gives no record;
GAMS writes EPS for a zero marginal of a nonbasic row, which TIMES.jl's duals do not tell apart
(docs/known-differences.md K4).

GAMS: wrtbprice.mod L15-18, v4.9.7.
"""
function bprice_records(tm, marginal)
    pvt = gparam(tm, "COEF_PVT")
    curs = Dict{String,Vector{String}}()
    foreach(k -> pushat!(curs, k[1], k[2]), gset(tm, "G_RCUR").keys)
    dem = gset(tm, "DEM").members
    out = Dict{NTuple{5,String},Float64}()
    for (lim, eq) in (("LO", "EQG_COMBAL"), ("FX", "EQE_COMBAL"))      # L17, then L18
        for (r, t, c, s, l) in gset(tm, "RCS_COMBAL").keys
            (l == lim && (r, c) in dem) || continue
            m = marginal(eq, (r, t, c, s))
            for cu in get(curs, r, String[])
                k = (r, t, c, s, cu)
                v = m === nothing ? GZERO : GNum(1.0) / gv(pvt, (r, t)) * GNum(m)   # DINV(R,T,CUR)*EQx_COMBAL.M
                gassign!(out, k, v)
            end
        end
    end
    return out
end

"""
    write_bprice(tm, dirs; marginal) -> Vector{String}

Write the base prices (`bprice_records`) to each folder in `dirs` as TIMES.jl's Arrow form of
GAMS's `com_bprice.gdx` (a dump with SOL_BPRICE, DAM_COEF, DAM_TVOC and SOL_ACFR, the last three
empty), which a later run with %TIMESED% YES reads (q1, 19 Nov 2026). Refused: the damage
coefficients of DAM_ELAST (L21-25) and SOL_ACFR under %ANNCOST% LEV (L30), which needs the
reports' REG_ACOST (M1.6).

GAMS: wrtbprice.mod L1-34 (maindrv.mod L121-122), v4.9.7.
"""
function write_bprice(tm, dirs; marginal)
    any(k -> k[3] == "N", gparam_opt(tm.data, "DAM_ELAST", 3).keys) &&
        throw(UnportedError("wrtbprice.mod L21-25 (damage coefficients for DAM_ELAST)"))
    uppercase(strip(gswitch(tm, "ANNCOST", ""))) == "LEV" &&
        throw(UnportedError("wrtbprice.mod L30 (SOL_ACFR under %ANNCOST% LEV: REG_ACOST, M1.6)"))
    recs = bprice_records(tm, marginal)
    keys_ = gams_sort!(collect(keys(recs)), tm.data)
    uels = String[]
    seen = Set{String}()
    foreach(k -> foreach(x -> x in seen || (push!(seen, x); push!(uels, x)), k), keys_)
    sym(name, dom, text) = Dict{String,Any}("name" => name, "kind" => "parameter", "type" => "", "dimension" => length(dom),
                                            "domain" => dom, "description" => text, "records" => 0, "file" => nothing)
    for dir in dirs
        mkpath(dir)
        e = sym("SOL_BPRICE", ["REG", "ALLYEAR", "COM", "ALL_TS", "CUR"], "")
        if !isempty(keys_)
            cols = Pair{Symbol,Any}[Symbol("d", i) => String[k[i] for k in keys_] for i in 1:5]
            v = [recs[k] for k in keys_]
            push!(cols, :value => v, :value__sv => Int8[x == 0.0 ? Int8(1) : Int8(0) for x in v])
            Arrow.write(joinpath(dir, "SOL_BPRICE.arrow"), NamedTuple(cols))
            e["records"], e["file"] = length(keys_), "SOL_BPRICE.arrow"
        end
        entries = [e, sym("DAM_COEF", ["REG", "ALLYEAR", "COM", "S"], "Coefficient from commodity to damage"),
                   sym("DAM_TVOC", ["REG", "ALLYEAR", "COM", "LIM"], "Variance of emissions by year"),
                   sym("SOL_ACFR", ["R", "UC_COST", "YEAR"], "")]
        Arrow.write(joinpath(dir, "uels.arrow"), (uel=uels,))
        manifest = Dict{String,Any}("format" => Reference.FORMAT, "format_version" => 1, "content" => "base prices",
                                    "source" => "TIMES.jl: wrtbprice.mod (elastic demand base prices)",
                                    "times_version" => "$(TIMES_GAMS_VERSION) @ $(TIMES_GAMS_COMMIT)",
                                    "uels" => "uels.arrow", "symbols" => entries)
        open(io -> JSON.print(io, manifest, 1), joinpath(dir, "manifest.json"), "w")
    end
    return String.(dirs)
end

"""
    write_bprice_after_solve(tm, out) -> Vector{String}

maindrv.mod L121-122: with %TIMESED% neither 0 nor YES (as written, compared case-exactly), the base
prices of the solved model go to `com_bprice` and to `%GDXPATH%%RUN_NAME%_DP`, both in `out`, the
folder that stands for GAMS's working folder (docs/known-differences.md K4). Nothing otherwise.
"""
function write_bprice_after_solve(tm, out::AbstractString)
    t = timesed(tm)
    (t == "0" || t == "YES") && return String[]
    m = tm.model
    marg(name, k) = (c = constraint_ref(tm, name, k); c === nothing ? nothing : JuMP.dual(c))
    dp = gswitch(tm, "GDXPATH", "") * gswitch(tm, "RUN_NAME", "") * "_DP"
    return write_bprice(tm, [joinpath(out, "com_bprice"), isabspath(dp) ? dp : joinpath(out, dp)]; marginal=marg)
end

"The JuMP row of equation `name` at `key`, or `nothing` when the model has no such row."
function constraint_ref(tm, name::AbstractString, key::Tuple)
    f = get(tm.eqs.families, uppercase(name), nothing)
    f === nothing && return nothing
    return get(f.refs, key, nothing)
end
