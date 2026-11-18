---
name: file-issue
description: "Turn what the owner describes into a GitHub issue written for both the owner and the builder, then ask the owner to approve building it. Use when the owner asks for an issue to be filed: \"file an issue for…\", \"open an issue about…\", \"write this up as an issue\". A problem merely described in conversation is discussed, not filed."
---

# File an issue

The owner describes something: a bug they saw, a change they want. It becomes a GitHub issue that
the owner can read in plain words and a builder can build from without asking anything, and then
the owner decides whether it is built. Nothing is built here; approval hands over to the
`build-issue` skill, installed beside this one.

The *issue template*, *approval label* and *sign-off* settings come from the `## Building issues`
section of `CLAUDE.md` (or `AGENTS.md`), described in `../build-issue/settings.md`; each has a
default, so a missing section does not stop an issue being filed.

`gh` means the GitHub CLI: `gh`, or the same CLI installed as `gh-cli`. If neither runs, or it is
not signed in, tell the owner and stop.

## 1. Understand it

Read what bears on it before asking anything: the `## Building issues` section of `CLAUDE.md` (or
`AGENTS.md`), `GLOSSARY.md`, the decision records (ADRs), the code it touches, and open issues that
may already cover it (`gh issue list --search "<words>"`). Finding the facts is your job; the owner
is asked only for decisions. A long investigation can go to a subagent.

Then put the open questions to the owner a round at a time, each with your recommended answer (the
`grilling` skill, where installed, is the discipline). Done when every behaviour the change
introduces is decided, and what is left is a fork the owner chose to leave open.

An issue too big for one PR (more than one session's work, or several independent changes) is not
filed as one: propose splitting it into tickets with the `to-tickets` skill, where installed, or as
separate issues.

## 2. Write it

Use the *issue template* setting where the project has one; otherwise
[template.md](template.md). The plain part is for the owner: what they will see, in their words.
The technical part is for the builder: behaviour, the interfaces involved, where it lives, and
acceptance criteria each checkable by a test or a command. Use the glossary's terms.

File it with `gh issue create --title "<title>" --body-file -`, ending the body with the
*sign-off* setting's lines. No bare `@name` anywhere on GitHub.

## 3. Ask for approval

Give the owner the issue's title, number and link, its plain summary, and anything left to decide,
and ask whether to build it. Approval is the owner's word in the conversation ("approved", "go
ahead", "build it"); nothing else counts, and you never approve on their behalf.

On approval, record it and hand over:

```sh
fp=$(gh issue view N --json body -q .body | shasum -a 256 | cut -c1-12)
gh issue edit N --add-label <approval label>
gh issue comment N --body "build-issue: approved by the owner on <date> (\"<their words>\"); body $fp"
```

The *approval label* setting names the label (default `ready-for-agent`); create it with
`gh label create` if the repository lacks it. Then follow the `build-issue` skill for issue N,
starting at its section 0.

If the owner asks for changes instead, edit the body (`gh issue edit N --body-file -`) and ask
again. After approval the body is not edited: later decisions go in comments, and an edited body
needs approving again.
