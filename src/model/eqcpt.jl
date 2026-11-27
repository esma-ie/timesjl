# EQE_CPT / EQL_CPT / EQG_CPT: capacity transfer. VAR_CAP (or a capacity
# bound) equals the surviving new capacity of all vintages.
#
# GAMS: eqcpt.mod L18-27, v4.9.7, included from eqmain.mod L77-79 as
#   $BATINCLUDE eqcpt.mod E E "RTP_VARP(R,T,P) OR YES$CAP_BND(R,T,P,'FX')" "VAR_CAP(R,T,P)"
#   $BATINCLUDE eqcpt.mod L L "((NOT RTP_VARP(R,T,P))$CAP_BND(R,T,P,'LO'))" "CAP_BND(R,T,P,'LO')"
#   $BATINCLUDE eqcpt.mod G G "((NOT RTP_VARP(R,T,P))$CAP_BND(R,T,P,'UP'))" "CAP_BND(R,T,P,'UP')"
# (%1 = equation type, %2 = name suffix, %3 = condition, %4 = left-hand side);
# declared eqdeclr.mod L64-66. The VALIDATE branch (eqmain.mod L72, L80-) is
# refused with VALIDATE; the ETL and MACRO additions to RTP_VARP (L73-74)
# with those switches (generate.jl).
#
# Macro expansions: %EQ% -> EQ, %VAR%/%VARV% -> VAR, %SOW%/%SWT%/%SWS% -> ''
# (setglobs.gms L348); %RCAPSUB% is the -VAR_SCAP term of early retirement
# (prepret.dsc L87, `rcapsub!`; M1.3 change 20b-2), empty without it. T =
# MILESTONYR, V = MODLYEAR. CAP_BND is read as the SOLVE sees it, after
# bndmain.mod L51 (bndmain.jl).

const CPT_VARIANTS = (("E", :varp_or_fx), ("L", "LO"), ("G", "UP"))

"""
    eq_cpt!(tm::TimesModel) -> Int

Generate every EQE_CPT, EQL_CPT and EQG_CPT row. Returns the number of rows.

    EQE_CPT(RTP(R,T,P))\$(RTP_VARP(R,T,P) OR YES\$CAP_BND(R,T,P,'FX')) ..
        VAR_CAP(R,T,P) =E= SUM(V\$COEF_CPT(R,V,T,P), COEF_CPT(R,V,T,P) *
                               (VAR_NCAP(R,V,P)\$MILESTONYR(V) + NCAP_PASTI(R,V,P)\$PASTYEAR(V)));
    EQL_CPT(RTP(R,T,P))\$((NOT RTP_VARP(R,T,P))\$CAP_BND(R,T,P,'LO')) .. CAP_BND(R,T,P,'LO') =L= [same sum];
    EQG_CPT(RTP(R,T,P))\$((NOT RTP_VARP(R,T,P))\$CAP_BND(R,T,P,'UP')) .. CAP_BND(R,T,P,'UP') =G= [same sum];

The SOW tags (sow_tags.jl): the row is `%EQ%%2_CPT(RTP(R,T,P) %SWT%)` (L18);
VAR_CAP is `%VAR%_CAP(R,T,P %SOW%)` (eqmain.mod L77) and the new capacity
`%VARV%_NCAP(R,V,P %SWS%)` (L26, `at = v`), with %RCAPSUB%.

GAMS: eqcpt.mod L18-27 with eqmain.mod L77-79, v4.9.7.
"""
function eq_cpt!(tm::TimesModel)
    milestonyr = gset(tm, "MILESTONYR")     # T: ALIAS(MILESTONYR,T,TT), initmty.mod L94
    modlyear = gset(tm, "MODLYEAR")         # V: ALIAS(MODLYEAR,V), setglobs.gms L147
    pastyear = gset(tm, "PASTYEAR")
    reg = gset(tm, "REG")
    rtp_varp = gset(tm, "RTP_VARP")
    cap_bnd = gparam(tm, "CAP_BND")
    coef_cpt = gparam(tm, "COEF_CPT")
    ncap_pasti = gparam(tm, "NCAP_PASTI")
    # SUM(V$COEF_CPT(R,V,T,P), ...): vintages per (r,t,p), in GAMS record order.
    v_of_rtp = Dict{NTuple{3,String},Vector{String}}()
    for (r, v, t, p) in coef_cpt.keys
        (v,) in modlyear || continue
        push!(get!(() -> String[], v_of_rtp, (r, t, p)), v)
    end
    function capacity!(expr, r, t, p)
        for v in get(v_of_rtp, (r, t, p), String[])
            c = gv(coef_cpt, (r, v, t, p))
            (v,) in milestonyr && addterm!(expr, c, tm, "VAR_NCAP", r, v, p; at=v)   # %VARV%_NCAP(R,V,P %SWS%) (L26)
            (v,) in pastyear && addconst!(expr, c * gv(ncap_pasti, (r, v, p)))
            rcapsub!(expr, c, tm, r, v, t, p)                       # %RCAPSUB% (prepret.jl)
        end
        return expr
    end

    n = 0
    for (eqtype, which) in CPT_VARIANTS
        name = "EQ$(eqtype)_CPT"
        for (r, t, p) in gset(tm, "RTP")
            ((r,) in reg && (t,) in milestonyr) || continue
            for sow in sw_rows(tm, t)   # %SWT% (L18)
                set_sow!(tm, sow)
                varp = (r, t, p) in rtp_varp
                lhs = JuMP.AffExpr(0.0)
                if which === :varp_or_fx
                    (varp || haskey(cap_bnd, (r, t, p, "FX"))) || continue
                    addterm!(lhs, GNum(1.0), tm, "VAR_CAP", r, t, p)
                else
                    (!varp && haskey(cap_bnd, (r, t, p, which))) || continue
                    addconst!(lhs, gv(cap_bnd, (r, t, p, which)))
                end
                rhs = capacity!(JuMP.AffExpr(0.0), r, t, p)
                gconstraint!(tm, eqtag(tm, name), swt(tm, (r, t, p), t), eqtype, lhs, rhs) === nothing || (n += 1)
            end
        end
    end
    return n
end
