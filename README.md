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

## relay

Two skills that take a request from you to a merged PR, with you deciding at three points: what
gets built, when it merges, and when it deploys. Everything between runs on its own.

```
you                         the agent (orchestrator)                subagents
───                         ────────────────────────                ─────────
"file an issue for …"  ──►  questions you, writes the issue
"approved"             ──►  claims it, worktree, brief  ──────────► builder: test first, checks, draft PR
                            review until clean  ◄──────────────────► reviewer: findings on the PR
                            re-runs the checks, waits on CI, ready
reads the report       ◄──  what it does, what was checked, decisions to confirm
"merge"                ──►  merges exactly the commit it reported, cleans up
"deploy and check"     ──►  deploys, shows the checks
```

- **`file-issue`**: say "file an issue for …" and the agent reads the code, asks you what only you
  can decide, and files an issue in two layers: a plain summary for you, and the technical part a
  builder works from, with acceptance criteria. It then asks whether to build it. Your "approved" is
  recorded on the issue (a label, and a comment quoting you with a fingerprint of the issue's text),
  so a later edit to the issue needs approving again.
- **`build-issue`**: on approval, or "run #N" for an issue that already exists, the agent claims
  the issue and builds it in a git worktree beside the repository, itself or through a background
  builder. A separate reviewer reviews the PR until it finds nothing, for up to three rounds before
  it asks you. The agent re-runs the checks on the pushed commit, waits on CI, and reports the PR
  ready: merge-ready as it stands. On **"merge"** it merges exactly that commit (GitHub refuses if
  the branch moved), cleans up, and rebases PRs stacked on it. **"What's in flight?"** lists each
  build; **"deploy and check"** deploys and shows the checks.

The issue's `build-issue:` comments are the record of each build, so a fresh session can pick up
where another stopped. Builders and reviewers never merge or deploy.

They work in any coding agent that loads skills, and use the GitHub CLI (`gh`, or the same CLI
installed as `gh-cli`). They work beside the skills in
[mattpocock/skills](https://github.com/mattpocock/skills) where those are installed: `grilling`
while filing, `triage`'s labels and briefs, `tdd` for testing, `code-review` and `pr` at the gate,
`to-tickets` and `implement-spec` for work too big for one PR, and `retro` after a build that went
wrong. None of them is required.

### Project settings

Each project describes itself in a `## Building issues` section of its `CLAUDE.md` (or
`AGENTS.md`): its check command, flaky suites, worktree setup, protected paths, generated files,
hard rules, deploy and so on. For example:

```markdown
## Building issues

Issues are filed, built, merged and deployed through the `relay` skills (`file-issue`,
`build-issue`; from juchengquan/claude-osprey).

- **Check:** `make check`
- **Extra tests:** `npm --prefix web test`, 3 runs in a row
- **Worktree setup:** `npm ci`
- **Protected paths:** `~/srv/shop`: the live site runs from it; only `make deploy` moves it
- **Generated files:** `web/dist` via `make build-ui`
- **Deploy:** from `~/srv/shop`, `make deploy`; then show `/health` answering ok
```

Only **Check** is required. Every setting, with a template, is in
[`settings.md`](plugins/relay/skills/build-issue/settings.md). Where a project has no section,
`build-issue` drafts one for you to paste in and asks before building; it never edits the file
itself.

### Install

In Claude Code:

```
/plugin install relay --marketplace juchengquan/claude-osprey
```

or `claude plugin install relay --marketplace juchengquan/claude-osprey` from a shell. The skills
then run as `/relay:file-issue` and `/relay:build-issue`, or on their own when you say "file an
issue for …" or "run #N".

In OpenCode, Codex, Cursor and the other agents the [`skills`](https://github.com/vercel-labs/skills)
CLI supports:

```
npx skills add juchengquan/claude-osprey --skill file-issue --skill build-issue -g
```

Install them one way per agent: in Claude Code, the plugin alone, or each skill appears twice.

### Testing a change to it

`plugins/relay/tests/dry-run.sh` runs the skills from this checkout against a scratch repository
with a local origin and a stand-in GitHub CLI, and checks what they did. Nothing reaches GitHub,
but each scenario is a real model call; `dry-run.sh --list` names them, with which run by default.

## Changing a plugin

An installed plugin stays on its `version` until that changes, so every change to a plugin bumps
the `version` in its `.claude-plugin/plugin.json`. Before pushing, run `tools/validate.sh`: it checks
that Claude Code accepts the marketplace and every plugin, that the `skills` CLI finds every skill,
and that every plugin the branch changes has a new version.
A change to `relay`'s behaviour comes with a dry-run scenario that shows it.
