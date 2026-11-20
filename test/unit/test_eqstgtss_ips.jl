# EQ_STSBAL at ANNUAL with the PRC_STGIPS charging terms (eqstgtss.mod L78-83, M1.3 change 45).
# No row of TIMES v4.9.7 reaches them: RP_STL's levels are TSL+1 (ppmain.mod L1089) and RP_STL is
# declared after the DD files (ppmain.mod L23), so neither GAMS nor any data gives it ANNUAL.
# The terms are checked here on a constructed state: demo12_ips's inter-period storage STKOIL1
# (PRC_STGIPS on OIL, PRC_TS at ANNUAL) given RP_STL(REG1,STKOIL1,ANNUAL,N). No GAMS reference.
using Test, JuMP
import TOML
using OpenTIMES: TimesModel, gset, gput!, gparam
import OpenTIMES

let fx = only(f for f in TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]
              if f["prefix"] == "demo12_ips_off")
    tm = TimesModel(joinpath(FIXTURES, "demo12_ips_off_presolve"); reduce=fx["reduce"], switches=fx["switches"])
    @test isempty(gset(tm, "RP_STL"))                                    # demo12_ips has no STS storage
    @test ("REG1", "STKOIL1", "OIL") in gset(tm, "PRC_STGIPS")
    gput!(tm, "RP_STL", Set([("REG1", "STKOIL1", "ANNUAL", "N")]))
    n = OpenTIMES.eq_stsbal!(tm)
    @test n > 0
    row(t) = constraint_by_name(tm.model, "EQ_STSBAL(REG1,$t,$t,STKOIL1,ANNUAL,ANNUAL,N)")
    var(name, t, c) = variable_by_name(tm.model, "$name(REG1,$t,$t,STKOIL1,$c,ANNUAL)")
    actflo = gparam(tm, "PRC_ACTFLO")
    for t in ("2005", "2030")
        con = row(t)
        @test con !== nothing
        f = constraint_object(con).func
        c_soil, c_sact = coefficient(f, var("VAR_SOUT", t, "OIL")), coefficient(f, var("VAR_SOUT", t, "ACT"))
        c_sin = coefficient(f, var("VAR_SIN", t, "OIL"))
        @test c_soil != 0 && c_soil == c_sact                           # -VAR_SOUT(C), -VAR_SOUT(%PGPRIM%)
        a = OpenTIMES.gv(actflo, ("REG1", t, "STKOIL1", "OIL")).v
        @test c_sin ≈ -c_soil / a rtol = 1e-12                          # +1/PRC_ACTFLO * VAR_SIN(C)$IPS('IN')
        @test length(f.terms) == 3                                      # INDCO2 is not in PRC_STGIPS
    end
end
