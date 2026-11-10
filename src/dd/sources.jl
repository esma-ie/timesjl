# M1.4 change 2c: where the TIMES source and the open demo models come from.
#
# The DD reader compiles TIMES's own files (src/dd/compile.jl), so it needs the TIMES v4.9.7 source
# at run time. It is a pinned download (Artifacts.toml): the GitHub archive of
# etsap-TIMES/TIMES_model @ d9a6a25, fetched on first use and checked by hash (James, 10 Nov 2026).

"Full commit of `etsap-TIMES/TIMES_model` in Artifacts.toml (the `TIMES_GAMS_COMMIT` baseline)."
const TIMES_MODEL_COMMIT = "d9a6a25ad25ca080202a53d694de816ac3f7324e"

"Full commit of `etsap-TIMES/TIMES_Demo` in Artifacts.toml (CC BY 4.0)."
const TIMES_DEMO_COMMIT = "962db8603aa00850b8581e6374b4f0559c47dd52"

"""
    times_source() -> String

The folder of the TIMES v4.9.7 source (`maindrv.mod`, `initsys.mod`, ...): the pinned download of
`etsap-TIMES/TIMES_model` @ d9a6a25, fetched on first use. The environment variable
`TIMESJL_TIMES_SOURCE` names a local folder instead (a clone of the same commit, for work offline);
it must hold `maindrv.mod`.
"""
function times_source()
    p = get(ENV, "TIMESJL_TIMES_SOURCE", "")
    if !isempty(p)
        isfile(joinpath(p, "maindrv.mod")) ||
            throw(ArgumentError("TIMESJL_TIMES_SOURCE=$(repr(p)) holds no maindrv.mod"))
        return p
    end
    joinpath(artifact"TIMES_model", "TIMES_model-" * TIMES_MODEL_COMMIT)
end

"""
    times_demo_dir() -> String

The `model` folder of the pinned `etsap-TIMES/TIMES_Demo` @ 962db86 (CC BY 4.0; IEA-ETSAP), with
the demo models' run and DD files (`demo12.run`, ...), fetched on first use.
"""
times_demo_dir() = joinpath(artifact"TIMES_Demo", "TIMES_Demo-" * TIMES_DEMO_COMMIT, "model")

"""
    compile_run(runfile; dirs=String[], full=true, licencelevel=0, globals=Dict()) -> GamsCompile

Compile a TIMES run file and its DD files as GAMS does (`gams_compile!`), without GAMS. The include
path is the run file's folder, then the TIMES source ([`times_source`](@ref)), then `dirs`.
`globals` sets `\$SETGLOBAL` names before the run, as GAMS's `--name=value` does (e.g.
`RUN_NAME`). `full=false` stops at `\$BATINCLUDE maindrv.mod`.
"""
function compile_run(runfile::AbstractString; dirs=String[], full::Bool=true, licencelevel::Int=0,
                     globals=Dict{String,String}())
    g = GamsCompile(; dirs=[times_source(); String.(dirs)], full, licencelevel)
    for (k, v) in globals
        g.globals[uppercase(String(k))] = String(v)
    end
    gams_compile!(g, runfile)
end
