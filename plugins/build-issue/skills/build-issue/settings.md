# The `## Building issues` section

Every project-specific value the `build-issue` skill uses comes from a `## Building issues` section
in the project's `CLAUDE.md` (or `AGENTS.md`). The owner writes it; the skill only reads it.

## When the section or a setting is missing

Draft the section from what the repository shows: the Makefile, `package.json` scripts,
`pyproject.toml`, CI workflows, lockfiles, generated-file headers, and the project's own docs. Show
the draft to the owner to paste in, mark every value you assumed rather than found, and wait for
their answer before building. An optional setting that is absent means "none": build without it and
say nothing.

## The settings

Each is one bullet under the heading, its label in bold. Commands are written as they are run from
the repository root.

| Setting | Required | What it holds | How the skill uses it |
| :- | :- | :- | :- |
| **Check** | yes | The one command that must pass: lint, types, tests | Run on exactly the committed tree by the builder, and again on the pushed head before "ready" |
| **Extra tests** | no | Commands outside the check, each with how many runs in a row must pass (for a suite known to flake) | Run with the check, the stated number of times |
| **Worktree setup** | no | Commands that make a fresh worktree buildable, such as installing dependencies from the lockfile | Run once in each new worktree |
| **Protected paths** | no | Trees something live runs from, and what alone may move them (usually the deploy) | Never built in, pulled or fast-forwarded |
| **Generated files** | no | Each generated file or directory, and the command that regenerates it | The only way they change; on a conflict they are regenerated, never hand-merged |
| **Must change together** | no | Areas that change in lockstep, such as two backends or a schema and its fixtures | A change to one carries the other in the same PR; reaching one makes the build heavy |
| **Heavy areas** | no | Code whose change needs a background agent however small it looks, such as a scheduler or stored samples | A build that reaches one goes to an agent; a light build that reaches one stops and is handed over |
| **Hard rules** | no | Rules quoted verbatim in every brief, such as services and databases a builder may not write to | Pasted word for word into the brief, ahead of the skill's own rules |
| **Branch prefixes** | no | The allowed `<type>` prefixes of branch names | Defaults to `feat`, `fix`, `refactor`, `docs` |
| **Review extras** | no | Checks the reviewer runs when a change includes something, such as a migration tried on a copy of real data | Run by the second agent at the gate when the condition holds |
| **CI wait** | no | How long to wait for the PR's CI checks | Waited on before "ready" when the PR has checks; defaults to 30 minutes |
| **Deploy** | no | The tree to deploy from, the deploy command, and the post-deploy checks to show | Used only on "deploy and check"; without it there is nothing to deploy |
| **Sign-off** | no | Lines that end every commit message and PR body | Appended as given |

## Template

```markdown
## Building issues

Builds, merges and deploys follow the `build-issue` skill (from juchengquan/claude-osprey).

- **Check:** `<command>`
- **Extra tests:** `<command>`, <N> runs in a row
- **Worktree setup:** `<command>`; `<command>`
- **Protected paths:** `<path>`: <what runs from it>; only `<deploy command>` moves it
- **Generated files:** `<path>` via `<command>`
- **Must change together:** `<area>` and `<area>`
- **Heavy areas:** `<path>`
- **Hard rules:**
  > <rule, quoted exactly as builders must read it>
- **Branch prefixes:** `feat`, `fix`, `refactor`, `docs`
- **Review extras:** when <condition>, <check>
- **CI wait:** <minutes> minutes
- **Deploy:** from `<tree>`, `<command>`; then show:
  - <check>
- **Sign-off:** <lines>
```

## Example

```markdown
## Building issues

Builds, merges and deploys follow the `build-issue` skill (from juchengquan/claude-osprey).

- **Check:** `make check`
- **Extra tests:** `npm --prefix web test`, 3 runs in a row (the jsdom suite flakes under load)
- **Worktree setup:** `npm ci`; `uv sync --locked`
- **Protected paths:** `~/srv/shop`: the live site runs from it; only `make deploy` moves it
- **Generated files:** `web/dist` via `make build-ui`; `api/openapi.json` via `make openapi`
- **Must change together:** the API's routes and `web/src/api.ts`
- **Heavy areas:** `api/billing/`
- **Hard rules:**
  > No requests to the live API at localhost:8080 other than GET. Open the live database only
  > read-only (`sqlite3 -readonly`).
- **Review extras:** when the PR adds a migration, run it on a fresh backup of the live database
  and compare every row before and after
- **Deploy:** from `~/srv/shop`, `make deploy`; then show:
  - `/health` answering ok, and the service's start time later than the deploy
  - the page on the real URL with no console errors
- **Sign-off:** `Co-Authored-By: <the agent's attribution line>`
```
