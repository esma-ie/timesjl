# M1.4 change 2c: the pinned TIMES source (Artifacts.toml), and demo12 compiled from its own DD files
# with no GAMS, against the input dump of the licensed reference run (fixture demo12_off_input).
# M1.4 change 6: the same for every demo12 variant with an input fixture (reference/crafted.toml):
# its DD files are TIMES_Demo's and its own (reference/dd/<case>, in this repository).
# TIMES_Demo is CC BY 4.0 (redistribute = "public" in reference/suite.toml and reference/crafted.toml).
using Test, TOML
using TIMES: times_source, times_demo_dir, compile_run, grecords, gdx_uels, gdx_symbols,
             TIMES_MODEL_COMMIT, TIMES_GAMS_COMMIT
using TIMES.Reference: load_dump, read_symbol, SV_EPS

@test startswith(TIMES_MODEL_COMMIT, TIMES_GAMS_COMMIT)
src = times_source()
@test all(f -> isfile(joinpath(src, f)), ("maindrv.mod", "initsys.mod", "initmty.mod", "eqobj.mod"))

const FIX = joinpath(@__DIR__, "..", "fixtures")
const REFDIR = joinpath(@__DIR__, "..", "..", "reference")

"The include directories of a suite or crafted case: {times_demo} the pinned download, {crafted} reference/dd."
function case_dirs(model)
    model == "TIMES_Demo-demo12" && return [times_demo_dir()]
    e = only(filter(m -> m["name"] == model, TOML.parsefile(joinpath(REFDIR, "crafted.toml"))["model"]))
    map(e["idirs"]) do d
        startswith(d, "{times_demo}/model") ? times_demo_dir() :
        startswith(d, "{crafted}") ? normpath(joinpath(REFDIR, "dd", d[length("{crafted}/")+1:end])) : error("root of $d")
    end
end

"""
Compile `runfix`/tjl_presolve.run (the harness's patched run file, reference/python/runfile.py
`patch_run`, kept as a fixture) with the case's DD files and compare it with the input fixture: the
symbols GAMS's GDX file holds (G57) both ways; every set and parameter (keys, record order, values,
EPS, element text); the label order (G55); no compile warning.
"""
function check_dd_case(model, runfix, inputfix)
    d = load_dump(joinpath(FIX, inputfix))
    g = compile_run(joinpath(FIX, runfix, "tjl_presolve.run"); dirs=[case_dirs(model); joinpath(REFDIR, "gams")],
                    globals=Dict("RUN_NAME" => model))
    names = Set(uppercase(s.name) for s in gdx_symbols(g))
    @test isempty(setdiff(keys(d.symbols), names))
    @test isempty(setdiff(names, keys(d.symbols)))
    bad = String[]
    for (k, info) in d.symbols
        info.kind in (:set, :parameter) || continue
        s = g.syms[k]
        ks, vs = grecords(g, s)
        r = read_symbol(d, k)
        if ks != [collect(x) for x in r.keys]
            push!(bad, "$k: keys")
        elseif info.kind === :set
            vs == r.text || push!(bad, "$k: text")
        else
            v, sp = r.values["value"], r.special["value"]
            all(i -> (vs[i][2] === :eps) == (sp[i] == SV_EPS) &&
                     (vs[i][2] === :eps || vs[i][1] == v[i] || abs(vs[i][1] - v[i]) <= 1e-9 * max(1, abs(v[i]))), eachindex(vs)) ||
                push!(bad, "$k: values")
        end
    end
    @test isempty(bad)
    @test gdx_uels(g) == d.uels
    @test g.warnings == 0
end

# demo12, reduce_off (fixture demo12_off_run, demo12_off_input)
@testset "demo12" begin
    check_dd_case("TIMES_Demo-demo12", "demo12_off_run", "demo12_off_input")
end

# every demo12 variant with an input fixture; each <prefix>_run is the run file of the variant its
# <prefix>_input comes from (as_run, demo12_qa reduce_off). demo12_qa99 has no run fixture: its
# reference run is not on the reference machine.
@testset "variant $p" for p in ("demo12_uc", "demo12_refit", "demo12_refit_afc", "demo12_curex", "demo12_ucdyn",
                                "demo12_ucattr", "demo12_flomrk", "demo12_mrkx", "demo12_cumc", "demo12_ashar",
                                "demo12_lev", "demo12_levstd", "demo12_bndc", "demo12_flobnd", "demo12_flofr",
                                "demo12_ls", "demo12_lst", "demo12_pf", "demo12_pfd", "demo12_qa")
    check_dd_case("TIMES_Demo-" * p, p * "_run", p * "_input")
end

# M1.4 change 7: the controls of restart and stepped runs (initmty.mod L440-447). demo12_step sets
# TIMESTEP 20; L443 runs after compilation and finds 20 in AGE. Input fixture only: the stepped
# solve (solve.stp) is M1.5.
@testset "stepped-run controls, initmty.mod L442-444" begin
    @testset "demo12_step: TIMESTEP 20" begin
        check_dd_case("TIMES_Demo-demo12_step", "demo12_step_run", "demo12_step_input")
        g = compile_run(joinpath(FIX, "demo12_step_run", "tjl_presolve.run");
                        dirs=[case_dirs("TIMES_Demo-demo12_step"); joinpath(REFDIR, "gams")],
                        globals=Dict("RUN_NAME" => "TIMES_Demo-demo12_step"))
        @test g.globals["STEPPED"] == "+" && g.globals["VAR_UC"] == "YES"      # L446-447
    end
    # demo12 with the controls given as on the command line (--TIMESTEP=5): members of AGE (1*200),
    # of ALLYEAR (1960*2200), of J (1*999) or YES pass; anything else is GAMS's ABORT
    ctl(gl) = compile_run(joinpath(FIX, "demo12_off_run", "tjl_presolve.run");
                          dirs=[case_dirs("TIMES_Demo-demo12"); joinpath(REFDIR, "gams")],
                          globals=merge(Dict("RUN_NAME" => "TIMES_Demo-demo12"), gl))
    g = ctl(Dict("TIMESTEP" => "5", "FIXBOH" => "2010", "SPOINT" => "YES"))
    @test g.globals["STEPPED"] == "+"
    @test ctl(Dict("FIXBOH" => "2010", "SPOINT" => "3")).globals["STEPPED"] == "-"       # L445
    @test_throws "Invalid Control: TIMESTEP" ctl(Dict("TIMESTEP" => "250"))
    @test_throws "Invalid Control: TIMESTEP" ctl(Dict("TIMESTEP" => "YES"))
    @test_throws "Invalid Control: FIXBOH" ctl(Dict("FIXBOH" => "1950"))
    @test_throws "Invalid Control: SPOINT" ctl(Dict("SPOINT" => "NO"))
end
