---
name: build-issue
description: Build a GitHub issue from branch to merged PR — choose whether the main session or a background agent builds it, set up its worktree, brief the builder, gate the PR (checks, independent review, mutation checks), clean up after the owner merges, and deploy when asked. Use when the owner says "run #N" / "build #N", "run #A and #B in parallel", "rebase the stack" or "check the merge conflicts" on PRs built this way, "#N merged", or "deploy and check".
---

# Build an issue

The owner names an issue; it comes back as a PR the owner can merge without re-checking it. The owner
merges every PR and decides every deploy. Everything here serves that: what reaches the owner as
"ready" has passed the whole gate on exactly the commit they will merge.

## 0. Before anything

**The GitHub CLI.** `gh` below means the GitHub CLI: run `gh`, and where it is not installed, the
same CLI installed as `gh-cli`. If neither runs, or it is not signed in, tell the owner and stop.

**The project's settings.** Read the `## Building issues` section of the project's `CLAUDE.md`, or
of `AGENTS.md` where `CLAUDE.md` has none. If both have one, follow `CLAUDE.md` and tell the owner
they differ. The section supplies every project-specific value this skill names as a *setting*
below. Read [settings.md](settings.md) when the section is missing, or a setting this build needs is
missing or unclear: draft the section from what the repository shows, show it to the owner to paste
in, name each value you assumed, and wait for their answer before building. The settings are the
owner's to write; leave the files that hold them untouched.

## 1. Who builds it

**The main session** builds it when it is light:
- one area, a handful of files, no migration, nothing in the *must change together* or
  *heavy areas* settings;
- a rebase, a conflict, a merge clean-up, a deploy check;
- anything the owner is waiting on in the conversation.

**A background agent** builds it when:
- the owner asks for parallel work ("run #A and #B in parallel": one agent each);
- it spans a *must change together* setting, a *heavy area*, a migration, or a large
  generated-file change;
- it will run long and the owner wants the conversation free meanwhile.

**An issue with open forks** (its text says "to decide", or investigation could change the plan) is
built in two phases: the builder investigates and STOPS with a report and the forks, each with a
recommendation; the owner decides (ask at most four questions at once); the decisions are recorded
as a comment on the issue; then the build goes on.

**When light turns out heavy** (the fix reaches a migration, the schema, a *heavy area*, or
something the *must change together* setting pairs with it), stop, tell the owner what was found, and hand it to an
agent.

Two issues can run in parallel when they touch different files. A sweeping rename or move runs
alone, or as a pure-rename commit first so a later rebase stays mechanical.

## 2. The worktree

Build outside every *protected path* setting: those are trees something live runs from, moved only
by the deploy, never pulled or fast-forwarded by hand. Each build gets a worktree BESIDE the
repository:

```sh
git fetch -q origin
git worktree add -q -b <type>/<slug> ../<repo>-<short> origin/<default branch>
cd ../<repo>-<short>
```

then run the *worktree setup* setting there. `<type>` comes from the *branch prefixes* setting
(default: `feat`, `fix`, `refactor`, `docs`). Scratch files go in the session's own temporary
directory or inside the worktree (deleted before committing), never a shared `/tmp`.

## 3. The brief

A background builder knows only what the brief says; when the main session builds, the brief is its
own checklist. Point it at the issue (`gh issue view N --comments`), at `CLAUDE.md` / `AGENTS.md` and
the decision records (ADRs) that bear on it, and give it:
- the worktree path and branch, and that it works only there;
- any decisions already made, and what a parallel builder is touching, so it keeps clear;
- the practice below, and the *hard rules* setting, verbatim, followed by these, which hold in every
  project:

> Never merge, and never push to the default branch. Never deploy. Never print secrets or `.env`
> files. Never kill processes by name pattern; wait on your own jobs by PID or file.

**Practice the brief requires:**
- test-driven: a failing test first, then the code (the `tdd` skill, where installed, is the
  reference);
- generated files only through the *generated files* setting's commands, never by hand;
- every area the *must change together* setting pairs with the change, changed in the same PR;
- a mutation check for every guard or rule the change adds: commit the change, undo the guard, show
  which tests fail, and restore it with `git checkout -- <file>`;
- the *check* setting run on exactly the committed tree, and each *extra test* the number of times
  its setting says;
- a DRAFT PR whose body says what each decision built, the mutation results, and `Closes #N` (or
  `Part of #N`); the `pr` skill, where installed, shapes the rest of the body.

Commits and PR bodies end with the *sign-off* setting's lines. No bare `@name` anywhere on GitHub.

## 4. The gate, before "ready"

1. **Review** every PR except a trivial one: a trivial PR adds no file, changes about 100 lines or
   fewer, and carries no decision the builder made that the issue had not. Every other PR goes to a
   SECOND agent, given the PR and the issue (never the builder's account of it), asked for ranked,
   confirmed findings, each with its evidence. The
   `code-review` skill, where installed, can run it. It also runs each *review extras* setting that
   applies, such as a migration tried on a copy of real data. Send the findings back to the builder;
   a finding that changes a decision goes to the owner first.
2. **Re-run it yourself** on the pushed head: the *check* setting and every *extra test* setting. A
   builder's "passes" is a claim until you have seen it pass.
3. `gh pr ready N`, then confirm `gh pr view N --json mergeable,mergeStateStatus` reads `MERGEABLE`
   and `CLEAN` (poll while it reads `UNKNOWN`).
4. Tell the owner: what it does, what was checked and by whom, and anything they will notice live.
   If two open PRs touch the same files, say which to merge first and why
   (`git merge-tree --write-tree --name-only origin/<a> origin/<b>`).

## 5. After "merged"

1. Confirm it, chained, before deleting anything; after a squash merge the branch tip is no evidence:
   ```sh
   m=$(gh pr view N --json state,mergeCommit -q '.state+" "+.mergeCommit.oid') && echo $m &&
   git fetch -q origin && git merge-base --is-ancestor ${m#* } origin/<default branch> &&
   git worktree remove ../<repo>-<short> && git branch -D <branch> &&
   git push -q origin --delete <branch>
   ```
   If the owner says "merged" and `state` is `OPEN`, it did not merge (usually a conflict). Say so
   and rebase it.
2. **Stacked or conflicting PRs:** `git rebase origin/<default branch>`, or
   `git rebase --onto origin/<default branch> <old base>` after the base was squash-merged. Resolve
   source conflicts by reading both sides; a generated file is never hand-merged: regenerate it with
   the *generated files* setting's command and commit that. Then the gate's step 2 again, push with
   `--force-with-lease`, and note the rebase in the PR body.
3. Stop. No pull and no deploy unless the owner asks.

## 6. "Deploy and check"

Only when the owner says so, and only where the project has a *deploy* setting; without one, tell
the owner there is nothing to run. From the tree the setting names, run its deploy command, then show
each of its *post-deploy checks*, with the evidence for each.

A change to live DATA (a row to correct) is the owner's call each time: take a named backup first,
kept for good; change exactly the rows named; and show them after.
