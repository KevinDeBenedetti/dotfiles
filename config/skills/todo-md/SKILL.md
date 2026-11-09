---
name: todo-md
description: Format and editing rules for a project's TODO.md - English-only sections, task line syntax, the owner's manual-steps section, BLOCKED markers, done entries, and the migration of legacy or French TODO files. Use whenever reading, creating, adding to, editing, triaging or migrating a TODO.md in any project, including from the next-task command.
---

# TODO.md

`TODO.md`, at the root of a project, is the task list its owner shares with
coding agents (Claude Code, OpenCode, VS Code Copilot). The `next-task` command
works it; this skill is the format every edit follows, whichever tool or
command makes it.

## Language

English only — headings, tasks, notes and manual steps — whatever language the
conversation uses. Keep verbatim what is not prose: code, commands, paths,
identifiers, links, numbers, dates, quoted output, and product text localized
on purpose (a French UI label stays French, in backticks).

## Layout

Exactly these headings, in this order:

```markdown
# TODO

## 🔴 In progress
## 🟡 To do
## 🖐 Manual — do it yourself, in order
## 🟢 Ideas / backlog
## 🤖 Agent recommendations
## 🔒 Security audit
## ✅ Done
```

| Section                  | Holds                                                                                           | Worked by              |
| ------------------------ | ----------------------------------------------------------------------------------------------- | ---------------------- |
| 🔴 In progress           | The task an agent is on, or stopped on (`BLOCKED`)                                              | `next-task`, first     |
| 🟡 To do                 | Tasks the owner approved, most important first                                                  | `next-task`            |
| 🖐 Manual                | Steps only the owner can take: push, deploy, credentials, UI settings, checks agents cannot run | the owner              |
| 🟢 Ideas / backlog       | Ideas not approved yet                                                                          | nobody, until promoted |
| 🤖 Agent recommendations | Agent suggestions waiting for triage                                                            | the owner triages      |
| 🔒 Security audit        | Agent security findings waiting for triage                                                      | the owner triages      |
| ✅ Done                  | Finished tasks and steps, newest first                                                          | —                      |

- Create a missing section empty, in its place. Never rename, reorder or drop
  one.
- A short intro paragraph under a heading is fine (the order of the manual
  steps, say); everything else is a list item.
- Only the owner approves an item: by moving it to `🟡 To do`, or by naming it
  to `next-task`. An agent adds a task to `🟡 To do` only when asked to, or
  when it splits an approved task.
- Reminders (such as the dotfiles' Claude Code `Stop` hook) find sections by
  these headings and show only the first line of each item: keep the headings
  exact and make every first line understandable on its own.

## Size

The whole file is read on every `next-task` run: keep it under ~20 KB (about
5k tokens). Hence the limits below — a line holds what to do and why, while
history, measurements and procedures go to the commit message, `docs/` or the
code. Long lines already in the file stay as they are unless the owner asks.

## Lines

### Task — `🔴`, `🟡`, `🟢`

```markdown
- [ ] <TYPE>: <description>
```

- `<TYPE>` is the commit type the change will ship under, upper-cased (see the
  `commit-types` skill): `FEAT`, `FIX`, `PERF`, `DEPS`, `DOCS`, `CHORE`, `TEST`,
  `BUILD`, `CI`. Never `REFACTOR`: a refactor is a `CHORE`.
- `(URGENT)` right after the type marks a critical task: `FIX(URGENT): …`.
  Otherwise priority comes from the section and the order.
- One line of at most ~300 characters: what, where (file or area) and why.
- A task an agent could not finish ends with
  ` — BLOCKED YYYY-MM-DD: <what is needed>`, the need in a few words that name
  what it waits for (`🖐 2.1`, `2026-11-16`, a decision on the retry budget).
  `next-task` skips the task until the owner removes the marker.

### Recommendation — `🤖`

```markdown
- [ ] <TYPE>: <change> (<file or area>) — <evidence and expected benefit>
```

At most ~300 characters, and at most 10 open recommendations: when the section
is full, add none and tell the owner that triage is due.

### Security finding — `🔒`

```markdown
- [ ] <TYPE>: [<SEVERITY>] <fix> (<file:line>) — <risk and why it matters>
```

`<SEVERITY>` is `CRITICAL`, `HIGH`, `MEDIUM` or `LOW`; a `CRITICAL` finding also
takes `(URGENT)`. At most ~300 characters. The tag stays when the owner
promotes the finding. Never write a secret value, only where it is.

### Manual step — `🖐`

````markdown
### 1. Today — publish the release

- [ ] 1.1 Run the Docker-backed tests — Success: `0 failed`.
  ```sh
  make test
  ```
- [ ] 1.2 Check the deployed version — Success: it prints `v1.4.0`.
  Wait for the release job to finish first.
  ```sh
  curl -s https://example.com/version
  ```
````

- The first line — number, action, success signal — stays under ~100
  characters: reminders show nothing else. The exact command goes in an
  indented block below it, with at most two lines of context (why, when).
- Each step says exactly what to run or click and what success looks like, so
  the owner can take it without the agent.
- Group steps under numbered `###` headings when the order matters, and number
  them `<group>.<n>`. Never renumber: done entries refer to `🖐 1.1`.
- When only part of a step is done, record that part in `✅ Done` and keep the
  rest, marked `(remaining)` after its number.

### Done — `✅`, newest first

```markdown
- [x] YYYY-MM-DD — <TYPE>: <what changed> — <how it was verified>
```

- Today's real date (`date +%F`); never invent or reuse one.
- At most ~300 characters: the details belong in the commit message.
- A manual step moves here once the owner confirms it, or once its success
  signal was checked read-only:
  `- [x] YYYY-MM-DD — CHORE: 🖐 1.1 <what was done> — <what was observed>`.
- Keep the 10 most recent entries. When you add one, delete older entries, but
  only those already in the committed file (`git show HEAD:TODO.md`), so git
  history keeps them. Nothing is deleted when git does not track `TODO.md`.

## Editing

- Re-read the file right before editing it: the owner edits it too.
- Change only the lines you mean to. Never delete, or mark done, a task that was
  not done.
- Move a task between sections without rewording it, beyond fixing its syntax.
- Do not commit: the owner does.

## Migrating a legacy file

A `TODO.md` that does not follow this layout, or is not in English, is migrated
in one pass, before any other edit:

1. Rename the headings, then add the missing sections in their place:

   | Legacy heading                                                               | Heading                                |
   | ---------------------------------------------------------------------------- | -------------------------------------- |
   | `🔴 En cours`, `In Progress`                                                 | `🔴 In progress`                       |
   | `🟡 À faire`, `To Do`, `Todo`                                                | `🟡 To do`                             |
   | `🖐 Manuel — à faire toi-même, dans l'ordre`, `🟡 À faire (manuellement, …)` | `🖐 Manual — do it yourself, in order` |
   | `🟢 Idées / backlog`, `Backlog`                                              | `🟢 Ideas / backlog`                   |
   | `🤖 Claude — recommandations`                                                | `🤖 Agent recommendations`             |
   | `✅ Fait`, `Done`                                                            | `✅ Done`                              |

2. Translate every line into English, faithfully and completely: same facts,
   same detail, same order and checkbox state. Do not summarize.
3. Fix the syntax: a checkbox on every item, upper-case types, `REFACTOR` →
   `CHORE`. A done item with no date stays undated: never make one up.
4. Ask the owner where something goes when it has no clear place (an unknown
   heading, items outside any section) instead of guessing.
5. Report the migration on its own and, when git tracks `TODO.md`, propose a
   separate commit for it (`chore: migrate TODO.md to the English layout`), so
   it does not mix with task changes.
