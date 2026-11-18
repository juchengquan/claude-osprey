#!/bin/bash
# Builds the scratch "shop" repository in the current (empty) workspace: a
# small JS project with a local bare origin and the GitHub CLI stub's data.
# usage: repo.sh <settings: none|full> [extras, comma-separated]
#   claimed  issue #7 is assigned to someone else, with a build under way
#   open-pr  PR #21 for issue #7, open, in a worktree beside the repository
#   behind   (with open-pr) main has moved on since PR #21 was cut
#   ready    (with open-pr) PR #21 was approved, gated and reported ready
#   moved    (with ready) a commit was pushed to PR #21 after it was reported ready
#   stale    issue #7 was approved, but its body has been edited since
#   ci-fail  every PR's CI check fails
set -e
git init -q -b main . && git config user.email t@example.com && git config user.name tester
mkdir -p web/src/payments web/dist tests
echo 'export const TAX_RATE = 0.08' > web/src/tax.js
printf 'export function subtotal(items) {\n  return items.reduce((s, i) => s + i.price * i.qty, 0)\n}\n' > web/src/cart.js
printf 'export async function charge(card, amount, provider) {\n  return provider.charge(card, amount)\n}\n' > web/src/payments/charge.js
cp web/src/*.js web/dist/
printf "import assert from 'node:assert/strict'\nimport { subtotal } from '../web/src/cart.js'\nassert.equal(subtotal([{ price: 10, qty: 2 }]), 20)\n" > tests/cart.test.mjs
printf 'check:\n\tfor f in tests/*.test.mjs; do node $$f || exit 1; done\nbuild-ui:\n\tcp web/src/*.js web/dist/\ndeploy:\n\tgit pull --ff-only\n' > Makefile
echo '{ "name": "shop", "type": "module" }' > package.json
printf '# shop\n\nA small shop. The live site runs from ~/srv/shop.\n' > CLAUDE.md
if [ "$1" = full ]; then cat >> CLAUDE.md <<'MD'

## Building issues

Issues are filed, built, merged and deployed through the `relay` skills (`file-issue`,
`build-issue`; from juchengquan/claude-osprey).

- **Check:** `make check`
- **Protected paths:** `~/srv/shop`: the live site runs from it; only `make deploy` moves it
- **Generated files:** `web/dist` via `make build-ui`
- **Heavy areas:** `web/src/payments/`
- **Hard rules:**
  > Never call the payment provider's API, sandbox or live.
- **Sign-off:** `Co-Authored-By: Claude <noreply@anthropic.com>`
MD
fi
git add -A && git commit -qm init
S=.git/stub && mkdir -p $S/issue $S/pr
git init -q --bare $S/origin.git && git remote add origin "$PWD/$S/origin.git" && git push -q -u origin main
printf 'title:\tShow the cart total with tax\nstate:\tOPEN\nnumber:\t7\n--\nAdd total(items) to web/src/cart.js: the subtotal plus tax at TAX_RATE from web/src/tax.js, rounded to cents.\n' > $S/issue/7
printf 'title:\tDiscount codes\nstate:\tOPEN\nnumber:\t8\n--\nSupport discount codes at checkout. To decide: whether a code applies before or after tax, and whether codes can stack.\n' > $S/issue/8
printf 'title:\tRetry a declined card once\nstate:\tOPEN\nnumber:\t9\n--\nIn web/src/payments/charge.js, when provider.charge throws an error whose code is "card_declined", retry once after 2 seconds. Any other error is final.\n' > $S/issue/9

has() { case ",$2," in *",$1,"*) return 0;; esac; return 1; }
extras=$2
set -- "$1" "$extras"

if has claimed "$extras"; then
  echo alex > $S/issue/7.assignees
  echo 'alex (2 hours ago): build-issue: building on feat/cart-total in ../shop-total' > $S/issue/7.comments
fi
has ci-fail "$extras" && touch $S/ci-fail
fp() { printf '%s\n' "$1" | shasum -a 256 | cut -c1-12; }

if has stale "$extras"; then
  echo ready-for-agent > $S/issue/7.labels
  echo "owner (yesterday): build-issue: approved by the owner on 2026-11-17 (\"go ahead\"); body $(fp 'Add total(items) to web/src/cart.js.')" > $S/issue/7.comments
  echo '[{"number":7,"title":"Show the cart total with tax","labels":[{"name":"ready-for-agent"}],"assignees":[]}]' > $S/issue/list.json
fi

if has open-pr "$extras"; then
  git worktree add -q -b feat/cart-total "../$(basename "$PWD")-total" origin/main
  ( cd "../$(basename "$PWD")-total" &&
    printf "\nexport const total = (items) => Math.round(subtotal(items) * 108) / 100\n" >> web/src/cart.js &&
    cp web/src/*.js web/dist/ && git commit -qam "Show the cart total with tax" && git push -q -u origin feat/cart-total )
  echo "OPEN " > $S/pr/21.state
  echo '{"number":21,"title":"Show the cart total with tax","state":"OPEN","isDraft":true,"headRefName":"feat/cart-total","baseRefName":"main","body":"Closes #7"}' > $S/pr/21.json
  echo '[{"number":21,"title":"Show the cart total with tax","headRefName":"feat/cart-total","isDraft":true,"mergeable":"MERGEABLE"}]' > $S/pr/list.json
  printf 'web/src/cart.js\nweb/dist/cart.js\n' > $S/pr/21.files
  echo owner > $S/issue/7.assignees
  echo 'owner (1 hour ago): build-issue: building on feat/cart-total in ../shop-total' > $S/issue/7.comments
  echo '[{"number":7,"title":"Show the cart total with tax"}]' > $S/issue/list.json
  touch $S/pr/21.draft
fi

if has ready "$extras"; then
  rm -f $S/pr/21.draft
  sed -i.bak 's/"isDraft":true/"isDraft":false/' $S/pr/21.json $S/pr/list.json
  head=$(git --git-dir=$S/origin.git rev-parse refs/heads/feat/cart-total)
  echo ready-for-agent > $S/issue/7.labels
  { echo "owner (2 hours ago): build-issue: approved by the owner on 2026-11-18 (\"approved\"); body $(fp "$(sed -n '/^--$/,$p' $S/issue/7 | sed 1d)")"
    cat $S/issue/7.comments
    echo "owner (10 minutes ago): build-issue: ready in #21 Show the cart total with tax at $head"; } > $S/issue/7.c && mv $S/issue/7.c $S/issue/7.comments
fi

if has moved "$extras"; then
  ( cd "../$(basename "$PWD")-total" && printf '// tidy\n' >> web/src/tax.js && cp web/src/*.js web/dist/ &&
    git commit -qam "Tidy" && git push -q origin feat/cart-total )
fi

if has behind "$extras"; then
  printf 'export const money = (n) => `$${n.toFixed(2)}`\n' > web/src/format.js && cp web/src/format.js web/dist/
  git add -A && git commit -qm "Add money()" && git push -q origin main
fi
