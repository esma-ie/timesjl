# M1.3 (25b-1): the QA log (QA_CHECK.LOG) and GAMS's PUT rules (src/prep/qalog.jl).
# The expected text was written by GAMS 54.6.1 from the same PUT statements
# (docs/discrepancies.md G53).

import TOML
using TIMES: TimesModel, QaLog, qput!, qat!, qnl!, qclose!, qa_text, qnum, qcenter, qlab12, qa_compare, gams_warnings

@testset "QA log: PUT rules" begin
    # numbers: F:0:0, Z:0:0 (0.5), G:0:5, F, G, H (NW=12, ND=2), Z:<3:0, H:0:0, G:8:3
    @test join([qnum(3, 0, 0), qnum(0.5, 0, 0), qnum(-12.345678, 0, 5), qnum(3, 12, 2), qnum(-12.345678, 12, 2),
                qnum(1234567.891, 12, 2), qnum(0.5, 3, 0; left=true), qnum(1234567.891, 0, 0), qnum(-12.345678, 8, 3)], "|") ==
          "3|0|-12.34568|        3.00|      -12.35|  1234567.89|0  |1234568| -12.346"
    # EPS:0:2, INF, -INF, 1e15 (E format), 1e-7, 1e-7:0:2
    @test join([qnum(TIMES.GEPS, 0, 2), qnum(Inf, 12, 2), qnum(-Inf, 12, 2), qnum(1e15, 12, 2), qnum(1e-7, 12, 2), qnum(1e-7, 0, 2)], "|") ==
          "0.00|        +INF|        -INF|1.000000E+15|        0.00|0.00"
    @test qnum(2.675, 0, 2) == "2.67" && qnum(0.125, 0, 2) == "0.12"     # the binary value, half to even
    @test qcenter("AB", 5) == " AB  " && qcenter("ABC", 6) == " ABC  "
    @test qlab12("REG1") == "REG1        " && qlab12("AVERYLONGREGIONNAME1") == "AVERYLONGREGIONNAME1"
    # the cursor overwrites; a line of blanks is written as one blank; trailing blanks dropped
    q = QaLog()
    qput!(q, "x"); qat!(q, 5); qput!(q, "y"); qat!(q, 3); qput!(q, "z"); qnl!(q)
    qput!(q, "   "); qnl!(q); qput!(q, "a  "); qnl!(q)
    @test qa_text(q) == "x z y\r\n \r\na\r\n"
    # PUTCLOSE writes a pending line only; a '/' after it writes an empty line
    q = QaLog(); qput!(q, "a"); qnl!(q); qclose!(q); qput!(q, "b"); qclose!(q)
    @test qa_text(q) == "a\r\nb\r\n"
    q = QaLog(); qput!(q, "a"); qnl!(q); qnl!(q); qclose!(q); qnl!(q); qput!(q, "b"); qat!(q, 1); qput!(q, "c")
    @test qa_text(q) == "a\r\n\r\n\r\nc\r\n"
end

@testset "QA log: pp_qaput.mod" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_input"); switches=fx["switches"])
    TIMES.qa_group!(tm)
    TIMES.pp_qaput!(tm, 11, "Group one")
    TIMES.pp_qaput!(tm, 1, "Group one")
    qput!(TIMES.qalog(tm), " WARNING       - x:   R=" * qlab12("REG1") * " P=REG1")
    @test qa_text(tm) == "              ******          TIMES -- VERSION 4.9.7           ******\r\n" *
                         "              **************   QUALITY ASSURANCE LOG   **************\r\n\r\n" *
                         " *** Group one\r\n *11\r\n *01 WARNING       - x:   R=REG1         P=REG1\r\n"
    @test TIMES.gscalar(tm, "PUTOUT") == 1 && TIMES.gscalar(tm, "PUTGRP") == 1 && TIMES.gscalar(tm, "ERRLEV") == 11
    # the compare: a prefix ending at a line end, GAMS going on with a new group
    ref = qa_text(tm) * "\r\n *** Next group\r\n *01 W\r\n"
    @test qa_compare(qa_text(tm), ref)[1] && !qa_compare(qa_text(tm), ref; complete=true)[1]
    @test !qa_compare(qa_text(tm), replace(ref, "*11" => "*12"))[1]
    @test qa_compare("", "")[1]
    # the compilation summary of a listing
    f = tempname()
    write(f, "x\n**** 0 ERROR(S)   88 WARNING(S)\n")
    @test gams_warnings(f) == 88 && gams_warnings(f * "_none") == 0
end

# The crafted cases (reference/crafted.toml, M1.3 change 25b-3): demo12 with data the QA checks
# complain about, every step from the input dump on one TimesModel, the QA log against GAMS's.
# demo12_qa: warnings, the run goes on; demo12_qa99: a FATAL error, pp_qack.mod L380 aborts.
using TIMES: init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
             ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!,
             ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!, ppmain_ucmap!, ppmain_blend!,
             ppmain_reduce!, ppm_ext_actef!, ppm_ext!, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!,
             coef_ext!, prepret_decl!, eqobjinv_prep!, eqobjfix_prep!, eqobsalv_prep!, eqmain_prep!, bnd_data!,
             pp_qack_data!, pp_clean!, gscalar
const QA_CHAIN = (init_ext!, ppmain_head!, ppmain_years!, timslice!, ppmain_rtp!, preppm!, prep_ext!, preppm_shape!,
                  ppmain_topo!, ppmain_tslvl!, ppmain_life!, pp_prelv!, pp_qafs!, ppmain_dflt!, ppmain_tsattr!,
                  ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!, ppmain_stg!, ppmain_uc!,
                  ppmain_ucmap!, ppmain_blend!, ppmain_reduce!, ppm_ext_actef!, ppm_ext!, coef_cpt!, coef_nio!,
                  coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, prepret_decl!, eqobjinv_prep!, eqobjfix_prep!,
                  eqobsalv_prep!, eqmain_prep!, bnd_data!, pp_qack_data!, pp_clean!)

@testset "QA log: crafted cases against GAMS" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    for (prefix, aborts) in (("demo12_qa", false), ("demo12_qa99", true))
        tm = TimesModel(joinpath(FIXTURES, prefix * "_input"); switches=fx["switches"])   # demo12.run's switches
        err = nothing
        try
            foreach(f -> f(tm), QA_CHAIN)
        catch e
            err = e
        end
        @test (err !== nothing) == aborts
        aborts && @test occursin("FATAL QA ERROR", sprint(showerror, err))
        qok, note = qa_compare(qa_text(tm), read(joinpath(FIXTURES, prefix * "_qa_check.log"), String); complete=true)
        qok || println(prefix, " QA log: ", note)
        @test qok
        aborts || @test all(n -> gscalar(tm, n) == 0, ("PUTOUT", "PUTGRP", "ERRLEV"))   # pp_qack.mod L385
    end
end
