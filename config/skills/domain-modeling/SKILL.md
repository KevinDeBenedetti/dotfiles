---
name: domain-modeling
description: Build and sharpen a project's domain language - challenge terms, settle them in GLOSSARY.md, record hard-to-reverse decisions as ADRs. Use when a change names or redefines a concept, when terminology is unclear or disputed, or when writing or editing a GLOSSARY.md or an ADR.
---

# Domain modeling

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

The active discipline: changing the model, not only reading it. Reading
`GLOSSARY.md` for vocabulary is a habit of every skill and does not need this
one.

## Files

`GLOSSARY.md` and `docs/adr/` at the repository root; a `GLOSSARY-MAP.md`
there means several contexts, each with its own glossary. The project's
`docs/agents/domain.md` wins when it says otherwise. Create a file only when
there is something to write in it.

## While designing

- **Challenge against the glossary.** A term used against its definition is
  called out at once: "the glossary says a cancellation is X; you mean Y?"
- **Sharpen vague words.** Offer one precise term for an overloaded one:
  "account: the customer, or the user?"
- **Test with scenarios.** Invent concrete edge cases that force a line
  between two concepts.
- **Check against the code.** When what the owner says and what the code does
  differ, say which lines disagree and ask which is right.

## GLOSSARY.md

Update it the moment a term is settled. One entry per term:

```markdown
## Order

A customer's confirmed request for one or more items.

_Avoid_: purchase, basket (a basket is not confirmed yet).
```

A glossary holds definitions and the words to avoid: no implementation
detail, no plan, no decision record.

## ADRs

Offer one only when the decision is all three: **hard to reverse**,
**surprising without its context**, and **the result of a real trade-off**.
Number it after the last one (`docs/adr/0003-<slug>.md`):

```markdown
# 3. <the decision, as a statement>

## Context

<the forces at play, and the alternatives that were real>

## Decision

<what was chosen>

## Consequences

<what becomes easier, what becomes harder>
```

A change that contradicts an existing ADR says so, and why it is worth
reopening. Pages under `docs/` of the owner's repositories also follow the
`docs-hub` skill.
