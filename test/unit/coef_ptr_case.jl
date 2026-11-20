# Crafted states for coef_ptr.mod (v4.9.7): the TIMES_Demo demo12 ppm dump
# (test/fixtures/demo12_off_ppm) taken through coef_cpt and coef_nio, then
# given the FLO_FUNC and FLO_SUM data no public reference run has, so that
# every translated path of the file is checked against coef_ptr.mod run by
# GAMS itself (scripts/make_coef_ptr_unit.jl, test/unit/test_coef_ptr.jl).
#
# demo12 has FLO_SUM only (emission factors, cg1 = cg2 = the emission
# commodity) and no FLO_FUNC, so it reaches L15-16 and L34 alone. The
# processes used, all in REG1 (REG2 is left alone): ELCTNGAS01 (DAYNITE;
# ELC, ELCCO2, ELCGAS; vintages 2010-2050), ELCTECOA00 (SEASON; ELC,
# ELCCO2, ELCCOA; 2004-2030) and COTNCOA1 (ANNUAL; COMCO2, COMCOA, DCOT;
# 2010-2050). NRG holds ELC, ELCGAS, ELCCOA and COMCOA, not DCOT; ELCCOA is
# a REG1 commodity that ELCTNGAS01 does not use.

using OpenTIMES: TimesModel, gvalues, gput!, coef_cpt!, coef_nio!

const COEF_PTR_CASE_SWITCHES = Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VALIDATE" => "NO", "STAGES" => "NO")

"""
The cases, name => description:

- "flofunc": the FLO_FUNC paths (L18-33).
  - ELCTNGAS01 2010, forward FLO_FUNC(ELCGAS,ELC) at SD, SN and WD (none at
    WN) and at ANNUAL (not a DAYNITE timeslice: left out of the L31 sum),
    with no FLO_SUM: L21-22. A FLO_SUM(ELCGAS,ELCCO2,ELC) at SD adds
    ELCCO2 to the single-commodity group ELCGAS: L23.
  - ELCTNGAS01 2015, reverse FLO_FUNC(ELC,NRG) at SD and SN with
    FLO_SUM(NRG,ELCGAS,ELC) at SD: L18-19 (CG_GRP, then CGTES2 at every
    vintage for ELC and ELCGAS in NRG) and the 1/FLO_FUNC term of L32.
  - ELCTNGAS01 2020, both directions, FLO_FUNC(NRG,ELC) and
    FLO_FUNC(ELC,NRG) at SD: L32 takes the forward one; L27 drops the
    (ELC,NRG) direction where CG_GRP(NRG,ELC) has a FLO_SUM.
  - ELCTNGAS01 2030, FLO_FUNC(ELCGAS,ELCCOA) at SD: ELCCOA is a REG1
    commodity outside the process (L51 removes the RPCC_FFUNC record;
    L50 still adds ELCCOA to PRC_CG).
  - COTNCOA1 2030, reverse FLO_FUNC(DCOT,NRG) with FLO_SUM(NRG,COMCOA,DCOT)
    at ANNUAL.
- "flosum": FLO_SUM edge cases (L15-16, L27, L34).
  - ELCTNGAS01 2010, FLO_FUNC(ELCGAS,ELC) at SD with an EPS
    FLO_SUM(ELCGAS,ELCGAS,ELC) at SN: L27 with `YES\$EPS` true (G6, G25).
  - ELCTECOA00 2015, demo12's FLO_SUM(ELCCO2,ELCCOA,ELCCO2) at W set to
    EPS: L34 stores EPS with `\$=` (G24).
  - ELCTECOA00 at 2012 (not a model year), FLO_SUM(NRG,ELCGAS,ELC) at S:
    ELCGAS is not an RPC of the process, but L16 keeps the record (V
    filters, G27) and L24/L45 project it into CG_GRP (RPCC_FFUNC gains
    (NRG,ELC)).
  - COTNCOA1 2010, FLO_SUM(NRG,ELCGAS,DCOT) at ANNUAL: ELCGAS is not an RPC
    of the process and 2010 is a model year, so L16 removes it (kept, it
    would add (NRG,DCOT) to RPCC_FFUNC).
"""
const COEF_PTR_CASES = ["flofunc", "flosum"]

function coef_ptr_start(ppm_dir, name; switches=COEF_PTR_CASE_SWITCHES)
    tm = TimesModel(ppm_dir; switches)
    coef_cpt!(tm); coef_nio!(tm)
    coef_ptr_case!(tm, name)
    return tm
end

function coef_ptr_case!(tm, name)
    r = "REG1"
    ff = gvalues(tm, "FLO_FUNC", 6)
    fs = gvalues(tm, "FLO_SUM", 7)
    if name == "flofunc"
        for (s, x) in (("SD", 0.5), ("SN", 0.55), ("WD", 0.6), ("ANNUAL", 9.0))
            ff[(r, "2010", "ELCTNGAS01", "ELCGAS", "ELC", s)] = x
        end
        fs[(r, "2010", "ELCTNGAS01", "ELCGAS", "ELCCO2", "ELC", "SD")] = 2.0
        ff[(r, "2015", "ELCTNGAS01", "ELC", "NRG", "SD")] = 0.4
        ff[(r, "2015", "ELCTNGAS01", "ELC", "NRG", "SN")] = 0.5
        fs[(r, "2015", "ELCTNGAS01", "NRG", "ELCGAS", "ELC", "SD")] = 1.5
        ff[(r, "2020", "ELCTNGAS01", "NRG", "ELC", "SD")] = 3.0
        ff[(r, "2020", "ELCTNGAS01", "ELC", "NRG", "SD")] = 0.25
        ff[(r, "2030", "ELCTNGAS01", "ELCGAS", "ELCCOA", "SD")] = 0.7
        ff[(r, "2030", "COTNCOA1", "DCOT", "NRG", "ANNUAL")] = 0.8
        fs[(r, "2030", "COTNCOA1", "NRG", "COMCOA", "DCOT", "ANNUAL")] = 1.25
    elseif name == "flosum"
        ff[(r, "2010", "ELCTNGAS01", "ELCGAS", "ELC", "SD")] = 0.5
        fs[(r, "2010", "ELCTNGAS01", "ELCGAS", "ELCGAS", "ELC", "SN")] = 0.0                  # EPS
        fs[(r, "2015", "ELCTECOA00", "ELCCO2", "ELCCOA", "ELCCO2", "W")] = 0.0                # EPS (was 95)
        fs[(r, "2012", "ELCTECOA00", "NRG", "ELCGAS", "ELC", "S")] = 1.0
        fs[(r, "2010", "COTNCOA1", "NRG", "ELCGAS", "DCOT", "ANNUAL")] = 1.0
    else
        error("unknown coef_ptr case $name")
    end
    gput!(tm, "FLO_FUNC", ff)
    gput!(tm, "FLO_SUM", fs)
    return tm
end

"What coef_ptr.mod writes, compared after it (scripts/m12_probe.jl, plus the work sets it clears at L54)."
const COEF_PTR_OUTPUTS = ["COEF_PTRAN", "RPCC_FFUNC", "PRC_CG", "KEEP_FLOF", "ACT_FLO", "CGTEST", "CGTES2", "CG_GRP", "RP_GRP"]

"Symbols coef_ptr.mod declares itself (L12-13)."
const COEF_PTR_DECLARED = Set(["CGTEST", "CGTES2"])
