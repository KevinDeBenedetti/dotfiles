---
description: Work the next task (or all tasks) in the project's TODO.md, following a strict format.
argument-hint: "[all]"
---

Work tasks in the current project's TODO.md, following a strict format.

## 0. Mode (read `$ARGUMENTS`)
- **No argument** (or anything other than `all`) → **single mode**: do exactly ONE
  task, then stop. This is the default.
- **`all`** → **batch mode**: repeat the per-task procedure (steps 3→6) for every
  unchecked task in `🔴 En cours` then `🟡 À faire`, one at a time in priority
  order, until BOTH sections are empty. See §8 for the loop rules.

State which mode you are in before starting.

## 1. Locate TODO.md
Read `TODO.md` at the root of the current project. If none exists, say so and
stop — do not create one.

## 2. Expected structure (enforce it)
TODO.md must use these exact section headings, in this order. If a section is
missing, create it (empty) in the right place; never rename or reorder them:

```
# TODO

## 🔴 En cours
## 🟡 À faire
## 🟢 Idées / backlog
## 🤖 Claude — recommandations
## ✅ Fait
```

**Task line syntax** (every item is a checkbox):
`- [ ] <TYPE>: <description>`
where `<TYPE>` is one of `FEAT` | `FIX` | `CHORE` | `DOCS` | `REFACTOR` | `TEST`
(add `(URGENT)` right after the type when critical, e.g. `FEAT(URGENT):`).
Priority comes from the section, not the line. If an existing line doesn't match
this syntax, normalize it as you touch it.

## 3. Pick the task
Choose the highest-priority unchecked `[ ]` task: everything in `🔴 En cours`
first, then `🟡 À faire`. Within a section, `(URGENT)` wins, otherwise top-most.
Ignore `🟢 Idées / backlog`, `🤖 Claude — recommandations`, and `✅ Fait`.
State which task you picked before starting.

## 4. Implement
1. Implement the feature or fix.
2. Write or update tests if relevant; run them.
3. Keep the change consistent with the surrounding code and conventions.

## 5. Mark it done
Remove the task from its current section and add it to the TOP of `## ✅ Fait`
(newest first), using this exact syntax with today's date in ISO format:
`- [x] YYYY-MM-DD — <TYPE>: <description>`
Use the real current date (`YYYY-MM-DD`); never invent or reuse an old one. Do
not commit — leave staging/committing to the user.

## 6. Suggest backlog (Claude recommandations)
If, while working, you spotted worthwhile follow-ups (tech debt, missing tests,
risky patterns, quick wins), append them as unchecked items to
`## 🤖 Claude — recommandations` — do NOT implement them. One line each:
`- [ ] <TYPE>: <suggestion> — <short why>`
Skip duplicates already present anywhere in TODO.md. If you have nothing
genuinely useful to add, leave the section untouched.

## 7. Summary
Give a short summary: the task completed, what changed (files/tests), and any
recommendations you added.

## 8. Batch mode (`all`) loop rules
Only when invoked as `next-task all`:
- Process tasks **one at a time**, fully completing the per-task procedure
  (steps 3→6) for the current task before picking the next one. Re-pick from the
  live state of TODO.md each iteration (a finished task is now in `✅ Fait`, so
  the next highest-priority `[ ]` becomes current).
- **Scope is frozen at the items present in `🔴 En cours` / `🟡 À faire` when you
  start.** Items you add to `🤖 Claude — recommandations` while working are NOT
  promoted or executed in this run — that keeps the loop finite.
- **Stop** when no unchecked `[ ]` task remains in `🔴 En cours` or `🟡 À faire`.
- **Stop at the first failure.** If a task can't be completed (a test fails, the
  change breaks something, it needs a user decision, is too risky, is blocked, or
  depends on something out of scope), do NOT force it and do NOT move on to the
  next task. Leave the task in place (never delete a task you didn't do), then
  **halt the loop and ask the user for guidance** — explain what went wrong, what
  you tried, and the options you see. Resume the remaining tasks only once the
  user has decided.
- Give a brief per-task line as you go, then a **final consolidated summary**:
  tasks done, the task that halted the run (if any, with reason), all files/tests
  touched, and any recommendations added.
- Still do not commit — leave staging/committing to the user.
