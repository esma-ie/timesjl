# EQL_FLOFR / EQE_FLOFR / EQG_FLOFR: the share of a process flow in a timeslice
# (FLO_FR): the flow in the timeslice S against a fraction of the flow of the
# whole year, or of the flow of the parent timeslice of S.
#
# GAMS: eqflofr.mod L15-27, v4.9.7, included from eqmain.mod L118-120 as
#   $BATINCLUDE eqflofr.%1 L "'LO'"
#   $BATINCLUDE eqflofr.%1 E  LNX
#   $BATINCLUDE eqflofr.%1 G "'UP'"
# (%1 = equation type, %2 = the bound types L of the include; LNX = N, FX,
# setglobs.gms L154); declared eqdeclr.mod L74-76; in the model, mod_equa.mod
# L93-95. The equation reads `fraction * reference flow =%1= flow in S`, so
# a lower bound on the share is an =L= row and an upper bound an =G= row.
#
# Macro expansions: %EQ% -> EQ, %VAR% -> VAR, %SOW%/%SWT% -> '' (setglobs.gms
# L348); %R_T% -> 'R,T' (maindrv.mod L39); %cal_red% -> cal_red.red under
# REDUCE YES, cal_nored.red otherwise (pp_reduce.red L58-59). T = MILESTONYR.
#
# The data statements are translated elsewhere: ppmain.mod L992 (pp_lvlbd,
# `ppmain_bnd.jl`) and pp_prelv.vda L99-109 (`pp_prelv.jl`), which write
# - the levelised form of a record at ANNUAL (L100-103): a bound in every
#   timeslice of the flow, times the timeslice's share of the year, and records
#   'N' at the timeslices above the flow's;
# - the records 'N' for the variable of the annual flow (L105-109): 1 at
#   ANNUAL and EPS at the other timeslices above the flow's.
#
# The reading of the equation, each point checked on the crafted case
# demo12_flofr against GAMS's matrix:
# - A record 'N' at S defines a variable for the flow of S: VAR_FLO(S) * N is
#   the sum of the flow variables at and below S (L17, L25-27; IPS = IN, N).
# - A bound (LO, FX, UP) at S, with SL the parent timeslice of S (RS_BELOW1):
#   - where SL has a record 'N' (an EPS counts), the reference flow is the
#     variable of SL or of ANNUAL, each where its record 'N' is above zero (L18;
#     TS_ANN(SL,TS): TS is SL or ANNUAL). An EPS is not above zero, so the EPS
#     records of pp_prelv.vda L109 send the reference to the ANNUAL variable;
#   - otherwise (L19-21) the reference flow is the sum of the flow variables
#     of the year for a value above zero, and of those in the line of SL
#     (RS_FR(R,SL,TS)) for a negative value or an EPS: the share of the parent
#     timeslice.
# - L27, `MIN(0,FLO_FR) -> BD(L)`: `->` is GAMS's logical implication. The
#   right-hand side is dropped only for a record 'N' whose value is negative or
#   EPS (MIN(0,EPS) is EPS, which is true): an 'N' with the value EPS gives the
#   row `EPS * VAR_FLO(S) =E= 0`, which GAMS keeps.
# - L21, `* ABS(FLO_FR)`: the absolute value of an EPS is an EPS.

"""
    eq_flofr!(tm::TimesModel) -> Int

Generate every EQ(l)_FLOFR row, in the order of eqmain.mod L118-120 (L with
LO, E with N and FX, G with UP). Returns the number of rows.

    EQ%1_FLOFR(RTPC(R,T,P,C),S,L(%2))\$(SUM(RPCS_VAR(RP_FLO(R,P),C,TS)\$TS_MAP(R,S,TS),1)\$FLO_FR(R,T,P,C,S,L))..
       SUM(RTP_VINTYR(R,V,T,P),VAR_FLO(R,V,T,P,C,S)\$IPS(L) +
         SUM(RS_BELOW1(R,SL,S),SUM(TS_ANN(SL,TS),VAR_FLO(R,V,T,P,C,TS)*(FLO_FR(RTPC,TS,'N')>0))\$FLO_FR(RTPC,SL,'N') +
           SUM(RTPCS_VARF(RTPC,TS)\$(FLO_FR(RTPC,S,L)>-INF\$RS_FR(R,SL,TS)),
               %cal_red% C COM TS P T
              )\$(NOT FLO_FR(RTPC,SL,'N')))\$BD(L)) * ABS(FLO_FR(RTPC,S,L))
       =%1=
       SUM((RTP_VINTYR(R,V,T,P),RTPCS_VARF(RTPC,TS))\$(STOA(TS)\$TS_MAP(R,S,TS)),
           %cal_red% C COM TS P T
          )\$(MIN(0,FLO_FR(RTPC,S,L))->BD(L));

The flow variables enter through `cal_nored!`, which under REDUCE replaces a
flow variable by what stands for it (`cal_red!`); the variables of an
aggregate flow (L17-18) are VAR_FLO itself. STOA(TS) is zero for ANNUAL only
(timslice.mod L106).

GAMS: eqflofr.mod L15-27 with eqmain.mod L118-120, v4.9.7.
"""
function eq_flofr!(tm::TimesModel)
    flo_fr = gparam(tm, "FLO_FR")
    isempty(flo_fr) && return 0
    milestonyr, rtpc, rp_flo = gset(tm, "MILESTONYR"), gset(tm, "RTPC"), gset(tm, "RP_FLO")
    ts_map, ips, bd = gset(tm, "TS_MAP"), gset(tm, "IPS"), gset(tm, "BD")
    lnx = [k[1] for k in gset(tm, "LNX").keys]
    rs_fr, stoa = gparam(tm, "RS_FR"), gparam(tm, "STOA")
    var_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))           # (r,p,c)   -> RPCS_VAR(r,p,c,ts)
    varf_of_rtpc = indexby(gset(tm, "RTPCS_VARF"), (1, 2, 3, 4))    # (r,t,p,c) -> RTPCS_VARF(r,t,p,c,ts)
    vint_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))        # (r,t,p)   -> RTP_VINTYR(r,v,t,p)
    parent_of = indexby(gset(tm, "RS_BELOW1"), (1, 3))              # (r,s)     -> RS_BELOW1(r,sl,s)
    ann_of = indexby(gset(tm, "TS_ANN"), (1,))                      # (sl,)     -> TS_ANN(sl,ts)
    no2, no3, no4, no5 = NTuple{2,String}[], NTuple{3,String}[], NTuple{4,String}[], NTuple{5,String}[]

    n = 0
    for (eqtype, lims) in (("L", ["LO"]), ("E", lnx), ("G", ["UP"]))            # eqmain.mod L118-120
        name = "EQ$(eqtype)_FLOFR"
        rows = NTuple{6,String}[]
        for (r, t, p, c, s, l) in flo_fr.keys                                   # L15
            l in lims || continue
            ((t,) in milestonyr && (r, t, p, c) in rtpc && (r, p) in rp_flo) || continue
            any(((_, _, _, ts),) -> (r, s, ts) in ts_map, get(var_of_rpc, (r, p, c), no4)) || continue
            push!(rows, (r, t, p, c, s, l))
        end
        gams_sort!(rows, tm.data)
        for (r, t, p, c, s, l) in rows
            f = gv(flo_fr, (r, t, p, c, s, l))
            af = abs(f)                                                         # L21; ABS(EPS) = EPS
            vints = get(vint_of_rtp, (r, t, p), no4)
            varf = get(varf_of_rtpc, (r, t, p, c), no5)
            isbd = (l,) in bd
            lhs = JuMP.AffExpr(0.0)
            for (_, v, _, _) in vints                                           # L17
                (l,) in ips && addterm!(lhs, af, tm, "VAR_FLO", r, v, t, p, c, s)
                isbd || continue                                                # L21, $BD(L)
                for (_, sl, _) in get(parent_of, (r, s), no3)                   # L18
                    if haskey(flo_fr, (r, t, p, c, sl, "N"))                    # $FLO_FR(RTPC,SL,'N'), true for an EPS
                        for (_, ts) in get(ann_of, (sl,), no2)
                            gv(flo_fr, (r, t, p, c, ts, "N")).v > 0 || continue # an EPS is not above zero
                            addterm!(lhs, af, tm, "VAR_FLO", r, v, t, p, c, ts)
                        end
                    else                                                        # L19-21
                        for (_, _, _, _, ts) in varf
                            (haskey(rs_fr, (r, sl, ts)) ? f.v > -Inf : f.v > 0) || continue
                            cal_nored!(lhs, tm, af, r, v, t, p, c, ts)
                        end
                    end
                end
            end
            rhs = JuMP.AffExpr(0.0)
            if iszero(gmin(GZERO, f)) || isbd                                   # L27, MIN(0,FLO_FR) -> BD(L)
                for (_, v, _, _) in vints, (_, _, _, _, ts) in varf             # L25
                    (haskey(stoa, (ts,)) && (r, s, ts) in ts_map) || continue
                    cal_nored!(rhs, tm, GNum(1.0), r, v, t, p, c, ts)           # L26
                end
            end
            gconstraint!(tm, name, (r, t, p, c, s, l), eqtype, lhs, rhs) === nothing || (n += 1)
        end
    end
    return n
end
