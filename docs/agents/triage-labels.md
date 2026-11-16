---
title: Triage Labels
---

# Triage Labels

The skills speak in terms of five canonical triage roles. This repository has
no labels: its tracker is `TODO.md` (see `issue-tracker.md`), so each role is a
place in that file, following the `todo-md` skill.

| Role in mattpocock/skills | Where it goes in `TODO.md`                                             | Meaning                                   |
| ------------------------- | ---------------------------------------------------------------------- | ----------------------------------------- |
| `needs-triage`            | `🤖 Agent recommendations` (`🔒 Security audit` for security findings) | The owner has not evaluated it yet        |
| `needs-info`              | The line ends with ` — BLOCKED YYYY-MM-DD: <what is needed>`           | Waiting on the owner for information      |
| `ready-for-agent`         | `🟡 To do`                                                             | Approved and fully specified for an agent |
| `ready-for-human`         | `🖐 Manual — do it yourself, in order`                                 | Only the owner can do it                  |
| `wontfix`                 | Removed from the file, with the reason given in the reply              | Will not be actioned                      |

When a skill says to apply a role, move or mark the line as the table says,
never add a label string to it. Moving a line into `🟡 To do` approves it, so
only do that when the owner says so.
