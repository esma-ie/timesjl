# Crafted states for ppmain.mod L1228-1333 (v4.9.7): the blending block
# without blending data. The TIMES_Demo demo12 prelv checkpoint
# (test/fixtures/demo12_off_prelv) is given a REFUNIT for REG1, and GAMS
# runs ppmain.mod L616-1333 itself on it (scripts/make_ppmain_blend_unit.jl;
# test/unit/test_m13_ppmain_blend.jl).

using OpenTIMES: TimesModel, gvalues, gput!
import TOML

"""
The case run by GAMS:

- "blend": REFUNIT(REG1) = 2 given (kept by L1251), REG2 without (set to 1).
"""
const PPMAIN_BLEND_CASES = ["blend"]

function ppmain_blend_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_prelv"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    name == "blend" || error("unknown ppmain_blend case $name")
    gput!(tm, "REFUNIT", Dict{Tuple{String},Float64}(("REG1",) => 2.0))
    return tm
end

"What ppmain.mod L1228-1333 writes, on top of ppmain.mod L616-1226, compared at L1333."
const PPMAIN_BLEND_NEW = ["REFUNIT", "BLE_SPE", "BLE_TP", "BLE_SPEOPR", "BLE_OPR", "BLE_INP", "BLE_SPEINP", "BLE_ENV", "BLE_BAL", "BL_UNIT",
                          "PEAKDA_BL", "RU_CVT", "RU_FEQ"]

"What ppmain.mod L1228-1333 declares itself (L1236-1243)."
const PPMAIN_BLEND_DECLARED_NEW = ["BLE_SPE", "BLE_TP", "BLE_SPEOPR", "BLE_OPR", "BLE_INP", "BLE_SPEINP", "BLE_ENV", "BLE_BAL"]
