# Model generation driver: every translated equation family, the bounds and
# the objective sense, after checking that the data asks for no equation
# family that is not translated yet.
#
# GAMS: maindrv.mod L77-92 (mod_vars, eqmain, mod_equa, bndmain), eqmain.mod
# L33-262, mod_equa.mod L16-213 (the MODEL statement), the extension MODEL
# additions mod_ext.vda L10-55 and mod_ext.dsc L9-12, solve.mod L37
# (`SOLVE %MODEL_NAME% MINIMIZING objZ`), v4.9.7.
#
# Completeness check. GAMS generates a row for every member of an
# equation's domain, so a family left out here would silently drop rows. For
# each untranslated family in the MODEL statement, `untranslated_families`
# tests a condition that holds whenever that family has at least one row:
# the non-emptiness of a set or parameter every member of the domain requires
# (conservative: it may refuse data for which GAMS would generate no row).
# Untranslated extensions are recognised by a switch or by a symbol only
# their declaration file declares.

"One untranslated equation family that the data would generate rows for."
const Untranslated = NamedTuple{(:family, :gams, :why),Tuple{String,String,String}}

"""
    untranslated_families(tm) -> Vector{Untranslated}

The equation families of the MODEL statement that are not translated yet and
for which the data (or a run switch) would give at least one row. Empty when
the model can be generated completely.
"""
function untranslated_families(tm::TimesModel)
    d = tm.data
    out = Untranslated[]
    note!(family, gams, why) = push!(out, (; family, gams, why))
    yes(name) = uppercase(gswitch(tm, name, "")) == "YES"
    S(name, N) = gset_opt(d, name, N)
    P(name, N) = gparam_opt(d, name, N)

    # --- run switches selecting other formulations ---------------------------
    for sw in ("STAGES", "SPINES", "OBJANN", "VALIDATE", "ETL", "CLI", "ABS", "ECB", "MCA")
        yes(sw) && note!("(variant $sw)", "mod_equa.mod / main_ext.mod", "switch $sw = YES")
    end
    # A stepped (myopic) run: %R_T% is 'R,SUBT(T)' (maindrv.mod L38-40), so every equation is generated for
    # the periods of one step, and solve.stp solves step by step (maindrv.mod L111-113): `solve_stepped!`
    # (M1.5). What solve.stp does under controls that are not translated is listed here (`stp_unported`)
    if stepped(tm) && !stp_is_step(tm)
        foreach(x -> note!("(stepped run)", x[1], x[2]), stp_unported(tm))
    end
    # %POWERFLO% YES: phase-angle grids are translated (EQ_GR_POWFLO, M1.3 change 27b), with the allocation of
    # supply and demand to grid nodes (EQ_GR_GENALL, EQ_GR_DEMALL, IREAUX: 27b-2) and the bound on a grid's net
    # imports and exports (EQ_GR_XBND); PTDF and gas grids are not
    if yes("POWERFLO")
        foreach(w -> note!("(variant POWERFLO)", "powerflo.vda", w), powerflo_model_unported(tm))
    end
    # the discrete unit commitment (a MIP): eqlducs.vda L128-175, and the DP_UNS term of EQ_ACTPL
    # (eqactups.vda L106-109)
    yes("DUC") && note!("(discrete unit commitment)", "eqlducs.vda L128-175, eqactups.vda L106-109", "switch DUC = YES")
    uppercase(gswitch(tm, "MACRO", "NO")) in ("YES", "CSA", "MSA", "MLF") &&
        note!("(MACRO)", "eqmacro.tm, mod_ext.msa/mlf", "switch MACRO = $(gswitch(tm, "MACRO", ""))")
    for (sym, ext) in (("BS_RVT", "ABS"), ("CM_PREDEF", "CLI"), ("TEG", "ETL"), ("ECT_CHP", "IER"), ("NITER", "MSA/MLF"))
        Reference.has_symbol(d.dump, sym) && note!("(extension $ext)", "equ_ext.$(lowercase(split(ext, '/')[1]))", "$sym is declared")
    end

    # --- eqmain.mod families ---------------------------------------------------
    # Families whose domain needs a parameter or set that is empty in a model without them.
    for (fam, gams, sym, N, kind) in (
            ("EQ_OBJELS / EQL_COMCES", "eqobjels.mod, mod_equa.mod L30/L80", "RCJ", 4, :s),
            ("EQ_DAMAGE / EQ_OBJDAM", "eqdamage.mod, mod_equa.mod L209-210", "DAM_COST", 4, :p),
            # VDA (always loaded, initmty.mod L458) and DSC extensions
            # the dispatching equations of eqactups.vda L39-117 (eq_actups!) and the unit commitment by
            # start-up type of eqlducs.vda L67-124 (eq_lducs!) are translated
            ("EQL_STGCCL", "eqactups.vda L121", "STG_MAXCYC", 3, :p),
            ("eq_sdind_1/eq_sdind_0", "eqlducs.vda L158-169", "DP_UNS", 7, :p),
            ("EQG_UCMAX/EQG_UCSUMAX", "ucbet.vda L46-125", "UC_GMAX", 5, :s),
            ("EQ_OBJBAL", "powerflo.vda (mod_ext.vda L42-43)", "COM_CSTBAL", 6, :p),
            ("EQ_RL_*", "resloadc.vda (mod_ext.vda L48-49)", "GR_VARGEN", 4, :p),
            ("EQ_MSNCAP*", "mod_ext.vda L51-52", "RTC_MS", 3, :s),
            ("EQ_GG_*", "mod_ext.vda L54-55", "GG_MM", 2, :s),
            ("EQ_DSCNCAP/EQ_DSCONE", "equ_ext.dsc L21-28", "PRC_DSCNCAP", 2, :s))
        if kind === :decl
            Reference.has_symbol(d.dump, sym) && note!(fam, gams, "$sym is declared")
        elseif Reference.has_symbol(d.dump, sym) && !isempty(kind === :p ? P(sym, N) : S(sym, N))
            note!(fam, gams, "$sym is not empty")
        end
    end
    # EQ_STGTSS and EQ_STSBAL are translated except for storage flexibility
    # (%STSFLX%: RP_STL entries other than 'N', with EQ_STSLEV).
    let k = findfirst(k -> k[4] != "N", gset(tm, "RP_STL").keys)
        k === nothing || note!("EQ_STSLEV and the STSFLX terms of EQ_STSBAL", "eqstgtss.mod L56-73, L88-93",
                               "RP_STL$(gset(tm, "RP_STL").keys[k])")
    end
    # User constraints (equserco.jl): nested UCs and the attribute ONLINE are
    # not translated (ANNUL with INVCOST, INVTAX, INVSUB: M1.3 change 42).
    isempty(S("UC_GMAP_U", 3)) ||
        note!("user constraints, nested (UC_UCN terms)", "equserco.mod L76, L99", "UC_GMAP_U is not empty")
    let other = [k for k in gset(tm, "UC_ATTR") if k[5] in UC_ATTR_REFUSED]
        isempty(other) || note!("user-constraint attribute ONLINE", "uc_cap.mod L36-42", "UC_ATTR$(first(other))")
    end
    return out
end

"""
    generate!(tm) -> Int

Build the whole model: refuse if [`untranslated_families`](@ref) finds any,
then generate the translated equation families, apply the bounds and set
`MINIMIZING objZ`. Returns the number of rows.

A stepped (myopic) run has no single model (maindrv.mod L111-113 includes
solve.stp, which generates and solves one model per step): `generate!`
throws an `ArgumentError` for the run itself and builds the model of one
step (`stp_model`); [`solve_stepped!`](@ref) runs the steps.

GAMS: eqmain.mod L34 (objective), L41 (EQ_ACTFLO), L47-49 (EQ(l)_ACTBND), L54-59 (EQ(l)_BNDNET, EQ(l)_BNDPRD), L64-66 (EQ_CAPACT), L67 (EQ(l)_CAPVAC, coef_csv.mod L75-77), L92
(EQ_CUMFLO), L98-106 (EQ_COMBAL, EQE_COMPRD), L146 (EQ_IRE), L152-154 (EQ(l)_IREBND), L159 (EQ_PEAK), L164
(EQ_PTRANS), L169 (EQ_STGIPS), L170 (EQ_STGAUX), L175 (EQ_STGTSS, EQ_STSBAL), L180-185 (EQ(l)_STGIN/STGOUT), L192 (EQ_BNDCST), L229 (EQE_UCT/UCRT/UCTS/UCRTS, the dynamic EQE_UCSU/UCRSU/UCRSUS/UCSUS and EQE_UCRS), L241-243 (EQ(l)_XBND); equ_ext.vda L85 (EQE_ACTEFF);
equ_ext.vda L88-89 (EQ(l)_CAFLAC, EQL_CAPFLO); equ_ext.vda L90 (EQ_CAPLOAD, EQ_ACTRAMP, EQ(l)_ACTUPS, EQL_ACTUPC, EQ_ACTPL, EQ_ACTRMPC, EQ_SLSIFT);
equ_ext.vda L91 (eq_sdlogic, eq_sudupt, eq_sdslant, eq_sdminon, eq_sudload, eq_sudtime, eq_sudpll);
equ_ext.vda L94-96 (EQ(l)_ASHAR); equ_ext.vda L105-106 (EQN/EQE_UCRTP, EQN_UCRTC); bndmain.mod; solve.mod L37, v4.9.7.
"""
function generate!(tm::TimesModel)
    u = untranslated_families(tm)
    isempty(u) || throw(UnportedError("equation families not translated yet: " *
                                      join(("$(x.family) [$(x.gams); $(x.why)]" for x in u), "; ")))
    (stepped(tm) && !stp_is_step(tm)) &&
        throw(ArgumentError("generate!: a stepped run (TIMESTEP = $(gswitch(tm, "TIMESTEP", ""))) has no single model; " *
                            "solve_stepped! generates and solves the model of each step (solve.stp)"))
    n = eq_obj!(tm)                  # eqmain.mod L34
    n += eq_actflo!(tm)              # L41
    n += eq_actbnd!(tm)              # L47-49
    n += eq_bndcom!(tm)              # L54-59
    n += eq_capact!(tm)              # L64-66
    n += eq_capvac!(tm)              # L67 (coef_csv.mod L75-77, with PRC_SIMV)
    n += eq_cpt!(tm)                 # L77-79
    n += eq_cumcom!(tm)              # L89-90
    n += eq_cumflo!(tm)              # L92
    n += eq_combal!(tm)              # L98-106
    n += eq_flobnd!(tm)              # L111-113
    n += eq_flofr!(tm)               # L118-120
    n += eq_floshr!(tm)              # L125-134
    n += eq_flomrk!(tm)              # L139-141
    n += eq_ire!(tm)                 # L146
    n += eq_irebnd!(tm)              # L152-154
    n += eq_peak!(tm)                # L159
    n += eq_ptrans!(tm)              # L164
    n += eq_stgips!(tm)              # L169
    n += eq_stgaux!(tm)              # L170
    n += eq_stgtss!(tm)              # L175
    n += eq_stgflo!(tm)              # L180-185
    n += eq_bndcst!(tm)              # L192
    n += eq_uc!(tm)                  # L229
    n += eq_xbnd!(tm)                # L241-243
    n += eq_blnd!(tm)                # L249-252
    n += eq_acteff!(tm)              # VDA: equ_ext.vda L85 (pp_actef.vda L56)
    n += eq_caflac!(tm)              # VDA: equ_ext.vda L88-89
    n += eq_actups!(tm)              # VDA: equ_ext.vda L90 (eqactups.vda L39-117)
    n += eq_slsift!(tm)              #   eqactups.vda L131
    n += eq_lducs!(tm)               # VDA: equ_ext.vda L91 (eqlducs.vda L67-124)
    n += eq_ashar!(tm)               # VDA: equ_ext.vda L94-96
    n += eq_ucrtp!(tm)               # VDA: equ_ext.vda L105-106
    n += eq_gr_powflo!(tm)           # VDA: equ_ext.vda L101 (powerflo.vda POWFLO, M1.3 change 27b)
    n += eq_gr_genall!(tm)           #   powerflo.vda L290-313 (M1.3 change 27b-2)
    n += eq_gr_demall!(tm)           #   powerflo.vda L314-340 (M1.3 change 27b-2)
    n += eq_gr_xbnd!(tm)             #   powerflo.vda L341-359
    n += eq_ret!(tm)                 # DSC: mod_equa.mod L212 (prepret.dsc EQOBJ; RP_RTF marks VNRET)
    apply_bounds!(tm)                # maindrv.mod L92
    JuMP.@objective(tm.model, Min, getvar!(tm, "OBJZ"))   # solve.mod L37
    return n
end
