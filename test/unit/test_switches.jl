# Run-switch logic that reads only the $SET switches, not model data, so it
# runs on the synthetic tiny_dump. Moved from test_coef_cpt.jl and
# test_eq_obj.jl when the DemoS fixtures were removed (27 Oct 2026).
#
# GAMS: initmty.mod L426-431 (%CTST%, OBLONG) and eqobj.mod L59, v4.9.7.

using OpenTIMES: TimesModel, ctst, objective_switches

tiny(sw) = TimesModel(joinpath(FIXTURES, "tiny_dump"); switches=sw)

@testset "ctst (initmty.mod L426-430)" begin
    @test ctst(tiny(Dict("OBJ" => "AUTO", "OBLONG" => "YES"))) == "**0"
    @test ctst(tiny(Dict("OBJ" => "mod"))) == "**0"                  # OBJ MOD sets OBLONG (L427)
    @test ctst(tiny(Dict("OBJ" => "ALT"))) == "**EPS"
    @test ctst(tiny(Dict("OBJ" => "ALT", "OBLONG" => "YES"))) == "**0"
    @test ctst(tiny(Dict("OBJ" => "LIN", "OBLONG" => "YES"))) == "**EPS"   # last applicable line wins
    @test ctst(tiny(Dict("OBJ" => "AUTO", "OBLONG" => "NO"))) == ""
end

@testset "objective switches (initmty.mod L426-431, eqobj.mod L59)" begin
    sw(d) = objective_switches(tiny(d))
    @test sw(Dict("OBJ" => "AUTO", "MID_YEAR" => "YES", "OBLONG" => "YES", "VARCOST" => "LIN")) ==
          (obj="AUTO", oblong=true, ctst="**0", varcost="LIN", objvar_obj="AUTO")
    @test sw(Dict{String,String}()).ctst == ""
    @test sw(Dict("OBJ" => "MOD")).ctst == "**0"                       # MOD implies OBLONG
    @test sw(Dict("OBJ" => "LIN", "OBLONG" => "YES")).ctst == "**EPS"   # L430 comes last
    alt = sw(Dict("OBJ" => "ALT", "OBLONG" => "YES"))
    @test alt.varcost == "LIN" && alt.objvar_obj == "LIN" && alt.ctst == "**0"
end
