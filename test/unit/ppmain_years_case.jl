# Crafted states for ppmain.mod L138-191 (v4.9.7): the TIMES_Demo demo12 init
# checkpoint (test/fixtures/demo12_off_init) given the data no core reference
# run has, so that the paths of L138-191 the core models do not reach are
# checked against ppmain.mod L1-191 run by GAMS itself
# (scripts/make_ppmain_years_unit.jl, test/unit/test_m13_ppmain_years.jl).
#
# demo12 runs with OBJ MOD (so OBLONG, and ALTOBJ stays 1: the periods are
# rebuilt at L150-155). MILESTONYR is 2005, 2010, 2015, 2020, 2030, 2050 and
# its periods are contiguous; B(2005) = E(2005) = 2005, E(2050) = 2052.

using OpenTIMES: TimesModel, gvalues, gmembers, gput!, gput_scalar!
import TOML

"""
The cases run by GAMS:

- "altobj": 2020 left out of MILESTONYR, B(2005) = 1990 and E(2050) = 2100,
  so L153 resets B(2005) to 2005 and L154 resets E(2050) from B(2050) =
  2041, where MOD(2050-2041+1,5) = 0: `1\$MOD(...)` binding first gives 2060,
  `(...)\$MOD(...)` would delete E(2050).
- "altobj_mod": 2020 and 2030 left out and E(2050) = 2100: B(2050) = 2033,
  MOD(18,5) = 3, E(2050) = 2067.
- "offthd5": G_OFFTHD 0.4 at 2010, EPS at 2012 (an EPS data year, not a
  milestone) and 0.8 at 2030, no option (5: forward extrapolation only).
- "offthd1", "offthd2", "offthd14", "offthdneg", "offthdeps": the same data
  with G_OFFTHD('0') = 1 (interpolation only), 2 (EPS outside the data), 14
  (last digit 4: backward only), -1 (nothing) and EPS.

And one for Julia only (GAMS ABORTs): "oblong_gap", OBJ STD (ALTOBJ 0) with
OBLONG and a one-year gap after 2010 (E(2010) = 2011), so L159 aborts.
"""
const PPMAIN_YEARS_CASES = ["altobj", "altobj_mod", "offthd5", "offthd1", "offthd2", "offthd14", "offthdneg", "offthdeps"]

function ppmain_years_start(fixtures, name)
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(fixtures, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(fixtures, "demo12_off_init"); switches=Dict{String,String}(k => string(v) for (k, v) in fx["switches"]))
    ppmain_years_case!(tm, name)
    return tm
end

function ppmain_years_case!(tm, name)
    put!(n, pairs...) = (v = gvalues(tm, n, 1); foreach(((k, x),) -> v[(k,)] = x, pairs); gput!(tm, n, v))
    drop_t!(ys...) = gput!(tm, "MILESTONYR", filter(k -> !(k[1] in ys), gmembers(tm, "MILESTONYR", 1)))
    offthd = ("2010" => 0.4, "2012" => 0.0, "2030" => 0.8)            # 0.0 is EPS
    if name == "altobj"
        drop_t!("2020")
        put!("B", "2005" => 1990.0)
        put!("E", "2050" => 2100.0)
    elseif name == "altobj_mod"
        drop_t!("2020", "2030")
        put!("E", "2050" => 2100.0)
    elseif name == "offthd5"
        put!("G_OFFTHD", offthd...)
    elseif startswith(name, "offthd")
        opt = Dict("offthd1" => 1.0, "offthd2" => 2.0, "offthd14" => 14.0, "offthdneg" => -1.0, "offthdeps" => 0.0)[name]
        put!("G_OFFTHD", offthd..., "0" => opt)
    elseif name == "oblong_gap"
        tm.switches["OBJ"] = "STD"
        tm.switches["OBLONG"] = "YES"
        gput_scalar!(tm, "ALTOBJ", 0.0)
        put!("E", "2010" => 2011.0)
    else
        error("unknown ppmain_years case $name")
    end
    return tm
end

"What ppmain.mod L138-191 writes, compared after it."
const PPMAIN_YEARS_OUTPUTS = ["B", "E", "D", "M", "ALTOBJ", "MIYR_1", "MIYR_V1", "MIYR_VL", "PASTYEAR", "LEAD", "LAGT", "IPD", "FPD",
                              "MINYR", "PYR_V1", "MIYR_L", "PASTMILE", "EOHYEARS", "PERIODYR", "G_OFFTHD"]
