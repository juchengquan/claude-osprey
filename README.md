# claude-osprey

Small mods for [Claude Code](https://claude.com/claude-code), each installed on its own from this
repository.

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
installed and signed in (`gh auth login`). It shows the 25 most recently updated PRs of each kind.

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
