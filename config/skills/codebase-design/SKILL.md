---
name: codebase-design
description: Vocabulary and principles for designing deep modules - module, interface, seam, adapter, depth. Use when shaping or reshaping a module or its interface, deciding where a seam goes, making code easier to test, or when another skill needs these terms.
---

# Codebase design

<!-- Adapted from mattpocock/skills (MIT). Notice: config/skills/NOTICE.md in
     the dotfiles repository. Edit it there only. -->

Design **deep** modules: much behaviour behind a small interface, at a clean
seam, tested through that interface. This is a reference to consult while
designing, not a session to run.

## Terms

Use them as defined, every time.

- **Module**: anything with an interface and an implementation, at any scale
  (a function, a script, a package).
- **Interface**: everything a caller must know to use the module correctly:
  the signature, and also the invariants, the ordering, the error modes, the
  required configuration.
- **Depth**: how much behaviour a caller gets per unit of interface learned.
  Deep: a small interface over a lot of behaviour. Shallow: an interface
  nearly as complex as what it hides.
- **Seam**: the place where a module's interface lives, and where behaviour
  can be swapped without editing the callers.
- **Adapter**: a concrete thing that satisfies an interface at a seam.
- **Leverage**: what callers gain from depth. **Locality**: what maintainers
  gain, as change, bugs and knowledge stay in one place.

## Principles

- **The interface is the test surface.** Callers and tests cross the same
  seam. A test that has to reach past the interface says the module has the
  wrong shape.
- **The deletion test.** Imagine the module gone. Complexity vanishes: it was
  a pass-through. Complexity reappears in every caller: it earns its place.
- **Two adapters make a seam real.** With a single one the seam is a guess:
  add it when something actually varies there.
- **Depth belongs to the interface.** A deep module may be built of small
  parts; they stay private to it.

## Shaping an interface

Ask, in this order: can it have fewer entry points; can each take simpler
arguments; can more of the complexity move behind it?

For testability:

1. take dependencies as arguments (or environment, or `PATH`) instead of
   creating them inside;
2. return a result instead of changing something elsewhere;
3. keep the surface small: fewer entry points, fewer tests to write.

When the interface is still open, sketch two or three clearly different
shapes and compare them on depth, locality and where the seam falls, before
writing the code.
