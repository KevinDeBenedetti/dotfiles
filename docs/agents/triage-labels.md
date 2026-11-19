---
title: Triage Labels
---

# Triage Labels

The skills speak in terms of five canonical triage roles. This repository uses
them as GitHub labels, each named after its role, plus `urgent`.

| Label             | Meaning                                                    |
| ----------------- | ---------------------------------------------------------- |
| `needs-triage`    | The owner has not evaluated it yet                         |
| `needs-info`      | Waiting on the owner for information                       |
| `ready-for-agent` | Approved and fully specified: `/next-issue` works it       |
| `ready-for-human` | Only the owner can do it: `/next-issue manual` guides them |
| `wontfix`         | Will not be actioned                                       |
| `urgent`          | Goes first among the `ready-for-agent` issues              |

`ready-for-agent` is the owner's approval: an agent sets it only when the owner
says so, or on the sub-issues it cuts from an approved issue. New tickets an
agent files on its own take `needs-triage`.
