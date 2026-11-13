# demo12 variants for advanced TIMES features

Approved by James on 5 Nov 2026. Each variant is TIMES_Demo demo12 (CC BY 4.0)
with a small added DD file that switches on one advanced feature, as documented
in the ETSAP User Notes (`etsap-TIMES/TIMES_Documentation/User_Notes`, CC BY 4.0)
or announced in `Version.log` of TIMES v4.9.7 but not yet in the PDF
documentation. They fill the CI gap that demo12 alone leaves: features only the
large core models (or none of them) reach.

## How a variant is made and checked

1. Read the User Note or `Version.log` entry and the GAMS source of the
   feature (never from memory); write `reference/dd/<case>/<feature>.dd` and a
   run file that is `demo12.run` plus its include; add the case to
   `reference/crafted.toml`.
2. Run the harness with GAMS 54.6.1 on James's workstation, both variants,
   CPLEX and HiGHS (`make_reference.py --suite reference/crafted.toml`).
   Check that GAMS generates every intended equation family (the CONVERT
   dictionary) and that the solve is optimal.
3. CI (`test/unit/test_variants.jl`, registry
   `test/fixtures/variant_fixtures.toml`, fixtures by
   `scripts/make_variant_fixture.jl`): preprocessing from the input dump to
   ppm on every symbol, and model generation refusing exactly the families not
   yet translated, so a feature can never yield a model with rows missing.
4. When a translation change covers the feature, its list of untranslated
   families shrinks; at empty, the variant moves to
   `test/fixtures/public_fixtures.toml` with its matrix and solution (layers
   2-3).

Extension scope (docs/translation-guide.md): core and VDA in Phase 1, DSC next;
MACRO, stochastics, ETL, climate and damage after M1.7.

## Order: the order the features entered TIMES (James, 5 Nov 2026)

| # | Variant | Case | First release (Version.log) | GAMS | Status |
| --- | --- | --- | --- | --- | --- |
| 2 | Dispatching and unit commitment | `TIMES_Demo-demo12_uc` | 3.7.0, Aug 2014 (ramping, `eqactups.vda`); 3.9.0, Oct 2015 (linear dispatch); 3.9.7, Jul 2016 (unit commitment by start-up type, `eqlducs.vda`), announced 4.0.0 | `eqactups.vda`, `eqlducs.vda` | made (5 Nov 2026) |
| 5 | Retrofits and lifetime extensions | `TIMES_Demo-demo12_refit` | 4.1.2, Mar 2017 (`PRC_REFIT`); 4.1.6, 4.6.4, 4.6.7-8, 4.7.1 | User Note `TIMES-Refits-Note.pdf`; `prepret.dsc`, `ppmain.mod` L484-487 | made (5 Nov 2026); translated, layers 2-3 PASS (M1.3 change 20b, 6 Nov 2026) |
| 1 | Load shifting | `TIMES_Demo-demo12_ls`, `TIMES_Demo-demo12_lst` | 4.3.0, Jan 2019 (`STG_SIFT`); 4.3.6 (asymmetric) | User Note `TIMES-Load-Shifting.pdf`; `eqactups.vda` | made (8 Nov 2026); translated, layers 2-3 PASS (M1.3 change 24) |
| 4 | Dynamic time slices | | 4.3.2, Mar 2019 (varying cycles); 4.4.1, Feb 2020 (time-slice trees, `dynslite.vda`) | User Note `User_Note-TIMES-Dynamic-timeslices.docx` | |
| 3 | Flexible time-slice storage (STSFLX) | | 4.5.8, Sep 2021 | User Note `TIMES-Experimental-STS-Variant.pdf` | |
| 7a | Recent attributes, first batch | | 4.6.3-4.7.5, Jul 2022 - Oct 2023: `G_RFRIR`, `NCAP_AFSX`, emissions on CHP activity, non-vintaged `ACT_FLO`, `NCAP_ICOM` for past investments | Version.log | |
| 6 | PTDF power grid | | 4.8.4, Dec 2024 - 4.9.0, Jul 2025 (on the DC power flow of 3.3.6, Jul 2012) | User Note `TIMES-Grid-Features.pdf`; `powerflo.vda` | begun 9 Nov 2026: demo12_pf, a phase-angle grid on the REG1-REG2 link (M1.3 change 27a); demo12_pfa adds the allocation of generation and sectoral demand to the grid nodes (M1.3 change 27a-2, 10 Nov 2026); demo12_pfd adds a second grid node in REG1, so the demand allocation rows exist (M1.3 change 27b-2, 13 Nov 2026: both cases pass layers 2-3); the PTDF case follows (with M1.3 change 27, the public case for JRC-EU-TIMES's power flow; moved ahead of variants 4, 3 and 7a by James, 7 Nov 2026) |
| 7b | Recent attributes, second batch | | 4.9.2-4.9.3, Oct 2025 - Feb 2026: bounds on absolute power rate levels, OCOM flows from retirements | Version.log | |

Later, outside Phase 1's core and VDA scope: lumpy investments and early
retirement (DSC); logit market sharing (ECB), MACRO-MSA and MLF, stochastics,
ETL, the Climate Module, damage costs; the Weymouth gas grid (nonlinear).

## Variant 2: dispatching and unit commitment (5 Nov 2026)

`reference/dd/demo12_uc/uc.dd`, on the gas plant ELCTEGAS00 (DAYNITE):

- REG1, linear dispatch: `ACT_UPS` UP/LO 0.5 (ramp rates), FX 0.25,
  `ACT_MINLD` 0.3, `ACT_LOSPL` FX 0.1, `ACT_CSTUP` at DAYNITE, `ACT_TIME`
  UP/LO 6 h and N 200, `ACT_CSTRMP` UP/LO.
- REG2, unit commitment by start-up type: `ACT_UPS` FX 0.3, `ACT_MINLD` 0.4,
  `ACT_LOSPL` FX 0.05, `ACT_CSTSD` for HOT, WARM and COLD start-ups and HOT
  shut-down, `ACT_SDTIME` 2/4/8 h up and 1 h down, `ACT_MAXNON` HOT 8 h and
  WARM 48 h, `ACT_LOSSD` HOT, `ACT_TIME` UP/LO 4 h. A process with start-up
  types gets the `eqlducs.vda` equations instead of the linear dispatch ones
  (`eqlducs.vda` EQU section), so the two regions reach both.
- Linear: discrete unit commitment needs `$SET DUC YES` (binary variables,
  indicator constraints), so it waits for MIP support.

GAMS 54.6.1, both variants, optimal (objective 23,961,066.47 by CPLEX and
HiGHS, against demo12's 23,960,685.77): 32 EQ_CAPLOAD, 32 EQ_ACTRAMP, 32
EQE_ACTUPS, 16 EQL_ACTUPS, 40 EQL_ACTUPC, 32 EQ_ACTPL, 16 EQ_ACTRMPC, 48
eq_sdlogic, 48 eq_sudupt, 24 eq_sdslant, 16 eq_sdminon, 16 eq_sudload, 32
eq_sudtime and 16 eq_sudpll rows. TIMES.jl: the M1.3 chain from the input
dump PASS at every checkpoint on both variants (821 symbols); model
generation refuses the eight untranslated groups (all 14 families). CI
fixture `demo12_uc` (as_run).

## Variant 5: retrofits and lifetime extensions (5 Nov 2026)

From the User Note "Retrofits and Lifetime Extensions in TIMES" (TIMES v4.1
User Note, March 2017, updated April 2023): `PRC_REFIT(r,prc,p)` maps a host
process to an option, +1 mod 2 a lifetime extension, -1 mod 2 a retrofit;
values with |N| > 2, or +2/+4 on the host itself, force the refitted capacity
to equal the retired capacity, and +4 stops forced retrofits cascading. Each
option is characterised as a full new technology; refits need early
retirement (demo12.run's DSCAUTO YES gives it).

`reference/dd/demo12_refit/refit.dd`: host ELCTECOA00 (demo12's existing coal
plant, residual capacity to 2035); options ELCLECOA01 (lifetime extension,
efficiency 0.384, investment 600, life 20) and ELCRFCOA01 (efficiency
retrofit, 0.42, 300, 15), both from 2010. REG1: +1 and -1. REG2: +3 and -3,
and +4 on the host.

GAMS 54.6.1, both variants, optimal (objective 23,926,037.11 by CPLEX and
HiGHS): 24 EQL_REFIT, 7 EQL_SCAP and 17 EQ_CUMRET rows, 41 VAR_RCAP and 31
VAR_SCAP columns; the optimum buys the retrofit in both regions. TIMES.jl:
the M1.3 chain PASS on both variants (822 symbols).

The variant found a silent gap in model generation: TIMES.jl built the model
without the 48 retirement rows and 72 columns, with no error. Both checks for
early retirement (`untranslated_families`, `objective_unported`) looked for
the symbol VNRET, which is a `$MACRO` (prepret.dsc L41) and so never in a
dump. They now look for RP_RTF, which prepret.dsc declares (L22) exactly
when it defines VNRET. OTUS9r-reference has early retirement on (55 PRC_REFIT
and 948 RCAP_BND records; 660 EQL_REFIT and 2,008 EQ_CUMRET rows in GAMS), so
its model now also refuses for that reason, and needs the retirement
equations (docs/m13-plan.md, change 20b).

Translated by M1.3 change 20b (6 Nov 2026, in four parts: the retirement
equations, the -VAR_SCAP capacity terms, the VAR_RCAP/VAR_SCAP bounds, the
objective terms). The whole model passes layers 2 and 3 on both variants
(as_run 3,351 rows, 4,627 columns, 19,246 nonzeros; reduce_off 8,893, 9,891,
32,422; objective 23,926,037.11), and so does the crafted case
TIMES_Demo-demo12_refit_afc, which adds the paths the variant does not reach
(EQL_CAPFLO with two retiring vintages, RCAP_BND LO/FX and a negative 'N'
option). CI fixtures `demo12_refit` and `demo12_refit_afc`, whole model.
