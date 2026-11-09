# M1.4 changes 2-4: GAMS's compile phase (src/dd/compile.jl) on small synthetic run files. The TIMES
# source is not in CI; scripts/m14_probe.jl checks the real run files against the input dumps on
# James's machine.
using Test
using TIMES: GamsCompile, gams_compile!, gsym, grecords, gdx_uels, DDSyntaxError

function compile_files(files::Dict{String,String}; run="m.run", kw...)
    dir = mktempdir()
    for (n, t) in files
        write(joinpath(dir, n), t)
    end
    g = GamsCompile(; dirs=[dir], kw...)
    gams_compile!(g, joinpath(dir, run))
end

const MAIN = "\$BATINCLUDE maindrv.mod mod\n"

@testset "switches, \$IF and \$BATINCLUDE arguments" begin
    g = compile_files(Dict(
        "m.run" => "\$SET A yes\n\$SETGLOBAL B 'quoted value' SETGLOBAL C two\n\$BATINCLUDE sub.mod x1 'two words'\n" * MAIN,
        "sub.mod" => "\$IFI %A%==YES SET S1 / a1 /;\n\$IF %A%==YES SET S2 / b1 /;\n\$IF NOT SET ZZ \$SETLOCAL Q %1\nSET S3 / %Q% /;\n\$IF '%2'=='two words' SET S4 / ok /;\n\$IF DECLARED S1 SET S5 / d /;\n\$IF DEFINED NOPE SET S6 / e /;\n"))
    @test gsym(g, "S1") !== nothing && gsym(g, "S2") === nothing
    @test g.globals["B"] == "quoted value" && g.globals["C"] == "two"
    @test first(grecords(g, gsym(g, "S3"))) == [["x1"]]
    @test gsym(g, "S4") !== nothing && gsym(g, "S5") !== nothing && gsym(g, "S6") === nothing
end

@testset "declarations: \$ONMULTI, first non-blank text, aliases, scalars" begin
    # TIMES's own files (.mod) are read in source mode, with ALIAS and SCALAR; the run file in DD mode
    g = compile_files(Dict("m.run" => "\$ONMULTI\nSET T / x /\n\$BATINCLUDE d.mod\n" * MAIN,
        "d.mod" => "SET T 'Universe of T' / y /;\nSET T ' ' / z 'zz' /;\nSET T / z 'new' /;\nALIAS(T,TT,T2);\nSCALAR K 'k' / 3 /, Z0;\nPARAMETER P(T) 'p' / x 1, y 0 /;\n"))
    t = gsym(g, "T")
    @test t.text == "Universe of T"
    @test grecords(g, t) == ([["x"], ["y"], ["z"]], ["", "", "new"])
    @test gsym(g, "TT") === t && g.syms["T2"].kind === :alias
    @test last(grecords(g, gsym(g, "K"))) == [(3.0, :none)]
    @test last(grecords(g, gsym(g, "Z0"))) == [(0.0, :none)]       # a scalar always has its record
    @test first(grecords(g, gsym(g, "P"))) == [["x"]]               # a zero is not stored without $ONEPS
    @test_throws DDSyntaxError compile_files(Dict("m.run" => "SET A / a /;\nSET A / b /;\n" * MAIN))   # no $ONMULTI
end

@testset "data: \$ONEPS, domain checks under \$ONWARNING, \$KILL, labels" begin
    g = compile_files(Dict("m.run" => "\$ONMULTI\n\$ONEPS\n\$ONWARNING\nSET R / r1, R2 /;\nPARAMETER P(R) / r1 0, r2 5, r9 1 /;\nSET Q(R) / r2 /;\nPARAMETER K(R) / r1 2 /;\n\$KILL K\n" * MAIN))
    @test grecords(g, gsym(g, "P")) == ([["r1"], ["R2"]], [(0.0, :eps), (5.0, :none)])   # first spelling R2 kept
    @test g.warnings == 1 && occursin("r9", g.warnlog[1])
    @test isempty(first(grecords(g, gsym(g, "K"))))
    @test gdx_uels(g) == ["r1", "R2"]                        # r9 was read but no record keeps it
    @test_throws DDSyntaxError compile_files(Dict("m.run" => "SET R / r1 /;\nPARAMETER P(R) / r9 1 /;\n" * MAIN))
end

@testset "ranges, SET.x, label lists, \$GOTO, \$ONTEXT, % lines" begin
    g = compile_files(Dict(
        "m.run" => "\$BATINCLUDE sys.mod\n" * MAIN,
        "sys.mod" => "\$ onlisting ontext\nSET IGNORED / i /;\n\$ offtext\nSET Y / 2001*2003 /\nSET E / SET.Y, EOH /\nSET M(Y,Y) / 2001.(2002,2003) /;\n\$GOTO DONE\nSET SKIPPED / s /;\n\$LABEL DONE\n%1\$SET X 1\n"))
    @test gsym(g, "IGNORED") === nothing && gsym(g, "SKIPPED") === nothing
    @test first(grecords(g, gsym(g, "E"))) == [["2001"], ["2002"], ["2003"], ["EOH"]]
    @test first(grecords(g, gsym(g, "M"))) == [["2001", "2002"], ["2001", "2003"]]
end

@testset "GDX label order is the order of first writing (G55)" begin
    g = compile_files(Dict("m.run" => "\$ONMULTI\nSET A / a1, a2 /;\nSET B / b1 /;\nSET A / a0 /;\n" * MAIN))
    @test g.labels.labels == ["a1", "a2", "b1", "a0"]
    @test gdx_uels(g) == ["a1", "a2", "a0", "b1"]
end

@testset "the run must reach maindrv.mod; unknown dollar controls stop" begin
    @test_throws DDSyntaxError compile_files(Dict("m.run" => "SET A / a /;\n"))
    @test_throws DDSyntaxError compile_files(Dict("m.run" => "\$FOO bar\n" * MAIN))
end
