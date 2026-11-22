# Fewer merge conflicts: a proposal

Status: proposal of 22 Nov 2026, for James. Nothing in it is built until he
answers (Open decisions, `docs/decisions.md`). The `/sync-prs` command is
the exception: it follows the current rules, and its PR builds it.

Not a translation change: no GAMS code is translated, and nothing TIMES.jl
generates changes.

## The problem

Work runs in several Claude tabs at once, one branch and one worktree per
change. The code rarely clashes; a few shared documents do.

Files changed by the last 60 merged PRs (to 22 Nov 2026):

| File | PRs |
| --- | --- |
| `docs/decisions.md` | 55 |
| `docs/translation-guide.md` | 47 |
| `docs/m13-plan.md` | 40 |
| `docs/gams-julia-map.md` | 40 |
| `reference/crafted.toml` | 38 |
| `reference/dd/README.md` | 37 |
| `test/fixtures/public_fixtures.toml` | 29 |

Files that had to be resolved by hand in the 35 "merge origin/main into the
branch" commits from 12 to 22 Nov 2026:

| File | Merges |
| --- | --- |
| `docs/decisions.md` | 32 |
| `docs/m13-plan.md` | 16 |
| `docs/translation-guide.md` | 12 |
| `reference/dd/README.md`, `reference/crafted.toml` | 10 each |
| `test/fixtures/public_fixtures.toml` | 8 |
| `docs/gams-julia-map.md` | 7 |
| any source or test file | 3 or fewer |

The decision log causes almost all of it, for two reasons:

- Every PR adds its rows at the top of the same two tables ("Decisions in
  the chat" and "Log by pull request"). Two PRs that do so always clash.
- The rule asks each PR to record the outcome of the PRs merged before it.
  So after every merge, every other open PR edits the same rows.

A coordinating agent with subagents would not remove these conflicts: they
come from many branches writing to the same lines, not from who does the
writing. The proposals below change where those lines live, and give the
shared text one owner.

## Proposal 1: the decision log, one file per pull request (rule-level)

Layout:

```
docs/decisions/
  README.md              the rule (moved from decisions.md, unchanged)
  open.md                the Open decisions list
  pr/0189.md             one file per PR: its heading and its table
  chat/2026-11-22-q1.md  one file per answer given in the chat
docs/decisions.md        built from the folder by scripts/decision_log.py
```

Who writes what:

- **A PR** adds only its own file, `docs/decisions/pr/<number>.md`, the day
  it opens. A new file never conflicts.
- **An answer in the chat** gets its own file, written by the tab that
  records it. Two tabs never write the same file.
- **Outcomes after merges** ("accepted by merge", "merged <date>"), the
  **Open decisions list** and the built `docs/decisions.md` are kept by
  one tab only, the integrator, in one log PR after each check-in (as
  #188 did on 21 Nov 2026). No other PR touches them.

`docs/decisions.md` keeps its present look (the rule, Open decisions, the
chat table newest first, the log by PR newest first), so nothing changes
for the reader. The script only puts the files together. It changes no
text, and fails if a file does not have the expected heading and table.

Changing to the new layout is one PR. The script splits today's file into
the folder, then builds it back. The check is that the rebuilt
`docs/decisions.md` is identical to the old one.

CLAUDE.md, Decision log, last sentence. Now: "Update the log in each PR,
and record the outcome when it merges or James answers." Proposed: "Each
PR adds its own file in `docs/decisions/pr/`; the integrator tab records
outcomes and keeps the Open decisions list, after each check-in." The rule
itself (default built in, no default, rule-level needs an explicit yes) is
unchanged.

Rule-level: it changes a rule in CLAUDE.md, so it needs James's explicit
yes.

## Proposal 2: shared status text kept by the integrator

`docs/m13-plan.md` and `docs/translation-guide.md` clash for the same
reason: each change adds its own row (rarely a conflict) and also edits
shared lines (the table of refused features, the milestone's status
paragraph). Proposed:

- A change PR adds or edits only the rows and paragraphs of its own
  change: its row in the change table of `m13-plan.md`, its rows in
  `gams-julia-map.md`.
- The shared lines (the refused-features table, the status paragraph of
  `translation-guide.md`, the gate summary) are updated by the integrator
  in the same log PR after each check-in, from the PRs merged that day.

Until then they lag main by half a day at most. Not rule-level, but it
changes what each PR records, so it is asked rather than built.

## Proposal 3: the lists that only grow

`reference/crafted.toml`, `test/fixtures/public_fixtures.toml` and
`reference/dd/README.md` gain one entry per crafted case, usually at the
end, so two PRs that both add a case clash at the end of the file.

- **(a) Git's union merge**, one line in `.gitattributes` for the three
  files. When both sides add lines at the same place, Git keeps both.
  Cheap, but it can silently duplicate a line that both sides changed,
  and GitHub's "can be merged" check may not use it. `/sync-prs` would
  then parse both TOML files and run `reference/python/test_suite.py`
  after each merge.
- **(b) One file per case** (`reference/crafted/<case>.toml`,
  `test/fixtures/public/<case>.toml`), read through one loader function.
  New files never conflict, but some 50 scripts and tests read these files
  directly today, so it is a larger PR with its own checks (every loader
  returns the same list as before).

Recommended: (a) now, and (b) only if (a) causes trouble. These files cause
a quarter as many conflicts as the decision log, so Proposal 1 matters
more.

## How the tabs work together

- **One tab per change**, in its own worktree, as now. It writes code, its
  tests, its own rows and its own decision file.
- **One integrator tab.** After James merges at a check-in, it runs
  `/sync-prs`: brings every open PR up to date with main, then writes the
  day's log PR (Proposals 1 and 2), then lists the worktrees whose PRs
  have merged and removes them once James says yes.
- **Dependent changes** (stochastic changes 71 to 76) start from the
  previous change's branch rather than from main, and say so in the PR.
- **Housekeeping in one PR:** the dashboard refresh and the log go in
  one PR per check-in where both are due.
