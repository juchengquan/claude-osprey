#!/bin/bash
# Builds the scratch "shop" repository in the current (empty) workspace: a
# small JS project with a local bare origin and the GitHub CLI stub's data.
# usage: repo.sh <settings: none|full> [open-pr]
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

Builds, merges and deploys follow the `build-issue` skill (from juchengquan/claude-osprey).

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

# An open PR, #21, for issue #7, built in a worktree beside the repository.
if [ "$2" = open-pr ]; then
  git worktree add -q -b feat/cart-total "../$(basename "$PWD")-total" origin/main
  ( cd "../$(basename "$PWD")-total" &&
    printf "\nexport const total = (items) => Math.round(subtotal(items) * 108) / 100\n" >> web/src/cart.js &&
    cp web/src/*.js web/dist/ && git commit -qam "Show the cart total with tax" && git push -q -u origin feat/cart-total )
  echo "OPEN " > $S/pr/21.state
  echo '{"number":21,"state":"OPEN","headRefName":"feat/cart-total","baseRefName":"main","mergeable":"MERGEABLE"}' > $S/pr/21.json
fi
