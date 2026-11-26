---
name: writing-for-agents
description: Reference for writing a document an agent reads - a skill, an AGENTS.md or CLAUDE.md, a doc reached from one. Use when creating, editing or reviewing a SKILL.md, AGENTS.md, CLAUDE.md, a prompt or a hook's context message.
---

# Writing for agents

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

The same levers make any agent-facing document predictable. When the document
is a skill, read [skill-mechanics.md](./skill-mechanics.md) too: frontmatter,
invocation, and where shared material goes.

## Pointers

A **pointer** is a line the agent always has in context that names material it
does not: a skill's description, a line of `AGENTS.md` naming a doc. Its
wording, not its target, decides when the agent goes and reads.

- Say what the material is, then the distinct cases that should trigger it.
- One trigger per case: two words for the same case are one case written
  twice.
- Lead with the word the owner actually uses in their prompts.

## Two budgets

- **Context load**: what sits in the window on every turn (`AGENTS.md`, each
  skill description). Every line there is paid whether or not it is used.
- **Cognitive load**: what the owner must remember exists (a user-invoked
  skill, a doc nothing points to).

Material behind a pointer costs the pointer's line only.

## Where a piece goes

1. **A step in the file**: what the agent does, in order.
2. **Reference in the file**: rules and definitions it consults while doing
   it.
3. **Reference in a file beside it**, behind a pointer: what only some runs
   need.

Inline what every run needs; move out what only one case reaches. Keep a
concept's definition, rules and caveats under one heading.

## Steps end on a criterion

Each step ends on a condition the agent can check: "every modified file
listed", "the command printed `0 failed`". A vague one ("once understood")
lets the step end early. A demanding one ("every", "each") makes the agent do
the legwork.

## Wording

- **State the target.** "Write one-line comments" works where a ban on long
  comments half-reads as a reminder of them. Keep a prohibition for a hard
  guardrail, next to what to do instead.
- **One word per concept**, used every time (*seam*, *red*, *tight*). Prefer
  a word the model already knows to one you must define.
- **One source of truth.** A rule lives in one file; the others point to it.
- **Leave lookups to the environment.** Scripts, config keys and `--help`
  output are read where they live. Write down what cannot be found by
  looking: the convention, the reason, the trap.
- **Delete what changes nothing.** A sentence the agent already follows by
  default is removed whole.

## Check

Done when: every step has a checkable end; every line bears on what the
document does; no rule is stated twice; and you have run the document on a
real task once and read what the agent did with it.
