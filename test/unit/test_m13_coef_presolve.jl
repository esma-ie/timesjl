# M1.3 changes 25-1 and 25-2: the coef -> pre-solve step, from GAMS's coef dump to its
# pre-solve dump (docs/m13-plan.md): prepret.dsc DECL (mod_vars.mod L94, early retirement),
# the data statements of eqobj.mod L14-39 (with prepret.dsc EQOBJ), eqobjinv.mod L18-274
# (with coef_alt.lin INV under OBJ MOD), eqobjfix.mod L19-175 (with coef_alt.lin FIX) and
# eqobsalv.mod L11-82. Compared at 1e-9 on the symbols they settle
# that nothing later in the step changes.

using TIMES: TimesModel, DumpData, layer1, prepret_decl!, prepret_decl_symbols, eqobjinv_prep!,
             eqobjinv_prep_symbols, eqobjfix_prep!, eqobjfix_prep_symbols, eqobsalv_prep!, eqobsalv_prep_symbols, gset, gparam
using TIMES.Reference: ispass
import TOML

let refit = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
                 if v["prefix"] == "demo12_refit")
    cases = [("demo12_off", Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VAR_UC" => "YES"), 51),
             ("demo12_refit", refit["switches"], 66),
             ("demo12_objinv", refit["switches"], 51)]            # the same demo12 switches as the refit case
    for (prefix, sw, nsym) in cases
        @testset "$prefix: coef -> presolve, eqobj and eqobjinv data" begin
            tm = TimesModel(joinpath(FIXTURES, prefix * "_coef"); switches=sw)
            prepret_decl!(tm)
            eqobjinv_prep!(tm)
            eqobjfix_prep!(tm)                      # change 25-2
            eqobsalv_prep!(tm)
            names = vcat(prepret_decl_symbols(tm), eqobjinv_prep_symbols(tm), eqobjfix_prep_symbols(tm),
                         eqobsalv_prep_symbols(tm))
            r = layer1(tm, DumpData(joinpath(FIXTURES, prefix * "_presolve")), names)
            foreach(d -> ispass(d) || println("$prefix: ", d, " ", d.examples), r)
            @test length(r) == nsym && all(ispass, r)
            if prefix == "demo12_objinv"
                # case 2b (ILED with repeated investments) and the decommissioning spreads
                @test !isempty(gset(tm, "OBJ_2B")) && !isempty(gset(tm, "OBJ_SUMIII"))
                # eqobsalv.mod: decommissioning salvage (SALV_DEC) and the surveillance spreads
                @test !isempty(gparam(tm, "SALV_DEC"))
            end
            if prefix == "demo12_refit"
                # prepret.dsc L62 forces the retiring refit vintages into investment case 2a
                @test ("REG1", "2010", "ELCRFCOA01") in gset(tm, "OBJ_2A")
            end
        end
    end
end
