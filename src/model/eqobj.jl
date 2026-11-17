# The objective function: EQ_OBJ and its components EQ_OBJINV, EQ_OBJFIX,
# EQ_OBJVAR and EQ_OBJSALV, one component row per region and currency
# (RDCUR).
#
# GAMS: eqobj.mod (L26-28 SUM_OBJ, L75-98 EQ_OBJ), eqobjinv.mod L280-321,
# eqobjfix.mod L182-225, eqobjvar.mod L14-113, eqobsalv.mod L92-140,
# v4.9.7; eqobj.mod is included from eqmain.mod L34 (MACRO not YES).
#
# Scope (M1.1): the equation definitions. The coefficients these files
# compute before their definitions (COR_SALVI, OBJ_DIVI, OBJ_SUMII,
# INVSPRED, OBJSCC, SALV_DEC, OBJ_LINT, ...) are coefficient calculation:
# they are read from the pre-solve dump here and translated in M1.2, where
# each is checked against the same dump. SUM_OBJ (eqobj.mod L26-28) is small
# and computed here; the tests check it against the dump.
#
# Index sets. Several controlling indices are subsets of ALLYEAR, and a
# subset index in a SUM over a multi-dimensional set filters that set's
# members (GAMS 54.6.0, docs/discrepancies.md G8):
# T, TT = MILESTONYR (initmty.mod L94); V = MODLYEAR, PYR = PASTYEAR
# (setglobs.gms L146-147); K = EACHYEAR, Y and Y_EOH are sets of their own
# (coef_obj.mod L12-14); K_EOH (eqobj.mod L14-17); JOT = AGE = LIFE
# (eqobjinv.mod L27, setglobs.gms L283); LL, YEAR = ALLYEAR (initsys.mod L59).
#
# Macros:
# - OBJ_ICOST/ISUB/ITAX/FOM/FSB/FTX/DCOST/DLAGC/ACOST(r,y,p,m) and
#   OBJ_FCOST/FDELV/FTAX(r,y,p,c,s,m) are $macros over the stored OB_*
#   parameters with the year index moved last (coef_obj.mod L156-168; OBMAC is
#   YES on GAMS >= 23), e.g. OBJ_ICOST(r,y,p,m) = OB_ICOST(r,p,m,y).
# - %CTST% (initmty.mod L426-430): '**EPS' for OBJ ALT or LIN, '**0' when
#   OBLONG is YES (OBJ MOD implies OBLONG, L427), '' otherwise. When it is
#   not '', coef_alt.lin is included from eqobjinv.mod L239 and
#   eqobjfix.mod L164 and sets %CAPJD% = `OBJ_JD(R,CUR,K_EOH,JOT)*` and
#   %CAPWD% = `OBJ_WD(R,CUR,K_EOH,JOT,K)*` (coef_alt.lin L91, L107); both are
#   '' otherwise (setglobs.gms L360). OBJ AUTO (reference/templates/scenario.run) is not
#   tested anywhere in v4.9.7 and so behaves like the default.
# - %TPULSE% in eqobjvar.mod (L14-17, last applicable wins): the default
#   PERIODYR(T,Y_EOH) weighted by OBJ_DISC; OBJ ALT adds *OBJ_ALTV(R,T); OBJ
#   LIN uses TPULSEYR/TPULSE; VARCOST LIN uses OBJ_LINT. eqobj.mod L59 turns
#   OBLONG+ALT into OBJ LIN and VARCOST LIN for eqobjvar.mod. eqmain.mod
#   L33's `$SETLOCAL OBJ mod` is not visible in included files
#   (docs/discrepancies.md G7).
# - %VART%/%VARV%/%VARM% -> VAR, %SWS%/%SOW% -> '' (setglobs.gms L348).
#
# Early retirement (VNRET: prepret.dsc OBJFIX and OBSALV, eqobjfix.mod L214,
# eqobsalv.mod L105) is in `objfix_ret!` and `objsalv_ret!` (prepret.jl).
#
# Not translated yet; data or switches that need them raise UnportedError:
# MACRO (eqobj.tm), OBJANN (eqobjann.tm), ETL, elastic demand (RCJ: eqobjels.mod and EQ_OBJ L89-90), damage
# costs (DAM_COST: eqdamage.mod changes OBV and SUM_OBJ), capacity-related flow costs (cal_caps.mod:
# RPC_CAPFLO/NCAP_COM),
# VALIDATE, STAGES.

"""
    objective_switches(tm) -> NamedTuple

The objective-related GAMS switches as the TIMES source derives them from
the run's OBJ, OBLONG and VARCOST (initmty.mod L426-431, eqobj.mod L59).
"""
function objective_switches(tm::TimesModel)
    obj = uppercase(gswitch(tm, "OBJ", ""))
    oblong = uppercase(gswitch(tm, "OBLONG", "")) == "YES" || obj == "MOD"   # initmty.mod L427
    ctst = ""                                                                # L426
    obj == "ALT" && (ctst = "**EPS")                                         # L428
    oblong && (ctst = "**0")                                                 # L429
    obj == "LIN" && (ctst = "**EPS")                                         # L430
    varcost = uppercase(gswitch(tm, "VARCOST", ""))
    oblong && obj == "ALT" && (varcost = "LIN")                              # L431, eqobj.mod L59
    objvar_obj = (oblong && obj == "ALT") ? "LIN" : obj                      # eqobj.mod L59
    return (; obj, oblong, ctst, varcost, objvar_obj)
end

function objective_unported(tm::TimesModel)
    d = tm.data
    yes(name) = uppercase(gswitch(tm, name, "")) == "YES"
    yes("MACRO") && throw(UnportedError("MACRO objective (eqobj.tm, eqmain.mod L35)"))
    yes("OBJANN") && throw(UnportedError("annualized objective (eqobjann.tm, eqobj.mod L70)"))
    yes("ETL") && throw(UnportedError("ETL terms in the objective (eqobjinv.mod L292, eqobsalv.mod L102-103)"))
    yes("VALIDATE") && throw(UnportedError("VALIDATE branches of the objective"))
    yes("STAGES") && throw(UnportedError("stochastic objective (STAGES)"))
    isempty(gparam_opt(d, "DAM_COST", 4)) || throw(UnportedError("damage costs (eqdamage.mod via eqmain.mod L262)"))
    isempty(gset_opt(d, "RCJ", 4)) || throw(UnportedError("elastic demand costs (eqobjels.mod, EQ_OBJ L89-90)"))
    return nothing
end

"""
    sum_obj(tm) -> Dict{Tuple{String,String},Float64}

SUM_OBJ(ITEM,ITEM), the summation weights of the objective components:

    SUM_OBJ(OBV,ITEM) = DIAG(OBV,ITEM);
    SUM_OBJ(OBV('OBJSAL'),OBV) = -1;
    SUM_OBJ(R,'OBJELS') = 1\$SUM(RCJ(R,C,J,BD),1);

In the second statement OBV controls both positions, so only
SUM_OBJ('OBJSAL','OBJSAL') becomes -1. GAMS: eqobj.mod L26-28, v4.9.7.
"""
function sum_obj(tm::TimesModel)
    get!(tm.cache, "SUM_OBJ") do
        s = Dict{Tuple{String,String},Float64}()
        for (o,) in gset(tm, "OBV")
            s[(o, o)] = 1.0
        end
        s[("OBJSAL", "OBJSAL")] = -1.0
        for (r, _, _, _) in gset_opt(tm.data, "RCJ", 4)
            s[(r, "OBJELS")] = 1.0
        end
        s
    end::Dict{Tuple{String,String},Float64}
end

# OBJ_x(r,y,p,m) = OB_x(r,p,m,y) and OBJ_x(r,y,p,c,s,m) = OB_x(r,p,c,s,m,y)
# (coef_obj.mod L157-168).
obmac(p::GamsParam{4}, r, y, pr, m) = gv(p, (r, pr, m, y))
obmac(p::GamsParam{6}, r, y, pr, c, s, m) = gv(p, (r, pr, c, s, m, y))

const NO4 = NTuple{4,String}[]
const NO5 = NTuple{5,String}[]
const NO6 = NTuple{6,String}[]

"Data of the objective definitions, read once per model."
function objective_context(tm::TimesModel)
    get!(tm.cache, "objective") do
        gp(n) = gparam(tm, n)
        gs(n) = gset(tm, n)
        (rdcur = gs("RDCUR"), obv = gs("OBV"),
         # controlling year sets (see the file header)
         t = gs("MILESTONYR"), v = gs("MODLYEAR"), pyr = gs("PASTYEAR"), k = gs("EACHYEAR"),
         y = gs("Y"), y_eoh = gs("Y_EOH"), k_eoh = gs("K_EOH"),
         allyear = [k[1] for k in gs("ALLYEAR").keys],
         allyear_ord = Dict(k[1] => i for (i, k) in enumerate(gs("ALLYEAR").keys)),
         age_ord = Dict(k[1] => i for (i, k) in enumerate(gs("LIFE").keys)),
         obj_disc = gp("OBJ_DISC"), ncap_pasti = gp("NCAP_PASTI"),
         invspred_of = indexby(gs("INVSPRED"), (1, 2)),
         # EQ_OBJINV
         sumii_of_r = indexby(gs("OBJ_SUMII"), (1,)), obj_icur = gs("OBJ_ICUR"),
         ob_icost = gp("OB_ICOST"), ob_itax = gp("OB_ITAX"), ob_isub = gp("OB_ISUB"),
         cor_salvi = gp("COR_SALVI"), obj_divi = gp("OBJ_DIVI"), obj_pasti = gp("OBJ_PASTI"),
         obj_iad = gp("OBJ_IAD"), sumiii_of_r = indexby(gs("OBJ_SUMIII"), (1,)),
         ob_dcc = gp("OB_DCC"), cor_salvd = gp("COR_SALVD"), obj_diviii = gp("OBJ_DIVIII"),
         obj_jd = gp("OBJ_JD"),
         # EQ_OBJFIX
         sumiv_of_r = indexby(gs("OBJ_SUMIV"), (2,)), rtp_ishpr = gs("RTP_ISHPR"),
         obj_life = gp("OBJ_LIFE"), ob_fom = gp("OB_FOM"), ob_ftx = gp("OB_FTX"), ob_fsb = gp("OB_FSB"),
         obj_diviv = gp("OBJ_DIVIV"), obj_wd = gp("OBJ_WD"),
         opyear_of_life = indexby(gs("OPYEAR"), (1,)),
         periodyr_of_y = indexby(gs("PERIODYR"), (2,)), rtp_cpx = gp("RTP_CPX"), ncap_cpx = gp("NCAP_CPX"),
         shape_of = indexby(gs("RTP_SHAPE"), (1, 2, 3, 4)), shape = gp("SHAPE"), multi = gp("MULTI"),
         sumivs_of_r = indexby(gs("OBJ_SUMIVS"), (1,)), ob_dlc = gp("OB_DLC"), obj_2a = gs("OBJ_2A"),
         # EQ_OBJSALV
         sums_of_r = indexby(gs("OBJ_SUMS"), (1,)), sums3_of_r = indexby(gs("OBJ_SUMS3"), (1,)),
         objscc = gp("OBJSCC"), obj_dceoh = gp("OBJ_DCEOH"), salv_dec = gp("SALV_DEC"),
         salv_inv = gp("SALV_INV"), ncap_ocom_of_rvp = indexby(gp("NCAP_OCOM"), (1, 2, 3)),
         ncap_ocom = gp("NCAP_OCOM"), ncap_valu = gp("NCAP_VALU"), com = gs("COM"))
    end
end

"`(VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V))` times `k`, into `expr`."
function add_ncap_or_pasti!(expr, tm, x, k::GNum, r, v, p; pasti::Bool=true)
    (v,) in x.t && addterm!(expr, k, tm, "VAR_NCAP", r, v, p)
    pasti && (v,) in x.pyr && addconst!(expr, k * gv(x.ncap_pasti, (r, v, p)))
    return expr
end

"""
    eq_obj!(tm::TimesModel) -> Int

Generate EQ_OBJ and its four components; returns the number of rows.

    EQ_OBJ .. -objZ + SUM(RDCUR(R,CUR),
                SUM((ITEM,OBV)\$SUM_OBJ(ITEM,OBV), VAR_OBJ(R,OBV,CUR)*SUM_OBJ(ITEM,OBV))) =E= 0;

GAMS: eqobj.mod L26-28 and L75-98; eqobjinv.mod L280-321; eqobjfix.mod
L182-225; eqobjvar.mod L14-113; eqobsalv.mod L92-140, v4.9.7.
"""
function eq_obj!(tm::TimesModel)
    objective_unported(tm)
    n = eq_objinv!(tm) + eq_objfix!(tm) + eq_objvar!(tm) + eq_objsalv!(tm)
    so = sum_obj(tm)
    x = objective_context(tm)
    lhs = JuMP.AffExpr(0.0)
    addterm!(lhs, GNum(-1.0), tm, "OBJZ")
    for (r, cur) in x.rdcur, ((_, obv), w) in sort!(collect(so))
        (obv,) in x.obv || continue
        addterm!(lhs, GNum(w), tm, "VAR_OBJ", r, obv, cur)
    end
    gconstraint!(tm, "EQ_OBJ", (), "E", lhs, JuMP.AffExpr(0.0)) === nothing || (n += 1)
    return n
end

"Right-hand side of a component row: `SUM(OBV,SUM_OBJ(item,OBV)*VAR_OBJ(R,OBV,CUR))`."
function obj_component_rhs(tm, x, r, cur, item)
    rhs = JuMP.AffExpr(0.0)
    for ((i, obv), w) in sort!(collect(sum_obj(tm)))
        i == item && (obv,) in x.obv && addterm!(rhs, GNum(w), tm, "VAR_OBJ", r, obv, cur)
    end
    return rhs
end

"""
    eq_objinv!(tm) -> Int

    EQ_OBJINV(RDCUR(R,CUR)) ..
      SUM(OBJ_SUMII(R,T,P,LIFE,K_EOH,JOT)\$OBJ_ICUR(R,T,P,CUR), %CAPJD%
          SUM(INVSPRED(K_EOH,JOT,Y,K), OBJ_DISC(R,K,CUR) *
              (OBJ_ICOST(R,K,P,CUR) + OBJ_ITAX(R,K,P,CUR) - OBJ_ISUB(R,K,P,CUR))) *
          COR_SALVI(R,T,P,CUR) / OBJ_DIVI(R,T,P) * VAR_NCAP(R,T,P)) +
      SUM(OBJ_SUMII(R,PASTYEAR(V),P,LIFE,K_EOH,JOT)\$OBJ_PASTI(R,V,P,CUR), %CAPJD%
          SUM(INVSPRED(K_EOH,JOT,LL,K), OBJ_DISC(R,K,CUR) * (...)) *
          OBJ_PASTI(R,V,P,CUR) * COR_SALVI(R,V,P,CUR) / OBJ_DIVI(R,V,P))
      + OBJ_IAD(R,CUR) +
      SUM(OBJ_SUMIII(R,V,P,LL,K,Y)\$OBJ_DCOST(R,V,P,CUR),
          OBJ_DISC(R,Y,CUR) * COR_SALVD(R,V,P,CUR) * OBJ_DCOST(R,K,P,CUR) *
          (VAR_NCAP(R,V,P)\$MILESTONYR(V) + OBJ_PASTI(R,V,P,CUR)\$PASTYEAR(V)) / OBJ_DIVIII(R,V,P))
      =E= SUM(OBV,SUM_OBJ('OBJINV',OBV)*VAR_OBJ(R,OBV,CUR));

GAMS: eqobjinv.mod L280-321, v4.9.7 (ETL L292 and STAGES L296-299 refused).
"""
function eq_objinv!(tm::TimesModel)
    x = objective_context(tm)
    capjd = !isempty(objective_switches(tm).ctst)
    n = 0
    for (r, cur) in x.rdcur
        lhs = JuMP.AffExpr(0.0)
        # %CAPJD% SUM(INVSPRED(K_EOH,JOT,<third>,K), OBJ_DISC(R,K,CUR)*(ICOST+ITAX-ISUB)),
        # <third> being Y in the first sum and LL (no filter) in the PASTI sum.
        function spread(k_eoh, jot, p, third)
            s = GZERO
            for (_, _, yy, k) in get(x.invspred_of, (k_eoh, jot), NO4)
                (k,) in x.k && (third === nothing || (yy,) in third) || continue
                s = s + gv(x.obj_disc, (r, k, cur)) *
                        (obmac(x.ob_icost, r, k, p, cur) + obmac(x.ob_itax, r, k, p, cur) - obmac(x.ob_isub, r, k, p, cur))
            end
            return capjd ? gv(x.obj_jd, (r, cur, k_eoh, jot)) * s : s
        end
        for (_, v, p, _, k_eoh, jot) in get(x.sumii_of_r, (r,), NO6)
            (k_eoh,) in x.k_eoh || continue
            if (v,) in x.t && (r, v, p, cur) in x.obj_icur
                c = spread(k_eoh, jot, p, x.y) * gv(x.cor_salvi, (r, v, p, cur)) / gv(x.obj_divi, (r, v, p))
                addterm!(lhs, c, tm, "VAR_NCAP", r, v, p)
            end
            if (v,) in x.v && (v,) in x.pyr && haskey(x.obj_pasti, (r, v, p, cur))     # PASTI charge
                addconst!(lhs, spread(k_eoh, jot, p, nothing) * gv(x.obj_pasti, (r, v, p, cur)) *
                               gv(x.cor_salvi, (r, v, p, cur)) / gv(x.obj_divi, (r, v, p)))
            end
        end
        addconst!(lhs, gv(x.obj_iad, (r, cur)))
        for (_, v, p, _, k, y) in get(x.sumiii_of_r, (r,), NO6)                     # decommissioning
            ((v,) in x.v && (k,) in x.k && (y,) in x.y) || continue
            iszero(obmac(x.ob_dcc, r, v, p, cur)) && continue                         # $OBJ_DCOST(R,V,P,CUR)
            c = gv(x.obj_disc, (r, y, cur)) * gv(x.cor_salvd, (r, v, p, cur)) * obmac(x.ob_dcc, r, k, p, cur)
            divi = gv(x.obj_diviii, (r, v, p))
            divi.v == 0 && throw(DomainError(divi, "OBJ_DIVIII$((r, v, p)) is zero (GAMS: division by zero)"))
            (v,) in x.t && addterm!(lhs, c / divi, tm, "VAR_NCAP", r, v, p)
            (v,) in x.pyr && addconst!(lhs, c * gv(x.obj_pasti, (r, v, p, cur)) / divi)
        end
        gconstraint!(tm, "EQ_OBJINV", (r, cur), "E", lhs, obj_component_rhs(tm, x, r, cur, "OBJINV")) === nothing || (n += 1)
    end
    return n
end

"""
    eq_objfix!(tm) -> Int

    EQ_OBJFIX(RDCUR(R,CUR)) ..
      SUM(OBJ_SUMIV(K_EOH,R,V,P,JOT,LIFE)\$(NOT RTP_ISHPR(R,V,P)),
          SUM(INVSPRED(K_EOH,JOT,LL,K), OBJ_LIFE(LL,R,JOT,LIFE,CUR) * %CAPWD%
              (OBJ_FOM(R,K,P,CUR)+OBJ_FTX(R,K,P,CUR)-OBJ_FSB(R,K,P,CUR))) *
          (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)) / OBJ_DIVIV(R,V,P)) +
      SUM(OBJ_SUMIV(K_EOH,RTP_ISHPR(R,V,P),JOT,LIFE),
          SUM((INVSPRED(K_EOH,JOT,LL,K),OPYEAR(LIFE,AGE),Y_EOH(LL+(ORD(AGE)-1))),
              OBJ_DISC(R,Y_EOH,CUR) * (1+SUM(PERIODYR(T,Y_EOH),RTP_CPX(R,V,P,T))\$NCAP_CPX(R,V,P)) * %CAPWD%
              (OBJ_FOM(R,K,P,CUR) * (1+SUM(RTP_SHAPE(R,V,P,'1',J,JJ),SHAPE(J,AGE)*MULTI(JJ,Y_EOH)-1)) +
               OBJ_FTX(R,K,P,CUR) * (1+SUM(RTP_SHAPE(R,V,P,'2',J,JJ),...)) -
               OBJ_FSB(R,K,P,CUR) * (1+SUM(RTP_SHAPE(R,V,P,'3',J,JJ),...))))
          * (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)) / OBJ_DIVIV(R,V,P)) +
      SUM(OBJ_SUMIVS(R,V,P,K,Y), OBJ_DISC(R,Y,CUR) * OBJ_DLAGC(R,K,P,CUR) *
          (VAR_NCAP(R,V,P)\$MILESTONYR(V) + (NCAP_PASTI(R,V,P)\$PASTYEAR(V))\$OBJ_2A(R,V,P)))
      =E= SUM(OBV,SUM_OBJ('OBJFIX',OBV)*VAR_OBJ(R,OBV,CUR));

`Y_EOH(LL+(ORD(AGE)-1))` is the year ORD(AGE)-1 places after LL in ALLYEAR,
taken only if it is in Y_EOH (G8). GAMS: eqobjfix.mod L182-225, v4.9.7 (the
VALIDATE lines L205-207 are refused; the VNRET hook L214 is `objfix_ret!`,
M1.3 change 20b-4; the shaped
branch for RTP_ISHPR is translated but no test model exercises it yet).
"""
function eq_objfix!(tm::TimesModel)
    x = objective_context(tm)
    capwd = !isempty(objective_switches(tm).ctst)
    wd(r, cur, k_eoh, jot, k) = capwd ? gv(x.obj_wd, (r, cur, k_eoh, jot, k)) : GNum(1.0)
    lead(ll, n) = (i = x.allyear_ord[ll] + n; 1 <= i <= length(x.allyear) ? x.allyear[i] : nothing)
    function shaped(r, v, p, cls, age, y)
        s = GZERO
        for (_, _, _, _, j, jj) in get(x.shape_of, (r, v, p, cls), NO6)
            s = s + (gv(x.shape, (j, age)) * gv(x.multi, (jj, y)) - 1)
        end
        return 1 + s
    end
    n = 0
    for (r, cur) in x.rdcur
        lhs = JuMP.AffExpr(0.0)
        for (k_eoh, _, v, p, jot, life) in get(x.sumiv_of_r, (r,), NO6)
            ((k_eoh,) in x.k_eoh && (v,) in x.v) || continue
            c = GZERO
            for (_, _, ll, k) in get(x.invspred_of, (k_eoh, jot), NO4)
                (k,) in x.k || continue
                w = wd(r, cur, k_eoh, jot, k)
                if !((r, v, p) in x.rtp_ishpr)
                    c = c + gv(x.obj_life, (ll, r, jot, life, cur)) * w *
                            (obmac(x.ob_fom, r, k, p, cur) + obmac(x.ob_ftx, r, k, p, cur) - obmac(x.ob_fsb, r, k, p, cur))
                    continue
                end
                for (_, age) in get(x.opyear_of_life, (life,), NTuple{2,String}[])
                    y = lead(ll, x.age_ord[age] - 1)
                    (y === nothing || !((y,) in x.y_eoh)) && continue
                    cpx = GZERO
                    for (t, _) in get(x.periodyr_of_y, (y,), NTuple{2,String}[])
                        (t,) in x.t && (cpx = cpx + gv(x.rtp_cpx, (r, v, p, t)))
                    end
                    c = c + gv(x.obj_disc, (r, y, cur)) * (1 + gif(cpx, haskey(x.ncap_cpx, (r, v, p)))) * w *
                            (obmac(x.ob_fom, r, k, p, cur) * shaped(r, v, p, "1", age, y) +
                             obmac(x.ob_ftx, r, k, p, cur) * shaped(r, v, p, "2", age, y) -
                             obmac(x.ob_fsb, r, k, p, cur) * shaped(r, v, p, "3", age, y))
                end
            end
            # GAMS divides even when the sum is zero, so a missing OBJ_DIVIV is
            # an error either way (docs/discrepancies.md G9).
            add_ncap_or_pasti!(lhs, tm, x, c / gv(x.obj_diviv, (r, v, p)), r, v, p)
        end
        for (_, v, p, k, y) in get(x.sumivs_of_r, (r,), NO5)        # decommissioning surveillance
            ((v,) in x.v && (k,) in x.k && (y,) in x.y) || continue
            c = gv(x.obj_disc, (r, y, cur)) * obmac(x.ob_dlc, r, k, p, cur)
            add_ncap_or_pasti!(lhs, tm, x, c, r, v, p; pasti=(r, v, p) in x.obj_2a)
        end
        objfix_ret!(lhs, tm, x, r, cur, wd, shaped)                 # L214: prepret.dsc OBJFIX (prepret.jl)
        gconstraint!(tm, "EQ_OBJFIX", (r, cur), "E", lhs, obj_component_rhs(tm, x, r, cur, "OBJFIX")) === nothing || (n += 1)
    end
    return n
end

"""
    tpulse(tm, r, t, cur) -> Vector{Tuple{String,GNum}}

The years and weights of `SUM(%TPULSE% * x(Y_EOH))` in eqobjvar.mod for
period `t`, region `r` and currency `cur` (L14-17; the header of this file
says which variant applies).
"""
function tpulse(tm::TimesModel, r::String, t::String, cur::String)
    tab = get!(tm.cache, "TPULSE/objvar") do
        Dict{NTuple{3,String},Vector{Tuple{String,GNum}}}()
    end::Dict{NTuple{3,String},Vector{Tuple{String,GNum}}}
    get!(tab, (r, t, cur)) do
        sw = objective_switches(tm)
        x = objective_context(tm)
        out = Tuple{String,GNum}[]
        if sw.varcost == "LIN"            # Y_EOH$OBJ_LINT(R,T,Y_EOH,CUR),OBJ_LINT(R,T,Y_EOH,CUR)
            lint = gparam(tm, "OBJ_LINT")
            by = get!(() -> indexby(lint, (1, 2, 4)), tm.cache, "OBJ_LINT/rtc")
            for k in get(by, (r, t, cur), NO4)
                (k[3],) in x.y_eoh && push!(out, (k[3], gv(lint, k)))
            end
        elseif sw.objvar_obj == "LIN"     # TPULSEYR(T,Y_EOH),TPULSE(T,Y_EOH)*OBJ_DISC(R,Y_EOH,CUR)
            tp = gparam(tm, "TPULSE")
            by = get!(() -> indexby(gset(tm, "TPULSEYR"), (1,)), tm.cache, "TPULSEYR/t")
            for (_, y) in get(by, (t,), NTuple{2,String}[])
                (y,) in x.y_eoh && push!(out, (y, gv(tp, (t, y)) * gv(x.obj_disc, (r, y, cur))))
            end
        else                              # PERIODYR(T,Y_EOH),[OBJ_ALTV(R,T)*]OBJ_DISC(R,Y_EOH,CUR)
            by = get!(() -> indexby(gset(tm, "PERIODYR"), (1,)), tm.cache, "PERIODYR/t")
            for (_, y) in get(by, (t,), NTuple{2,String}[])
                (y,) in x.y_eoh || continue
                d = gv(x.obj_disc, (r, y, cur))
                push!(out, (y, sw.objvar_obj == "ALT" ? gv(gparam(tm, "OBJ_ALTV"), (r, t)) * d : d))
            end
        end
        out
    end
end

"""
    eq_objvar!(tm) -> Int

    EQ_OBJVAR(RDCUR(R,CUR)) ..
      SUM(RTP_VARA(R,T,P)\$OBJ_ACOST(R,T,P,CUR), SUM(%TPULSE% * OBJ_ACOST(R,Y_EOH,P,CUR)) *
          SUM((RTP_VINTYR(R,V,T,P),PRC_TS(R,P,S)), VAR_ACT(R,V,T,P,S) * POWER(RS_STGAV(R,S),1\$RP_STG(R,P)))) +
      SUM(RTP_VINTYR(R,V,T,P)\$RPC_CUR(R,P,'ACT',CUR),
        SUM(RP_UPS(R,P,TSL,L('UP')),ACT_CSTUP(R,V,P,TSL,CUR)*OBJ_PVT(R,T,CUR)*SUM(TS_GROUP(R,TSL,S),RS_STGPRD(R,S)*VAR_UPS(R,V,T,P,S,L))) +
        SUM(RP_UPT(R,P,UPT,'UP'),ACT_CSTSD(R,V,P,UPT,'FX',CUR)*OBJ_PVT(R,T,CUR)*SUM(TS_GROUP(R,TSL,S)\$RP_DPL(R,P,TSL),RS_STGPRD(R,S)*VAR_UPT(R,V,T,P,S,UPT))) +
        SUM(RP_UPR(R,P,BDNEQ(BD)),ACT_CSTRMP(R,V,P,BD,CUR)*OBJ_PVT(R,T,CUR)*SUM(PRC_TS(R,P,S),RS_STGPRD(R,S)*VAR_UDP(R,V,T,P,S,BD)))) +
      SUM(RHS_COMBAL(R,T,C,S), VAR_COMNET(R,T,C,S) * SUM(%TPULSE% * SUM(COSTYPE,OBJ_COMNT(R,Y_EOH,C,S,COSTYPE,CUR)))) +
      SUM(RHS_COMPRD(R,T,C,S), VAR_COMPRD(R,T,C,S) * SUM(%TPULSE% * SUM(COSTYPE,OBJ_COMPD(R,Y_EOH,C,S,COSTYPE,CUR)))) +
      SUM((RTPCS_VARF(R,T,P,C,S),RPC_IREIO(R,P,C,IE,'OUT')), SUM(%TPULSE% * OBJ_IPRIC(R,Y_EOH,P,C,S,IE,CUR)) *
          SUM(RTP_VINTYR(R,V,T,P), VAR_IRE(R,V,T,P,C,S,IE)\$(NOT RPC_AIRE(R,P,C)) +
                                   (VAR_ACT(R,V,T,P,S)*PRC_ACTFLO(R,V,P,C))\$RPC_AIRE(R,P,C))) +
      SUM(RTPCS_VARF(R,T,P,C,S)\$SUM(OBJ_VFLO(RP_FLO(R,P),C,CUR,UC_COST),1),
          SUM(TS_ANN(S,TS), SUM(%TPULSE% * (OBJ_FCOST+OBJ_FDELV+OBJ_FTAX)(R,Y_EOH,P,C,TS,CUR))) *
          SUM(RTP_VINTYR(R,V,T,P), [%cal_red% C COM S P T])) +
      SUM(RTPCS_VARF(R,T,P,C,S)\$SUM(OBJ_VFLO(RP_IRE(R,P),C,CUR,UC_COST),1),
          SUM(TS_ANN(S,TS), SUM(%TPULSE% * (...))) *
          SUM(RTP_VINTYR(R,V,T,P), SUM(RPC_IRE(R,P,C,IE), [VAR_IRE or VAR_ACT*PRC_ACTFLO]) +
              SUM((RPC_IRE(R,P,COM,IE),IO)\$IRE_FLOSUM(R,T,P,COM,S,IE,C,IO),
                  IRE_FLOSUM(R,T,P,COM,S,IE,C,IO) %MX% * [VAR_IRE or VAR_ACT*PRC_ACTFLO for COM]))) +
      SUM(OBJ_VFLO(RPC_STG(R,P,C),CUR,'COST'),
          SUM((RTP_VINTYR(R,V,T,P),RPCS_VAR(R,P,C,S)),
              SUM(TS_ANN(S,TS), SUM(%TPULSE% * (VAR_SIN(R,V,T,P,C,S)*OBJ_FCOST(R,Y_EOH,P,C,TS,CUR) +
                                               VAR_SOUT(R,V,T,P,C,S)*STG_EFF(R,V,P)*OBJ_FDELV(R,Y_EOH,P,C,TS,CUR)))))) +
      [cal_caps L98-100] +
      SUM((BLE_OPR(R,BLE,OPR),TT(T)), SUM(%TPULSE% * OBJ_BLNDV(R,Y_EOH,BLE,OPR,CUR)) * VAR_BLND(R,T,BLE,OPR))
      =E= SUM(OBV,SUM_OBJ('OBJVAR',OBV)*VAR_OBJ(R,OBV,CUR));

The blending costs (L105-107) are on every stream of BLE_OPR in every period
TT (an alias of T), also before the blend's first year under specification
(no BLE_TP): OBJ_BLNDV is coef_obj.mod L93-94.

%MX% is `*(1+RTP_FFCS(R,V,P,C,C))` when RTP_FFCS is DEFINED (L83), ''
otherwise (setglobs.gms L356). COSTYPE is an alias of UC_COST
(initsys.mod L158), IO of IN_OUT (initsys.mod L67).
GAMS: eqobjvar.mod L14-113, v4.9.7.
"""
function eq_objvar!(tm::TimesModel)
    x = objective_context(tm)
    rtp_vara = gset(tm, "RTP_VARA")
    vint_of_rtp = indexby(gset(tm, "RTP_VINTYR"), (1, 3, 4))
    ts_of_rp = indexby(gset(tm, "PRC_TS"), (1, 2))
    rp_stg = gset(tm, "RP_STG")
    rs_stgav = gparam(tm, "RS_STGAV")
    ob_act = gparam(tm, "OB_ACT")
    rhs_combal, rhs_comprd = gset(tm, "RHS_COMBAL"), gset(tm, "RHS_COMPRD")
    obj_comnt, obj_compd = gparam(tm, "OBJ_COMNT"), gparam(tm, "OBJ_COMPD")
    costype = [k[1] for k in gset(tm, "UC_COST")]
    rtpcs_varf = gset(tm, "RTPCS_VARF")
    ireio_of_rpc = indexby(gset(tm, "RPC_IREIO"), (1, 2, 3))
    obj_ipric = gparam(tm, "OBJ_IPRIC")
    rpc_aire = gset(tm, "RPC_AIRE")
    prc_actflo = gparam(tm, "PRC_ACTFLO")
    vflo = Set((k[1], k[2], k[3], k[4]) for k in gset(tm, "OBJ_VFLO"))   # SUM(OBJ_VFLO(R,P,C,CUR,UC_COST),1)
    rp_flo, rp_ire = gset(tm, "RP_FLO"), gset(tm, "RP_IRE")
    ts_ann_of_s = indexby(gset(tm, "TS_ANN"), (1,))
    ob_fcos, ob_fdel, ob_ftax = gparam(tm, "OB_FCOS"), gparam(tm, "OB_FDEL"), gparam(tm, "OB_FTAX")
    ire_of_rpc = indexby(gset(tm, "RPC_IRE"), (1, 2, 3))
    ire_of_rp = indexby(gset(tm, "RPC_IRE"), (1, 2))
    ire_flosum = gparam(tm, "IRE_FLOSUM")
    rtp_ffcs = gparam_opt(tm.data, "RTP_FFCS", 5)
    io_set = [k[1] for k in gset(tm, "IN_OUT")]
    rpc_stg = gset(tm, "RPC_STG")
    stg_var_of_rpc = indexby(gset(tm, "RPCS_VAR"), (1, 2, 3))          # (r,p,c) -> RPCS_VAR(r,p,c,s)
    stg_eff = gparam(tm, "STG_EFF")
    vflo_cost = [k for k in gset(tm, "OBJ_VFLO") if k[5] == "COST" && (k[1], k[2], k[3]) in rpc_stg]
    vint_of_rp = indexby(gset(tm, "RTP_VINTYR"), (1, 4))               # (r,p) -> RTP_VINTYR(r,v,t,p)
    # dispatching costs (L36-39)
    dd = tm.data
    rpc_cur = gset_opt(dd, "RPC_CUR", 4)
    ups_of_rp = indexby(gset_opt(dd, "RP_UPS", 4), (1, 2))              # (r,p) -> RP_UPS(r,p,tsl,l)
    upr_of_rp = indexby(gset_opt(dd, "RP_UPR", 3), (1, 2))              # (r,p) -> RP_UPR(r,p,bd)
    upt_of_rp = indexby(gset_opt(dd, "RP_UPT", 4), (1, 2))              # (r,p) -> RP_UPT(r,p,upt,bd)
    dpl_of_rp = indexby(gset_opt(dd, "RP_DPL", 3), (1, 2))              # (r,p) -> RP_DPL(r,p,tsl)
    ups_rp = sort!(unique!(vcat(collect(keys(ups_of_rp)), collect(keys(upr_of_rp)), collect(keys(upt_of_rp)))))
    group_of = indexby(gset_opt(dd, "TS_GROUP", 3), (1, 2))             # (r,tsl) -> TS_GROUP(r,tsl,s)
    act_cstup, act_cstrmp = gparam_opt(dd, "ACT_CSTUP", 5), gparam_opt(dd, "ACT_CSTRMP", 5)
    act_cstsd = gparam_opt(dd, "ACT_CSTSD", 6)
    obj_pvt, rs_stgprd = gparam_opt(dd, "OBJ_PVT", 3), gparam_opt(dd, "RS_STGPRD", 2)
    # blending costs (L105-107)
    ble_opr_of_r = indexby(gset_opt(tm.data, "BLE_OPR", 3), (1,))      # (r,) -> BLE_OPR(r,ble,opr)
    obj_blndv = gparam_opt(tm.data, "OBJ_BLNDV", 5)
    # capacity-related flow costs (L97-100)
    capflo = gset_opt(tm.data, "RPC_CAPFLO", 4).keys
    vnt_of_v = indexby(gset(tm, "VNT"), (1,))                            # v -> VNT(v,t)
    coef_icom, coef_ocom = gparam_opt(tm.data, "COEF_ICOM", 5), gparam_opt(tm.data, "COEF_OCOM", 5)
    rs_fr_obj, g_yrfr_obj = gparam(tm, "RS_FR"), gparam(tm, "G_YRFR")
    ncap_pasti_obj, milestonyr_obj = gparam(tm, "NCAP_PASTI"), gset(tm, "MILESTONYR")
    ncom_obj, coef_cio_obj, coef_cpt_obj = gparam(tm, "NCAP_COM"), gparam(tm, "COEF_CIO"), gparam(tm, "COEF_CPT")
    cptyr_obj, prc_rcap_obj = gset(tm, "RTP_CPTYR"), gset_opt(tm.data, "PRC_RCAP", 2)
    vntrt_obj = gset_opt(tm.data, "VNTRT", 2)
    ble, opr = gset_opt(tm.data, "BLE", 1), gset_opt(tm.data, "OPR", 1)

    weighted(r, t, cur, f) = (w = GZERO; for (y, wy) in tpulse(tm, r, t, cur); w = w + wy * f(y); end; w)
    vintages(r, t, p) = (k[2] for k in get(vint_of_rtp, (r, t, p), NO4) if (k[2],) in x.v)
    function ire_or_act!(expr, k, r, v, t, p, c, s, ie)
        if !((r, p, c) in rpc_aire)
            addterm!(expr, k, tm, "VAR_IRE", r, v, t, p, c, s, ie)
        else
            addterm!(expr, k * gv(prc_actflo, (r, v, p, c)), tm, "VAR_ACT", r, v, t, p, s)
        end
    end

    n = 0
    for (r, cur) in x.rdcur
        lhs = JuMP.AffExpr(0.0)
        # Activity costs (L30-34).
        for (rr, t, p) in rtp_vara
            (rr == r && (t,) in x.t && haskey(ob_act, (r, p, cur, t))) || continue
            w = weighted(r, t, cur, y -> obmac(ob_act, r, y, p, cur))
            for v in vintages(r, t, p), (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[])
                addterm!(lhs, w * gpower(gv(rs_stgav, (r, s)), (r, p) in rp_stg ? 1 : 0), tm, "VAR_ACT", r, v, t, p, s)
            end
        end
        # Dispatching costs (L36-39): start-ups (L37), start-ups by type (L38) and load changes (L39).
        for (rr, p) in ups_rp
            (rr == r && (r, p, "ACT", cur) in rpc_cur) || continue
            for (_, v, t, _) in get(vint_of_rp, (r, p), NO4)             # RTP_VINTYR(R,V,T,P)
                pvt = gv(obj_pvt, (r, t, cur))
                for (_, _, tsl, l) in get(ups_of_rp, (r, p), NO4)
                    l == "UP" || continue
                    k = gv(act_cstup, (r, v, p, tsl, cur)) * pvt
                    for (_, _, s) in get(group_of, (r, tsl), NTuple{3,String}[])
                        addterm!(lhs, k * gv(rs_stgprd, (r, s)), tm, "VAR_UPS", r, v, t, p, s, "UP")
                    end
                end
                for (_, _, upt, bd) in get(upt_of_rp, (r, p), NO4)
                    bd == "UP" || continue
                    k = gv(act_cstsd, (r, v, p, upt, "FX", cur)) * pvt
                    for (_, _, tsl) in get(dpl_of_rp, (r, p), NTuple{3,String}[]),
                        (_, _, s) in get(group_of, (r, tsl), NTuple{3,String}[])

                        addterm!(lhs, k * gv(rs_stgprd, (r, s)), tm, "VAR_UPT", r, v, t, p, s, upt)
                    end
                end
                for (_, _, bd) in get(upr_of_rp, (r, p), NTuple{3,String}[])
                    bd in ("LO", "UP") || continue                          # BDNEQ(BD)
                    k = gv(act_cstrmp, (r, v, p, bd, cur)) * pvt
                    for (_, _, s) in get(ts_of_rp, (r, p), NTuple{3,String}[])
                        addterm!(lhs, k * gv(rs_stgprd, (r, s)), tm, "VAR_UDP", r, v, t, p, s, bd)
                    end
                end
            end
        end
        # Commodity costs on net and production (L44-47).
        for (set, par, var) in ((rhs_combal, obj_comnt, "VAR_COMNET"), (rhs_comprd, obj_compd, "VAR_COMPRD"))
            for (rr, t, c, s) in set
                (rr == r && (t,) in x.t && (c,) in x.com) || continue
                w = weighted(r, t, cur, y -> (a = GZERO; for ct in costype; a = a + gv(par, (r, y, c, s, ct, cur)); end; a))
                addterm!(lhs, w, tm, var, r, t, c, s)
            end
        end
        for (rr, t, p, c, s) in rtpcs_varf
            (rr == r && (t,) in x.t) || continue
            # Prices of imports/exports from/to external regions (L54-59).
            for (_, _, _, ie, io) in get(ireio_of_rpc, (r, p, c), NO5)
                io == "OUT" || continue
                w = weighted(r, t, cur, y -> gv(obj_ipric, (r, y, p, c, s, ie, cur)))
                for v in vintages(r, t, p)
                    ire_or_act!(lhs, w, r, v, t, p, c, s, ie)
                end
            end
            # Flow costs (L66-71) and those of trade processes (L74-87).
            (r, p, c, cur) in vflo || continue
            w = GZERO
            for (_, ts) in get(ts_ann_of_s, (s,), NTuple{2,String}[])
                w = w + weighted(r, t, cur, y -> obmac(ob_fcos, r, y, p, c, ts, cur) + obmac(ob_fdel, r, y, p, c, ts, cur) +
                                                 obmac(ob_ftax, r, y, p, c, ts, cur))
            end
            if (r, p) in rp_flo
                for v in vintages(r, t, p)
                    cal_nored!(lhs, tm, w, r, v, t, p, c, s)
                end
            end
            if (r, p) in rp_ire
                for v in vintages(r, t, p)
                    for (_, _, _, ie) in get(ire_of_rpc, (r, p, c), NO4)
                        ire_or_act!(lhs, w, r, v, t, p, c, s, ie)
                    end
                    for (_, _, com, ie) in get(ire_of_rp, (r, p), NO4), io in io_set
                        fs = (r, t, p, com, s, ie, c, io)
                        haskey(ire_flosum, fs) || continue
                        k = w * (gv(ire_flosum, fs) * (1 + gv(rtp_ffcs, (r, v, p, c, c))))
                        ire_or_act!(lhs, k, r, v, t, p, com, s, ie)
                    end
                end
            end
        end
        # Storage flow costs (L89-91): FLO_COST on the input, FLO_DELIV on the output * STG_EFF.
        for (rv, p, c, cv, _) in vflo_cost
            (rv == r && cv == cur) || continue
            for (_, v, t, _) in get(vint_of_rp, (r, p), NO4)
                ((v,) in x.v && (t,) in x.t) || continue
                for (_, _, _, s) in get(stg_var_of_rpc, (r, p, c), NO4)
                    ksin, ksout = GZERO, GZERO
                    eff = gv(stg_eff, (r, v, p))
                    for (_, ts) in get(ts_ann_of_s, (s,), NTuple{2,String}[])
                        ksin = ksin + weighted(r, t, cur, y -> obmac(ob_fcos, r, y, p, c, ts, cur))
                        ksout = ksout + weighted(r, t, cur, y -> eff * obmac(ob_fdel, r, y, p, c, ts, cur))
                    end
                    addterm!(lhs, ksin, tm, "VAR_SIN", r, v, t, p, c, s)
                    addterm!(lhs, ksout, tm, "VAR_SOUT", r, v, t, p, c, s)
                end
            end
        end
        # Costs of the flows tied to investment and decommissioning (L97-100, cal_caps.mod L18-21, M1.3
        # change 53), with %1 = T, %3 = TS and S = ANNUAL:
        #   SUM((VNT(V,T),RPC_CAPFLO(R,V,P,C)), ((COEF_ICOM(R,V,T,P,C)+COEF_OCOM(R,V,T,P,C)) * G_YRFR(R,S) *
        #     (VAR_NCAP(R,V,P)$MILESTONYR(V) + NCAP_PASTI(R,V,P)) *
        #     SUM(RPCS_VAR(R,P,C,TS), RS_FR(R,TS,S) * SUM(TS_ANN(TS,SL),SUM(%TPULSE%*(OBJ_FCOST+OBJ_FDELV+OBJ_FTAX)(R,Y_EOH,P,C,SL,CUR)))))
        #   $(COEF_ICOM(R,V,T,P,C)+COEF_OCOM(R,V,T,P,C))
        # NCAP_PASTI is not conditioned on PASTYEAR here, unlike cal_cap.mod. Then the flows over the
        # lifetime (cal_caps.mod L22-26, M1.3 change 54), in the same sum:
        #   SUM((RTP_CPTYR(R,V,T,P),IO)$NCAP_COM(R,V,P,C,IO), COEF_CPT(R,V,T,P) * NCAP_COM(R,V,P,C,IO) * G_YRFR(R,S) *
        #     (VAR_NCAP(R,V,P)$T(V) + NCAP_PASTI(R,V,P) - SUM(VNTRT(V,MODLYEAR(T)),VAR_SCAP(R,V,T,P))$PRC_RCAP(R,P)) *
        #     SUM(RPCS_VAR(R,P,C,TS), RS_FR(R,TS,S) * [the costs]) * (1+COEF_CIO(R,V,T,P,C,IO)))
        for (rr, v, p, c) in capflo
            rr == r || continue
            for (_, t) in get(vnt_of_v, (v,), NTuple{2,String}[])
                k0 = gv(coef_icom, (r, v, t, p, c)) + gv(coef_ocom, (r, v, t, p, c))
                coms = (r, v, t, p) in cptyr_obj ? [io for io in ("IN", "OUT") if haskey(ncom_obj.values, (r, v, p, c, io))] : String[]
                (iszero(k0) && isempty(coms)) && continue
                cost = GZERO
                for (_, _, _, ts) in get(stg_var_of_rpc, (r, p, c), NO4)
                    w = GZERO
                    for (_, sl) in get(ts_ann_of_s, (ts,), NTuple{2,String}[])
                        w = w + weighted(r, t, cur, y -> obmac(ob_fcos, r, y, p, c, sl, cur) + obmac(ob_fdel, r, y, p, c, sl, cur) +
                                                         obmac(ob_ftax, r, y, p, c, sl, cur))
                    end
                    cost = cost + gv(rs_fr_obj, (r, ts, "ANNUAL")) * w
                end
                yrfr = gv(g_yrfr_obj, (r, "ANNUAL"))
                if !iszero(k0)
                    k = k0 * yrfr * cost
                    (v,) in milestonyr_obj && addterm!(lhs, k, tm, "VAR_NCAP", r, v, p)
                    addconst!(lhs, k * gv(ncap_pasti_obj, (r, v, p)))
                end
                for io in coms
                    k = gv(coef_cpt_obj, (r, v, t, p)) * gv(ncom_obj, (r, v, p, c, io)) * yrfr * cost *
                        (1 + gv(coef_cio_obj, (r, v, t, p, c, io)))
                    (v,) in milestonyr_obj && addterm!(lhs, k, tm, "VAR_NCAP", r, v, p)
                    addconst!(lhs, k * gv(ncap_pasti_obj, (r, v, p)))
                    ((r, p) in prc_rcap_obj && (v, t) in vntrt_obj && (t,) in x.v) &&
                        addterm!(lhs, -k, tm, "VAR_SCAP", r, v, t, p)
                end
            end
        end
        # Commodity blending costs (L105-107).
        for (_, b, o) in get(ble_opr_of_r, (r,), NTuple{3,String}[])
            ((b,) in ble && (o,) in opr) || continue
            for (t,) in x.t
                addterm!(lhs, weighted(r, t, cur, y -> gv(obj_blndv, (r, y, b, o, cur))), tm, "VAR_BLND", r, t, b, o)
            end
        end
        gconstraint!(tm, "EQ_OBJVAR", (r, cur), "E", lhs, obj_component_rhs(tm, x, r, cur, "OBJVAR")) === nothing || (n += 1)
    end
    return n
end

"""
    eq_objsalv!(tm) -> Int

    EQ_OBJSALV(RDCUR(R,CUR)) ..
      SUM(OBJ_SUMS(R,T,P), OBJSCC(R,T,P,CUR) * VAR_NCAP(R,T,P)) * OBJ_DCEOH(R,CUR) +
      SUM(OBJ_SUMS(R,PYR(V),P), OBJSCC(R,V,P,CUR) * NCAP_PASTI(R,V,P)) * OBJ_DCEOH(R,CUR) +
      SUM(OBJ_SUMS3(R,T,P), VAR_NCAP(R,T,P) * SALV_DEC(R,T,P,CUR)) * OBJ_DCEOH(R,CUR) +
      SUM(OBJ_SUMS3(R,PYR,P), NCAP_PASTI(R,PYR,P) * SALV_DEC(R,PYR,P,CUR)) * OBJ_DCEOH(R,CUR) +
      SUM(OBJ_SUMIVS(R,V,P,K,Y)\$SALV_INV(R,V,P,K), OBJ_DISC(R,Y,CUR) * OBJ_DLAGC(R,K,P,CUR) *
          SALV_INV(R,V,P,K) * (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V))) +
      SUM((OBJ_SUMIII(R,V,P,LL,K,Y),COM)\$((NOT Y_EOH(Y))\$NCAP_OCOM(R,V,P,COM)),
          (1-SALV_INV(R,V,P,LL)) * NCAP_VALU(R,K,P,COM,CUR) * OBJ_DISC(R,Y,CUR) *
          (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)) * NCAP_OCOM(R,V,P,COM) / OBJ_DIVIII(R,V,P))
      =E= VAR_OBJ(R,'OBJSAL',CUR);

GAMS: eqobsalv.mod L92-140, v4.9.7 (ETL L102-103 is refused; the VNRET hook
L105 is `objsalv_ret!`, M1.3 change 20b-4).
"""
function eq_objsalv!(tm::TimesModel)
    x = objective_context(tm)
    n = 0
    for (r, cur) in x.rdcur
        lhs = JuMP.AffExpr(0.0)
        dceoh = gv(x.obj_dceoh, (r, cur))
        for (_, v, p) in get(x.sums_of_r, (r,), NTuple{3,String}[])
            k = gv(x.objscc, (r, v, p, cur))
            (v,) in x.t && addterm!(lhs, k * dceoh, tm, "VAR_NCAP", r, v, p)
            (v,) in x.v && (v,) in x.pyr && addconst!(lhs, k * gv(x.ncap_pasti, (r, v, p)) * dceoh)
        end
        objsalv_ret!(lhs, tm, x, r, cur, dceoh)                     # L105: prepret.dsc OBSALV (prepret.jl)
        for (_, v, p) in get(x.sums3_of_r, (r,), NTuple{3,String}[])
            k = gv(x.salv_dec, (r, v, p, cur))
            (v,) in x.t && addterm!(lhs, k * dceoh, tm, "VAR_NCAP", r, v, p)
            (v,) in x.pyr && addconst!(lhs, gv(x.ncap_pasti, (r, v, p)) * k * dceoh)
        end
        for (_, v, p, k, y) in get(x.sumivs_of_r, (r,), NO5)
            ((v,) in x.v && (k,) in x.k && (y,) in x.y && haskey(x.salv_inv, (r, v, p, k))) || continue
            c = gv(x.obj_disc, (r, y, cur)) * obmac(x.ob_dlc, r, k, p, cur) * gv(x.salv_inv, (r, v, p, k))
            add_ncap_or_pasti!(lhs, tm, x, c, r, v, p)
        end
        for (_, v, p, ll, k, y) in get(x.sumiii_of_r, (r,), NO6)                    # late revenues
            ((v,) in x.v && (k,) in x.k && (y,) in x.y && !((y,) in x.y_eoh)) || continue
            for (_, _, _, com) in get(x.ncap_ocom_of_rvp, (r, v, p), NO4)
                (com,) in x.com || continue
                c = (1 - gv(x.salv_inv, (r, v, p, ll))) * gv(x.ncap_valu, (r, k, p, com, cur)) * gv(x.obj_disc, (r, y, cur))
                add_ncap_or_pasti!(lhs, tm, x, c * gv(x.ncap_ocom, (r, v, p, com)) / gv(x.obj_diviii, (r, v, p)), r, v, p)
            end
        end
        rhs = JuMP.AffExpr(0.0)
        addterm!(rhs, GNum(1.0), tm, "VAR_OBJ", r, "OBJSAL", cur)
        gconstraint!(tm, "EQ_OBJSALV", (r, cur), "E", lhs, rhs) === nothing || (n += 1)
    end
    return n
end
