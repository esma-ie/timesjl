# Crafted cases: added data files

Each folder holds the files a crafted case in [`../crafted.toml`](../crafted.toml)
adds to an open suite model, to reach TIMES code paths no suite model's data
reaches. A crafted case inherits the licence of the model it extends; the files
here are TIMES.jl's own (GPL-3.0-or-later, like the repository) and contain no
data from any other model.

| Folder | Extends | What it adds | Made for |
| --- | --- | --- | --- |
| `demo12_red17b/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_red17b.run`: `demo12.run` unchanged but for a three-line header and the include of `red17b.dd`. `red17b.dd`: `VDA_EMCB` OIL→INDCO2 (0.1 in both regions) and four `FLO_BND` records on `REFEOIL00`'s OIL input (LO, UP below and above the existing `ACT_BND`, FX) | M1.3 change 17b, 5 Nov 2026: under REDUCE, an emission whose source flow is the activity flow (`cal_red.red` L37-38) and flow bounds on that flow (`bnd_flo.mod` L37-39); with REDUCE off, `bnd_flo.mod` L25-27. Fixtures `demo12_red17b`, `demo12_red17b_off` |
| `demo12_ips/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_ips.run`: `demo12.run` with the include of `ips.dd`. `ips.dd`: an inter-period crude-oil store STKOIL1 in both regions (vintaged in REG2), STG_CHRG before the first period, STG_LOSS 2%, an INDCO2 output tied to the storage level | M1.3 changes 19 and 19b, 5 Nov 2026: EQ_STGIPS (both row kinds, both vintage branches) and EQ_STGAUX's inter-period terms (`eqstgaux.mod` L25-32). Fixtures `demo12_ips`, `demo12_ips_off` |
| `demo12_uc/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_uc.run`: `demo12.run` with the include of `uc.dd`. `uc.dd`: dispatching attributes on REG1's ELCTEGAS00 (ACT_UPS, ACT_MINLD, ACT_LOSPL, ACT_CSTUP, ACT_TIME, ACT_CSTRMP) and unit commitment by start-up type on REG2's (ACT_CSTSD, ACT_SDTIME, ACT_MAXNON, ACT_LOSSD) | demo12 variant 2 (`docs/demo12-variants.md`), 5 Nov 2026: `eqactups.vda`, `eqlducs.vda`. Fixture `demo12_uc` (`test/fixtures/variant_fixtures.toml`) |
| `demo12_refit/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_refit.run`: `demo12.run` with the include of `refit.dd`. `refit.dd`: two refit options of the coal plant ELCTECOA00 (ELCLECOA01 lifetime extension, ELCRFCOA01 retrofit) in both regions, PRC_REFIT +1/-1 in REG1, +3/-3 and +4 on the host in REG2 | demo12 variant 5 (`docs/demo12-variants.md`), 5 Nov 2026: `prepret.dsc` (EQL_REFIT, EQ_CUMRET, EQL_SCAP). Fixture `demo12_refit` (`test/fixtures/variant_fixtures.toml`) |
| `demo12_ucrt/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_ucrt.run`: `demo12.run` with the include of `ucrt.dd`. `ucrt.dd`: five dynamic bounds (UC_DYNBND): wind capacity UP (both regions, REG2 with no growth factor), solar investment LO (REG1), oil-plant activity FX (REG2), GAS production UP and net COA LO (REG1, ANNUAL-level commodities) | M1.3 change 20, 6 Nov 2026: `equcrtp.vda` EQU_EXT, the branches OTUS9r does not reach (EQN_UCRTP on CAP and NCAP, EQE_UCRTP, EQN_UCRTC) |
| `demo12_refit_afc/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) and `demo12_refit/refit.dd` | `demo12_refit_afc.run`: `demo12.run` with the includes of `refit.dd` and `afc.dd`. `afc.dd`: NCAP_AFC on the coal input ELCCOA of the retiring plant ELCTECOA00 (both regions) and a second past vintage of it in REG1 (NCAP_PASTI 1995); RCAP_BND LO (2015) and FX (2030) in REG1 and a negative 'N' option in REG2 | M1.3 changes 20b-2 and 20b-3, 6 Nov 2026: the `%RCAPSBM%` term of `eqcaflac.vda` L57 (EQL_CAPFLO) with two retiring vintages in one row (G48); the retirement bounds of `prepret.dsc` L66-76 no suite model reaches. Fixture `demo12_refit_afc` (`test/fixtures/variant_fixtures.toml`) |

| `demo12_curex/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_curex.run`: `demo12.run` with the include of `curex.dd`. `curex.dd`: currencies MUSD, MGBP and MJPY, a second discount currency in REG1 (G_DRATE), global rates (G_CUREX, one chained, one with two targets) and a regional rate (R_CUREX), and ACT_COST, NCAP_FOM and FLO_DELIV records in those currencies | M1.3 change 26, 8 Nov 2026: currency conversion (`preppm.mod` L27-28, `curex.gms`). Fixture `demo12_curex` |
| `demo12_ucdyn/` | TIMES_Demo demo12 (`etsap-TIMES/TIMES_Demo` @ `962db86`, CC BY 4.0) | `demo12_ucdyn.run`: `demo12.run` with the include of `ucdyn.dd`. `ucdyn.dd`: five dynamic user constraints in the RHS direction, one per family (EQE_UCRSU twice, EQE_UCSU, EQE_UCRSUS, EQE_UCSUS), with CAP, NCAP, ACT, FLO, COMPRD, COMNET and IRE terms, GROWTH, SYNC, UC_TIME, and the past investments of the hydro plant in the first period | M1.3 change 21, 9 Nov 2026: `equserco.mod` L80-106 and `uc_pasti.mod`. Fixture `demo12_ucdyn` |

Make a crafted reference with the harness's `--suite` option, for example:

```
python reference/python/make_reference.py --suite reference/crafted.toml --out ../timesjl-reference --solvers CPLEX,HIGHS --root times_source=../TIMES_model --root times_demo=../TIMES_Demo --model TIMES_Demo-demo12_red17b
```

then the fixtures with `scripts/make_m11_fixture.jl`.
