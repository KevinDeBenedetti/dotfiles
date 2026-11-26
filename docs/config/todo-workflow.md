---
title: TODO Workflow
---

# TODO Workflow

Each project keeps its tasks in a root `TODO.md` that its owner shares with the
coding agents. The `/next-task` command works the file, the `todo-md` skill
defines its format and the `manual-steps` skill guides you through its manual
steps, in Claude Code, OpenCode and VS Code Copilot alike (see
[Skills](./skills.md) for how they reach each tool).

| Piece                | Source                                | Role                                                     |
| -------------------- | ------------------------------------- | -------------------------------------------------------- |
| `todo-md` skill      | `config/skills/todo-md/SKILL.md`      | Format of `TODO.md`, applied to every edit of the file   |
| `/next-task` command | `config/skills/next-task/SKILL.md`    | Picks, implements, verifies and records tasks            |
| `manual-steps` skill | `config/skills/manual-steps/SKILL.md` | Guided chat through the `🖐 Manual` steps, one at a time |

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

| Invocation           | Effect                                                            |
| -------------------- | ----------------------------------------------------------------- |
| `/next-task`         | Works the next task, then stops                                   |
| `/next-task all`     | Works every open task of `🔴` and `🟡`, one at a time             |
| `/next-task 3`       | The same, for the next three tasks                                |
| `/next-task <words>` | Works the open item matching the words, outside `🖐 Manual`       |
| `/next-task manual`  | Guides you through the `🖐 Manual` steps ([below](#manual-steps)) |

For each task, the agent:

1. moves it to `🔴 In progress`, so an interrupted run leaves a trace;
2. implements it, with its tests and the docs it makes stale;
3. runs the project's checks — a check it cannot run becomes a `🖐 Manual`
   step, never a pass — then a real test: the command that exercises the change
   the way its user would, run by the agent when it can, otherwise handed to
   you as a "Try it" line;
4. moves it to `✅ Done` with the date and how it was verified;
5. hands you the commit, without committing: one runnable
   `git add … && git commit …` line, then the push and the pull request
   commands (see [Git Workflow](./git-workflow.md)). On a shared branch
   (`main`, `dev`, …), it hands you the branch command first.

A task it cannot finish stays in `🔴 In progress`, marked
`BLOCKED YYYY-MM-DD: <what is needed>`, and the agent asks what to do. Later
runs skip a `BLOCKED` task until the owner removes the marker or names the
task.

After the task — once at the end of a batch — the agent adds at most about five
grounded recommendations and five security findings for triage.

### A whole batch with one command

`/next-task all` is the one command for everything that is approved:

1. It first lists the `BLOCKED` tasks and asks which blockers are resolved;
   those join the run.
2. It works the tasks one at a time. After each one it reports what changed,
   the checks and their result, the "Try it" command with its success signal,
   and the proposed commit message with its files.
3. A task that blocks is marked and reported, and the run goes on with the
   tasks that do not depend on it. The blockers are put to you once, at the
   end.
4. It ends with the summary and a commit plan: one grouped commit for the
   batch, with one body line per task, handed over as a single runnable
   `git add … && git commit …` line for its files.
   Its type is the one with the highest release impact among the tasks. Ask
   for one commit per task when you want the changelog to list each of them.
5. When `🖐 Manual` has open steps, it asks whether to go through them now and,
   on a yes, continues with the guided session [below](#manual-steps).

## Agent skills

`/next-task` loads four engineering skills of `config/skills/` at fixed steps,
in the three tools alike (see [Skills](./skills.md#existing-skills)).

| Skill             | Used by `/next-task`                                                         |
| ----------------- | ---------------------------------------------------------------------------- |
| `diagnosing-bugs` | To find the cause of a `FIX` before changing anything                        |
| `grilling`        | To settle an ambiguous task with you, in one round of questions              |
| `tdd`             | To write the test first for a `FEAT` or `FIX`                                |
| `code-review`     | To review the task's changes once the checks pass, before it is recorded     |

The planning flows are not owned yet: in Claude Code they come from the
`mattpocock-skills` plugin (see [Claude Code](./claude-code.md#plugins)).
`to-tickets` only runs when you call it (`/mattpocock-skills:to-tickets`): the
agent splits a task too big for one change itself.

The plugin also feeds the file. In a repository set up with
`/mattpocock-skills:setup-matt-pocock-skills` to use `TODO.md` as its tracker,
the planning skills write tasks that `/next-task` then works. This repository
is not one of them: it tracks its work in GitHub Issues (see
`.agents/issue-tracker.md` and
[Issue Workflow](./issue-workflow.md)). With `TODO.md` as the tracker:

1. `grilling` settles a design with you.
2. `/mattpocock-skills:to-spec` writes it to `.scratch/<feature>/spec.md`.
3. `/mattpocock-skills:to-tickets` cuts it into task lines, added to
   `🤖 Agent recommendations`.
4. You approve them by moving them to `🟡 To do`.
5. `/next-task all` works them.

The plugin's `implement` skill is not used: it commits, and committing stays
yours.

## Manual steps

`🖐 Manual` holds what only you can do: push, deploy, enter a secret, change a
UI setting, run a check the agent cannot. `/next-task manual` takes you through
those steps in a guided chat, following the `manual-steps` skill:

| Invocation                  | Scope                                   |
| --------------------------- | --------------------------------------- |
| `/next-task manual`         | Every open step, in the section's order |
| `/next-task manual 2.1`     | That step                               |
| `/next-task manual 2`       | The open steps of group `### 2.`        |
| `/next-task manual <words>` | The open steps matching the words       |

1. The agent opens with a plan: each step, ready or waiting — on a date, an
   event or another step, worked out from `✅ Done` and today's date.
2. Then one step per message: where to run it, the exact command, what it
   changes, the success signal and how to answer.
3. You run it and paste the output, or reply `done`, `skip` or `stop`, or ask
   a question. The agent checks the output against the success signal, and
   troubleshoots one action at a time when it does not match.
4. Each step is recorded as soon as it is settled — done, partial
   (`(remaining)`) or dropped with your reason — so a session stopped halfway
   resumes where it left off. A task `BLOCKED` on that step loses its marker,
   ready for `/next-task`.
5. At the end: what is done, skipped and still waiting, and the runnable
   commit command for the `TODO.md` change.

The agent never takes your part — commit, push, deploy, secrets — and never
asks for a secret value: you put it where it belongs and reply `done`. It may
run a step that is only a read-only check itself, when its session allows.

## Reminders

In Claude Code, the `next-steps.sh` `Stop` hook (see
[Claude Code](./claude-code.md)) closes each turn with what is left for you:
the files to re-stage, commit or push, the `BLOCKED` tasks and what they wait
for, the task `/next-task` would take, the items waiting for triage, and the
open `🖐 Manual` steps, with `/next-task manual` to take them. It finds
sections by their emoji or their English or French words, so it also reads a
`TODO.md` not migrated yet.

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
