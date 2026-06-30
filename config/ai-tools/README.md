# ai-tools

Centralized config + helpers for the local AI tooling (`scripts/ai/*`), talking
to Ollama over its HTTP API. Sourced, never executed:

```sh
source "${XDG_CONFIG_HOME:-$HOME/.config}/ai-tools/config.sh"
```

| File        | Role                                                             |
| ----------- | --------------------------------------------------------------- |
| `config.sh` | Defaults (`AI_HOST`, `AI_MODEL`, …) + `ai_run` / `ai_require_deps` helpers |

Override any `AI_*` default via the environment.

## Commit types ↔ release-please (source of truth)

`scripts/ai/git-aicommit` generates **Conventional Commits** messages. The set of
types it may emit is dictated by the **release-please** configuration that cuts
my releases — the source of truth lives in the **`github-workflows`** repo at
`.github/release/release-please-config.json` (mirrored here for this repo at the
same path).

That config uses `release-type: "simple"` with **no custom `changelog-sections`**,
so release-please falls back to its **default Conventional Commits parser**. The
practical consequences the prompt is built around:

| Type                                   | Release effect            | Changelog |
| -------------------------------------- | ------------------------- | --------- |
| `feat`                                 | minor                     | shown (Features) |
| `fix`                                  | patch                     | shown (Bug Fixes) |
| `perf`                                 | patch                     | shown |
| `deps`, `revert`, `docs`, `style`, `chore`, `test`, `build`, `ci` | none | hidden |
| `refactor`                             | **never emitted**         | — |

`refactor` is deliberately **excluded** from the types `git-aicommit` may suggest:
the config does not surface it, so a pure code refactor with no user-facing effect
is committed as `chore` instead. The prompt in `scripts/ai/git-aicommit` is the
implementation of this policy; `tests/ai/git-aicommit.bats` guards it against
regression.

When the release-please config changes (e.g. a custom `changelog-sections` block
is added), update the type list and grouping in `scripts/ai/git-aicommit`'s prompt
to match — they must stay in sync with this source of truth.
