# EQ(l)_INSHR / EQ(l)_OUTSHR: flow shares. A commodity's flow is at least
# (LO), exactly (FX) or at most (UP) its share FLO_SHAR of the flows of its
# group on the same side of the process.
#
# GAMS: eqfloshr.mod L17-42, v4.9.7, included from eqmain.mod L125-127
# (IN) and L132-134 (OUT) as
#   $BATINCLUDE eqfloshr.mod L LO IN   |  E FX IN  |  G UP IN
#   $BATINCLUDE eqfloshr.mod L LO OUT  |  E FX OUT |  G UP OUT
# (%1 = equation type, %2 = bound type, %3 = IN/OUT); declared in
# eqdeclr.mod as EQ(l)_INSHR / EQ(l)_OUTSHR(R,ALLYEAR,ALLYEAR,P,C,CG,S).
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_V_T% -> 'R,V,T' (maindrv.mod L39); %cal_red% -> cal_nored.red,
# or cal_red.red under REDUCE YES (cal_red.jl), used only on the RPG_RED
# branch, which is empty unless the reduction ran (pp_reduce.red) and is not
# parity-checked yet. V = MODLYEAR,
# T = MILESTONYR.

const FLOSHR_VARIANTS = (("L", "LO"), ("E", "FX"), ("G", "UP"))

"""
    eq_floshr!(tm::TimesModel) -> Int

Generate every EQ(l)_INSHR and EQ(l)_OUTSHR row. Returns the number of rows.

    EQ%1_%3SHR(RTP_VINTYR(R,V,T,P),C,CG,S)\$((RP_STD(R,P)*TOP(R,P,C,'%3')*RTPCS_VARF(R,T,P,C,S))\$FLO_SHAR(R,V,P,C,CG,S,'%2')) ..
      FLO_SHAR(R,V,P,C,CG,S,'%2') *
        (SUM((TOP(R,P,COM,'%3'),RTPCS_VARF(R,T,P,COM,TS))\$COM_GMAP(R,CG,COM),
             VAR_FLO(R,V,T,P,COM,TS)*RS_FR(R,S,TS)*(1+RTCS_FR(R,T,COM,S,TS)))\$(NOT RPG_RED(R,P,CG,'%3')) +
         SUM((TOP(R,P,COM,'%3'),RTPCS_VARF(R,T,P,COM,TS))\$COM_GMAP(R,CG,COM),
             [cal_red COM COM1 TS P T] * RS_FR(R,S,TS)*(1+RTCS_FR(R,T,COM,S,TS)))\$RPG_RED(R,P,CG,'%3')
        )\$(FLO_SHAR(R,V,P,C,CG,S,'%2') > 0)
      =%1=
      VAR_FLO(R,V,T,P,C,S)\$(NOT RPG_RED(R,P,CG,'%3')) + ([cal_red C COM S P T])\$RPG_RED(R,P,CG,'%3');

A share of EPS (or below zero) leaves the group sum out (`\$(FLO_SHAR > 0)`,
EPS comparing as 0, docs/discrepancies.md G12), so the row reads
`0 =%1= VAR_FLO(...)`.

The SOW tags (sow_tags.jl): the row is `%EQ%%1_%3SHR(... %SWT%)` (L17); every
term is `%VAR%_FLO(... %SOW%)` (L24, L38, and %cal_red%).

GAMS: eqfloshr.mod L17-42 with eqmain.mod L125-134, v4.9.7.
"""
function eq_floshr!(tm::TimesModel)
    flo_shar = gparam(tm, "FLO_SHAR")
    isempty(flo_shar) && return 0
    modlyear = gset(tm, "MODLYEAR")
    tx = eq_periods(tm)   # %R_T%, %TX%: SUBT in a stepped run (maindrv.mod L38-40)
    rp_std = gset(tm, "RP_STD")
    top = gset(tm, "TOP")
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    rpg_red = gset_opt(tm.data, "RPG_RED", 4)
    com_gmap = gset(tm, "COM_GMAP")
    rs_fr = gparam(tm, "RS_FR")
    rtcs_fr = gparam(tm, "RTCS_FR")
    t_of_rvp = indexby(gset(tm, "RTP_VINTYR"), (1, 2, 4))   # (r,v,p) -> RTP_VINTYR(r,v,t,p)
    top_of_rpio = indexby(top, (1, 2, 4))                   # (r,p,io) -> TOP(r,p,com,io)
    varf_of_rtpc = indexby(rtpcs_varf, (1, 2, 3, 4))         # (r,t,p,c) -> (r,t,p,c,ts)
    no4 = NTuple{4,String}[]
    no5 = NTuple{5,String}[]

    n = 0
    for io in ("IN", "OUT"), (eqtype, bd) in FLOSHR_VARIANTS
        name = "EQ$(eqtype)_$(io)SHR"
        rows = NTuple{7,String}[]
        for (r, v, p, c, cg, s, b) in flo_shar.keys
            (b == bd && (v,) in modlyear) || continue
            ((r, p) in rp_std && (r, p, c, io) in top) || continue
            for (_, _, t, _) in get(t_of_rvp, (r, v, p), no4)
                ((t,) in tx && (r, t, p, c, s) in rtpcs_varf) || continue
                push!(rows, (r, v, t, p, c, cg, s))
            end
        end
        gams_sort!(rows, tm.data)
        for (r, v, t, p, c, cg, s) in rows
            share = gv(flo_shar, (r, v, p, c, cg, s, bd))
            red = (r, p, cg, io) in rpg_red
            for sow in sw_rows(tm, t)   # %SWT% (eqfloshr.mod L17)
                set_sow!(tm, sow)
                lhs = JuMP.AffExpr(0.0)
                if share.v > 0                                    # $(FLO_SHAR(...) > 0)
                    for (_, _, com, _) in get(top_of_rpio, (r, p, io), no4)
                        (r, cg, com) in com_gmap || continue
                        for (_, _, _, _, ts) in get(varf_of_rtpc, (r, t, p, com), no5)
                            w = gv(rs_fr, (r, s, ts)) * (1 + gv(rtcs_fr, (r, t, com, s, ts)))
                            if !red
                                addterm!(lhs, share * w, tm, "VAR_FLO", r, v, t, p, com, ts)
                            else
                                cal_nored!(lhs, tm, share * w, r, v, t, p, com, ts)
                            end
                        end
                    end
                end
                rhs = JuMP.AffExpr(0.0)
                if !red
                    addterm!(rhs, GNum(1.0), tm, "VAR_FLO", r, v, t, p, c, s)
                else
                    cal_nored!(rhs, tm, GNum(1.0), r, v, t, p, c, s)
                end
                gconstraint!(tm, eqtag(tm, name), swt(tm, (r, v, t, p, c, cg, s), t), eqtype, lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
