#!/bin/bash
# Dry runs of the build-issue skill: each scenario builds a scratch repository
# with a local origin and a stand-in GitHub CLI, runs `claude -p` with this
# plugin loaded, and checks the transcript. Nothing reaches GitHub. Each run
# is a real model call; the default set costs about $1.50.
#
# usage: plugins/build-issue/tests/dry-run.sh [scenario...]
#   default: fires-and-drafts no-fire open-forks false-merged heavy-area
#            already-claimed status
#   opt-in, a whole build each (about $0.50-1):  light-build behind-main ci-fails
set -u
here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(cd "$here/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-issue-dry-run.XXXXXX")"
mkdir -p "$work/bin" && cp "$here/fixture/gh" "$work/bin/gh" && chmod +x "$work/bin/gh"
READ_ONLY="Read Glob Grep Skill Bash(gh *) Bash(git status*) Bash(git log*) Bash(git remote*) Bash(git worktree list*) Bash(git fetch*) Bash(git branch*) Bash(git merge-base*) Bash(ls *) Bash(cat *) Bash(command -v *)"
BUILD="Read Glob Grep Skill Write Edit Bash Agent"
failed=0

# run <scenario> <settings> <fixture extras> <tools> <prompt>
run() {
  local name=$1 dir="$work/$1/shop"
  mkdir -p "$dir" && (cd "$dir" && bash "$here/fixture/repo.sh" "$2" "$3" >/dev/null) || { echo "✗ $name: fixture failed"; failed=1; return; }
  (cd "$dir" && PATH="$work/bin:$PATH" claude -p "$5" --plugin-dir "$plugin" --allowedTools "$4" \
      --output-format stream-json --verbose --max-turns 30 > "$work/$name.jsonl" 2>&1)
}

# check <scenario> <python expression over: tools (list of (name, input json)), final (str), git (str)>
check() {
  local name=$1 desc=$2 expr=$3
  local gitstate; gitstate="$(git -C "$work/$name/shop" worktree list 2>/dev/null; git -C "$work/$name/shop" branch -a 2>/dev/null)"
  local stub="$work/$name/shop/.git/stub"
  if GITSTATE="$gitstate" STUB="$stub" python3 - "$work/$name.jsonl" "$expr" <<'PY'
import json, os, re, sys
tools, results = [], []
for line in open(sys.argv[1]):
    try: m = json.loads(line)
    except ValueError: continue
    if m.get("type") == "assistant" and not m.get("parent_tool_use_id"):
        for c in m["message"]["content"]:
            if c["type"] == "tool_use": tools.append((c["name"], json.dumps(c["input"])))
    if m.get("type") == "result": results.append(m.get("result") or "")
final = "\n".join(results)  # a background agent finishing late adds a second result
used = lambda name, pat=".*": any(n == name and re.search(pat, i, re.S) for n, i in tools)
git = os.environ["GITSTATE"]
stub = os.environ["STUB"]
def stubfile(path):
    try: return open(os.path.join(stub, path)).read()
    except OSError: return ""
comments = lambda n: stubfile(f"issue/{n}.comments")
readied = os.path.exists(os.path.join(stub, "readied"))
sys.exit(0 if eval(sys.argv[2]) else 1)
PY
  then echo "  ✓ $desc"; else echo "  ✗ $desc"; failed=1; fi
}

scenario() {
  case $1 in
    fires-and-drafts)
      run $1 none "" "$READ_ONLY" "run #7"
      check $1 "the skill fires on 'run #7'" 'used("Skill", "build-issue")'
      check $1 "it drafts a Building issues section with the check command" 're.search(r"## Building issues", final) and "make check" in final'
      check $1 "it creates no worktree and edits no settings file" 'not used("Bash", "worktree add") and not used("Write") and not used("Edit")'
      check $1 "it claims nothing before the settings exist" 'not used("Bash", r"issue (edit|comment)")' ;;
    already-claimed)
      run $1 full claimed "$BUILD" "run #7"
      check $1 "the skill fires" 'used("Skill", "build-issue")'
      check $1 "it builds nothing: no worktree, no claim" 'not used("Bash", r"worktree add|issue edit|pr create")'
      check $1 "it names who holds it" 're.search(r"alex", final)' ;;
    status)
      run $1 full open-pr "$READ_ONLY" "what's in flight?"
      check $1 "the skill fires" 'used("Skill", "build-issue")'
      check $1 "it changes nothing" 'not used("Bash", r"worktree (add|remove)|issue (edit|comment)|pr (ready|edit|create)")'
      check $1 "it matches issue, PR and worktree" 're.search(r"#?21", final) and re.search(r"#?7", final) and re.search(r"shop-total|cart-total", final)'
      check $1 "it names PRs by title" 're.search(r"cart total", final, re.I)' ;;
    no-fire)
      run $1 full "" "$READ_ONLY" "triage #7: is it clear enough to build? Just tell me, don't build it."
      check $1 "the skill does not fire on triage" 'not used("Skill", "build-issue")'
      check $1 "no worktree is created" 'not used("Bash", "worktree add")' ;;
    open-forks)
      run $1 full "" "$BUILD" "run #8"
      check $1 "the skill fires" 'used("Skill", "build-issue")'
      check $1 "it builds nothing: no commit, no PR" 'not used("Bash", r"git commit|pr create")'
      check $1 "it stops with the two forks named" 're.search(r"tax", final, re.I) and re.search(r"stack", final, re.I) and re.search(r"recommend", final, re.I)' ;;
    false-merged)
      run $1 full open-pr "$BUILD" "#21 merged"
      check $1 "it checks the PR's state on GitHub" 'used("Bash", r"pr view 21")'
      check $1 "it deletes nothing" 'not used("Bash", r"worktree remove|branch -D|--delete") and "feat/cart-total" in git and "shop-total" in git'
      check $1 "it says the PR did not merge" 're.search(r"(not|n.t) (been )?merged|still open|OPEN", final)' ;;
    heavy-area)
      run $1 full "" "$BUILD" "run #9"
      check $1 "the build goes to an agent" 'used("Agent") or used("Task")'
      check $1 "the agent is pointed at brief.md" 'any(n in ("Agent", "Task") and "brief.md" in i for n, i in tools)'
      check $1 "the brief carries the hard rule verbatim" 'any(n in ("Agent", "Task") and "Never call the payment provider" in i for n, i in tools)'
      check $1 "it claims the issue first" 'used("Bash", r"issue edit 9.*--add-assignee") and "build-issue:" in comments(9)' ;;
    light-build)
      run $1 full "" "$BUILD" "run #7"
      check $1 "it builds in a worktree beside the repository" 'used("Bash", r"worktree add\S* .*\.\./shop-")'
      check $1 "it runs the check and opens a draft PR" 'used("Bash", "make check") and used("Bash", r"pr create.*--draft")'
      check $1 "it looks for CI before ready, and marks it ready" 'used("Bash", r"pr checks") and used("Bash", r"pr ready")'
      check $1 "the report uses the gate's headings" 'all(re.search(h, final) for h in ("What it does", "Checked", "notice live"))'
      check $1 "the issue records the claim and the ready" 'used("Bash", r"issue edit 7.*--add-assignee") and re.search(r"build-issue:.*ready", comments(7))' ;;
    behind-main)
      run $1 full open-pr,behind "$BUILD" "run #7. PR #21 is mine from a session that died; take it over and get it ready."
      check $1 "it brings the branch up to date before readying" 'used("Bash", r"rebase") and readied'
      check $1 "it re-runs the check after the rebase" 'any(n == "Bash" and "make check" in i for n, i in tools[[k for k, (n, i) in enumerate(tools) if n == "Bash" and "rebase" in i][0]:]) if used("Bash", "rebase") else False'
      check $1 "it records the takeover on the issue" 're.search(r"build-issue:.*(took|taking|take) (it )?over", comments(7), re.I)' ;;
    ci-fails)
      run $1 full ci-fail "$BUILD" "run #7"
      check $1 "it never marks the PR ready" 'not readied'
      check $1 "it looked at CI" 'used("Bash", r"pr checks")'
      check $1 "it reports the stop with its headings" 're.search(r"What happened", final) and re.search(r"What it needs from you", final)'
      check $1 "the issue records the stop" 're.search(r"build-issue:.*(stop|fail)", comments(7), re.I)' ;;
    *) echo "unknown scenario: $1"; failed=1 ;;
  esac
}

for s in "${@:-fires-and-drafts no-fire open-forks false-merged heavy-area already-claimed status}"; do
  for one in $s; do echo "$one"; scenario "$one"; done
done
echo "transcripts: $work"
exit $failed
