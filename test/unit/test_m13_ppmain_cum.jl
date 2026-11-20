# M1.3 (13b): ppmain.mod L1003-1056 (v4.9.7): the cumulative bounds moved
# from BOH and EOH to the first and last years, and the commodities whose
# VAR_COMNET or VAR_COMPRD goes on the RHS of the balance. Layer 1 on
# TIMES_Demo demo12 reduce_off from the prelv checkpoint, compared at the
# ppm checkpoint on what these lines settle (scripts/m13_probe.jl does the
# same on the core reference runs), and on crafted states against GAMS
# running ppmain.mod L616-1056 itself, every symbol written compared at
# L1056 (scripts/m13_replay.jl does the same on the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!,
             ppmain_bnd!, ppmain_cum!, ppmain_cum_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

const PPMAIN_TO_CUM = (pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_flo!, ppmain_flofs!, ppmain_ire!, ppmain_bnd!, ppmain_cum!)

@testset "prelv -> ppm: ppmain.mod L1003-1056 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    foreach(f -> f(tm), PPMAIN_TO_CUM)
    names = ppmain_cum_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    @test length(names) == 15 && all(ispass, r)
    # L1014: ACT_CUM up to EOH becomes FLO_CUM of ACT up to 2200
    @test any(k -> k[3] == "ACT" && k[5] == "2200", keys(gparam(tm, "FLO_CUM").values))
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")
isdefined(@__MODULE__, :PPMAIN_TSATTR_NEW) || include("ppmain_tsattr_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLO_NEW) || include("ppmain_flo_case.jl")
isdefined(@__MODULE__, :PPMAIN_FLOFS_NEW) || include("ppmain_flofs_case.jl")
isdefined(@__MODULE__, :PPMAIN_IRE_NEW) || include("ppmain_ire_case.jl")
isdefined(@__MODULE__, :PPMAIN_BND_NEW) || include("ppmain_bnd_case.jl")
include("ppmain_cum_case.jl")
const PPMAIN_CUM_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW, PPMAIN_FLO_NEW, PPMAIN_FLOFS_NEW, PPMAIN_IRE_NEW, PPMAIN_BND_NEW,
                                   PPMAIN_CUM_NEW))

@testset "ppmain.mod L616-1056 against GAMS on crafted states" begin
    u = "UC_RNW-PP_LOW"
    for name in PPMAIN_CUM_CASES
        tm = ppmain_cum_start(FIXTURES, name)
        foreach(f -> f(tm), PPMAIN_TO_CUM)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_cum_unit_gams", name)), PPMAIN_CUM_ALL)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test length(r) == 140 && all(ispass, r)
        v(n) = gparam(tm, n).values
        has(n, k...) = k in gset(tm, n).members
        # L1007-1009: BOH and EOH moved to 1960 and 2200, the BOH/EOH records deleted, UC_CUMACT as a flow of ACT
        @test haskey(v("UC_CUMFLO"), (u, "REG1", "ELCTEGAS00", "ELC", "1960", "2200")) && !haskey(v("UC_CUMFLO"), (u, "REG1", "ELCTEGAS00", "ELC", "BOH", "EOH"))
        @test haskey(v("UC_CUMFLO"), (u, "REG1", "ELCTECOA00", "ACT", "2010", "2200")) && isempty(v("UC_CUMACT"))
        # L1022, L1025, L1039-1042: COM_CUMNET from BOH to EOH covers every milestone of ELCCO2
        @test haskey(v("COM_CUM"), ("REG1", "NET", "1960", "2200", "ELCCO2", "UP")) && has("RTC_NET", "REG1", "2050", "ELCCO2")
        # L1049-1050: the COM_CSTNET flag at year '0' and the last timeslice; COA on the RHS in every milestone
        @test haskey(v("COM_CSTNET"), ("REG1", "0", "COA", "WN", "MEuro05")) && has("RHS_COMBAL", "REG1", "2005", "COA", "ANNUAL")
        # L1051: ELC's bound at S puts SD and SN on the RHS; COA's EPS LO and INF UP do not
        @test has("RHS_COMBAL", "REG1", "2015", "ELC", "SD") && !has("RHS_COMBAL", "REG1", "2015", "ELC", "WD")
        # L1053-1055: COM_TAXPRD flags DCOT; COM_BNDPRD FX puts COA on the RHS of VAR_COMPRD
        @test has("RHS_COMPRD", "REG1", "2015", "DCOT", "ANNUAL") && has("RHS_COMPRD", "REG1", "2010", "COA", "ANNUAL")
    end
end
