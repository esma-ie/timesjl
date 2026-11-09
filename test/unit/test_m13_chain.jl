# M1.3 gate in CI (docs/m13-plan.md "Gate"): TIMES_Demo demo12 reduce_off from
# the input dump through the whole preprocessing chain, TIMES.jl's own state
# carried from one segment to the next (scripts/m13_gate.jl does the same on
# the core reference runs, both variants), compared with GAMS at every
# checkpoint on every set and parameter; then on through the coefficient
# stage (coefmain.mod and coef_ext.vda), compared with the coef dump on the
# fixture's coef_symbols; then the coef -> pre-solve step (M1.3 change 25),
# compared with the pre-solve dump on every set and parameter; and finally the
# model generated from that state, against GAMS's matrix (layer 2) and
# objective (layer 3). The model is also checked from the pre-solve dump with
# REDUCE off and on (test_public_parity.jl: demo12_off, demo12_red).

using TIMES: TimesModel, DumpData, layer1, init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!,
             preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!,
             ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!,
             ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!,
             coef_shp!, coef_ext!, prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
             pp_qack_data!, pp_clean!, generate!
using TIMES.Reference: ispass, canonical_from_jump, canonical_from_dump, compare_lp
import TOML, JSON, JuMP, HiGHS

"The coef -> pre-solve step (maindrv.mod L76-111), in order (M1.3 change 25)."
const M13_COEF_PRESOLVE = (prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
                           pp_qack_data!, pp_clean!)

"The preprocessing steps by segment: (start checkpoint, next checkpoint, steps), maindrv.mod L55-58 order."
const M13_CHAIN = [
    ("input", "init", (init_ext!,)),
    ("init", "prep", (ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!)),
    ("prep", "prelv", (preppm_shape!, ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!)),
    ("prelv", "ppm", (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!,
                      ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!)),
]

"Carry `tm`'s state (every symbol read or written, and the switches) into a TimesModel of `dir` (scripts/m13_gate.jl)."
function carry_state(tm, dir)
    nt = TimesModel(dir; switches=tm.switches)
    merge!(nt.switches, tm.switches)
    merge!(nt.data.sets, tm.data.sets)
    merge!(nt.data.params, tm.data.params)
    return nt
end

chain_symbols(d) = sort([i.name for i in values(d.dump.symbols) if i.kind in (:set, :parameter) && !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV"))])

@testset "M1.3 chain: input dump -> ppm -> coefficients -> pre-solve -> model, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    for (a, b, steps) in M13_CHAIN
        names = chain_symbols(tm.data)
        foreach(f -> f(tm), steps)
        ref = DumpData(joinpath(FIXTURES, "demo12_off_" * b))
        r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n), names))
        foreach(d -> ispass(d) || println("input -> ", b, ": ", d, " ", d.examples), r)
        @test length(r) > 800 && all(ispass, r)
        tm = carry_state(tm, joinpath(FIXTURES, "demo12_off_" * b))
    end
    # coefmain.mod order, then coef_ext.vda (test_public_parity.jl, check_layer1_coef); compared on the
    # fixture's coef_symbols and on every set and parameter of the ppm dump (with the scratch scalars
    # filparam.gms, fillcost.gms and coef_ext.vda L23 leave, M1.3 change 25-5)
    names = chain_symbols(tm.data)
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    ref = DumpData(joinpath(FIXTURES, "demo12_off_coef"))
    r = layer1(tm, ref, unique(vcat(fx["coef_symbols"], filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))))
    foreach(d -> ispass(d) || println("coefficients: ", d, " ", d.examples), r)
    @test length(r) > 900 && all(ispass, r)
    @test all(n -> n in names, ("FIRST_VAL", "LAST_VAL", "MY_FYEAR", "F", "Z", "MY_F"))
    # the coef -> pre-solve step, every set and parameter at the pre-solve checkpoint
    tm = carry_state(tm, joinpath(FIXTURES, "demo12_off_coef"))
    names = chain_symbols(tm.data)
    foreach(f -> f(tm), M13_COEF_PRESOLVE)
    ref = DumpData(joinpath(FIXTURES, "demo12_off_presolve"))
    r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))
    foreach(d -> ispass(d) || println("coef -> presolve: ", d, " ", d.examples), r)
    @test length(r) > 800 && all(ispass, r)
    # the model from TIMES.jl's own state: matrix and objective against GAMS
    tm = carry_state(tm, joinpath(FIXTURES, "demo12_off_presolve"))
    generate!(tm)
    mine = canonical_from_jump(tm.model)
    gref = canonical_from_dump(joinpath(FIXTURES, "demo12_off_matrix", "matrix"), joinpath(FIXTURES, "demo12_off_matrix", "dictmap"))
    cmp = compare_lp(mine, gref)
    ispass(cmp) || foreach(println, cmp.examples)
    @test ispass(cmp)
    sol = JSON.parsefile(joinpath(FIXTURES, "demo12_off_solution.json"))
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer); JuMP.set_silent(tm.model)
    JuMP.optimize!(tm.model)
    @test JuMP.termination_status(tm.model) == JuMP.OPTIMAL
    for (_, gobj) in sol["objval"]
        @test isapprox(JuMP.objective_value(tm.model), gobj; rtol=1e-6)
    end
end
