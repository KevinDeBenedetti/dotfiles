---
title: TODO Workflow
---

# TODO Workflow

Each project keeps its tasks in a root `TODO.md` that its owner shares with the
coding agents. The `/next-task` command works the file and the `todo-md` skill
defines its format, in Claude Code, OpenCode and VS Code Copilot alike (see
[Skills](./skills.md) for how both reach each tool).

| Piece                | Source                           | Role                                                   |
| -------------------- | -------------------------------- | ------------------------------------------------------ |
| `todo-md` skill      | `config/skills/todo-md/SKILL.md` | Format of `TODO.md`, applied to every edit of the file |
| `/next-task` command | `config/commands/next-task.md`   | Picks, implements, verifies and records tasks          |

## Sections

| Section                                | Holds                                                       | Worked by           |
| -------------------------------------- | ----------------------------------------------------------- | ------------------- |
| `🔴 In progress`                       | The task an agent is on, or stopped on (`BLOCKED`)          | `/next-task`, first |
| `🟡 To do`                             | Approved tasks, most important first                        | `/next-task`        |
| `🖐 Manual — do it yourself, in order` | Steps only the owner can take, each with its success signal | the owner           |
| `🟢 Ideas / backlog`                   | Ideas not approved yet                                      | nobody              |
| `🤖 Agent recommendations`             | Agent suggestions waiting for triage                        | the owner triages   |
| `🔒 Security audit`                    | Agent security findings waiting for triage                  | the owner triages   |
| `✅ Done`                              | Finished tasks and steps, dated, newest first               | —                   |

A task reads `- [ ] <TYPE>: <description>`, where `<TYPE>` is the upper-cased
Conventional Commit type it will ship under (`FEAT`, `FIX`, `CHORE`, …, never
`REFACTOR`). The owner approves an item by moving it to `🟡 To do`, or by
naming it to `/next-task`; agents never approve one on their own.

## Running tasks

| Invocation           | Effect                                                      |
| -------------------- | ----------------------------------------------------------- |
| `/next-task`         | Works the next task, then stops                             |
| `/next-task all`     | Works every open task of `🔴` and `🟡`, one at a time       |
| `/next-task 3`       | The same, for the next three tasks                          |
| `/next-task <words>` | Works the open item matching the words, outside `🖐 Manual` |

For each task, the agent:

1. moves it to `🔴 In progress`, so an interrupted run leaves a trace;
2. implements it, with its tests and the docs it makes stale;
3. runs the project's checks — a check it cannot run becomes a `🖐 Manual`
   step, never a pass;
4. moves it to `✅ Done` with the date and how it was verified;
5. proposes a Conventional Commit message and the files to stage, without
   committing.

A task it cannot finish stays in `🔴 In progress`, marked
`BLOCKED YYYY-MM-DD: <what is needed>`, and the agent stops to ask. A batch
stops at its first blocker; later runs skip a `BLOCKED` task until the owner
removes the marker or names the task.

After the task — once at the end of a batch — the agent adds at most about five
grounded recommendations and five security findings for triage. A batch ends
with a commit plan: one commit per task, in order.

## Reminders

In Claude Code, the `next-steps.sh` `Stop` hook (see
[Claude Code](./claude-code.md)) closes each turn with what is left for you:
the files to re-stage, commit or push, the `BLOCKED` tasks and what they wait
for, the task `/next-task` would take, the items waiting for triage, and the
open `🖐 Manual` steps. It finds sections by their emoji or their English or
French words, so it also reads a `TODO.md` not migrated yet.

## Size

`/next-task` reads the whole file on every run, so the skill keeps it under
about 20 KB:

| Item                          | Limit                                                             |
| ----------------------------- | ----------------------------------------------------------------- |
| Task, recommendation, finding | ~300 characters                                                   |
| Manual step                   | ~100 characters on its first line, the command in a block below   |
| `BLOCKED` marker              | a few words naming what the task waits for                        |
| `🤖 Agent recommendations`    | 10 open items: past that, the agent adds none and asks for triage |
| `✅ Done`                     | ~300 characters per entry, the 10 most recent entries             |

Older done entries are pruned only once git holds them (`git show HEAD:TODO.md`),
so their history stays in the repository.

## English only

Everything written to `TODO.md` is in English, whatever the language of the
conversation, and so are commit messages (`commit-types` skill). A `TODO.md`
still in the former French layout (`🔴 En cours`, `🟡 À faire`, `✅ Fait`, …)
is migrated on its first edit — headings renamed, content translated — as a
change of its own.
