"""
    TIMES

Julia/JuMP translation of the IEA-ETSAP TIMES model generator.

Phase 1 translates TIMES v4.9.8 (`etsap-TIMES/TIMES_model` @ `7064680`) with
exact numerical parity. The baseline moved from v4.9.7 (`d9a6a25`) on 26 Nov 2026,
after the M1.3 gate: the source download is v4.9.8; until their pull requests merge,
`TIMES_GAMS_VERSION` stays 4.9.7 and the v4.9.8 changes to
ppmain.mod, pp_qack.mod, pp_chp.mod, coef_obj.mod and prepret.dsc are not yet translated
(docs/translation-guide.md, "Source of truth"). The `TIMES.Reference` submodule reads GAMS reference
dumps and compares them with TIMES.jl output; the model itself is added
milestone by milestone from M1.1.
"""
module TIMES

"""TIMES GAMS version this code is translated from and its CI fixtures were made with: 4.9.7 until the
last v4.9.8 diff pull request, which moves it with the fixtures. The QA log's title (%SYSTEM.TITLE%,
initsys.mod L1) is taken from it (src/prep/qalog.jl `qa_title`)."""
const TIMES_GAMS_VERSION = v"4.9.7"

"Commit of `etsap-TIMES/TIMES_model` this code is translated from (see `TIMES_GAMS_VERSION`)."
const TIMES_GAMS_COMMIT = "d9a6a25"

import JuMP
import HiGHS   # the default solver of run_model (src/run.jl)
import Arrow, JSON
using LazyArtifacts   # lazy artifacts need the module itself loaded (Artifacts.toml, src/dd/sources.jl)

include("reference/Reference.jl")
include("dd/ddparse.jl")
include("dd/compile.jl")
include("dd/sources.jl")
include("dd/writedump.jl")
include("model/gams_data.jl")
include("model/mod_vars.jl")
include("model/sow_tags.jl")
include("model/equations.jl")
include("model/eqactflo.jl")
include("model/eqactbnd.jl")
include("model/eqbndcom.jl")
include("model/eqcapact.jl")
include("model/coef_csv.jl")
include("model/eqcapvac.jl")
include("model/eqcpt.jl")
include("model/cal_red.jl")
include("model/eqptrans.jl")
include("model/eqfloshr.jl")
include("model/eqflomrk.jl")
include("model/eqcumflo.jl")
include("model/eqcumcom.jl")
include("model/eqcombal.jl")
include("model/eqflobnd.jl")
include("model/eqflofr.jl")
include("model/eqire.jl")
include("model/eqirebnd.jl")
include("model/eqxbnd.jl")
include("model/eqblnd.jl")
include("model/eqbndcst.jl")
include("model/eqpeak.jl")
include("model/eqobjels.jl")
include("model/eqstgtss.jl")
include("model/eqstgips.jl")
include("model/eqstgaux.jl")
include("model/eqstgflo.jl")
include("model/equserco.jl")
include("model/eqobjinv_prep.jl")
include("model/eqobjfix_prep.jl")
include("model/eqmain_prep.jl")
include("model/qack_prep.jl")
include("model/qack_log.jl")
include("model/eqobj.jl")
include("model/eqdamage.jl")
include("model/bndmain.jl")
include("ext/vda/pp_actef.jl")
include("ext/vda/eqashar.jl")
include("ext/vda/ucbet.jl")
include("ext/vda/eqcaflac.jl")
include("ext/vda/eqslsift.jl")
include("ext/vda/eqactups.jl")
include("ext/vda/eqlducs.jl")
include("coef/state.jl")
include("coef/coef_cpt.jl")
include("coef/coef_nio.jl")
include("coef/coef_ptr.jl")
include("coef/coef_obj.jl")
include("coef/coef_alt.jl")
include("coef/coef_shp.jl")
include("coef/coef_ext.jl")
include("coef/later.jl")
include("ext/dsc/init_ext.jl")
include("ext/vda/equcrtp.jl")
include("ext/vda/init_ext.jl")
include("prep/qalog.jl")
include("prep/ppmain.jl")
include("prep/timslice.jl")
include("prep/pp_off.jl")
include("prep/interp.jl")
include("ext/dsc/prepret.jl")
include("prep/curex.jl")
include("prep/preppm.jl")
include("ext/vda/prep_ext.jl")
include("ext/vda/powerflo.jl")
include("ext/vda/cstbal.jl")
include("ext/vda/resloadc.jl")
include("ext/vda/gasgrids.jl")
include("ext/vda/dynslite.jl")
include("prep/ppmain_prelv.jl")
include("prep/ppmain_life.jl")
include("ext/vda/pp_prelv.jl")
include("prep/pp_qafs.jl")
include("prep/ppmain_dflt.jl")
include("prep/ppmain_tsattr.jl")
include("prep/elastic.jl")
include("prep/ppmain_flo.jl")
include("prep/ppmain_flofs.jl")
include("prep/ppmain_ire.jl")
include("prep/ppmain_bnd.jl")
include("prep/ppmain_cum.jl")
include("prep/ppmain_stg.jl")
include("prep/ppmain_uc.jl")
include("prep/ppmain_ucmap.jl")
include("prep/ppmain_blend.jl")
include("prep/ppmain_reduce.jl")
include("ext/vda/ppm_ext.jl")
include("model/generate.jl")
include("model/solve_stp.jl")     # M1.5: the stepped (myopic) solve, solve.stp
include("model/bnd_stp.jl")       # M1.5: the bounds of a stepped run and the model of one step
include("model/solution.jl")      # #97: the solution as a TIMES.jl dump (M1.6, started early)
include("solver_options.jl")      # run_model: the solver option file (<solver>.opt), as GAMS reads it (20 Nov 2026)
include("run.jl")                 # run_model: a model from its run and DD files, without GAMS (18 Nov 2026)

export run_model

end # module TIMES
