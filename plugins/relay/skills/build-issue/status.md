# "Where is #N?" / "What's in flight?"

Read only; change nothing. The issues, PRs and worktrees are the whole record.

1. **Gather:**
   ```sh
   gh issue view N --comments                    # for one issue; its build-issue: comments are its history
   gh issue list --assignee @me --state open --search "build-issue in:comments" --json number,title
   gh issue list --label <approval label> --state open --json number,title,assignees   # approved
   gh pr list --author @me --state open --json number,title,headRefName,isDraft,mergeable
   git worktree list
   ```
2. **Match** each issue to its PR (`Closes #N` in the body, or the branch its latest `build-issue:`
   comment names) and each PR to its worktree (by branch).
3. **Report** one line per build: the issue by title and number, its stage (the latest
   `build-issue:` comment, and when), its PR by title and number with draft/ready and mergeable,
   and its worktree. Then the approved issues no build has claimed yet. Then list what does not match up: a worktree with no open PR, a claimed issue
   with no worktree, a PR whose issue was never claimed. Say what each probably needs; do nothing
   about it until the owner asks.
