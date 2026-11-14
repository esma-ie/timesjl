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
             pp_qack_data!, pp_clean!, generate!, qa_carry!, qa_text, qa_compare
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
    return qa_carry!(nt, tm)                    # the QA log goes on (M1.3 change 25b-1)
end

"Every set and parameter of the dump `d` (less the QA-log scalars unless `qa`: pp_qack.mod's log is change 25b-2)."
chain_symbols(d; qa=true) = sort([i.name for i in values(d.dump.symbols) if i.kind in (:set, :parameter) &&
                                  (qa || !(i.name in ("PUTOUT", "PUTGRP", "ERRLEV")))])

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
    # the QA log written by preprocessing against GAMS's QA_CHECK.LOG of the pre-solve run (M1.3 change 25b-1)
    qok, note = qa_compare(qa_text(tm), read(joinpath(FIXTURES, "demo12_off_qa_check.log"), String))
    qok || println("QA log: ", note)
    @test qok
    @test occursin("COM_FR does not sum to unity", qa_text(tm))
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
    # the whole QA log, pp_qack.mod's checks included (M1.3 change 25b-2)
    qok, note = qa_compare(qa_text(tm), read(joinpath(FIXTURES, "demo12_off_qa_check.log"), String); complete=true)
    qok || println("QA log: ", note)
    @test qok
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

# M1.4 change 5: the same run with no GAMS state at all. The input is compiled from demo12's own run
# and DD files (the pinned TIMES_Demo and TIMES sources, test_ddsource.jl) and written as a dump;
# TIMES.jl's state then goes on alone through every segment (no checkpoint dump is read into it) to
# the model, which is compared with GAMS's matrix and objective (scripts/m13_gate.jl --from-dd).
# M1.4 change 9: the same for every crafted case with a run fixture (reference/crafted.toml; its DD
# files are TIMES_Demo's and its own, reference/dd/<case>), in the variant of its fixtures (as run).
using TIMES: compile_run, write_dump, times_demo_dir, qa_warnings!
using TIMES.Reference: load_dump, compare_dumps

"The DD folders of demo12 or of a crafted case (reference/crafted.toml `idirs`), then reference/gams."
function chain_dirs(model)
    ref = joinpath(@__DIR__, "..", "..", "reference")
    model == "TIMES_Demo-demo12" && return [times_demo_dir(), joinpath(ref, "gams")]
    e = only(filter(m -> m["name"] == model, TOML.parsefile(joinpath(ref, "crafted.toml"))["model"]))
    dirs = map(e["idirs"]) do d
        startswith(d, "{times_demo}/model") ? times_demo_dir() :
        startswith(d, "{crafted}") ? normpath(joinpath(ref, "dd", d[length("{crafted}/")+1:end])) : error("root of $d")
    end
    return [dirs; joinpath(ref, "gams")]
end

"""
The fixture entry `fx` (prefix, model, reduce, switches) from its run file and DD files to the model,
on TIMES.jl's state alone: the compile against `<prefix>_input` (every symbol and the label order),
the state after the coef -> pre-solve step against `<prefix>_presolve` (every set and parameter),
the QA log against `<prefix>_qa_check.log` (`qalog`), and, with `matrix`, the model against GAMS's
matrix (`<prefix>_matrix`, layer 2) and the HiGHS optimum against GAMS's objective (layer 3).
"""
function dd_chain(fx; qalog=false, matrix=true)
    p, fix = fx["prefix"], s -> joinpath(FIXTURES, fx["prefix"] * s)
    g = compile_run(joinpath(fix("_run"), "tjl_presolve.run"); dirs=chain_dirs(fx["model"]), globals=Dict("RUN_NAME" => fx["model"]))
    dir = write_dump(g, mktempdir(); source="$p, compiled from its DD files")
    r = compare_dumps(load_dump(dir), load_dump(fix("_input")))
    @test length(r.symbols) > 800 && all(ispass, r.symbols) && isempty(r.only_left) && isempty(r.only_right)
    @test load_dump(dir).uels == load_dump(fix("_input")).uels
    tm = TimesModel(dir; switches=fx["switches"], reduce=get(fx, "reduce", false))
    qa_warnings!(tm, g.warnings)
    names = chain_symbols(tm.data)
    for (a, b, steps) in M13_CHAIN
        foreach(f -> f(tm), steps)
    end
    coef_cpt!(tm); coef_nio!(tm); coef_ptr!(tm); coef_obj!(tm); coef_alt!(tm); coef_shp!(tm); coef_ext!(tm)
    foreach(f -> f(tm), M13_COEF_PRESOLVE)
    ref = DumpData(fix("_presolve"))
    r = layer1(tm, ref, filter(n -> haskey(ref.dump.symbols, n) && n != "TJL_SOLVEINFO", names))
    foreach(d -> ispass(d) || println(p, ", DD files -> presolve: ", d, " ", d.examples), r)
    @test length(r) > 800 && all(ispass, r)
    if qalog
        qok, note = qa_compare(qa_text(tm), read(fix("_qa_check.log"), String); complete=true)
        qok || println(p, ", QA log: ", note)
        @test qok
    end
    matrix || return
    generate!(tm)
    cmp = compare_lp(canonical_from_jump(tm.model), canonical_from_dump(joinpath(fix("_matrix"), "matrix"),
                                                                        joinpath(fix("_matrix"), "dictmap")))
    ispass(cmp) || foreach(println, cmp.examples)
    @test ispass(cmp)
    @test JuMP.num_constraints(tm.model; count_variable_in_set_constraints=false) == fx["rows"]
    JuMP.set_optimizer(tm.model, HiGHS.Optimizer); JuMP.set_silent(tm.model)
    JuMP.optimize!(tm.model)
    @test JuMP.termination_status(tm.model) == JuMP.OPTIMAL
    for (_, gobj) in JSON.parsefile(fix("_solution.json"))["objval"]
        @test isapprox(JuMP.objective_value(tm.model), gobj; rtol=1e-6)
    end
end

const PUBLIC_FX = TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]

@testset "M1.4: DD files -> input -> pre-solve -> model, TIMES_Demo demo12, no GAMS state" begin
    dd_chain(only(filter(f -> f["prefix"] == "demo12_off", PUBLIC_FX)); qalog=true)
end

# Every public fixture of a crafted case that has its run file (<prefix>_run): 20 cases, each a whole
# model. demo12_uc (unit commitment) has no matrix fixture: its compile is checked, and the chain
# stops in coef_ext! with the refusal of eqlducs.vda, which is not translated.
const CRAFTED_FX = filter(f -> f["prefix"] != "demo12_off" && isdir(joinpath(FIXTURES, f["prefix"] * "_run")), PUBLIC_FX)

@testset "M1.4: DD files -> model, crafted cases, no GAMS state" begin
    @test length(CRAFTED_FX) == 20
    @testset "$(fx["prefix"])" for fx in CRAFTED_FX
        dd_chain(fx)
    end
    @testset "demo12_uc (compiled, then refused: unit commitment)" begin
        uc = only(filter(v -> v["prefix"] == "demo12_uc", TOML.parsefile(joinpath(FIXTURES, "variant_fixtures.toml"))["variant"]))
        @test_throws "not yet translated: eqlducs.vda L12-41" dd_chain(uc; matrix=false)
    end
end
