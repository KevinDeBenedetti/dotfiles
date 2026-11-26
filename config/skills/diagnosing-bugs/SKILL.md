---
name: diagnosing-bugs
description: Diagnosis loop for a bug or a performance regression - build one command that goes red on the bug, minimise it, rank falsifiable hypotheses, probe one variable at a time, then fix behind a regression test. Use when something is reported broken, failing, throwing, flaky or slow, before changing any code to fix it.
---

# Diagnosing bugs

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

A discipline for bugs whose cause is not known yet. The phases run in order;
skip one only with a stated reason. Read `GLOSSARY.md` and the ADRs of the
area first when the project has them.

Everything shown here (commands, output, captured artifacts) is redacted
first: `<REDACTED>` in place of each secret, credentials left in the
environment, only the lines that carry the signal quoted.

## 1. Build a red loop

The loop is the skill: one command that goes **red** on this bug and green
once it is fixed. With it, every later phase is mechanical; without it,
reading code only produces theories. Spend the effort here.

Ways to get one, cheapest first:

1. a failing test at the seam that reaches the bug;
2. a `curl` or CLI call on a fixture, its output diffed against a known-good
   one;
3. a replayed capture (request, payload, event log) through the code path;
4. a throwaway harness that calls the code path with the rest stubbed;
5. a loop over many inputs, for "sometimes wrong";
6. `git bisect run` on the command, when the bug sits between two known
   states;
7. a script that drives the owner through the manual steps, as a last resort.

Then make it **tight**: seconds to run, the same verdict every run, asserting
the reported symptom and nothing looser. For a flaky bug the target is a high,
stable reproduction rate: repeat the trigger, add load, narrow the timing.

Done when you have run the command, shown it and its output, and it fails on
the symptom the owner reported. No such command after a real attempt: stop,
list what you tried, and ask for what would make one possible (access to the
environment that reproduces it, a redacted capture, temporary
instrumentation). No hypothesis before the loop exists.

## 2. Minimise

Cut inputs, callers, config and steps one at a time, re-running the loop after
each cut. Done when removing any remaining element turns the loop green.

## 3. Hypothesise

Write three to five hypotheses, ranked, before testing any. Each one states
its prediction: "if X is the cause, changing Y makes the loop green". One
that predicts nothing is dropped. Show the list to the owner, who may re-rank
it at a glance, and carry on with your order when they are away.

## 4. Probe

One variable per probe, each probe tied to one prediction. Prefer a debugger
or REPL; otherwise targeted logs at the boundary that separates two
hypotheses, every line tagged with one unique prefix (`[DEBUG-a4f2]`). For a
performance regression, measure a baseline first, then bisect.

## 5. Fix behind a regression test

1. Turn the minimised repro into a failing test at a seam that exercises the
   bug as it happens at its call site. Watch it fail.
2. Apply the fix. Watch it pass.
3. Re-run the loop of phase 1 on the original, un-minimised scenario.

No seam reaches the bug: say so. That is a finding about the code's design
(`codebase-design`), reported with the fix, and no shallow test stands in.

## 6. Clean up

Done when all of these hold:

- the phase 1 loop is green on the original scenario;
- the regression test passes, or the missing seam is reported;
- `grep` finds no line with the debug prefix;
- throwaway harnesses are deleted;
- the commit message you hand over names the cause that proved right.
