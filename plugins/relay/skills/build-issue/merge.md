# "Merge #N"

The owner's "merge" covers the PR as it was reported ready: the commit in the latest
`build-issue: ready in <PR> at <commit>` comment on its issue. Nothing else is merged on it.

## 1. Before merging

All of these hold, or nothing is merged and the owner hears which one failed:
- the owner said "merge" for this PR in this conversation;
- the report's **Decisions to confirm** are answered, or it had none;
- `gh pr view P --json headRefOid,isDraft,mergeable,mergeStateStatus` shows the head is the ready
  commit, not a draft, `MERGEABLE` and `CLEAN`;
- where the PR has CI, `gh pr checks P` passes.

A head that moved since the ready report means the PR changed after it was checked: it goes back
through the gate and is reported ready again, and the owner says "merge" again.

## 2. Merge

```sh
gh pr merge P --squash --match-head-commit <ready commit>
```

`--match-head-commit` makes GitHub refuse the merge if the branch moved in the meantime. Branches
are deleted by the clean-up, not here: the worktree still has the branch checked out.

## 3. After

Follow [after-merge.md](after-merge.md): confirm the merge commit is on the default branch, record
the merge on the issue, clean up, and rebase the PRs stacked on it.

A stacked PR merges on the same word only when the owner said so for it too ("merge the stack"),
and only when its rebase had no conflicts and its gate passed again with nothing found; its new head
becomes its ready commit. Otherwise report it ready again and wait.

No deploy follows a merge unless the owner asks.
