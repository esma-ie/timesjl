# M1.4 change 1: parse every DD and run file of the open suite models with src/dd/ddparse.jl.
#
#   julia --project=. scripts/m14_parse_suite.jl [--sources ../timesjl-sources] [folder ...]
#
# With no folders, it reads the open models' scenario folders below --sources (CLAUDE.md: open
# licences only; never TIM or JRC-EU-TIMES). Prints, per folder, the files, the SET and PARAMETER
# symbols, the records, and the parse time; a DDSyntaxError stops with the file and line.
using TIMES: parse_dd_file, DDSymbol, DDDirective

const OPEN_FOLDERS = [
    "TIMES_Demo/model",
    "TIMES-NZ/dd/steady-v308", "TIMES-NZ/dd/shift-v308",
    "OTCGEN/dd/gc_ref", "OTNYC/dd/s1_nyc_ref",
    "OTUS9r/dd/reference", "OTUS9r/dd/tax1_wo_mou",
]

function main(args)
    sources = joinpath(@__DIR__, "..", "..", "timesjl-sources")
    folders = String[]
    i = 1
    while i <= length(args)
        if args[i] == "--sources"
            sources = args[i+1]; i += 2
        else
            push!(folders, args[i]); i += 1
        end
    end
    isempty(folders) && (folders = [joinpath(sources, f) for f in OPEN_FOLDERS])
    for d in folders
        isdir(d) || (println("== $d: not found, skipped"); continue)
        files = sort(filter(f -> endswith(lowercase(f), ".dd") || endswith(lowercase(f), ".run"), readdir(d; join=true)))
        nsym = nrec = ndir = 0; bytes = 0
        t = @elapsed for f in files
            it = parse_dd_file(f)
            bytes += filesize(f)
            for x in it
                x isa DDSymbol && (nsym += 1; nrec += length(x.records))
                x isa DDDirective && (ndir += 1)
            end
        end
        println("== $(relpath(d, sources)): PASS · $(length(files)) files, $(round(bytes / 2^20, digits=1)) MB · ",
            "$nsym symbols, $nrec records, $ndir dollar lines · $(round(t, digits=1)) s")
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main(ARGS)
end
