# Crafted states for coef_alt.lin (v4.9.7): the TIMES_Demo demo12 ppm dump
# (test/fixtures/demo12_off_ppm) taken through coef_cpt, coef_nio, coef_ptr and coef_obj under switch
# settings no reference run uses, so that every `$IF` path of the file is
# checked against coef_alt.lin run by GAMS itself
# (scripts/make_coef_alt_unit.jl, test/unit/test_coef_alt.jl).
#
# Every reference run but OTCGEN and OTNYC has OBJ MOD or OBJ AUTO + OBLONG
# YES (%CTST% = **0, LINFLO 0, LINACC 0, ALTOBJ 1): the OBLONG branch of the
# CPT section only. OTCGEN and OTNYC (OBJ AUTO, no OBLONG) take the L59 exit,
# as the "plain" case does here.
# ELCTECOA00 (past vintage 2004 in REG1) and COTNCOA1 (new, 2010) are demo12
# processes.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, ctst

"""
The cases: name => (switches, ALTOBJ, state edits). ALTOBJ follows
initmty.mod L420-432 (1; 2 for ALT; 3 for LIN; -2 for OBLONG + ALT; 0 for
STD), as the ppm dump would hold it.
"""
const COEF_ALT_CASES = [
    # OBJ AUTO without OBLONG: %CTST% empty, the include ends at L59 (YK1 kept from L32)
    "plain" => (Dict("OBJ" => "AUTO", "OBLONG" => "NO"), 1.0),
    # OBJ ALT without OBLONG: %CTST% **EPS, LINFLO 1, LINACC 0, OBJ_ALTV, L74 RB, L83-86 RTP_CAPVL
    "alt" => (Dict("OBJ" => "ALT", "OBLONG" => "NO"), 2.0),
    # OBJ LIN without OBLONG: LINFLO 1, LINACC 1, no OBJ_ALTV
    "lin" => (Dict("OBJ" => "LIN", "OBLONG" => "NO"), 3.0),
    # OBLONG with OBJ ALT: VARCOST LIN, LINACC 1, %ILED% dropped from L78 (L44), ALTOBJ -2
    "oblong_alt" => (Dict("OBJ" => "ALT", "OBLONG" => "YES"), -2.0),
    # OBJ STD with OBLONG (the reference setting but ALTOBJ 0) and INT_DEFAULT('PASTI') with a past
    # lead time above COEF_ILED (L68-69), plus an NCAP_ILED on a new vintage (the %ILED% term of L78)
    "pasti" => (Dict("OBJ" => "STD", "OBLONG" => "YES"), 0.0),
]

const COEF_ALT_BASE_SWITCHES = Dict("VALIDATE" => "NO", "STAGES" => "NO", "VARCOST" => "")

function coef_alt_start(ppm_dir, name)
    sw, altobj = Dict(COEF_ALT_CASES)[name]
    tm = TimesModel(ppm_dir; switches=merge(COEF_ALT_BASE_SWITCHES, sw))
    gput!(tm, "ALTOBJ", altobj == 0 ? Dict{Tuple{},Float64}() : Dict{Tuple{},Float64}(() => altobj))
    r, p = "REG1", "ELCTECOA00"
    iled = gvalues(tm, "NCAP_ILED", 3)
    iled[(r, "2010", "COTNCOA1")] = 2.0                               # a lead time on a new vintage
    if name == "pasti"
        gput!(tm, "INT_DEFAULT", Set([("PASTI",)]))
        phyr = gmembers(tm, "PHYR", 1); push!(phyr, ("2004",)); gput!(tm, "PHYR", phyr)
        iled[(r, "2004", p)] = 3.0                                     # above COEF_ILED (0): L69 shortens it
    end
    gput!(tm, "NCAP_ILED", iled)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm)
    return tm
end

"What coef_alt.lin writes, compared after it (scripts/m12_probe.jl)."
const COEF_ALT_OUTPUTS = ["PERDINV", "TPULSEYR", "TPULSE", "OBJ_LINT", "OBJ_ALTV", "RTP_CAPVL", "RB", "R_DF", "COEF_CPT",
                          "PASTSUM", "YK1", "FIL2", "MY_ARRAY", "FPD", "OBJ_PVT", "COEF_PVT", "NCAP_ILED"]

"Symbols coef_alt.lin declares itself (L13-22)."
const COEF_ALT_DECLARED = Set(["PERDINV", "TPULSEYR", "TPULSE", "OBJ_LINT", "OBJ_ALTV", "RTP_CAPVL", "RB", "R_DF",
                               "OBJ_WD", "OBJ_JD"])
