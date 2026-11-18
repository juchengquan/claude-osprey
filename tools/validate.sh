#!/bin/bash
# Checks the marketplace and its plugins before a change is pushed:
#   1. Claude Code accepts the marketplace and every plugin;
#   2. the skills CLI (the install path for OpenCode and other agents) finds
#      every skill under plugins/*/skills/;
#   3. every plugin this branch changes has a new version, since an
#      installed plugin stays on its version until that changes.
# usage: tools/validate.sh [base branch, default origin/main]
set -u
cd "$(dirname "$0")/.."
base=${1:-origin/main}
status=0
fail() { echo "✗ $*"; status=1; }

echo "1. claude plugin validate"
claude plugin validate . >/dev/null 2>&1 && echo "  ✓ marketplace" || fail "marketplace: run 'claude plugin validate .'"
for p in plugins/*/; do
  p=${p%/}
  claude plugin validate "$p" >/dev/null 2>&1 && echo "  ✓ $p" || fail "$p: run 'claude plugin validate $p'"
done

echo "2. the skills CLI finds every skill"
listed=$(npx -y skills add . --list 2>&1)
for s in plugins/*/skills/*/SKILL.md; do
  name=$(basename "$(dirname "$s")")
  grep -q "│    $name\$" <<<"$listed" && echo "  ✓ $name" || fail "$name: not listed by 'npx skills add . --list' (check its frontmatter)"
done

echo "3. every changed plugin has a new version (since this branch left $base)"
git fetch -q origin 2>/dev/null
fork=$(git merge-base "$base" HEAD)
for p in plugins/*/; do
  p=${p%/}
  git diff --quiet "$fork" -- "$p" && continue
  old=$(git show "$fork:$p/.claude-plugin/plugin.json" 2>/dev/null | jq -r .version)
  new=$(jq -r .version "$p/.claude-plugin/plugin.json")
  if [ -n "$old" ] && [ "$old" = "$new" ]; then fail "$p changed but its version is still $new"
  else echo "  ✓ $p (${old:-new} → $new)"; fi
done

exit $status
