# Running a TIMES model from its own run file and DD files, without GAMS: the order of maindrv.mod,
# compile phase to solve. James, 18 Nov 2026: a function in the package, so TIMES.jl can be used
# without cloning the repository (README, Quick start). This file holds no translated GAMS
# statement: it calls the translated files in maindrv.mod's order, as scripts/run_dd.jl did from
# 10 Nov 2026 (M1.4 change 6).

"""
    PRESOLVE_STEPS

The translated steps from the input data to the pre-solve state, in GAMS's order: each entry is
(checkpoint the step starts after, name, function), the checkpoints being those of the reference
harness (input, init, prep, prelv, ppm, coef; `docs/m13-plan.md`).

GAMS: maindrv.mod L55-113, v4.9.7:
- input -> init, L55: `main_ext.mod init_ext` (init_ext.dsc, init_ext.vda);
- init -> prep -> prelv -> ppm, L56: ppmain.mod (with preppm.mod, prep_ext.vda, pp_prelv.vda),
  then L58: `main_ext.mod ppm_ext` (ppm_ext.dsc, ppm_ext.vda);
- ppm -> coef, L72-73: coefmain.mod (coef_cpt, coef_nio, coef_ptr, coef_obj, coef_alt, coef_shp),
  then `main_ext.mod coef_ext`;
- coef -> presolve, L77-80: mod_vars.mod and eqmain.mod data (with equ_ext.vda); L92: bndmain.mod
  data; L97: pp_qack.mod data; L113: solve.mod L1, pp_clean.mod.

This is the one list of the steps: `run_model` runs it, and `scripts/m13_probe.jl` and
`scripts/m13_gate.jl` take their steps from it to check each one against GAMS. A newly translated
step goes here, in its place in GAMS's order.
"""
const PRESOLVE_STEPS = Tuple{String,String,Function}[
    ("input", "init_ext", init_ext!),               # maindrv.mod L55: the whole input -> init segment
    ("init", "ppmain_head", ppmain_head!),          # ppmain.mod L1-137
    ("init", "ppmain_years", ppmain_years!),        # ppmain.mod L138-191
    ("init", "timslice", timslice!),                # ppmain.mod L196: timslice.mod with pp_off.mod
    ("init", "ppmain_rtp", ppmain_rtp!),            # ppmain.mod L199-247
    ("init", "preppm", preppm!),                    # ppmain.mod L248: preppm.mod L1-212
    ("init", "prep_ext", prep_ext!),                # preppm.mod L213-217: the whole init -> prep segment
    ("prep", "preppm_shape", preppm_shape!),        # preppm.mod L218-252: preshape.gms
    ("prep", "ppmain_topo", ppmain_topo!),          # ppmain.mod L249-328
    ("prep", "ppmain_tslvl", ppmain_tslvl!),        # ppmain.mod L329-460
    ("prep", "ppmain_life", ppmain_life!),          # ppmain.mod L461-611
    ("prep", "pp_prelv", pp_prelv!),                # ppmain.mod L615: pp_prelv.vda, the whole prep -> prelv segment
    ("prelv", "pp_qafs", pp_qafs!),                 # ppmain.mod L617: pp_qafs.mod
    ("prelv", "ppmain_dflt", ppmain_dflt!),         # ppmain.mod L619-682
    ("prelv", "ppmain_tsattr", ppmain_tsattr!),     # ppmain.mod L683-797
    ("prelv", "ppmain_flo", ppmain_flo!),           # ppmain.mod L800-821
    ("prelv", "ppmain_flofs", ppmain_flofs!),       # ppmain.mod L823-843
    ("prelv", "ppmain_ire", ppmain_ire!),           # ppmain.mod L846-933
    ("prelv", "ppmain_bnd", ppmain_bnd!),           # ppmain.mod L936-1001
    ("prelv", "ppmain_cum", ppmain_cum!),           # ppmain.mod L1003-1056
    ("prelv", "ppmain_stg", ppmain_stg!),           # ppmain.mod L1058-1099
    ("prelv", "ppmain_uc", ppmain_uc!),             # ppmain.mod L1101-1179
    ("prelv", "ppmain_ucmap", ppmain_ucmap!),       # ppmain.mod L1181-1226
    ("prelv", "ppmain_blend", ppmain_blend!),       # ppmain.mod L1228-1333
    ("prelv", "ppmain_reduce", ppmain_reduce!),     # ppmain.mod L1336-1357, pp_reduce.red
    ("prelv", "ppm_ext_actef", ppm_ext_actef!),     # maindrv.mod L58: ppm_ext.dsc, ppm_ext.vda L11-58 with pp_actef.vda
    ("prelv", "ppm_ext", ppm_ext!),                 # ppm_ext.vda L59-169 with equcrtp.vda PPM_EXT: the whole prelv -> ppm segment
    ("ppm", "coef_cpt", coef_cpt!),                 # maindrv.mod L72: coefmain.mod in order (M1.2)
    ("ppm", "coef_nio", coef_nio!),
    ("ppm", "coef_ptr", coef_ptr!),
    ("ppm", "coef_obj", coef_obj!),
    ("ppm", "coef_alt", coef_alt!),
    ("ppm", "coef_shp", coef_shp!),
    ("ppm", "coef_ext", coef_ext!),                 # maindrv.mod L73: coef_ext.vda, the whole ppm -> coef segment
    ("coef", "prepret_decl", prepret_decl!),        # mod_vars.mod L94: prepret.dsc DECL (data)
    ("coef", "eqobjinv_prep", eqobjinv_prep!),      # eqmain.mod L34: eqobj.mod L14-39, eqobjinv.mod L18-274
    ("coef", "eqobjfix_prep", eqobjfix_prep!),      # eqobj.mod L54: eqobjfix.mod L19-175 (coef_alt.lin FIX)
    ("coef", "eqobsalv_prep", eqobsalv_prep!),      # eqobj.mod L65: eqobsalv.mod L11-82
    ("coef", "eqmain_prep", eqmain_prep!),          # eqmain.mod L65-226, equ_ext.vda L76-90
    ("coef", "bnd_data", bnd_data!),                # maindrv.mod L92: bndmain.mod data statements
    ("coef", "pp_qack_data", pp_qack_data!),        # L97: pp_qack.mod data statements
    ("coef", "pp_clean", pp_clean!),                # L113: solve.mod L1, pp_clean.mod: the whole coef -> presolve segment
]

"""
    run_switches(runfile) -> Dict{String,String}

The `\$SET`, `\$SETGLOBAL` and `\$SETLOCAL` switches written in a run file (upper-case names), less
comment lines: the switches `TimesModel` takes (OBJ, REDUCE, TIMESTEP, ...). Switches set in a file
the run file includes are not read.
"""
function run_switches(path::AbstractString)
    sw = Dict{String,String}()
    for ln in eachline(path)
        startswith(lstrip(ln), "*") && continue
        m = match(r"^\s*\$\s*set(?:global|local)?\s+(\w+)\s+'?([^'\s]*)'?"i, ln)
        m === nothing || (sw[uppercase(m[1])] = m[2])
    end
    return sw
end

"""
    run_model(runfile; dd=String[], out=nothing, solve=true, optimizer=HiGHS.Optimizer,
              threads=TIMESJL_THREADS or 12, optfile=nothing, licence_level=0, write_solution=true,
              verbose=true)

Run a TIMES model from its run file and DD files, without GAMS:

1. compile the run file and its DD files as GAMS's compile phase does (`compile_run`), with
   `SOLVE_NOW NO` set just before `maindrv.mod` (in a copy in `out`; the run file is not changed),
   and write the result as an input dump to `out`;
2. preprocess and compute the coefficients (`PRESOLVE_STEPS`), and write TIMES's QA log to
   `out/QA_CHECK.LOG`;
3. generate the model;
4. with `solve=true`, solve it (HiGHS by default, with `threads` threads; another JuMP optimizer
   takes its own options, e.g. `JuMP.optimizer_with_attributes`) and, with
   `write_solution=true`, write the level and marginal of every variable and equation to
   `out/solution/` (Arrow files);
5. after an optimal solve with %TIMESED% neither 0 nor YES (an elastic demand base run, maindrv.mod
   L121-122), write the base prices to `out/com_bprice` and `out/%GDXPATH%%RUN_NAME%_DP`, Arrow
   folders that a later run with %TIMESED% YES reads in place of GAMS's GDX files (`write_bprice`;
   docs/known-differences.md K4).

A stepped (myopic) run (`TIMESTEP`) has no single model: with `solve=true` it is solved step by step
(`solve_stepped!`), and its solution is not written yet (M1.6).

- `dd`: the folders holding the DD files, searched in order; by default the run file's folder.
- `out`: where the output goes; a new temporary folder by default.
- `optfile`: the solver option file, as GAMS TIMES reads one (solve.mod L14-15). By default
  (`nothing`), `highs.opt` in the run file's folder if there is one, as GAMS reads `<solver>.opt`
  from its working folder; a path names another file; `false` reads none. It is read for HiGHS
  only (`optimizer=HiGHS.Optimizer`): GAMS option-file lines (`solver ipm`, `run_crossover=off`,
  `*` comments) with HiGHS's own option names. A line HiGHS does not take is left out with a note,
  and `threads` stays the limit (`highs_options`). Another solver's file in the run folder, such as
  VEDA's `cplex.opt`, is not read: the run says so.
- `licence_level`: GAMS's `%SYSTEM.LICENSELEVEL%`, 0 as a full licence (`docs/known-differences.md` K3).
- `verbose`: print one line per stage, starting `==` (as `scripts/run_dd.jl` does).

A TIMES feature TIMES.jl does not translate yet ends the run with `status = :not_translated` and
the error, which names the GAMS file it would need.

Returns a named tuple: `ok` (true when the run got as far as asked: solved to optimality with
`solve=true`), `status` (`:not_translated`, `:failed`, `:generated`, `:stepped` (a stepped run not
solved), `:solved`), `termination_status` (JuMP's, or `nothing`), `objective` (or `nothing`),
`model` (the `TimesModel`; its JuMP model is `model.model`), `steps` (a stepped run's steps, or
`nothing`), `out`, `error` (or `nothing`), `optfile` (the option file read, or `nothing`) and
`solver_options` (the `name => value` pairs given to the solver, `threads` among them for HiGHS).

The results come with no comparison with GAMS: `scripts/m13_gate.jl --from-dd` checks a model of
the reference suite against its GAMS runs.

# Example
```julia
using TIMES
r = run_model(joinpath(TIMES.times_demo_dir(), "demo12.run"); out="demo12_out")
r.objective
```
"""
function run_model(runfile::AbstractString; dd=String[], out=nothing, solve::Bool=true, optimizer=HiGHS.Optimizer,
                   threads::Integer=parse(Int, get(ENV, "TIMESJL_THREADS", "12")), optfile=nothing,
                   licence_level::Integer=0, write_solution::Bool=true, verbose::Bool=true)
    say(x...) = verbose && println(x...)
    highs = optimizer === HiGHS.Optimizer
    label = highs ? "HiGHS" : "the solver"
    attrs = Pair{String,Any}[]
    highs && push!(attrs, "threads" => Int(threads))
    # HiGHS keeps one thread scheduler per process, sized by the first solve; a later solve that asks
    # for more threads stops with OTHER_ERROR ("the scheduler has already been initialized"). As the
    # HiGHS.jl README says (Threads), reset it before a solve with `threads`, so that they apply, and
    # after it, so that a later solve in the same session with HiGHS's own default is not refused.
    reset_highs() = highs && HiGHS.Highs_resetGlobalScheduler(1)
    run = abspath(runfile)
    isfile(run) || throw(ArgumentError("no run file $run"))
    dirs = isempty(dd) ? [dirname(run)] : [abspath(d) for d in dd]
    out = out === nothing ? mktempdir() : abspath(out)
    name = splitext(basename(run))[1]

    # The solver option file (solver_options.jl; GAMS: solve.mod L14-15), read before the run starts
    # so that a wrong path stops it at once. Its options follow `threads`, so a smaller `threads` in
    # the file wins; highs_options keeps a larger one to the limit.
    opt, notes = nothing, String[]
    if optfile === nothing && solve && highs
        opt, notes = find_optfile(dirname(run), "HiGHS")
    elseif optfile === nothing && solve        # another solver: its option file is not read
        for f in sort(readdir(dirname(run)))
            lf = lowercase(f)
            endswith(lf, ".opt") && lf != "convert.opt" && push!(notes, "$f not read: option files are read for HiGHS only")
        end
    elseif optfile !== nothing && optfile !== false
        opt = abspath(optfile)
        isfile(opt) || throw(ArgumentError("no option file $opt"))
        highs || throw(ArgumentError("option files are read for HiGHS only (optimizer=HiGHS.Optimizer); " *
                                     "give another solver its options with JuMP.optimizer_with_attributes"))
    end
    if opt !== nothing
        given, bad = highs_options(read_optfile(opt); threads=threads)
        append!(notes, bad)
        for p in given
            filter!(q -> q.first != p.first, attrs)
            push!(attrs, p)
        end
        say("== $name: HiGHS options from $opt: ", join(("$k $v" for (k, v) in attrs), ", "))
    end
    foreach(n -> say("== $name: option file: ", n), notes)

    result(ok, status; tm=nothing, ts=nothing, obj=nothing, steps=nothing, err=nothing) =
        (ok=ok, status=status, termination_status=ts, objective=obj, model=tm, steps=steps, out=out, error=err,
         optfile=opt, solver_options=attrs)

    # As the reference harness does (make_reference.py, runfile.py): a copy of the run file with
    # SOLVE_NOW NO just before maindrv.mod, so that GAMS's solve and report files (solve.mod L22,
    # maindrv.mod L114) are not compiled; TIMES.jl solves the model itself. The original is untouched.
    lines = readlines(run)
    i = findlast(l -> occursin(r"^\s*\$\s*batinclude\s+maindrv\.mod"i, l), lines)
    i === nothing && throw(ArgumentError("$run has no \$BATINCLUDE maindrv.mod line"))
    insert!(lines, i, "\$SET SOLVE_NOW NO")
    mkpath(out)
    run2 = joinpath(out, basename(run))
    write(run2, join(lines, "\n") * "\n")
    t = @elapsed g = compile_run(run2; dirs=dirs, licencelevel=Int(licence_level), globals=Dict("RUN_NAME" => name))
    tw = @elapsed write_dump(g, out; source="$name: compiled from its DD files by TIMES.jl")
    say("== $name: compiled in $(round(t; digits=1)) s ($(g.warnings) compile warnings), input written to $out in ",
        round(tw; digits=1), " s")
    sw = run_switches(run)
    tm = TimesModel(out; switches=sw, reduce=uppercase(get(sw, "REDUCE", "NO")) == "YES")
    qa_warnings!(tm, g.warnings)                  # $IF WARNINGS (ppmain.mod L35)

    tp = 0.0
    stp = stepped(tm)
    for (a, b) in zip(("input", "init", "prep", "prelv", "ppm", "coef"), ("init", "prep", "prelv", "ppm", "coef", "presolve"))
        try
            # a stepped run: pp_clean.mod runs inside each step (solve.mod L12), not before the loop
            tp += @elapsed for (s, _, f) in PRESOLVE_STEPS
                s == a && !(stp && f === pp_clean!) && f(tm)
            end
        catch e
            e isa UnportedError || rethrow()
            say("== $name: not translated, in $a -> $b: ", sprint(showerror, e))
            return result(false, :not_translated; tm=tm, err=e)
        end
    end
    write(joinpath(out, "QA_CHECK.LOG"), qa_text(tm))
    say("== $name: preprocessed in $(round(tp; digits=1)) s; QA log in ", joinpath(out, "QA_CHECK.LOG"))

    if stp          # M1.5: one model per step (solve.stp), generated as each step is solved
        if !solve
            say("== $name: stepped run (TIMESTEP ", gswitch(tm, "TIMESTEP", ""),
                "): one model per step, generated as each step is solved; run with --solve")
            return result(true, :stepped; tm=tm)
        end
        hook = (tm, st, info) -> say("== $name: step ", info.step, " (periods ", join(info.periods, ", "), "): ", info.rows, " rows, ",
                                     info.columns, " columns; ", label, " ", info.status, ", objective ", info.objective,
                                     "; prepared, generated, solved in ", round(info.prepare_s; digits=1), ", ",
                                     round(info.generate_s; digits=1), ", ", round(info.solve_s; digits=1), " s")
        reset_highs()
        steps = try
            solve_stepped!(tm, optimizer; attributes=attrs, step_hook=hook)
        catch e
            reset_highs()
            e isa Union{UnportedError,ErrorException} || rethrow()
            say("== $name: ", e isa UnportedError ? "not translated, in the stepped solve: " : "", sprint(showerror, e))
            return result(false, e isa UnportedError ? :not_translated : :failed; tm=tm, err=e)
        end
        reset_highs()
        say("== $name: stepped run solved in ", length(steps), " steps; objective of the last step ", steps[end].objective,
            "; the solution of a stepped run is not written yet (M1.6)")
        return result(true, :solved; tm=tm, obj=steps[end].objective, steps=steps)
    end

    tg = @elapsed generate!(tm)
    m = tm.model
    say("== $name: model generated in $(round(tg; digits=1)) s: ", JuMP.num_constraints(m; count_variable_in_set_constraints=false),
        " rows, ", JuMP.num_variables(m), " columns")
    solve || return result(true, :generated; tm=tm)
    JuMP.set_optimizer(m, optimizer)
    JuMP.set_silent(m)
    foreach(((a, v),) -> JuMP.set_attribute(m, a, v), attrs)
    reset_highs()
    ts = @elapsed JuMP.optimize!(m)
    reset_highs()
    st = JuMP.termination_status(m)
    obj = st == JuMP.OPTIMAL ? JuMP.objective_value(m) : nothing
    say("== $name: ", JuMP.solver_name(m), " ", st, " in ", round(ts; digits=1), " s", obj === nothing ? "" : ", objective $obj")
    if write_solution && JuMP.has_values(m)
        sdir = joinpath(out, "solution")
        tw = @elapsed TIMES.write_solution(tm, sdir; source="$name: solved by TIMES.jl from its DD files",
                                           solver=highs ? "HiGHS.jl $(pkgversion(HiGHS))" : JuMP.solver_name(m))
        say("== $name: solution written to $sdir in ", round(tw; digits=1), " s")
    end
    # maindrv.mod L121-122: the base prices for a later elastic demand run (%TIMESED% neither 0 nor YES)
    if st == JuMP.OPTIMAL && JuMP.has_duals(m)
        bp = write_bprice_after_solve(tm, out)
        isempty(bp) || say("== $name: base prices written to ", join(bp, " and "))
    end
    return result(st == JuMP.OPTIMAL, :solved; tm=tm, ts=st, obj=obj)
end
