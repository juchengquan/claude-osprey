# Issue template

The title says the change in the owner's words, not the code's: "Show the cart total with tax",
not "Add total() to cart.js".

```markdown
## Summary

<Plain words, for the owner: what happens now, what should happen, and why it matters. No code
names unless the owner uses them.>

## Technical

**Now:** <the current behaviour, precisely; for a bug, how to see it>

**Wanted:** <the behaviour after the change, with its edge cases and errors>

**Where it lives:** <the interfaces, types, routes or modules involved, and the files as of today.
Paths may move; the interfaces are the contract.>

## Decisions

- <each decision taken while writing this, with the owner's answer>

## To decide

- <only forks the owner chose to leave open; empty in the usual case>

## Acceptance

- [ ] <one behaviour, checkable by a test or a command>
- [ ] <the project's check passes, and any generated files or must-change-together areas the
      change reaches are updated>

## Out of scope

- <what this change leaves alone, so the builder does not wander into it>
```
