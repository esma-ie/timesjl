# M1.4 changes 2-4: GAMS's compile phase (src/dd/compile.jl) on small synthetic run files. The TIMES
# source is not in CI; scripts/m14_probe.jl checks the real run files against the input dumps on
# James's machine.
using Test
using TIMES: GamsCompile, gams_compile!, gsym, grecords, gdx_uels, gdx_symbols, DDSyntaxError

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

@testset "change 2b: TIMES code after maindrv.mod" begin
    files = Dict(
        "m.run" => "\$ONEPS\nSET I / a, b /;\n\$BATINCLUDE maindrv.mod mod\nPARAMETER AFTER(I) 'after' //;\n",
        "maindrv.mod" =>
            # $SETARGS: a name with no argument is empty (setglobs.gms L13, L342)
            "\$SETARGS X1 X2\n\$IF NOT '%X2%'=='' \$EXIT\n" *
            # $IF with nothing after the condition governs the next line (eqobjfix.mod L205)
            "\$IF %NOPE%==YES\nSET SKIPPED / s /;\n\$IF NOT %NOPE%==YES\nSET KEPT / k /;\n" *
            # a declaration that goes on after a dollar line (eqdeclr.mod)
            "EQUATIONS\n  E1(I) 'one' //\n\$IF %NOPE%==YES E9 'not this'\n  E2(I) 'two' //\n;\n" *
            # code from a $IF line joins the next line (prepret.dsc L45-46)
            "\$IF NOT %NOPE%==YES POSITIVE\nVARIABLE V1(I);\nVARIABLE V2(I);\n" *
            # executable statements after maindrv.mod are skipped; they may span dollar lines
            "LOOP(I,\n\$IF %NOPE%==YES DISPLAY I;\n  V1.UP(I) = 1);\n" *
            # $IFE with CARD at compile time; $EVAL
            "\$IFE CARD(I)=2 SET CARD2 / c2 /;\n\$EVAL N '1+2*3'\nSET EV / e%N% /;\n" *
            # macros count as DECLARED and DEFINED (prepret.dsc L41 VNRET; VAR_STS)
            "\$MACRO MAC(X) V2(X)\n\$IF NOT DEFINED MAC PARAMETER MAC(I) //;\n\$IF DECLARED MAC SET MACSEEN / m /;\n" *
            # a scalar's 0 stays 0 under $ONEPS; arguments beyond 9
            "SCALAR Z0 / 0 /;\n\$BATINCLUDE args.mod 1 2 3 4 5 6 7 8 9 10 eleven\n" *
            # blanks before the dot of a key (eqbndcst.mod L22)
            "SET PAIR(I,I) / a   .(a,b) /;\nE1(I).. V1(I) =E= 1;\nVARIABLE UNUSED;\n",
        "args.mod" => "SET ARG11 / %11 /;\n")
    dir = mktempdir()
    for (n, t) in files
        write(joinpath(dir, n), t)
    end
    g = GamsCompile(; dirs=[dir], full=true)
    gams_compile!(g, joinpath(dir, "m.run"))
    @test first(grecords(g, gsym(g, "EV"))) == [["e7"]]
    @test gsym(g, "SKIPPED") === nothing && gsym(g, "KEPT") !== nothing
    @test g.syms["E1"].kind === :equation && haskey(g.syms, "E2") && !haskey(g.syms, "E9")
    @test g.syms["V1"].kind === :variable
    @test gsym(g, "CARD2") !== nothing
    @test !haskey(g.syms, "MAC") && gsym(g, "MACSEEN") !== nothing
    @test last(grecords(g, gsym(g, "Z0"))) == [(0.0, :none)]
    @test first(grecords(g, gsym(g, "ARG11"))) == [["eleven"]]
    @test first(grecords(g, gsym(g, "PAIR"))) == [["a", "a"], ["a", "b"]]
    @test gsym(g, "AFTER") !== nothing                       # the run file goes on after maindrv.mod
    names = [s.name for s in gdx_symbols(g)]
    @test "E1" in names && "V1" in names && !("UNUSED" in names)   # G57
    @test [x[2] for x in g.trace] == ["m.run", "maindrv.mod", "args.mod"]
end
