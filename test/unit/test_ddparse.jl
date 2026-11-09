# M1.4 change 1: the DD/run-file parser (src/dd/ddparse.jl) on synthetic text and on every crafted
# case in reference/dd (the suite's DD files are parsed by scripts/m14_parse_suite.jl on James's
# machine: they are not in the repository).
using Test
using TIMES: parse_dd, parse_dd_file, DDSymbol, DDDirective, DDOther, DDRecord, DDSyntaxError,
    LabelTable, intern!, labelpos

syms(items) = filter(x -> x isa DDSymbol, items)

@testset "demo12 style: no ';', unquoted labels, keyword ends the statement" begin
    t = "* the times-slices MUST come 1st\nSET ALL_TS\n/\n ANNUAL\n S\n SD\n/\n\nPARAMETER\nACT_BND ' '/\nREG1.2005.EXPCOA1.ANNUAL.UP 745.59485\nREG1.2005.FTE-AGROIL_NRGI.ANNUAL.LO -1.5E+3\n/\nSET REG\n/\n REG1 'REG1'\n/\n"
    it = parse_dd(t)
    @test length(it) == 3
    a, p, r = it
    @test a.kind === :set && a.name == "ALL_TS" && a.hasdata && [x.labels for x in a.records] == [["ANNUAL"], ["S"], ["SD"]]
    @test a.records[1].line == 4
    @test p.kind === :parameter && p.name == "ACT_BND" && p.text == " "
    @test p.records[1].labels == ["REG1", "2005", "EXPCOA1", "ANNUAL", "UP"] && p.records[1].value == 745.59485
    @test p.records[2].labels[3] == "FTE-AGROIL_NRGI" && p.records[2].value == -1500.0
    @test r.records[1].text == "REG1"
end

@testset "Veda style: quoted labels, '/;', blank lines, text on records" begin
    t = "\$ONEMPTY\n\$ONEPS\n\$SET RUN_NAME 'x'\nPARAMETER\n\nACT_BND ' '/\n'R0'.2010.'IMPNGAC1'.ANNUAL.LO 974.3222708352\n'R0'.0.'X'.ANNUAL.UP 0\n/;\n\nSET PRC_MAP\n\n/\n'R0'.'PRE'.'P1'\n/;\nSET UC_N\n/\n'UC_NCAPRLT*EXT*-' 'a * text'\n'A.B/C' \"dq\"\n/;\n"
    it = parse_dd(t)
    @test [x isa DDDirective ? x.text : x.name for x in it] == ["ONEMPTY", "ONEPS", "SET RUN_NAME 'x'", "ACT_BND", "PRC_MAP", "UC_N"]
    p = it[4]
    @test p.records[1].labels == ["R0", "2010", "IMPNGAC1", "ANNUAL", "LO"]
    @test p.records[2].labels[2] == "0" && p.records[2].value == 0.0 && p.records[2].special === :none
    @test it[5].records[1].labels == ["R0", "PRE", "P1"] && it[5].records[1].text == ""
    u = it[6].records
    @test u[1].labels == ["UC_NCAPRLT*EXT*-"] && u[1].text == "a * text"
    @test u[2].labels == ["A.B/C"] && u[2].text == "dq"
end

@testset "domains, declaration text, empty lists, several symbols in one statement" begin
    it = parse_dd("SETS\n  A(REG,*) 'pairs' / r1.x Text one, r2.y /\n  B Unquoted text\n  C / /;\nParameters P(REG) / r1 1, r2 .5 /, Q;\n")
    a, b, c, p, q = it
    @test a.domain == ["REG", "*"] && a.text == "pairs" && length(a.records) == 2
    @test a.records[1].labels == ["r1", "x"] && a.records[1].text == "Text one" && a.records[2].text == ""
    @test b.name == "B" && b.text == "Unquoted text" && !b.hasdata
    @test c.hasdata && isempty(c.records)
    @test p.kind === :parameter && [r.value for r in p.records] == [1.0, 0.5]
    @test q.name == "Q" && !q.hasdata
end

@testset "special values, comments, ONTEXT, run-file statements" begin
    t = "OPTION RESLIM=50000, PROFILE=1;\noption LP=CBC;\n\$ontext\nSET IGNORED / a /;\n\$offtext\n* a comment / with a slash\nPARAMETER P /\n* comment inside a list\na eps\nb INF\nc -inf\nd na\ne 1e-05\n/;\nSET MILESTONYR /2005,2010,2015/;\n\$ BATINCLUDE maindrv.mod mod\n"
    it = parse_dd(t)
    @test it[1] isa DDOther && it[1].text == "RESLIM=50000, PROFILE=1" && it[2].text == "LP=CBC"
    p = it[3]
    @test p.name == "P" && [r.special for r in p.records] == [:eps, :inf, :minf, :na, :none]
    @test p.records[1].value == 0.0 && p.records[3].value == -Inf && p.records[5].value == 1e-5
    @test [r.labels[1] for r in it[4].records] == ["2005", "2010", "2015"]
    @test it[5] isa DDDirective && it[5].text == "BATINCLUDE maindrv.mod mod"
end

@testset "a scalar parameter's list holds only its value" begin
    g = parse_dd("PARAMETER\nG_DYEAR ' '/\n2005\n\n/\n")[1]
    @test length(g.records) == 1 && isempty(g.records[1].labels) && g.records[1].value == 2005.0
    # a keyed record that starts with a number is not a scalar
    p = parse_dd("PARAMETER P / 2005 5\n1.5 3\n2005.X -1 /;")[1]
    @test [r.labels for r in p.records] == [["2005"], ["1", "5"], ["2005", "X"]] && [r.value for r in p.records] == [5.0, 3.0, -1.0]
end

@testset "syntax outside the subset stops with file and line" begin
    bad = [
        "TABLE T(*,*)\n  a b\n" => "TABLE",
        "SET S / (a,b).c /;" => "parenthesised",
        "SET S / a.(b,c) /;" => "parenthesised",
        "SET S / 1*10 /;" => "range",
        "PARAMETER P / a /;" => "without a value",
        "PARAMETER P / a 1x /;" => "not a number",
        "SET S / 'a /;" => "quote not closed",
        "SET S / a, b" => "not closed",
        "SET S /\n\$ONEPS\n a /;" => "dollar-control",
        "SCALAR X / 1 /;" => "SCALAR",
        "\$ONTEXT\nSET S;\n" => "OFFTEXT",
        "PUTCLOSE x;" => "PUTCLOSE",
        "FOO X;" => "unknown statement",
    ]
    for (t, msg) in bad
        e = try
            parse_dd(t; file="bad.dd"); nothing
        catch err
            err
        end
        @test e isa DDSyntaxError && e.file == "bad.dd" && occursin(msg, e.msg)
    end
    # `b c d` is valid GAMS: label b with the text "c d"; a parameter value that is not a number is not
    @test parse_dd("SET B / b c d /;")[1].records[1].text == "c d"
    e = try parse_dd("SET A / a /;\n\nPARAMETER B / b x /;"; file="f.dd") catch err; err end
    @test e isa DDSyntaxError && e.line == 3
end

@testset "LabelTable: case-insensitive, first spelling, order of first use" begin
    t = LabelTable()
    @test intern!(t, "Mt") == "Mt"
    @test intern!(t, "PJa") == "PJa"
    @test intern!(t, "MT") == "Mt"            # GAMS keeps the first spelling
    @test intern!(t, "pja ") == "PJa"         # trailing blanks are not part of a label
    @test t.labels == ["Mt", "PJa"] && length(t) == 2
    @test labelpos(t, "mt") == 1 && labelpos(t, "x") == 0
end

@testset "every crafted case in reference/dd parses" begin
    root = joinpath(@__DIR__, "..", "..", "reference", "dd")
    files = sort([joinpath(d, f) for (d, _, fs) in walkdir(root) for f in fs if endswith(f, ".dd") || endswith(f, ".run")])
    @test length(files) >= 16
    for f in files
        it = parse_dd_file(f)
        @test !isempty(it)
        endswith(f, ".dd") && @test !isempty(syms(it)) && all(s -> !s.hasdata || all(r -> !isempty(r.labels), s.records), syms(it))
        endswith(f, ".run") && @test any(x -> x isa DDDirective && occursin(r"^BATINCLUDE\s+maindrv\.mod"i, x.text), it)
    end
end
