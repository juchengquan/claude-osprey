#!/bin/bash
# Dry runs of the build-issue skill: each scenario builds a scratch repository
# with a local origin and a stand-in GitHub CLI, runs `claude -p` with this
# plugin loaded, and checks the transcript. Nothing reaches GitHub. Each run
# is a real model call; the default set costs about $1.50.
#
# usage: plugins/build-issue/tests/dry-run.sh [scenario...]
#   default: fires-and-drafts no-fire open-forks false-merged heavy-area
#   opt-in:  light-build (a whole build, about $0.50)
set -u
here="$(cd "$(dirname "$0")" && pwd)"
plugin="$(cd "$here/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/build-issue-dry-run.XXXXXX")"
mkdir -p "$work/bin" && cp "$here/fixture/gh" "$work/bin/gh" && chmod +x "$work/bin/gh"
READ_ONLY="Read Glob Grep Skill Bash(gh *) Bash(git status*) Bash(git log*) Bash(git remote*) Bash(git worktree list*) Bash(git fetch*) Bash(git branch*) Bash(git merge-base*) Bash(ls *) Bash(cat *) Bash(command -v *)"
BUILD="Read Glob Grep Skill Write Edit Bash Agent"
failed=0

# run <scenario> <settings> <fixture extra> <tools> <prompt>
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
  if GITSTATE="$gitstate" python3 - "$work/$name.jsonl" "$expr" <<'PY'
import json, os, re, sys
tools, final = [], ""
for line in open(sys.argv[1]):
    try: m = json.loads(line)
    except ValueError: continue
    if m.get("type") == "assistant" and not m.get("parent_tool_use_id"):
        for c in m["message"]["content"]:
            if c["type"] == "tool_use": tools.append((c["name"], json.dumps(c["input"])))
    if m.get("type") == "result": final = m.get("result") or ""
used = lambda name, pat=".*": any(n == name and re.search(pat, i, re.S) for n, i in tools)
git = os.environ["GITSTATE"]
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
      check $1 "it creates no worktree and edits no settings file" 'not used("Bash", "worktree add") and not used("Write") and not used("Edit")' ;;
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
      check $1 "the brief carries the hard rule verbatim" 'any(n in ("Agent", "Task") and "Never call the payment provider" in i for n, i in tools)' ;;
    light-build)
      run $1 full "" "$BUILD" "run #7"
      check $1 "it builds in a worktree beside the repository" 'used("Bash", r"worktree add\S* .*\.\./shop-")'
      check $1 "it runs the check and opens a draft PR" 'used("Bash", "make check") and used("Bash", r"pr create.*--draft")'
      check $1 "it looks for CI before ready, and marks it ready" 'used("Bash", r"pr checks") and used("Bash", r"pr ready")'
      check $1 "the report uses the gate's headings" 'all(h in final for h in ("What it does", "Checked", "You.ll notice live")) or all(re.search(h, final) for h in ("What it does", "Checked", "notice live"))' ;;
    *) echo "unknown scenario: $1"; failed=1 ;;
  esac
}

for s in "${@:-fires-and-drafts no-fire open-forks false-merged heavy-area}"; do
  for one in $s; do echo "$one"; scenario "$one"; done
done
echo "transcripts: $work"
exit $failed
