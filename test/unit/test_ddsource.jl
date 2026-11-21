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
                                "demo12_lev", "demo12_levstd", "demo12_bndc", "demo12_flobnd", "demo12_flofr", "demo12_irebnd", "demo12_xbnd", "demo12_disp",
                                "demo12_blnd", "demo12_capvac", "demo12_bndcst", "demo12_ucv",
                                "demo12_ls", "demo12_lst", "demo12_pf", "demo12_pfd", "demo12_qa", "demo12_ed", "demo12_edagg", "demo12_tsoff_rint")
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
    # M1.5 change 5: the second stepped case, with DD files of its own (G_OVERLAP, CAP_BND, REG_CUMCST,
    # user constraints summed over regions and periods)
    @testset "demo12_step2: TIMESTEP 20, G_OVERLAP 15" begin
        check_dd_case("TIMES_Demo-demo12_step2", "demo12_step2_run", "demo12_step2_input")
    end
    # M1.5 change 6: a stepped run with OBJ LIN (the DD files of demo12_objinv)
    @testset "demo12_steplin: OBJ LIN, TIMESTEP 20" begin
        check_dd_case("TIMES_Demo-demo12_steplin", "demo12_steplin_run", "demo12_steplin_input")
    end
    # M1.5 change 7: a stepped run with the DD files of five other crafted cases (uc.dd, blnd.dd, ips.dd,
    # refit.dd, ls.dd)
    @testset "demo12_step3: TIMESTEP 20, dispatching, blending, storage, retirement" begin
        check_dd_case("TIMES_Demo-demo12_step3", "demo12_step3_run", "demo12_step3_input")
    end
    # initmty.mod L420-432: ALTOBJ is 1 by its declaration; the OBJ and OBLONG controls of the run file
    # set it (L421 STD: 0; L422 ALT: 2; L423 LIN: 3; L432 OBLONG with ALT: -2). The run file of
    # demo12_steplin with its OBJ line replaced. GAMS's values of LIN and ALT are in the input dumps of
    # the crafted cases; STD and OBLONG with ALT follow the source (no reference run has them).
    @testset "the alternative objective controls, initmty.mod L420-432" begin
        run = read(joinpath(FIX, "demo12_steplin_run", "tjl_presolve.run"), String)
        line = r"\$ +SET +OBJ +LIN"
        @test count(line, run) == 1
        altobj(ctl) = mktempdir() do dir
            f = joinpath(dir, "tjl_presolve.run")
            write(f, replace(run, line => ctl))
            g = compile_run(f; dirs=[case_dirs("TIMES_Demo-demo12_steplin"); joinpath(REFDIR, "gams")],
                            globals=Dict("RUN_NAME" => "TIMES_Demo-demo12_steplin"))
            only(grecords(g, g.syms["ALTOBJ"])[2])[1]
        end
        @test altobj("\$   SET OBJ LIN") == 3
        @test altobj("\$   SET OBJ ALT") == 2
        @test altobj("\$   SET OBJ STD") == 0
        @test altobj("\$   SET OBJ MOD") == 1 && altobj("\$   SET OBJ AUTO") == 1
        @test altobj("\$   SET OBJ ALT\n\$   SET OBLONG YES") == -2
        @test altobj("\$   SET OBJ LIN\n\$   SET OBLONG YES") == 3
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

# M1.3 change 70: the stochastic extension's declarations and data (initmty.mod L435-437, initmty.stc),
# eight crafted cases, each compiled from its DD files to GAMS's input dump (as_run). demo12_sensis also
# reaches the report writer that solve.stc L7 compiles under SENSIS (rptlite.rpt with solsysd.v3: G63, and
# the Latin-1 label of rptlite.rpt L53). Their model fixtures come with changes 71-76 (docs/m13-plan.md).
@testset "stochastic $p" for p in ("demo12_stc", "demo12_stc3", "demo12_stcmx", "demo12_stclam", "demo12_stcext",
                                   "demo12_spines", "demo12_sensis", "demo12_tradeoff")
    check_dd_case("TIMES_Demo-" * p, p * "_run", p * "_input")
end

# G63 (GAMS 54.6.1, 20 Nov 2026): $GOTO goes to the first `$LABEL name` from the top, with the name
# substituted, and the dollar commands after the name run, also after the jump (solsysd.v3 L7-14)
@testset "\$GOTO and \$LABEL, G63" begin
    mktempdir() do dir
        write(joinpath(dir, "b.gms"), """
            \$SETARGS P1 P2
            \$GOTO %1
            \$LABEL X SHIFT
            SET S / %1 /;
            \$IF NOT '%2'=='' \$GOTO %P1%
            \$EXIT
            \$LABEL %P1% SHIFT SHIFT
            SET T / %1 /;
            """)
        for (call, s, t) in (("X one two three", ["one", "two", "three"], nothing), ("Y one two three", nothing, ["two"]))
            write(joinpath(dir, "a.run"), "\$ONMULTI\n\$BATINCLUDE b.gms $call\n")
            g = compile_run(joinpath(dir, "a.run"))
            mem(n) = haskey(g.syms, n) ? [only(k) for k in grecords(g, g.syms[n])[1]] : nothing
            @test mem("S") == s
            @test mem("T") == t
        end
        # $EOLCOM takes one marker, then the rest of the line runs
        write(joinpath(dir, "c.run"), "\$EOLCOM ! SETGLOBAL Z 1\nSET U / u1 / ! a comment\n")
        g = compile_run(joinpath(dir, "c.run"))
        @test g.globals["Z"] == "1"
        @test [only(k) for k in grecords(g, g.syms["U"])[1]] == ["u1"]
    end
end
