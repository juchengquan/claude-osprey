# After "merged"

## 1. Find the work

The session that built the PR may be gone; GitHub and git hold everything needed. From the PR number:

```sh
gh pr view N --json number,state,mergeCommit,headRefName,baseRefName
git worktree list                                         # the worktree whose branch is headRefName
gh pr list --state open --base <headRefName> --json number,headRefName   # PRs stacked on it
```

If the owner gave an issue number instead, find its PR with
`gh pr list --state all --search "<issue number> in:body" --json number,state,headRefName`.

## 2. Confirm it, then clean up

Confirm it, chained, before deleting anything; after a squash merge the branch tip is no evidence:

```sh
m=$(gh pr view N --json state,mergeCommit -q '.state+" "+.mergeCommit.oid') && echo $m &&
[ "${m%% *}" = MERGED ] && git fetch -q origin &&
git merge-base --is-ancestor ${m#* } origin/<default branch>
```

Then remove what still exists: the worktree (`git worktree remove <path>`), the local branch
(`git branch -D <branch>`), and the remote branch (`git push -q origin --delete <branch>`). Say which
of them were already gone.

If `state` is `OPEN`, it did not merge. Say so, delete nothing, and look for why: a conflict
(`gh pr view N --json mergeable,mergeStateStatus`), a failing check, or a merge never completed.
Rebase it if a conflict is the cause.

Before deleting a merged branch that other open PRs are stacked on, note its old tip
(`git rev-parse <branch>`): their rebase needs it.

## 3. Stacked or conflicting PRs

Rebase each in its own worktree: `git rebase origin/<default branch>`, or
`git rebase --onto origin/<default branch> <old base tip>` when its base was squash-merged. Resolve
source conflicts by reading both sides; a generated file is never hand-merged: regenerate it with the
*generated files* setting's command and commit that. Then:

1. the gate's re-run (SKILL.md section 4, step 2) on the rebased head;
2. `git push --force-with-lease`;
3. `gh pr edit P --base <default branch>` when its base branch is gone;
4. a note of the rebase in the PR body.

## 4. Stop

No pull and no deploy unless the owner asks. Report what was confirmed, what was removed, and what
each stacked PR's state is now.
