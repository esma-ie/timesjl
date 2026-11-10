# M1.4 change 2c: the pinned TIMES source (Artifacts.toml), and demo12 compiled from its own DD files
# with no GAMS, against the input dump of the licensed reference run (fixture demo12_off_input).
# TIMES_Demo is CC BY 4.0 (redistribute = "public" in reference/suite.toml).
using Test
using TIMES: times_source, times_demo_dir, compile_run, grecords, gdx_uels, gdx_symbols,
             TIMES_MODEL_COMMIT, TIMES_GAMS_COMMIT
using TIMES.Reference: load_dump, read_symbol, SV_EPS

@test startswith(TIMES_MODEL_COMMIT, TIMES_GAMS_COMMIT)
src = times_source()
@test all(f -> isfile(joinpath(src, f)), ("maindrv.mod", "initsys.mod", "initmty.mod", "eqobj.mod"))

# The run file is the harness's (reference/python/runfile.py patch_run) for the reduce_off variant,
# kept as a fixture (test/fixtures/demo12_off_run): REDUCE and SOLVE_NOW set to NO, `option LP=`
# left out, the TJLREF extension (reference/gams/*.tjlref) and the input checkpoint added. Its DD
# files come from the pinned TIMES_Demo.
d = load_dump(joinpath(@__DIR__, "..", "fixtures", "demo12_off_input"))
run = joinpath(@__DIR__, "..", "fixtures", "demo12_off_run", "tjl_presolve.run")
g = compile_run(run; dirs=[times_demo_dir(), joinpath(@__DIR__, "..", "..", "reference", "gams")],
                globals=Dict("RUN_NAME" => "TIMES_Demo-demo12"))

# every symbol of the dump declared, and no other the GDX file would hold (G57)
names = Set(uppercase(s.name) for s in gdx_symbols(g))
@test isempty(setdiff(keys(d.symbols), names))
@test isempty(setdiff(names, keys(d.symbols)))

# every set and parameter: keys, record order, values, EPS, element text
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
                 (vs[i][2] === :eps || abs(vs[i][1] - v[i]) <= 1e-9 * max(1, abs(v[i]))), eachindex(vs)) ||
            push!(bad, "$k: values")
    end
end
@test isempty(bad)
@test gdx_uels(g) == d.uels                     # the label order of the GDX file (G55)
@test g.warnings == 0
