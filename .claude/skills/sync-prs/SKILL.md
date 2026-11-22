---
name: sync-prs
description: Bring every open pull request up to date with main after merges, resolving merge conflicts (mostly docs/decisions.md) and recording the outcomes of the PRs merged since; then offer to remove worktrees whose PRs have merged. Run by the integrator tab after James merges at a check-in, or when he asks to resolve PR conflicts.
disable-model-invocation: true
argument-hint: "[PR numbers, default: every open PR]"
---

# /sync-prs

Bring open PRs up to date with `origin/main`, one at a time, and report what
was done. Background and the evidence behind this routine:
`docs/merge-conflicts-plan.md`.

Arguments: optional PR numbers. With none, take every open PR.

## 1. Survey

```bash
git fetch -q --prune origin
gh pr list --state open --limit 100 --json number,headRefName,mergeable,title
```

- `mergeable` UNKNOWN means GitHub has not computed it yet. Test locally
  instead: `git merge-tree --write-tree origin/main origin/<branch>` exits 0
  when the merge is clean.
- Sync only the PRs that conflict, unless James asked for all of them.
  A PR that is merely behind main needs nothing.
- List the PRs merged since the last sync (`gh pr list --state merged
  --limit 20 --json number,mergedAt,title`). Their outcomes are recorded
  in step 3.

## 2. Where to merge, for each PR

Find the worktree that holds the branch: `git worktree list --porcelain`.

- **A worktree holds it.** Merge there only if `git status --porcelain` is
  empty and the branch is neither ahead of nor behind `origin/<branch>`.
  Otherwise another tab is working in it. Skip the PR and report it; never
  stash, reset or switch branches in another tab's worktree.
- **No worktree holds it.** Make a temporary one in the session's
  scratchpad: `git worktree add --detach <scratchpad>/sync-<n>
  origin/<branch>`. Push with `git push origin HEAD:<branch>`, then
  `git worktree remove` it.

Always merge, never rebase: the branch is already pushed, and other tabs
or James may hold copies of it.

```bash
git merge --no-commit origin/main
git diff --name-only --diff-filter=U
```

## 3. Resolving

### docs/decisions.md (almost every conflict)

Both sides usually added rows at the top of the same table.

- **Keep both sides.** Never drop a row from either side.
- **Newest first:** in "Decisions in the chat", rows by date, newest at the
  top; on the same date, the PR's own rows above main's. In "Log by pull
  request", the PR's own section first, then main's sections.
- **Remove exact duplicates** (the same row on both sides) and keep one.
- **Record outcomes of PRs merged since** (from step 1) whose sections are
  still marked open. Do this whether or not they conflicted:
  - Heading: `(open)` becomes `(merged <d Mon yyyy>)`.
  - A row whose "Decided" cell is a built-in default ("Recommended: ...
    Built in.") and whose "How" is `open`: `accepted by merge, <date>`.
  - A row with no default, or a rule-level one with no explicit yes: leave
    it open. It belongs on the Open decisions list (check that it is
    there).
  - A row James has already answered keeps his answer.
  - A merged PR with no decisions ("Decisions for you: none") needs no
    entry.
- Use the merge date from `gh pr view <n> --json mergedAt`, in UTC.

### Other shared docs and lists

`docs/m13-plan.md`, `docs/translation-guide.md`, `docs/gams-julia-map.md`,
`reference/crafted.toml`, `reference/dd/README.md`,
`test/fixtures/public_fixtures.toml`:

- New rows or entries on both sides: keep both, in the file's order (change
  number for `m13-plan.md`; otherwise main's entries first).
- The same status line edited on both sides: combine both facts into the
  line; if they contradict, stop and ask James.
- After resolving a TOML file, check that it parses:
  `python -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" <file>`.

### Code (src/, test/, scripts/, reference/python/)

Resolve only when both sides add independent code (for example two new
`include`s or two new test files). Then run the tests that cover the files
(`julia --project=. test/unit/<file>.jl`, or `test/runtests.jl` for
`src/`), keeping to the run limits in CLAUDE.md (`TIMESJL_THREADS`). If the
two sides change the same logic, abort the merge (`git merge --abort`),
skip the PR, and report it with the conflicting hunks.

## 4. Check, commit, push

1. No conflict markers are left:
   `grep -n '^<<<<<<<\|^=======$\|^>>>>>>>' <files>` finds nothing.
2. `git diff origin/main --stat` shows only the PR's own changes, plus any
   outcomes recorded in step 3. Read the `docs/decisions.md` part of
   `git diff origin/main` to be sure.
3. Commit:
   `Merge remote-tracking branch 'origin/main' into <branch>; decision log: #<n> merged`
   (name the PRs whose outcomes were recorded), ending with the session's
   attribution lines.
4. Run `gh pr view <n> --json state` again just before pushing: James may
   have merged it meanwhile. Push only if it is still OPEN.
5. Confirm: `git fetch -q origin && git merge-tree --write-tree origin/main
   origin/<branch>` exits 0.

Do the PRs one at a time, refetching `origin/main` before each: a PR James
merges while the routine runs changes main for the next one.

## 5. Tidy merged worktrees (offer, do not do unasked)

List every worktree whose branch's PR has merged (`gh pr list --state
merged --json headRefName`), with:

- uncommitted files: `git -C <wt> status --porcelain | wc -l`;
- commits not on GitHub: `git -C <wt> rev-list --count HEAD --not
  --remotes=origin`. For each such commit, check whether a commit with the
  same title is on `origin/main` (a pre-rebase copy); if not, the worktree
  holds work that is not on GitHub: keep it and say so.

Never list the main folder, `TIMESjl-nightly`, `TIMESjl-m14`, or a
worktree inside another session's scratchpad. Show James the list and
remove only on his yes: `git worktree remove <wt>` (never `--force`), then
`git branch -D <branch>`.

## 6. Report

One short table for James: PR, files that conflicted, how each was resolved,
outcomes recorded, the merge commit, and every PR skipped with the reason.
Then the worktrees offered for removal, if any.
