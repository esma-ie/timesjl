# M1.3 change 25 (25-1 to 25-4): the coef -> pre-solve step, from GAMS's coef dump to its
# pre-solve dump (docs/m13-plan.md): prepret.dsc DECL (mod_vars.mod L94, early retirement),
# the data statements of eqobj.mod L14-39 (with prepret.dsc EQOBJ), eqobjinv.mod L18-274
# (with coef_alt.lin INV under OBJ MOD), eqobjfix.mod L19-175 (with coef_alt.lin FIX) and
# eqobsalv.mod L11-82; eqmain.mod's own data statements and equ_ext.vda's (25-3); bndmain.mod,
# pp_qack.mod and pp_clean.mod (25-4); compared on every set and parameter of the pre-solve dump. Compared at 1e-9 on the symbols they settle
# that nothing later in the step changes.

using TIMES: TimesModel, DumpData, layer1, prepret_decl!, prepret_decl_symbols, eqobjinv_prep!,
             eqobjinv_prep_symbols, eqobjfix_prep!, eqobjfix_prep_symbols, eqobsalv_prep!, eqobsalv_prep_symbols, eqmain_prep!,
             eqmain_prep_symbols, bnd_data!, pp_qack_data!, pp_clean!, gset, gparam
using TIMES.Reference: ispass
import TOML

let refit = only(v for v in TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]
                 if v["prefix"] == "demo12_refit")
    cases = [("demo12_off", Dict("OBJ" => "MOD", "VDA" => "YES", "DSCAUTO" => "YES", "VAR_UC" => "YES",
                                  "XTQA" => "YES"), 820),
             ("demo12_refit", refit["switches"], 821),
             ("demo12_objinv", refit["switches"], 820)]            # the same demo12 switches as the refit case
    for (prefix, sw, nsym) in cases
        @testset "$prefix: coef -> presolve, eqobj and eqobjinv data" begin
            tm = TimesModel(joinpath(FIXTURES, prefix * "_coef"); switches=sw)
            prepret_decl!(tm)
            eqobjinv_prep!(tm)
            eqobjfix_prep!(tm)                      # change 25-2
            eqobsalv_prep!(tm)
            eqmain_prep!(tm)                        # change 25-3
            bnd_data!(tm); pp_qack_data!(tm); pp_clean!(tm)   # change 25-4
            # every set and parameter of the pre-solve dump (less the QA-log scalars, 25b, and the harness's own)
            ref = DumpData(joinpath(FIXTURES, prefix * "_presolve"))
            names = sort([i.name for i in values(ref.dump.symbols) if i.kind in (:set, :parameter) &&
                          !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV", "TJL_SOLVEINFO"))])
            r = layer1(tm, ref, names)
            foreach(d -> ispass(d) || println("$prefix: ", d, " ", d.examples), r)
            @test length(r) >= nsym && all(ispass, r)
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
