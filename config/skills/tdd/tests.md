# Tests worth keeping

Reference for the `tdd` skill: what a good test looks like, and when a mock
is the right tool.

## Behaviour, through the interface

```text
good   "checkout with a valid cart creates one order"
       calls checkout(cart), asserts on what it returns and on what the
       public interface shows afterwards

bad    "checkout calls paymentClient.charge once"
       asserts on a call between two internals; a rewrite that still creates
       the order breaks it
```

- Name the test after the capability, in the project's own vocabulary.
- Arrange through the public interface too: build state the way a caller
  would, not by writing rows or files the module owns.
- One reason to fail per test. A second assertion earns its place when it is
  part of the same behaviour.
- A shell script is tested the same way: run it against a throwaway `HOME` or
  directory and assert on its output, exit status and the files it leaves.

## Mocking

Mock at the edge of the system, where the code meets what you do not own or
cannot run in a test: the network, the clock, randomness, a paid API, another
team's service.

- Keep your own modules real. A test that mocks the module next door tests
  the mock.
- Prefer a fake that behaves (an in-memory store, a stub binary on `PATH`, a
  local HTTP server) to a mock that records calls.
- Give the dependency to the code (an argument, an environment variable, a
  `PATH` entry) instead of patching it in from the test.
- A test that needs more than one or two mocks is pointing at a seam in the
  wrong place: see the `codebase-design` skill.
