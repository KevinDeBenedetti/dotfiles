---
title: Issue Tracker
---

# Issue Tracker

How the agent skills (`to-spec`, `to-tickets`, `triage`, `wayfinder`, …) track
work in this repository. There is no hosted tracker: issues are tasks in
`TODO.md` at the repository root, edited only under the rules of the `todo-md`
skill (layout, line format, who approves what). Work that does not fit on one
line (specs, wayfinder maps) lives under `.scratch/`.

Both `TODO.md` and `.scratch/` are gitignored and stay local: this repository
is public. Never commit or quote them in a commit message or pull request.

## Conventions

- One ticket is one task line in `TODO.md`: `- [ ] <TYPE>: <description>`, at
  most ~300 characters (see `todo-md`).
- Triage state is the section the line sits in, not a label (see
  `triage-labels.md`).
- Only the owner approves a ticket, by moving it to `🟡 To do`. An agent adds a
  line to `🟡 To do` only when asked to, or when it splits an approved task;
  otherwise new tickets go to `🤖 Agent recommendations`.
- A ticket backed by a spec ends with a pointer:
  ` — spec: .scratch/<feature-slug>/spec.md`.
- A spec is `.scratch/<feature-slug>/spec.md`. Discussion is appended at its
  bottom under a `## Comments` heading.

## Working the tickets

`/next-task` is how tickets get implemented here: it picks from `🟡 To do`,
verifies, records the task in `✅ Done` and proposes a commit. Do not use the
`implement` skill in this repository: it ends by committing, and only the
owner commits.

## When a skill says "publish to the issue tracker"

- A single ticket: add a task line to `🤖 Agent recommendations`, or to
  `🟡 To do` when the owner asked for the task.
- A spec (`to-spec`): write `.scratch/<feature-slug>/spec.md` (creating the
  directory), then add one task line pointing at it.
- Tickets cut from a spec (`to-tickets`): one task line per ticket, in
  implementation order, each pointing at the spec. No per-ticket files.

## When a skill says "fetch the relevant ticket"

Find the line in `TODO.md` the owner names (by its words or its position) and
follow its `spec:` pointer when it has one.

## Wayfinding operations

Used by `/wayfinder`. Its tickets need more state than a `TODO.md` line holds,
so they live in files; `TODO.md` gets a single line for the effort:
`- [ ] CHORE: wayfinder <effort> — map: .scratch/<effort>/map.md`.

- **Map**: `.scratch/<effort>/map.md` (the Notes / Decisions-so-far / Fog body).
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from
  `01`, with the question in the body. A `Type:` line records the ticket type
  (`research`/`prototype`/`grilling`/`task`); a `Status:` line records
  `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked
  when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open,
  unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set
  `Status: resolved`, then append a context pointer (gist + path) to the map's
  Decisions-so-far in `map.md`.
