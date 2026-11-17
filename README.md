# claude-osprey

Small mods for [Claude Code](https://claude.com/claude-code) and other coding agents, each installed
on its own from this repository.

## pr-radar

Keeps your GitHub pull requests beside the chat: your own open PRs and the open PRs waiting for your
review, across every repository, grouped by repository with CI, review and merge state.

- **`/prs`** opens the pane. Repository headings start collapsed; press one to expand it. Type any
  part of a repository name in the **repo** field to filter, or open it filtered with
  `/prs <part of a name>`, and press **↻** to refresh at once. Click a PR's number to open it in the
  browser; press **⧉** after its title to copy its URL.
- **The status line** keeps a one-line summary, such as `PRs: 3 open, 1 failing, 2 to review`.
- **A `pr_status` tool** lets Claude answer questions like "which of my PRs are failing?" from the
  same list.

It refreshes every 30 seconds through the GitHub CLI, so it needs [`gh`](https://cli.github.com)
(or the same CLI installed as `gh-cli`) signed in with `gh auth login`; without it, the pane says so. It shows the 25 most recently updated PRs of each kind.

### Install

At the prompt of a Claude Code terminal session:

```
/plugin install pr-radar --marketplace juchengquan/claude-osprey
```

Answer `y` to add the marketplace, then pick a scope (user, the first, loads it in every session).

From a shell:

```
claude plugin install pr-radar --marketplace juchengquan/claude-osprey
```

In the desktop app, where `/plugin` does not run: click + next to the prompt box, then Plugins,
Add marketplace with `juchengquan/claude-osprey`, then Add plugin.

To switch it off and on again: `claude plugin disable pr-radar@claude-osprey` and
`claude plugin enable pr-radar@claude-osprey`.

## build-issue

A skill that takes a GitHub issue from branch to a PR you can merge without re-checking it. Say
**"run #N"** (or "build #N", or "run #A and #B in parallel") and the agent:

- claims the issue (assigns it to you and comments), so no second session builds it too;
- decides whether the main session builds it or a background agent does, and for an issue with open
  questions, investigates first and stops for your decisions;
- builds in a git worktree beside the repository, never in a tree something live runs from;
- briefs the builder with the issue, your decisions and your project's hard rules, and holds it to
  test-first work, a mutation check for every rule it adds, and a draft PR;
- gates the PR: an independent review, the branch brought up to date, the checks re-run on the
  pushed commit, CI waited on, then ready; or, when something fails, a draft and a report of why.

Say **"#N merged"** and it confirms the merge on the default branch before removing the worktree and
branch; **"rebase the stack"** rebases dependent PRs; **"deploy and check"** deploys and shows the
checks; **"what's in flight?"** lists each build's issue, PR and worktree. The issue's comments are
the record of each build, so a fresh session picks up where another stopped. You merge every PR and
decide every deploy.

It works beside the skills in [mattpocock/skills](https://github.com/mattpocock/skills) where they
are installed: `tdd` for testing, `code-review` and `pr` at the gate, a `triage` brief as the
builder's starting point, `to-tickets` and `implement-spec` for an issue too big for one PR, and
`retro` after a build that went wrong. None of them is required.

It works in any coding agent that loads skills, and uses the GitHub CLI (`gh`, or the same CLI
installed as `gh-cli`).

### Project settings

Each project describes itself in a `## Building issues` section of its `CLAUDE.md` (or
`AGENTS.md`): its check command, flaky suites, worktree setup, protected paths, generated files,
hard rules, deploy and so on. For example:

```markdown
## Building issues

Builds, merges and deploys follow the `build-issue` skill (from juchengquan/claude-osprey).

- **Check:** `make check`
- **Extra tests:** `npm --prefix web test`, 3 runs in a row
- **Worktree setup:** `npm ci`
- **Protected paths:** `~/srv/shop`: the live site runs from it; only `make deploy` moves it
- **Generated files:** `web/dist` via `make build-ui`
- **Deploy:** from `~/srv/shop`, `make deploy`; then show `/health` answering ok
```

Only **Check** is required. Every setting, with a template, is in
[`settings.md`](plugins/build-issue/skills/build-issue/settings.md). Where a project has no section,
the skill drafts one for you to paste in and asks before building; it never edits the file itself.

### Install

In Claude Code:

```
/plugin install build-issue --marketplace juchengquan/claude-osprey
```

or `claude plugin install build-issue --marketplace juchengquan/claude-osprey` from a shell. It then
runs as `/build-issue:build-issue`, or on its own when you say "run #N".

In OpenCode, Codex, Cursor and the other agents the [`skills`](https://github.com/vercel-labs/skills)
CLI supports:

```
npx skills add juchengquan/claude-osprey --skill build-issue -g
```

Install it one way per agent: in Claude Code, the plugin alone, or the skill appears twice.

### Testing a change to it

`plugins/build-issue/tests/dry-run.sh` runs the skill from this checkout against a scratch
repository with a local origin and a stand-in GitHub CLI, and checks what it did: that it fires on
"run #N" and not on triage, drafts missing settings, stops on open forks and on an issue someone else
holds, deletes nothing for a PR that did not merge, briefs an agent for a heavy area, and reports
what is in flight without changing anything. `light-build`, `behind-main` and `ci-fails` each run a
whole build. Nothing reaches GitHub, but each scenario is a real model call (about $2 for the
default set, $0.50 to $1 for each whole build).

## Changing a plugin

An installed plugin stays on its `version` until that changes, so every change to a plugin bumps
the `version` in its `.claude-plugin/plugin.json`; CI fails a PR that changes a plugin without one.
A change to `build-issue`'s behaviour comes with a dry-run scenario that shows it.
