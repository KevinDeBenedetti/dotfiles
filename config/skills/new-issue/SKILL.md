---
name: new-issue
description: File the owner's requests (free text, one or many) as GitHub issues, related ones grouped into one, duplicates skipped, each ready for /next-issue; `dry-run` drafts them without filing.
argument-hint: "[dry-run] <requests>"
disable-model-invocation: true
metadata:
  opencode/slash: "false"
  opencode/autoinvoke: "false"
---

Turn the owner's requests into GitHub issues that `/next-issue` can work: one
issue per reviewable change, written from the code it touches.

<!-- Single source shared by Claude Code, OpenCode and VS Code Copilot
     (linked by os/helpers/links.sh). Keep it tool-neutral. The issues it files
     are worked by the next-issue skill; the audit skill files its own findings. -->

Everything you write onto GitHub — titles, bodies — is in English, whatever
the conversation language, and reads as the owner's own issue:
no AI attribution, no "Generated with …" line.

## 1. Mode

The argument is `$ARGUMENTS`. If that placeholder was left as-is (the tool did
not substitute it), the argument is whatever the user typed after the
`/new-issue` command instead.

| Argument             | Mode                                                  |
| -------------------- | ----------------------------------------------------- |
| `<requests>`         | **file**: §2 to §6, then the issues are created       |
| `dry-run <requests>` | **draft**: the same, the drafts shown, nothing filed  |
| none                 | ask the owner for the requests, then **file**         |

The requests are free text: a list, a paragraph, several asks in one sentence.

## 2. Prepare

1. Check the tracker answers: `gh issue list --limit 1`. When `gh` is missing,
   not signed in or cannot reach GitHub, say which and carry on as `dry-run`.
2. Read `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` when
   the project has them: they give its conventions and its label names.
3. List the open issues once, for §5:
   `gh issue list --state open --limit 200 --json number,title,labels`.

## 3. Split and group

Restate the requests as **changes**: one change is what a single reviewable
commit would do.

- **Group** the requests one change resolves into one issue (two asks about
  the same hook, a feature and the docs it needs).
- **Split** a request that holds several independent changes into one issue
  each; when one must land first, say so in the later one (`After #<number>`).

Done when every request maps to exactly one change, or to an existing issue
(§5). Show the mapping (request → change) in your reply, then carry on: the
owner already asked for these issues, and §4's questions are the one stop.

## 4. Understand

For each change, read the code it touches before writing a word of the issue:
the files, the function, the line where the behavior lives, the test file that
covers it. An issue that names `file:line` and a checkable result is one
`/next-issue` can work without asking again.

When a change needs a decision only the owner can make (which of two designs,
a name, a scope), ask, in **one** round covering every open change. A change
still open after that round is filed as blocked (§6).

## 5. Deduplicate

Search the open issues for each change, by its words and its files:

```sh
gh issue list --state open --search "<words>" --json number,title
```

A change an open issue already covers is not filed again: report that issue's
number instead. Existing issues stay as they are; a gap in one is the owner's
to raise there.

## 6. File

Skip this step in **draft** mode: show each issue's title, label and body.

The requests are the owner's: a change they asked for is approved work. Its
label follows from how well it is specified:

- Specified (what to change, what done looks like): `ready-for-agent`.

  ```sh
  gh issue create --label ready-for-agent --title '<change> (<file or area>)' --body-file "$(git rev-parse --absolute-git-dir)/ISSUE_BODY.md"
  ```

- Still waiting on the owner's answer after §4: `needs-info`, the open
  question first in the body.

  ```sh
  gh issue create --label needs-info --title '<change> (<file or area>)' --body-file "$(git rev-parse --absolute-git-dir)/ISSUE_BODY.md"
  ```

Each body goes through that file, as the `git-workflow` skill says, so the
shell leaves its backticks and `$` alone. The body, self-sufficient for
whoever works it later:

```markdown
## Problem
<what is missing or wrong today, with file:line and the evidence>

## Expected
<what done looks like, as checks someone can run: behavior, docs, tests>

## Suggested fix
<the direction, not a full design>

Requested by the owner.
```

Issues are public on a public repository: write only what could go in a
commit — no secret, no real IP address or host name, no content of gitignored
files.

## 7. Report

- One line per issue: its number, title and label, with the requests it
  groups.
- The requests matched to an existing issue, with its number.
- The questions left open (`needs-info` issues).
- The next step: `/next-issue` works the `ready-for-agent` ones.
