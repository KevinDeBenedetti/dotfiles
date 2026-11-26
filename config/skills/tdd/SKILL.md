---
name: tdd
description: Test-driven development - one failing test, then the least code that passes it, at seams agreed first. Use when building a feature or fixing a bug in a project that has a test suite, or when the owner asks for test-first, red-green or integration tests.
---

# Test-driven development

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

The loop is red, then green. This skill is what makes the loop leave tests
worth keeping. Read `GLOSSARY.md` when the project has one, so test names use
its vocabulary.

## Seams first

A **seam** is the public interface where behaviour is observed without
reaching inside. Before the first test, list the seams under test, each with
one line on what it catches and what it misses, and confirm the list with the
owner (in an unattended run: state it and carry on). Tests go at those seams
only: effort lands on the critical paths and the complex logic. When the shape
of the interface is itself the question, load the `codebase-design` skill for
its vocabulary.

## The loop

- **Red before green.** Write one failing test and run it: it fails, for the
  reason you expect. Then write the least code that passes it.
- **One vertical slice per cycle.** One seam, one test, one implementation.
  The next test answers what the last cycle taught you.
- **Use the project's own runner**, the command its `AGENTS.md`, `Makefile`
  or manifest gives: the single test file during the loop, the whole suite
  once at the end.
- **Restructuring waits** for the review (`code-review`), outside the loop.

## A test worth keeping

It states a behaviour through the public interface ("an expired token is
refused"), and survives a rewrite of the internals. See
[tests.md](./tests.md) for examples and for when to mock.

Three shapes to rewrite on sight:

- **Coupled to the implementation**: it mocks an internal collaborator, calls
  a private function or checks through a side channel. It breaks on a
  refactor that changed no behaviour.
- **Tautological**: the expected value is computed the way the code computes
  it, so the two can never disagree. Expected values come from a literal, a
  worked example or the spec.
- **Written in bulk**: every test first, then every implementation. Those
  tests describe imagined behaviour.
