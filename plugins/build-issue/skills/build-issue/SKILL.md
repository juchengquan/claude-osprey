---
name: build-issue
description: "Build a GitHub issue from branch to merged PR — who builds it (main session or background agent), its worktree, the builder's brief, the gate before ready, clean-up after merge, deploy on request. Use when the owner tells you to build an issue or to act on a PR built this way: \"run #N\" / \"build #N\", \"run #A and #B in parallel\", \"#N merged\", \"rebase the stack\", \"deploy and check\", or asks where builds stand (\"where is #N?\", \"what's in flight?\"). Questions about an issue itself (triage, \"is it clear?\", \"look at #N\") are answered without it."
---

# Build an issue

The owner names an issue; it comes back as a PR the owner can merge without re-checking it. The owner
merges every PR and decides every deploy. Everything here serves that: what reaches the owner as
"ready" has passed the whole gate on exactly the commit they will merge.

The files beside this one are part of the skill; `<skill dir>` below is the directory this file was
loaded from.

| The owner says | Do |
| :- | :- |
| "run #N", "build #N", "run #A and #B in parallel" | Sections 0–6 below |
| "#N merged", "rebase the stack", "check the merge conflicts" | Section 0, then [after-merge.md](after-merge.md) |
| "deploy and check" | Section 0, then [deploy.md](deploy.md) |
| "where is #N?", "what's in flight?" | [status.md](status.md) |

In everything the owner reads, name an issue or PR by its title and number ("#23 Format the cart
total"), never by a bare number.

## 0. Before anything

**The GitHub CLI.** `gh` below means the GitHub CLI: run `gh`, and where it is not installed, the
same CLI installed as `gh-cli`. If neither runs, or it is not signed in, tell the owner and stop.

**The project's settings.** Read the `## Building issues` section of the project's `CLAUDE.md`, or
of `AGENTS.md` where `CLAUDE.md` has none. If both have one, follow `CLAUDE.md` and tell the owner
they differ. The section supplies every project-specific value this skill names as a *setting*.
Read [settings.md](settings.md) when the section is missing, or a setting this work needs is missing
or unclear: draft the section from what the repository shows, show it to the owner to paste in,
name each value you assumed, and wait for their answer before building. The settings are the
owner's to write; leave the files that hold them untouched.

## 1. Claim it

The issue is the record of the build; no other state is kept. Before any work, read
`gh issue view N --comments`. A build is under way when a comment beginning `build-issue:` says so
and no later one says it stopped, was readied or merged.
- Assigned to someone other than the owner: it is theirs. Say so, and stop.
- Under way on the owner's claim: another session may hold it, or one may have died. Tell the owner
  what the comment says and stop, unless the owner has said to take it over; then carry on in the
  worktree, branch and PR it names, and comment that this session took it over.

Otherwise claim it: `gh issue edit N --add-assignee @me`, and a comment
`build-issue: building on <branch> in <worktree>`. Comment again, one line beginning `build-issue:`,
at each change of stage: stopped (and what it needs), ready (with the PR), failed. A decision the
owner makes on open forks goes on the issue too.

## 2. Who builds it

**The main session** builds it when it is light:
- one area, a handful of files, no migration, nothing in the *must change together* or
  *heavy areas* settings;
- anything the owner is waiting on in the conversation.

**A background agent** builds it when:
- the owner asks for parallel work ("run #A and #B in parallel": one agent each);
- it spans a *must change together* setting, a *heavy area*, a migration, or a large
  generated-file change;
- it will run long and the owner wants the conversation free meanwhile.

Start it in the background and hand the conversation back to the owner, saying what it is building
and where. Where this agent cannot start background agents, the main session builds each issue in
turn and says so.

**An issue with open forks** (its text says "to decide", or investigation could change the plan) is
built in two phases: the builder investigates and STOPS with a report and the forks, each with a
recommendation; the owner decides (ask at most four questions at once); the decisions are recorded
as a comment on the issue; then the build goes on.

**When light turns out heavy** (the fix reaches a migration, the schema, a *heavy area*, or something
the *must change together* setting pairs with it), stop, tell the owner what was found, and hand it to
an agent.

Two issues can run in parallel when they touch different files: before starting a second builder,
compare the files each will touch, and the files of every open PR (`gh pr diff P --name-only`). A
sweeping rename or move runs alone, or as a pure-rename commit first so a later rebase stays
mechanical.

**An issue too big for one PR** is not split on the fly: propose breaking it into tickets (the
`to-tickets` skill, then `implement-spec` to build them, where installed), or else put the split to
the owner as a fork.

## 3. The worktree

Build outside every *protected path* setting: those are trees something live runs from, moved only
by the deploy, never pulled or fast-forwarded by hand. Each build gets a worktree BESIDE the
repository:

```sh
git fetch -q origin
git worktree add -q -b <type>/<slug> ../<repo>-<short> origin/<default branch>
cd ../<repo>-<short>
```

then run the *worktree setup* setting there. `<type>` comes from the *branch prefixes* setting
(default: `feat`, `fix`, `refactor`, `docs`).

## 4. The brief

[brief.md](brief.md) is the builder's whole practice. A background builder is told to read
`<skill dir>/brief.md` by its absolute path, and given only what is particular to this build:
- the issue number, the worktree path and the branch;
- decisions already made, with a link to the issue comment that records them;
- the *hard rules* setting, verbatim;
- what a parallel builder is touching, so it keeps clear.

Where the builder cannot read files outside its worktree, paste brief.md's text in place of the path.
When the main session builds, it follows brief.md itself.

## 5. The gate, before "ready"

1. **Review** every PR except a trivial one: a trivial PR adds no file, changes about 100 lines or
   fewer, and carries no decision the builder made that the issue had not. Every other PR goes to a
   SECOND agent, told to read `<skill dir>/review.md` and given the PR number, the issue number, the
   worktree, and the *review extras* setting; never the builder's account of the work. Where the
   `code-review` skill is installed AND the repository is set up for it (its `## Agent skills`
   block exists), it can run beside review.md; otherwise review.md alone is the review. Send the
   findings back to the builder; a finding that changes a decision goes to the owner first.
2. **Up to date.** If `origin/<default branch>` has moved past the branch's base
   (`git merge-base --is-ancestor origin/<default branch> HEAD` fails), rebase onto it under
   after-merge.md section 3's rules, and push with `--force-with-lease`. The checks must run on what
   will merge.
3. **Re-run it yourself** on the pushed head: the *check* setting and every *extra test* setting. A
   builder's "passes" is a claim until you have seen it pass.
4. **CI.** When `gh pr checks N` lists checks, wait on `gh pr checks N --watch` for at most the
   *CI wait* setting (default 30 minutes). A failing check is a failed check (section 6); "no checks
   reported" means there is no CI to wait for.
5. `gh pr ready N`, then confirm `gh pr view N --json mergeable,mergeStateStatus` reads `MERGEABLE`
   and `CLEAN` (poll while it reads `UNKNOWN`), and comment `build-issue: ready in <PR>` on the issue.
6. **Report** to the owner under these headings, in this order:
   - **What it does**
   - **Checked**: each check, who ran it, and its evidence
   - **Decisions to confirm**: what the builder chose that the issue did not say
   - **You'll notice live**
   - **Merge order**: only when two open PRs touch the same files: which first, and why
     (`git merge-tree --write-tree --name-only origin/<a> origin/<b>`)

The gate is done when every item above has its evidence, on the commit the owner will merge.

## 6. When it goes wrong

The PR stays a draft through all of these, and the worktree is kept.
- **A check fails on the pushed head** (the *check*, an *extra test*, or CI): the builder fixes it.
  After two fix rounds that still fail, stop and report.
- **A flaky suite fails one of its runs:** re-run all of its runs once. If any fails again, it is a
  failure. A flake is never explained away into "ready".
- **The builder stalls, or stops without a PR:** read its report and the worktree. If what is left is
  light, the main session finishes it; otherwise report to the owner what it learned.
- **A review finding the builder cannot resolve:** report it to the owner with the reviewer's
  evidence.

A report of a stop uses the headings **What happened**, **Evidence**, **What it needs from you**,
and **Where it is** (worktree, branch, PR), and goes on the issue as a `build-issue:` comment too.

After a stop or a failure, offer the owner a retro on the session (the `retro` skill, where
installed): each finding becomes a fix to this skill or a new dry-run scenario.
