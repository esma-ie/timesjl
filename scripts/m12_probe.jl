# M1.2 work list: for each reference run (reduce_off), run the coefficient
# steps translated so far on the ppm dump and compare what they compute with
# the coef dump (layer 1, 1e-9).
#
#   julia --project=test scripts/m12_probe.jl <reference dir> [--root name=path ...] [<model> ...]
#
# Switches as in m11_probe.jl. After each step, the symbols it writes are
# compared, less the records a later coefficient file assigns
# (TIMES.later_overwrites; docs/m12-plan.md).

include(joinpath(@__DIR__, "m11_probe.jl"))      # run_switches, runfile_of, suite_switches, parse_probe_args
using TIMES: DumpData, layer1, coef_cpt!, coef_nio!, coef_ptr!, coef_obj!, coef_alt!, coef_shp!, coef_ext!, ctst, later_overwrites
using TIMES.Reference: ispass

"Translated steps in coefmain.mod order: (name, function, symbols to compare, symbols only when the model allows)."
const M12_STEPS = [
    ("coef_cpt", coef_cpt!,
     ["SOW", "SW_T", "B", "E", "M", "D", "MY_TS", "NCAP_AF", "NCAP_AFS", "COEF_AF", "RTPS_BD", "NCAP_AFBX", "RTP_ISHPR"],
     tm -> ctst(tm) == "" ? ["COEF_CPT"] : String[]),      # else COEF_CPT comes from coef_alt.lin
    ("coef_nio", coef_nio!,
     ["COEF_ICOM", "COEF_OCOM", "COEF_RCOM", "NCAP_OCOM", "NCAP_CLAG", "NCAP_CLED", "RPC_CAPFLO"],
     tm -> String[]),                                       # FIL, FIL2, CNT: work symbols reused later
    ("coef_ptr", coef_ptr!,
     ["COEF_PTRAN", "RPCC_FFUNC", "PRC_CG", "KEEP_FLOF", "ACT_FLO", "CGTEST", "CGTES2"],
     tm -> String[]),                                       # CG_GRP, RP_GRP: work sets reused later
    ("coef_obj", coef_obj!,
     ["TS_ANN", "EACHYEAR", "Y", "YK", "Y_EOH", "YR_V1", "YR_VL", "ACL", "G_DRATE", "OBJ_DISC", "G_DYEAR", "G_RCUR",
      "OBJ_PVT", "COEF_PVT", "OBJ_RFR", "OBJ_COMNT", "OBJ_COMPD", "OBJ_IPRIC", "FLO_COST", "FLO_DELIV", "OBJ_VFLO",
      "NCAP_ISPCT", "OB_ICOST", "OB_ISUB", "OB_ITAX", "OB_FOM", "OB_FSB", "OB_FTX", "OB_DCC", "OB_DLC", "OB_ACT",
      "OB_FCOS", "OB_FDEL", "OB_FTAX", "OBJ_FSUB", "RPC_CUR", "X_RP", "OB_COM", "OB_IRE", "SHEDJ", "SHAPED", "FIL"],
     tm -> String[]),
    ("coef_alt", coef_alt!,                                 # L31-58 (every path)
     ["PERDINV", "TPULSEYR", "TPULSE", "OBJ_LINT", "OBJ_ALTV", "YK1", "FPD", "OBJ_PVT", "COEF_PVT"],
     tm -> ctst(tm) == "" ? String[] :                      # %CTST% empty: the include ends at L59
           ["RTP_CAPVL", "RB", "R_DF", "COEF_CPT", "PASTSUM", "FIL2", "MY_ARRAY", "NCAP_ILED"]),   # L65-87, L160
    ("coef_shp", coef_shp!,
     ["OPYEAR", "AGEJ", "Z", "FLO_FUNCX", "NCAP_CPX", "RTP_CAPYR", "RTP_FFCX", "RTP_CPX", "COEF_CPT", "PRC_YMIN", "PRC_YMAX",
      "TRACKP", "RVPRL", "RP_GRP", "RTP_CGC", "COEF_CAP"],
     tm -> String[]),
    ("coef_ext", coef_ext!,                                 # the last file: nothing is left to a later one
     ["COEF_CPT", "NCAP_PASTI", "PRC_RESID", "RTFORC", "RP_STL", "COEF_AFUPS", "ACT_CSTUP", "RCS_COMBAL", "RTCS_VARC",
      "RPC_CONLY", "TOP_IRE", "TRACKC", "TRACKP", "RCS", "UC_TIME", "UC_ON", "R_UC", "COEF_PTRAN", "ACT_EFF", "RPCC_FFUNC",
      "RP_CGC", "TRACKPC", "RP_GRP", "CG_GRP", "RP_DCGG", "RTP_CAPYR", "RPCG_PTRAN", "UNCD7", "COEF_PVT", "VDA_DISC",
      "COEF_ILED", "ACT_FLO", "RTP_FFCX",
      # eqlducs.vda L15-41
      "RP_UPT", "RP_DP", "RP_DPL", "ACT_CSTSD", "ACT_SDTIME", "ACT_MAXNON", "ACT_LOSSD", "ACT_LOSPL", "DP_NON", "DP_PSUD",
      "DP_LOSD"],
     tm -> String[]),
]

function probe12(refdir, model; roots=Dict{String,String}(), variant="reduce_off")
    dir = joinpath(refdir, model, variant)
    isfile(joinpath(dir, "manifest.json")) || return println("== ", model, ": no reference")
    m = JSON.parsefile(joinpath(dir, "manifest.json"))
    (isdir(joinpath(dir, "ppm")) && isdir(joinpath(dir, "coef"))) || return println("== ", model, ": no ppm/coef dump")
    rf = runfile_of(refdir, model, variant)
    sw = rf === nothing ? suite_switches(model, m, roots) : run_switches(rf)
    tm = TimesModel(joinpath(dir, "ppm"); switches=sw)
    ref = DumpData(joinpath(dir, "coef"))
    for (name, f, syms, extra) in M12_STEPS
        try
            t = @elapsed f(tm)
            names = vcat(syms, extra(tm))
            later = later_overwrites(tm; after=name)
            r = layer1(tm, ref, names; exclude=later)
            bad = filter(!ispass, r)
            # GAMS records left out because a later file (not yet translated) assigns them
            nleft(n) = !haskey(later, n) ? 0 : ref.dump.symbols[n].kind == :set ?
                       count(later[n], TIMES.gset(ref, n).keys) : count(later[n], keys(TIMES.gparam(ref, n).values))
            nskip = sum(nleft, names)
            println("== ", model, " ", name, ": ", isempty(bad) ? "PASS" : "FAIL", " (", length(r), " symbols, ",
                    sum(d -> d.n_ref, r), " GAMS records", nskip > 0 ? ", $nskip left to later files" : "", ", ",
                    round(t; digits=2), " s)")
            for d in bad
                println("     ", d)
                foreach(e -> println("        ", e), d.examples)
            end
        catch e
            e isa TIMES.UnportedError || rethrow()
            println("== ", model, " ", name, ": not translated: ", sprint(showerror, e))
            return
        end
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    refdir, roots, models = parse_probe_args(ARGS)
    for model in models
        probe12(refdir, model; roots)
    end
end
