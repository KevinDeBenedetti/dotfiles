---
name: manual-steps
description: Guided chat that walks the owner through the open steps of the 🖐 Manual section of a project's TODO.md, one step at a time - plan the session, give each step's exact command and success signal, wait for the result, check it, troubleshoot, then record the step as done, partial or dropped and unblock the tasks waiting on it. Use for `next-task manual`, or whenever the owner asks to go through, walk through, resume or get help with the manual steps or manual tasks of a TODO.md.
---

# Manual steps

The `🖐 Manual` section of a project's `TODO.md` holds what only the owner can
do: push, deploy, enter a secret, change a UI setting, run a check an agent
cannot. This skill walks the owner through it in a chat, one step at a time,
from the plan to the record. `next-task manual` runs it, and so does a plain
request ("let's do my manual steps"). The `todo-md` skill defines the file:
follow it for every edit of `TODO.md`.

## Roles

- **The owner acts**: runs the commands, clicks, pushes, deploys, enters the
  secrets. They lead, too: they may ask for several steps at once, jump to
  another one or change the order.
- **You guide**: say what to do and where, give the exact command, read the
  result, check it against the success signal, troubleshoot and record.
- Never take the owner's part — commit, push, deploy, apply, a secret, a UI
  setting: that is what makes the step manual — and never work around a
  guardrail or a denied command. A step that is only a check (tests, a
  read-only query) you may run yourself when this session can: say so, and
  show what it printed.

## Start

1. Read `TODO.md` at the project root. No file, or no open step in
   `🖐 Manual`: say so — with the task `next-task` would take, if any — and
   stop.
2. A legacy or non-English file: migrate it first, as `todo-md` says.
3. Note `git status --short`: the changes already there stay out of the
   commit you propose.

## Scope

- Every open (`- [ ]`) step of `🖐 Manual`, or only the step (`1.2`), the
  group (`3`) or the steps matching the words the owner named. Ask when the
  words match several steps or none.
- In the section's order: the one its intro states, if any, then the file's —
  groups top to bottom, steps by number.
- Each step is **ready** — it can be done now — or **waiting**: on a date, an
  event or a step not done yet ("a day after 1.2", "at the next release").
  Work it out from the dates in `✅ Done` and today's (`date +%F`); check an
  event read-only when you can (a release, a CI run); ask when nothing tells.
  The owner may take a waiting step anyway: they see what you cannot.
- A step marked `(remaining)` after its number is partial: guide only the
  rest.

## Opening

One message: the plan, then the first ready step.

- The plan: one line per step — its number, a few words, ready or what it
  waits for. At most ~10 lines: sum up the rest ("6 more wait on events").
  Skip it when the scope is a single step.
- No ready step: say what each one waits for, and when it should be ready if
  a date tells. The owner may still take one; otherwise, close.

## One step at a time

Keep every message short: the owner is busy with the step itself.

### 1. Check

Before presenting a step, check read-only what you can:

- What it relies on still exists — the script, file, target or workflow its
  command names. A stale step is corrected first (see Record).
- Its success signal does not already hold. If it does, present the step as
  done, with the evidence, and record it on the owner's yes.

### 2. Present

- The number and the action, in one sentence, and the step's place among the
  ready ones (`2 of 4`).
- Where it runs — directory, repository, host, UI page — and when or why, if
  the step says.
- The exact commands, copy-paste ready: the step's own, verbatim, with the
  placeholders you can resolve filled in (`<ns>`, a date); ask for the
  others. One block per command whose result the owner must read.
- For an action that changes something: what it changes and how to undo it.
  Say so plainly when it cannot be undone.
- The success signal, then how to answer: the output (or the lines that
  matter — offer a `tail` or `grep` for a long one), `done`, `skip`, `stop`,
  or a question.

Leave out what does not apply. A step with several actions (PRs to merge,
boxes to tick) goes in parts, one per message, each with its success signal.

````markdown
**🖐 1.2 — check the deployed version** (2 of 4)

Once the release job is green, from any terminal:

```sh
curl -s https://example.com/version
```

Success: it prints `v1.4.0`. Paste what it prints, or reply `done`, `skip`
or `stop`.
````

### 3. Wait

End the message there: never assume a result, answer for the owner, or move
on without a reply.

### 4. Judge the reply

- **Output**: check it against the success signal and quote the line that
  proves it — or the one that breaks it. A pass is recorded; anything else is
  troubleshot.
- **`done`** without output: the owner's word is enough, unless the step asks
  for a value (a date, counts, a measurement): ask for it.
- **`skip`** — or "later", "not now": leave the step as it is and go on. The
  later steps of its group that build on it wait too; ask when unsure.
- **`stop`**: close the session.
- **A question**: answer it, then ask again for the step's result.
- **Moot**, says the owner: the step is dropped (see Record).

Once a step is recorded, say so in one line and present the next ready step
in the same message.

### 5. Troubleshoot

- Say what the output means and its likely cause, read from the code, config
  or docs the step touches — not guessed.
- One next action at a time, with its command and what it should show.
- Never weaken a success signal to make a step pass.
- A fix that changes the project (code, config, docs) is a task, not a step:
  add it to `🟡 To do` only when the owner asks. If they want it now, work it
  as `next-task` works a task the owner named — implement, verify, record,
  propose a commit — then resume the session.
- After two failed attempts, stop guessing: sum up what was tried and let the
  owner choose — dig further, record what is done and leave the rest
  `(remaining)`, skip, or turn it into a task.

## Record — after every step, before the next

Follow `todo-md` for every line, and re-read `TODO.md` right before each
edit: the owner edits it too.

- **Done**: move the step to the top of `✅ Done`, with what was observed as
  its proof — the success line, the value the step asked for. A task that
  needs that value reads it there.
- **Partial**: record the done part in `✅ Done`; keep the rest in its place,
  marked `(remaining)` and reworded to what is left.
- **Dropped**: record it in `✅ Done` as dropped, with the owner's reason.
  Never delete a step silently.
- **Stale**: say what changed in the project, propose the corrected step, and
  edit it once the owner agrees.
- A group with no open step left loses its `###` heading.
- **Unblock**: a task whose `BLOCKED` marker waits for this step (`🖐 1.2`),
  and for nothing still open, loses the marker: tell the owner it is ready
  for `next-task`.
- **Hand-off**: a step that ends with agent work ("tell the agent the date",
  "the agent then sizes the request") — name the task, and offer to work it
  right after the session, while the output is still in the conversation.
- New steps the session reveals: add them per `todo-md`, in their place in
  the order, and say so.

## Secrets and sensitive output

- Never ask for a secret value. The owner puts it where it belongs (the
  secret store, the `.env`, the UI) and replies `done`. For a file you cannot
  edit, give the exact lines to paste, with placeholders for the secrets.
- A secret pasted anyway: never repeat, quote or record it, and tell the
  owner it is now in the chat history, so rotating it is the safe move.
- Record observations only: no secret, and none of the infrastructure details
  the project keeps out of git (real IPs and host names in a public
  repository).

## Language

Talk with the owner in their language. `TODO.md` and commit messages stay in
English (`todo-md`, `commit-types`).

## Close

When the scope is done, no ready step is left, or the owner says `stop`:

- The steps done, partial, dropped and skipped; the waiting ones, with what
  they wait for and the next date, if one tells.
- The tasks unblocked or handed off, the steps added or corrected.
- One proposed Conventional Commit for the `TODO.md` change (`commit-types`),
  such as `chore(todo): record manual steps 1.1 and 1.2` — none when git
  ignores `TODO.md`. A task worked during the session gets its own commit,
  and the changes noted at the start are in none. Do not commit.
- What comes next: the next step to be ready, and when; the task `next-task`
  would take.
