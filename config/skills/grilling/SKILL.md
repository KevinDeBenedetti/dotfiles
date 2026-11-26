---
name: grilling
description: Interview the owner about a plan, a decision or a request until nothing is left assumed - numbered questions in rounds, each with a recommended answer. Use when a request leaves decisions open, when the owner asks to be grilled or to stress-test or challenge a plan, or before a design is turned into work.
---

# Grilling

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

Interview the owner until you share one understanding of the plan. Treat it as
a **design tree**: each decision opens the decisions that hang off it.

Work in **rounds**. The **frontier** is every decision whose prerequisites are
settled: what you can ask now without guessing an answer you have not heard.
Ask the whole frontier in one round, then wait.

```text
❓ **Q1 — <title>**: <the question, with its options when there are some>

➡️ <your recommended answer, and why in one line>

---

❓ **Q2 — <title>**: …
```

- Word each question so that "yes" accepts your recommendation.
- A question that depends on another one of the same round belongs to a later
  round.
- Facts are yours to find: read the code, the docs and the configuration
  (with a sub-agent on a fresh context when the tool has them) instead of
  asking. Decisions are the owner's: put each one to them.
- Ask in the owner's language. Use the project's vocabulary (`GLOSSARY.md`).
- After each round, recompute the frontier from the answers.

Done when the frontier is empty: every branch visited, nothing assumed. Sum up
the decisions in a short list and wait for the owner to confirm it before
acting on it. A caller that asks for a single round (`next-task`,
`next-issue`) gets one round, then carries on with the answers.
