---
description: Work the next task (or all tasks) in the project's TODO.md, following a strict format.
argument-hint: "[all]"
---

Work tasks in the current project's TODO.md, following a strict format.

<!-- Single source shared by Claude Code, OpenCode and VS Code Copilot
     (linked by os/helpers/links.sh). Keep it tool-neutral. -->

## 0. Mode
The argument is `$ARGUMENTS`. If that placeholder was left as-is (the tool did
not substitute it), the argument is whatever the user typed after the
`/next-task` command instead.
- **No argument** (or anything other than `all`) → **single mode**: do exactly ONE
  task, then stop. This is the default.
- **`all`** → **batch mode**: repeat the per-task procedure (steps 3→6b) for every
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
## 🔒 Security audit
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
Ignore `🟢 Idées / backlog`, `🤖 Claude — recommandations`, `🔒 Security audit`,
and `✅ Fait`.
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
Goal: propose changes that genuinely **improve the product**, grounded in
evidence already in the project — not generic advice. Do NOT implement them.

**Ground every suggestion in existing information.** Before suggesting, use what
you already have: the task you just did, the code you touched, `README`/`docs/`,
open/closed items in `TODO.md` (especially `✅ Fait` and `🟢 Idées / backlog` to
spot patterns and gaps), test coverage and failing/skipped tests, `git log`
history (recurring fixes, hot files), and repeated friction you hit. If you
can't point to a concrete file, behavior, or observed gap, don't suggest it.

**What counts as relevant** (pick the highest user/maintainer value first):
- Missing or weak user-facing capability, UX/DX friction, or an incomplete flow
  next to what you just changed.
- Reliability gaps: untested paths, silent failures, missing error handling,
  fragile scripts, flaky or skipped tests.
- Maintainability that unblocks future work: duplication, dead code, outdated or
  missing docs, inconsistent conventions.
- Quick wins with clear payoff over speculative rewrites.

**Quality bar.** Max ~5 items per run, ranked by impact (best first). Each must
be specific, actionable, and small enough to become a task. Name the target
(file/module/command) and the benefit. Skip vague items ("improve
performance", "add more tests"), anything already done, and duplicates already
present anywhere in TODO.md (including `🔒 Security audit`).

Append as unchecked items to `## 🤖 Claude — recommandations`, one line each:
`- [ ] <TYPE>: <suggestion> (<file/area>) — <evidence + expected benefit>`
If you have nothing genuinely useful to add, leave the section untouched.

## 6b. Security audit
Separate from §6. Briefly audit the code you touched **and its immediate
surroundings** (read-only; do not fix here) for security improvements, and
append findings to `## 🔒 Security audit`. Do NOT implement them.

**Look for**, as relevant to the project type:
- Secrets & credentials: hardcoded tokens/keys, secrets in config, logs, shell
  history, or committed files; missing `.gitignore`/gitleaks coverage.
- Injection & unsafe execution: unquoted shell variables, `eval`, `curl | sh`,
  unvalidated input passed to commands, paths, SQL, or templates.
- Supply chain: unpinned or unverified dependencies, actions, installers,
  Homebrew taps, or downloaded scripts without checksum/signature.
- Permissions & exposure: overly broad file modes, wildcard allowlists
  (e.g. Claude `permissions`), world-readable secrets, services bound to
  `0.0.0.0`, risky default ports.
- Hardening: missing input validation, weak/outdated crypto or TLS settings,
  insecure defaults, missing least-privilege, missing audit/CI security checks.

**Rules.** Only report issues you can tie to a concrete file/line or config
(never speculative). Rank by severity (highest first), max ~5 per run. Skip
duplicates already in TODO.md. Never write actual secret values into TODO.md —
reference the location only. If nothing real is found, leave the section
untouched.

One line each:
`- [ ] <TYPE>: [SEVERITY] <fix> (<file:line>) — <risk and why it matters>`
where `SEVERITY` is `CRITICAL` | `HIGH` | `MEDIUM` | `LOW` (usually
`FIX`/`CHORE`; use `(URGENT)` after the type for CRITICAL).

## 7. Summary
Give a short summary: the task completed, what changed (files/tests), and any
recommendations and security findings you added.

## 8. Batch mode (`all`) loop rules
Only when invoked as `next-task all`:
- Process tasks **one at a time**, fully completing the per-task procedure
  (steps 3→6b) for the current task before picking the next one. Re-pick from the
  live state of TODO.md each iteration (a finished task is now in `✅ Fait`, so
  the next highest-priority `[ ]` becomes current).
- **Scope is frozen at the items present in `🔴 En cours` / `🟡 À faire` when you
  start.** Items you add to `🤖 Claude — recommandations` or `🔒 Security audit`
  while working are NOT promoted or executed in this run — that keeps the loop
  finite.
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
  touched, and any recommendations and security findings added.
- Still do not commit — leave staging/committing to the user.
