---
description: Work the next task of the project's TODO.md (or all of them, the next N, or the one matching some words), verify it, record it and propose a commit.
argument-hint: "[all | N | task words]"
---

Work tasks from the current project's `TODO.md`.

<!-- Single source shared by Claude Code, OpenCode and VS Code Copilot
     (linked by os/helpers/links.sh). Keep it tool-neutral. -->

The `todo-md` skill (`~/.claude/skills/todo-md/SKILL.md`) defines the file:
sections, line syntax, the English-only rule and the migration of legacy files.
Load it before the first edit and follow it for every change to `TODO.md`.
Everything you write into the project — `TODO.md`, code, comments, docs, the
proposed commit message — is in English, whatever the conversation language.

## 1. Mode

The argument is `$ARGUMENTS`. If that placeholder was left as-is (the tool did
not substitute it), the argument is whatever the user typed after the
`/next-task` command instead.

| Argument        | Mode                                                                                 |
| --------------- | ------------------------------------------------------------------------------------ |
| none            | **single**: the next task, then stop                                                 |
| `all`           | **batch**: every open task of `🔴 In progress` and `🟡 To do`, one at a time (§10)   |
| a number `N`    | **batch**, limited to the next `N` tasks                                             |
| any other words | **single**, on the open item whose line matches them (§3); ask if none or several do |

State the mode — and in batch mode the tasks in scope — before starting.

## 2. Prepare

1. Read `TODO.md` at the project root. If there is none, say so and stop — do
   not create one.
2. If it does not follow the `todo-md` layout, or is not in English, migrate it
   first, in one pass, as the skill says, and report the migration as its own
   change.
3. Run `git status --short` and note the changes already there: they belong to
   no task and stay out of the commit plan.
4. Find how the project verifies a change: its `AGENTS.md` / `CLAUDE.md`, then
   the `Makefile`, package scripts and CI workflows.

## 3. Pick

- With words (§1): the open item whose line matches them, in any section but
  `🖐 Manual`. Naming it is the owner's approval, even for an idea, a
  recommendation, a finding or a `BLOCKED` task — for the latter, ask how the
  blocker was resolved unless the owner said so, then remove the marker.
- Otherwise, the candidates are the open `[ ]` tasks of `🔴 In progress`, then
  `🟡 To do`, except those marked `BLOCKED`. Within a section, `(URGENT)`
  first, then the top-most. Never pick from another section: `🖐 Manual` is the
  owner's, and ideas, recommendations and security findings are not approved
  until the owner moves them to `🟡 To do`.
- Move the task, unchanged, to `🔴 In progress` (an interrupted run then leaves
  a trace) and say which task you picked.
- No candidate: say so, with the number of `BLOCKED` tasks and of items waiting
  for triage, and stop.

## 4. Understand

- Read the code the task touches before changing anything.
- Already done, or made moot by other changes? Verify it, then record it as
  done (§7) with the evidence — no code change.
- Ambiguous, or it needs a decision only the owner can make? Ask before
  changing anything.
- Too big for one reviewable change? Split it into ordered sub-tasks: the first
  replaces it in `🔴 In progress`, the others go to the top of `🟡 To do`. Say
  so, then work the first.

## 5. Implement

- Make the smallest change that completes the task, in the style of the
  surrounding code.
- Add or update tests for the behavior you changed.
- Update what the change makes stale: `docs/` (`docs-hub` skill), `README.md`
  (`readme` skill), comments and examples.
- Follow the project's guardrails. Never stage, commit or push, and never read
  or write secrets.

## 6. Verify

- Run the project's checks that cover the change (§2). The task is done only
  when they pass; report what you ran and the result.
- A check that cannot run here (sandbox, no Docker, missing credentials,
  production or cluster access) is not a pass: add a `🖐 Manual` step with the
  exact command and its success signal, and say so.
- A failure you cannot fix within the task's scope is a blocker (§8).

## 7. Record

- Move the task from `🔴 In progress` to the top of `✅ Done`, as a done entry
  with today's real date (`date +%F`): what changed and how it was verified,
  in at most ~300 characters — the detail goes in the commit message. Prune
  `✅ Done` as the skill says.
- Whatever only the owner can do — push, deploy, apply, a UI setting, a secret
  — becomes `🖐 Manual` steps, referenced from the done entry.
- Propose one Conventional Commit message for the task (`commit-types` skill)
  and list the files it changed. Do not commit.

## 8. Blocked

When a task cannot be finished — a failing check you cannot fix, a missing
decision or access, out of scope, too risky:

- Do not force it. Never delete, or mark done, a task you did not finish.
- Leave it in `🔴 In progress`, ending with
  ` — BLOCKED YYYY-MM-DD: <what is needed>`.
- Leave your partial changes in place, and list them.
- Stop and ask the owner: what went wrong, what you tried, the options you see.
  Once they decide, remove the marker and carry on.

## 9. Recommendations and security audit

Single mode: after the task. Batch mode: once, at the end, over every task of
the run. Do NOT implement them. Use the skill's line formats, and leave a
section untouched when you have nothing genuinely useful to add.

**🤖 Agent recommendations** — changes that genuinely improve the product,
grounded in evidence already in the project, not generic advice:

- Ground every suggestion in what you have: the task you just did, the code you
  touched, `README` / `docs/`, the rest of `TODO.md` (patterns in `✅ Done`,
  gaps in `🟢 Ideas / backlog`), test coverage and skipped or flaky tests,
  `git log` (recurring fixes, hot files), friction you hit. No concrete file,
  behavior or observed gap: no suggestion.
- Highest user or maintainer value first: a missing or weak capability, UX/DX
  friction or an incomplete flow next to your change; reliability gaps
  (untested paths, silent failures, missing error handling, fragile scripts);
  maintainability that unblocks future work (duplication, dead code, stale
  docs); quick wins over speculative rewrites.
- At most ~5 per run, ranked by impact, each specific and small enough to
  become a task, naming its target and benefit. Skip vague items ("improve
  performance", "add more tests"), anything already done, and duplicates
  anywhere in `TODO.md`. When the section already holds 10 open items, add
  none and say that triage is due.

**🔒 Security audit** — a brief, read-only review of the code you touched and
its immediate surroundings, separate from the recommendations:

- Secrets and credentials: hardcoded tokens or keys, secrets in config, logs or
  committed files, missing `.gitignore` / gitleaks coverage.
- Injection and unsafe execution: unquoted shell variables, `eval`,
  `curl | sh`, unvalidated input reaching commands, paths, SQL or templates.
- Supply chain: unpinned or unverified dependencies, actions, images,
  installers or downloaded scripts without checksum or signature.
- Permissions and exposure: broad file modes, wildcard allowlists (agent
  `permissions` included), world-readable secrets, services bound to `0.0.0.0`.
- Hardening: missing input validation, weak crypto or TLS settings, insecure
  defaults, missing least privilege or CI security checks.

Only issues tied to a concrete file and line, never speculative; highest
severity first; at most ~5 per run; no duplicates of anything in `TODO.md`.
Never write a secret value into `TODO.md` — its location only.

## 10. Batch mode

- One task at a time: §3 to §8 for each, re-reading `TODO.md` before every
  pick. Give one line per task as you go.
- The scope is frozen at the start: the candidate tasks (§3), or the first `N`
  of them. Sub-tasks from a split replace their task; what you add to other
  sections during the run is not worked.
- Stop when the scope is done, or at the first blocker (§8): ask, and resume
  the remaining tasks only once the owner has decided.
- If the per-task checks were targeted, run the project's full check once at
  the end. When it fails, find the task that broke it and treat it as a
  blocker.
- Then §9, once, and the summary.

## 11. Summary

- **Single mode**: the task (done or blocked), files changed, checks run and
  their result, `🖐 Manual` steps added, recommendations and findings added,
  and the proposed commit (message and files).
- **Batch mode**: tasks done, the task that halted the run and why, `BLOCKED`
  tasks skipped, checks, manual steps, recommendations and findings, then a
  **commit plan**: one commit per task, in order, each with its message and
  files. Flag the files several tasks changed — `TODO.md` always is, unless
  git ignores it — and those that already had changes, so the owner stages
  them hunk by hunk (`git add -p`).
- In both, list the changes that were there before the run (§2) apart: they
  are in no commit.
