# M1.3 (10): ppmain.mod L683-797 (v4.9.7): the commodity attributes by
# timeslice (pp_lvlfc.mod), COM_FR, RS_FR and RTCS_FR, the elastic demand
# steps, the availability factors (pp_lvlbr.mod) and the peak contributions
# (pp_lvlpk.mod). Layer 1 on TIMES_Demo demo12 reduce_off from the prelv
# checkpoint, compared at the ppm checkpoint on what these lines settle
# (scripts/m13_probe.jl does the same on the core reference runs), and on
# crafted states against GAMS running ppmain.mod L616-797 itself, every
# symbol written compared at L797 (scripts/m13_replay.jl does the same on
# the core models' own states).

using OpenTIMES: TimesModel, DumpData, layer1, pp_qafs!, ppmain_dflt!, ppmain_tsattr!, ppmain_tsattr_symbols, gset, gparam
using OpenTIMES.Reference: ispass
import TOML

@testset "prelv -> ppm: ppmain.mod L683-797 layer 1, TIMES_Demo demo12" begin
    fx = only(filter(f -> f["prefix"] == "demo12_off", TOML.parsefile(joinpath(FIXTURES, "public_fixtures.toml"))["fixture"]))
    tm = TimesModel(joinpath(FIXTURES, "demo12_off_prelv"); switches=fx["switches"])
    pp_qafs!(tm)
    ppmain_dflt!(tm)
    ppmain_tsattr!(tm)
    names = ppmain_tsattr_symbols(tm)
    r = layer1(tm, DumpData(joinpath(FIXTURES, "demo12_off_ppm")), names)
    foreach(d -> ispass(d) || println(d, " ", d.examples), r)
    # no RP_STS or CHP, %REDUCE% NO, no STG_SIFT: NCAP_AF, PRC_TS, NCAP_PKCNT and RPC_PKC compared too
    @test length(names) == 18 && all(ispass, r)
end

isdefined(@__MODULE__, :PPMAIN_DFLT_OUTPUTS) || include("ppmain_dflt_case.jl")    # included by test_m13_ppmain_dflt.jl in runtests.jl
include("ppmain_tsattr_case.jl")
const PPMAIN_TSATTR_ALL = unique(vcat(PPMAIN_DFLT_OUTPUTS, PPMAIN_TSATTR_NEW))

@testset "ppmain.mod L616-797 against GAMS on crafted states" begin
    for name in PPMAIN_TSATTR_CASES
        tm = ppmain_tsattr_start(FIXTURES, name)
        pp_qafs!(tm)
        ppmain_dflt!(tm)
        ppmain_tsattr!(tm)
        r = layer1(tm, DumpData(joinpath(FIXTURES, "ppmain_tsattr_unit_gams", name)), PPMAIN_TSATTR_ALL)
        foreach(d -> ispass(d) || println(name, ": ", d, " ", d.examples), r)
        @test length(r) == 65 && all(ispass, r)
        v(n) = gparam(tm, n).values
        yr = Dict(k[2] => x for (k, x) in v("G_YRFR") if k[1] == "REG1")
        if name == "com"
            ie, fr = v("COM_IE"), v("COM_FR")
            # pp_lvlfc.mod L38-42: COA (ANNUAL) aggregated from S (0.9) and an EPS at W; ELC's S inherited down, WD kept
            @test ie[("REG1", "2020", "COA", "ANNUAL")] ≈ 0.9 * yr["S"]
            @test ie[("REG1", "2015", "ELC", "SD")] == 0.8 && ie[("REG1", "2015", "ELC", "WD")] == 0.95
            # L704-705: RCS is taken over every year, so WN (given in other years) gets no default in 2015
            @test !haskey(ie, ("REG1", "2015", "ELC", "WN")) && ie[("REG1", "2030", "ELC", "SD")] == 0.0
            # L695 (weighted) and L729: ELC at S and W summing to 1.2 normalised; DCOT's SD alone becomes 1
            @test fr[("REG1", "2015", "ELC", "S")] ≈ 0.5 && fr[("REG1", "2015", "ELC", "ANNUAL")] ≈ 1.0
            @test fr[("REG1", "2015", "DCOT", "SD")] ≈ 1.0 && !haskey(fr, ("REG1", "2015", "DCOT", "SN"))
            # L712: AGRELC's other DAYNITE slices filled with the year fractions before the normalisation
            @test fr[("REG1", "2010", "AGRELC", "SN")] ≈ yr["SN"] / (0.2 + yr["SN"] + yr["WD"] + yr["WN"])
            # L751: the DCOT elasticity aggregated to ANNUAL and made negative; without COM_BPRICE, or EPS, removed
            el = Dict(k => x for (k, x) in v("COM_ELAST") if k[1] == "REG1")
            @test el[("REG1", "2010", "DCOT", "ANNUAL", "LO")] ≈ -(0.5 * yr["S"] + 0.7 * yr["W"])
            @test length(el) == 3 && el[("REG1", "2010", "DCAP", "ANNUAL", "FX")] == 0.2
            # L753-754: COM_STEP LO from FX; RCJ up to the steps
            @test v("COM_STEP")[("REG1", "DCOT", "LO")] == 3.0 && length(gset(tm, "RCJ").keys) == 7
            # L701 (weighted): COM_BQTY summed to ANNUAL; ELC's ANNUAL value spread by year fraction
            @test v("COM_BQTY")[("REG1", "DCOT", "ANNUAL")] ≈ 150.0 && v("COM_BQTY")[("REG1", "ELC", "SD")] ≈ 80 * yr["SD"]
            # L697: the year outside DATAYEAR is left at ANNUAL
            @test haskey(v("OBJ_COMNT"), ("REG1", "2011", "ELC", "ANNUAL", "TAX", "MEuro05"))
        elseif name == "af"
            af = v("NCAP_AF")
            a(y, p, s, b="UP") = get(af, ("REG1", y, p, s, b), nothing)
            # pp_lvlbr.mod: inherited from ANNUAL; aggregated from the DAYNITE values; the lower value ignored under S
            @test a("2010", "ELCTECOA00", "S") == 0.8 && a("2010", "ELCTECOA00", "W") == 0.8
            @test a("2015", "ELCTECOA00", "S") ≈ (0.9 * yr["SD"] + 0.7 * yr["SN"]) / yr["S"]
            @test a("2015", "ELCTECOA00", "W") ≈ 0.6 * yr["WD"] / yr["W"] && a("2020", "ELCTECOA00", "S") == 0.85
            # L47-55: FX with UP and LO at S: UP and LO removed
            @test a("2030", "ELCTECOA00", "S", "FX") == 0.7 && a("2030", "ELCTECOA00", "S") === nothing
            # ppmain.mod L768: NCAP_AFS kept over the inherited value; S inherited down before ANNUAL
            @test a("2010", "ELCTEGAS00", "SD") == 0.5 && a("2015", "ELCTEGAS00", "SN") == 0.8 && a("2015", "ELCTEGAS00", "WN") == 0.9
            # L777: EPS at the slices without a value of a storage; L775: default UP 1 without UP/FX
            @test a("2010", "ELCTNOIL01", "SN") == 0.0 && a("2010", "COTEGAS", "ANNUAL") == 1.0
            # L772-784: without a positive UP/FX, the slices leave PRC_TS (below them too) for RTPCS_OUT
            ts = Set(k[3] for k in gset(tm, "PRC_TS").keys if k[1] == "REG1" && k[2] in ("ELCTNGAS01", "ELCTNCOA01"))
            @test ts == Set(["SD", "S"]) && ("REG1", "2010", "ELCTNCOA01", "ELC", "WN") in gset(tm, "RTPCS_OUT").members
            # Z as GAMS leaves it: the last value inherited down at L44 (ELCTEGAS00's ANNUAL in 2010)
            @test v("Z")[()] == 0.9
        else
            pk = v("NCAP_PKCNT")
            p(y, q, s) = get(pk, ("REG1", y, q, s), nothing)
            # pp_lvlpk.mod L27-38: S and W without ANNUAL (default 1 at ANNUAL) inherited; ANNUAL with SD
            @test p("2010", "ELCTEGAS00", "SN") == 0.7 && p("2010", "ELCTEGAS00", "WD") == 0.5
            @test p("2015", "ELCTEGAS00", "SD") == 0.6 && p("2015", "ELCTEGAS00", "WN") == 0.8
            # L47-48: PRC_PKAF without NCAP_PKCNT: the largest NCAP_AF; RPC_PKF EPS; RPC_PKC through the ELC loop
            @test p("2010", "ELCTNGAS01", "SD") == 0.85 && v("RPC_PKF")[("REG1", "ELCTNGAS01", "ELC")] == 0.0
            @test ("REG1", "ELCTNGAS01", "ELC") in gset(tm, "RPC_PKC").members
            # L21: FLO_PKCOI of the PRC_PKNO process removed
            @test collect(keys(v("FLO_PKCOI"))) == [("REG1", "2010", "ELCTECOA00", "ELC", "ANNUAL")]
        end
    end
end
