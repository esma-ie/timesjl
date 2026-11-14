# coef_csv.mod: the simulated vintages of the processes in PRC_SIMV ("simplified vintaging"), the
# capacity transfer COEF_CSV from true vintages to them, RTP_VINTYR rewritten to the simulated
# vintages, and AFS split into AFS and AFSV.
#
# GAMS: coef_csv.mod L11-74, v4.9.7, included from eqmain.mod L67 after the three eqcapact.mod
# includes: `$IF DEFINED PRC_SIMV $INCLUDE coef_csv.mod`. PRC_SIMV is DEFINED with PRC_SIMV data or
# %VINTOPT% 2 (initmty.mod L80 declares it without data; fillvint.gms L15 assigns it), as in
# `fillvint_init!` and `ppmain_life!`. L75-77 include eqcapvac.mod three times (eqcapvac.jl).
#
# T and TT are MILESTONYR, LL is ALLYEAR, V is MODLYEAR. %TRIVINT% is 6 unless set (L21).
#
# What the file does, for a simulated process (R,P) and a period T:
# - L24-39: the simulated vintages are marked in COEF_CAP(R,year,T,P) with alternating signs: the
#   year MY_ARRAY(TT) = YEARVAL(TT)-LEAD(TT) of the first vintage TT still alive in T (PRC_YMIN), and,
#   when T is far enough from it (%TRIVINT%), the milestone year in between that maximises the
#   product of the distances to both ends; L42 adds T itself.
# - L44: a true vintage TT that is a marked year is its own simulated vintage (COEF_CSV = 1).
# - L48-50: the past investments (PASTMILE) go to one simulated vintage, the year MIYR_1-LEAD.
# - L52-63: the other true vintages are shared between the two neighbouring simulated vintages, by
#   PASTSUM, the effective average vintage year.
# - L65: COEF_CPT is multiplied in. L68-72: RTP_VINTYR of the simulated processes becomes the
#   simulated vintages with a COEF_CSV entry. L74: their AFS entries move to AFSV.
#
# GAMS 54.6.1 executes L48 `OPTION FIL < T` with T an alias (of MILESTONYR) as an assignment of the
# EMPTY set (checked 14 Nov 2026 on a scratch model: the projection of the set under its own name
# gives its members, under its alias none). So FIL holds the one year MIYR_1-LEAD: YK1 and VTV
# stay empty, L60-63 share nothing, and L65 multiplies COEF_CPT only into the entries of that one
# simulated vintage. A true vintage that is not itself a simulated vintage then gives no capacity
# to any CAPVAC row. The translation follows GAMS as it runs (docs/discrepancies.md, G60 and D36); the
# statements L52-63 are translated as written and act on the FIL that GAMS has.

"`\$IF DEFINED PRC_SIMV` (eqmain.mod L67, mod_equa.mod L74): PRC_SIMV data, or %VINTOPT% 2."
simv_defined(tm::TimesModel) =
    !isempty(gset_opt(tm.data, "PRC_SIMV", 2)) || strip(gswitch(tm, "VINTOPT", "")) == "2"

"""
    coef_csv_symbols(tm) -> Vector{String}

The sets and parameters coef_csv! settles.
"""
coef_csv_symbols(tm) = ["MY_ARRAY", "PRC_YMIN", "PRC_SIMV", "MY_FIL2", "COEF_CSV", "FIL", "VTV", "PASTSUM", "COEF_CAP",
                        "RTP_VINTYR", "AFSV", "MY_F", "MY_FYEAR", "FIRST_VAL"]

"""
    coef_csv!(tm, afs) -> afs

The data statements of coef_csv.mod, on `afs`, the AFS set eqcapact.mod L20 has just built
(`eqmain_prep!`); the entries of the simulated processes leave it for AFSV.

    MY_ARRAY(T) = YEARVAL(T)-LEAD(T);                                                          (L24)
    OPTION CLEAR=PRC_YMIN;
    PRC_SIMV(RP)\$RP_UPL(RP,'FX')=NO;                                                           (L27)
    LOOP(T(LL), MY_F = YEARVAL(T); Z = MIN(B(T),YEARVAL(T)-FLOOR(LEAD(T)/2));
      PRC_YMIN(PRC_SIMV(R,P))\$RTP_VARA(R,T,P) =
        SMIN(RTP_CPTYR(R,TT,T,P)\$(MY_ARRAY(TT)+NCAP_TLIFE(R,TT,P)>Z),MY_ARRAY(TT));             (L30)
      LOOP(PRC_SIMV(R,P)\$RTP_VARA(R,T,P), MY_FYEAR = PRC_YMIN(R,P);
       IF(MY_FYEAR NE INF, F = MY_FYEAR-0.5; Z = MY_F-0.5;
         FIRST_VAL = (%TRIVINT%-0.5)*(%TRIVINT%+0.5);
         MY_FIL2(TT)= (YEARVAL(TT)-F)*(Z-YEARVAL(TT))\$RTP(R,TT,P); Z = SMAX(TT,MY_FIL2(TT));    (L35)
         IF(Z > FIRST_VAL, Z = SMIN(TT\$(MY_FIL2(TT) EQ Z),YEARVAL(TT));
              COEF_CAP(R,LL+(Z-MY_F),T,P) = -1;
              COEF_CAP(R,LL+(MY_FYEAR-MY_F),T,P) =  1;
         ELSE COEF_CAP(R,LL+(MY_FYEAR-MY_F),T,P) = -1;))));                                    (L39)
    COEF_CAP(R,T,T,P)\$(RTP_VARA(R,T,P)\$PRC_SIMV(R,P)) = 1;                                     (L42)
    COEF_CSV(RTP_CPTYR(R,TT,T,P),TT)\$COEF_CAP(R,TT,T,P) = 1;                                   (L44)
    OPTION CLEAR=YK1;
    IF(CARD(PRC_SIMV),
     LOOP(MIYR_1(LL), Z = LEAD(LL); OPTION FIL < T; FIL(LL-Z) = YES;                           (L48)
      COEF_CSV(RTP_CPTYR(R,PASTMILE,T,P),LL-Z)\$(PRC_SIMV(R,P)*NCAP_PASTI(R,PASTMILE,P)) = 1);  (L50)
     YK1(FIL,V)\$((NOT SAMEAS(FIL,V))\$FIL(V)) = YES;                                            (L52)
     VTV(YK1(FIL,V),T)\$((YEARVAL(T)-YEARVAL(FIL)-.5)*(YEARVAL(V)-YEARVAL(T)+.5) > 0) = YES;    (L53)
     PASTSUM(RTP(R,T,P))\$PRC_SIMV(R,P) = MIN(M(T),FLOOR(MAX(YEARVAL(T)-(LEAD(T)-1)/2,
       B(T)+MAX(NCAP_ILED(RTP),(D(T)+NCAP_ILED(RTP)-NCAP_TLIFE(RTP))/2))+0.5)); );             (L55-57)
    LOOP(YK1(LL,FIL), Z = YEARVAL(LL); F = YEARVAL(FIL);
     COEF_CSV(RTP_CPTYR(R,TT,T,P),FIL)\$((COEF_CAP(R,LL,T,P)*COEF_CAP(R,FIL,T,P) < 0)\$VTV(LL,FIL,TT))
       = (PASTSUM(R,TT,P)-Z)/(F-Z));                                                           (L60-63)
    COEF_CSV(RTP_CPTYR(R,V,T,P),FIL)\$PRC_SIMV(R,P) = COEF_CSV(R,V,T,P,FIL)*COEF_CPT(R,V,T,P);  (L65)
    OPTION CLEAR=YK1,CLEAR=VTV,CLEAR=PASTSUM;
    OPTION COEF_CAP < COEF_CSV;                                                                (L69)
    RTP_VINTYR(R,V,T,P)\$PRC_SIMV(R,P) = NO;
    RTP_VINTYR(R,V,T,P)\$COEF_CAP(R,V,T,P) = YES;                                               (L71)
    OPTION CLEAR=COEF_CAP;
    AFSV(AFS(R,T,P,S,BD))\$=PRC_SIMV(R,P); AFS(AFSV)=NO;                                        (L74)

- `LL+(n)` with LL the period T is the year n places after T on ALLYEAR; a non-integer n is rounded
  as GAMS rounds a lead (G29), and a year outside ALLYEAR takes no assignment.
- L35: the `\$RTP` makes MY_FIL2 zero for a milestone year that is not in RTP, and the SMAX runs
  over every TT, so a zero is in the maximum.
- L48: `OPTION FIL < T` leaves FIL empty (file header), then the year MIYR_1-LEAD joins.
- L69: COEF_CAP(R,ALLYEAR,LL,P) < COEF_CSV(R,ALLYEAR,LL,P,ALLYEAR) matches P and LL, and COEF_CAP's
  ALLYEAR with the last index of COEF_CSV, the simulated vintage: the sum over the true vintages
  (checked on demo12_capvac: RTP_VINTYR holds the simulated vintages).
- The scratch MY_ARRAY, PRC_YMIN, MY_FIL2, FIL, MY_F, MY_FYEAR, F, Z and FIRST_VAL stay as the last
  pass leaves them; YK1, VTV, PASTSUM and COEF_CAP end empty.

GAMS: coef_csv.mod L24-74, v4.9.7.
"""
function coef_csv!(tm::TimesModel, afs::Set{NTuple{5,String}})
    d = tm.data
    S(name, n) = gset_opt(d, name, n)
    P(name, n) = gparam_opt(d, name, n)
    ax = YearAxis(tm)
    yval(y) = ax.yearval[y]
    tlist = [k[1] for k in S("MILESTONYR", 1).keys]                         # T, TT
    tmem = Set(tlist)
    modlyear = S("MODLYEAR", 1)                                             # V
    LEAD, B, D, M = P("LEAD", 1), P("B", 1), P("D", 1), P("M", 1)
    no4 = NTuple{4,String}[]

    # L24: MY_ARRAY(T) = YEARVAL(T)-LEAD(T)
    my_array = gvalues(tm, "MY_ARRAY", 1)
    for t in tlist
        gassign!(my_array, (t,), yval(t) - gv(LEAD, (t,)).v)
    end
    gput!(tm, "MY_ARRAY", my_array)

    # L26-27: OPTION CLEAR=PRC_YMIN; PRC_SIMV(RP)$RP_UPL(RP,'FX')=NO
    prc_ymin = Dict{NTuple{2,String},Float64}()
    rp_upl = S("RP_UPL", 3)
    rp = S("RP", 2)
    simv = filter(k -> !(k in rp && (k[1], k[2], "FX") in rp_upl), gmembers(tm, "PRC_SIMV", 2))
    gput!(tm, "PRC_SIMV", simv)
    simv_keys = gams_sort!(collect(simv), d)

    # L28-39: the marks of the simulated vintages
    rtp_vara, rtp = S("RTP_VARA", 3), S("RTP", 3)
    rtp_cptyr = S("RTP_CPTYR", 4)
    cptyr_of = indexby(rtp_cptyr, (1, 3, 4))                                # (r,t,p) -> RTP_CPTYR(r,v,t,p)
    tlife = P("NCAP_TLIFE", 3)
    coef_cap = gvalues(tm, "COEF_CAP", 4)
    my_fil2 = gvalues(tm, "MY_FIL2", 1)
    trivint = parse(Float64, strip(gswitch(tm, "TRIVINT", "6")))            # L21
    sc = Dict{String,Float64}()                                             # the scalars this file assigns
    # COEF_CAP(R,LL+(n),T,P) = x, LL the period T
    function mark!(r, t, p, n, x)
        y = lead(ax, t, glead(n))
        y === nothing || gassign!(coef_cap, (r, y, t, p), x)
    end
    for t in tlist                                                          # LOOP(T(LL), ...)
        sc["MY_F"] = my_f = yval(t)
        sc["Z"] = z0 = min(gv(B, (t,)).v, yval(t) - floor(gv(LEAD, (t,)).v / 2))
        for (r, p) in simv_keys                                             # L30
            (r, t, p) in rtp_vara || continue
            ymin = Inf                                                      # SMIN over nothing is +INF
            for (_, tt, _, _) in get(cptyr_of, (r, t, p), no4)
                tt in tmem || continue
                a = gv(my_array, (tt,)).v
                a + gv(tlife, (r, tt, p)).v > z0 && (ymin = min(ymin, a))
            end
            gassign!(prc_ymin, (r, p), ymin)
        end
        for (r, p) in simv_keys                                             # L31-39
            (r, t, p) in rtp_vara || continue
            sc["MY_FYEAR"] = my_fyear = gv(prc_ymin, (r, p)).v
            my_fyear == Inf && continue
            sc["F"] = f = my_fyear - 0.5
            z = my_f - 0.5
            sc["FIRST_VAL"] = first_val = (trivint - 0.5) * (trivint + 0.5)
            zmax = -Inf
            for tt in tlist                                                 # L35
                x = (r, tt, p) in rtp ? (yval(tt) - f) * (z - yval(tt)) : 0.0
                gassign!(my_fil2, (tt,), x)
                zmax = max(zmax, x)
            end
            sc["Z"] = z = zmax
            if z > first_val
                sc["Z"] = z = minimum(yval(tt) for tt in tlist if gv(my_fil2, (tt,)).v == z)
                mark!(r, t, p, z - my_f, -1.0)
                mark!(r, t, p, my_fyear - my_f, 1.0)
            else
                mark!(r, t, p, my_fyear - my_f, -1.0)
            end
        end
    end
    gput!(tm, "PRC_YMIN", prc_ymin); gput!(tm, "MY_FIL2", my_fil2)

    # L42: COEF_CAP(R,T,T,P)$(RTP_VARA(R,T,P)$PRC_SIMV(R,P)) = 1
    for (r, p) in simv_keys, t in tlist
        (r, t, p) in rtp_vara && (coef_cap[(r, t, t, p)] = 1.0)
    end
    # L44: COEF_CSV(RTP_CPTYR(R,TT,T,P),TT)$COEF_CAP(R,TT,T,P) = 1
    coef_csv = gvalues(tm, "COEF_CSV", 5)
    cap_rtp = Set((k[1], k[3], k[4]) for k in keys(coef_cap))               # (r,t,p) with a COEF_CAP entry
    cptyr_cap = [k for k in rtp_cptyr.keys if (k[1], k[3], k[4]) in cap_rtp && k[2] in tmem && k[3] in tmem]
    for (r, tt, t, p) in cptyr_cap
        haskey(coef_cap, (r, tt, t, p)) && (coef_csv[(r, tt, t, p, tt)] = 1.0)
    end

    # L46-57
    yk1 = Set{NTuple{2,String}}()
    vtv = Set{NTuple{3,String}}()
    pastsum = gvalues(tm, "PASTSUM", 3)
    fil = nothing
    if !isempty(simv)
        pasti = P("NCAP_PASTI", 3)
        pastmile = S("PASTMILE", 1)
        for (ll,) in S("MIYR_1", 1).keys                                    # L48-50
            sc["Z"] = z = gv(LEAD, (ll,)).v
            fil = Set{NTuple{1,String}}()                                   # OPTION FIL < T: empty in GAMS 54.6.1 (file header)
            y0 = lead(ax, ll, -glead(z))
            y0 === nothing && continue
            push!(fil, (y0,))                                               # FIL(LL-Z) = YES
            for (r, v, t, p) in rtp_cptyr.keys
                ((v,) in pastmile && t in tmem && (r, p) in simv && haskey(pasti, (r, v, p))) || continue
                coef_csv[(r, v, t, p, y0)] = 1.0
            end
        end
        fil === nothing && (fil = gmembers(tm, "FIL", 1))                   # no MIYR_1: FIL is not assigned
        for (a,) in fil, (b,) in fil                                        # L52
            (a != b && (b,) in modlyear) && push!(yk1, (a, b))
        end
        for (a, b) in yk1, t in tlist                                       # L53
            (yval(t) - yval(a) - 0.5) * (yval(b) - yval(t) + 0.5) > 0 && push!(vtv, (a, b, t))
        end
        iled = P("NCAP_ILED", 3)
        for k in rtp.keys                                                   # L55-56
            (r, t, p) = k
            (t in tmem && (r, p) in simv) || continue
            il = gv(iled, k).v
            x = max(yval(t) - (gv(LEAD, (t,)).v - 1) / 2,
                    gv(B, (t,)).v + max(il, (gv(D, (t,)).v + il - gv(tlife, k).v) / 2))
            gassign!(pastsum, k, min(gv(M, (t,)).v, floor(x + 0.5)))
        end
        gput!(tm, "FIL", fil)
    end

    # L60-63: the shares of the true vintages between two neighbouring simulated vintages
    for (ll, fl) in gams_sort!(collect(yk1), d)
        sc["Z"] = z = yval(ll)
        sc["F"] = f = yval(fl)
        for (r, tt, t, p) in cptyr_cap
            (gv(coef_cap, (r, ll, t, p)).v * gv(coef_cap, (r, fl, t, p)).v < 0 && (ll, fl, tt) in vtv) || continue
            gassign!(coef_csv, (r, tt, t, p, fl), (gv(pastsum, (r, tt, p)).v - z) / (f - z))
        end
    end
    # L65: COEF_CSV(RTP_CPTYR(R,V,T,P),FIL)$PRC_SIMV(R,P) = COEF_CSV(R,V,T,P,FIL)*COEF_CPT(R,V,T,P)
    coef_cpt = P("COEF_CPT", 4)
    filnow = S("FIL", 1)
    for k in collect(keys(coef_csv))
        (r, v, t, p, fl) = k
        ((fl,) in filnow && (r, p) in simv && (r, v, t, p) in rtp_cptyr && (v,) in modlyear && t in tmem) || continue
        gassign!(coef_csv, k, gv(coef_csv, k) * gv(coef_cpt, (r, v, t, p)))
    end
    gput!(tm, "COEF_CSV", coef_csv)

    # L68-72: OPTION CLEAR=YK1,CLEAR=VTV,CLEAR=PASTSUM; COEF_CAP < COEF_CSV; RTP_VINTYR; CLEAR=COEF_CAP
    gput!(tm, "YK1", Set{NTuple{2,String}}()); gput!(tm, "VTV", Set{NTuple{3,String}}())
    gput!(tm, "PASTSUM", Dict{NTuple{3,String},Float64}())
    cap = Dict{NTuple{4,String},GNum}()                                     # COEF_CAP(R,simulated vintage,T,P)
    for k in gams_sort!(collect(keys(coef_csv)), d)
        (r, v, t, p, fl) = k
        cap[(r, fl, t, p)] = get(cap, (r, fl, t, p), GZERO) + gv(coef_csv, k)
    end
    rtp_vintyr = filter(k -> !((k[1], k[4]) in simv && (k[2],) in modlyear && k[3] in tmem), gmembers(tm, "RTP_VINTYR", 4))
    for ((r, v, t, p), x) in cap
        (!iszero(x) && (v,) in modlyear && t in tmem) && push!(rtp_vintyr, (r, v, t, p))
    end
    gput!(tm, "RTP_VINTYR", rtp_vintyr)
    gput!(tm, "COEF_CAP", Dict{NTuple{4,String},Float64}())

    # L74: AFSV(AFS(R,T,P,S,BD))$=PRC_SIMV(R,P); AFS(AFSV)=NO
    afsv = gmembers(tm, "AFSV", 5)
    foreach(k -> (k[1], k[3]) in simv && push!(afsv, k), afs)
    filter!(k -> !(k in afsv), afs)
    gput!(tm, "AFSV", afsv)
    foreach(((n, x),) -> gput_scalar!(tm, n, x), sc)
    return afs
end
