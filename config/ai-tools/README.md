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

## Settings

| Variable        | Default                | Role |
| --------------- | ---------------------- | ---- |
| `AI_HOST`       | `http://localhost:11434` | Ollama HTTP endpoint |
| `AI_MODELS`     | *(empty → automatic)*  | Ordered preference list of model names |
| `AI_MODELS_FAST`| *(empty → automatic)*  | Same, for the lighter model |
| `AI_MAX_MODEL_GB` | `8`                  | Size ceiling for automatic selection |
| `AI_MODEL`      | *(selected)*           | Pinning it bypasses selection entirely |
| `AI_MODEL_FAST` | *(selected)*           | Lighter / faster model |
| `AI_MAX_DIFF`   | `6000`                 | Max diff **bytes** sent to the model |
| `AI_TIMEOUT`    | `120`                  | `curl --max-time`, in seconds |
| `AI_NUM_CTX`    | `16384`                | Context window in **tokens** (`options.num_ctx`) |
| `AI_TEMPERATURE`| `0.3`                  | Sampling temperature |
| `AI_PRESENCE_PENALTY` | `0`              | Penalty on already-seen tokens |
| `AI_THINK`      | `false`                | Suppress reasoning; empty drops the field entirely |

## Model selection

**No model name is hardcoded**, and `tests/ai/config.bats` enforces it by
matching the *shape* of an Ollama tag (`name:9b`) in the non-comment lines of
`config.sh`. This file is tracked and shared; a model list is a per-user, often
per-machine choice.

Ollama already knows what exists and what each model can do, so nothing needs
declaring:

| Question | Answered by |
| -------- | ----------- |
| Which models are installed, and how big? | `/api/tags` |
| Can this one generate text? Can it think? | `/api/show` → `capabilities` |

Both are metadata endpoints: ~10 ms, and `ollama ps` confirms they load nothing.

### Order of precedence

1. **`AI_MODEL`** — an explicit pin. Taken at face value, no listing, no size
   check. `AI_MODEL_FAST` falls back to the same model, and `AI_THINK` is still
   detected from capabilities.
2. **`AI_MODELS`** — an ordered preference list of tags; the first one installed
   wins, and `AI_MAX_MODEL_GB` is ignored because an explicit choice is not
   second-guessed. This is the normal place to express a preference:

   ```sh
   # ~/.config/dotfiles/env.local.sh  (untracked)
   export AI_MODELS="qwen3.5:9b qwen2.5-coder:7b"
   ```
3. **Automatic** — the largest installed model that can generate and fits
   `AI_MAX_MODEL_GB`. Models without the `completion` capability are skipped:
   embedding models install like any other, and picking one would fail at
   generation time with a baffling error.

`AI_MODEL_FAST` follows the same ladder via `AI_MODELS_FAST`, defaulting to the
*smallest* model that can generate.

Deleting a model therefore degrades to the next candidate instead of leaving a
dangling default — which is exactly what `AI_MODEL_FAST=qwen2.5-coder:1.5b`
became the day that model was removed. When nothing matches, the error names the
`ollama pull` command to run.

`ai models` shows the outcome and how it was reached.

### Selection is lazy

`config.sh` is sourced by every script, `ai help` included; resolving at source
time would make all of them depend on a running Ollama. It happens on the first
real call instead, inside `ai_run`, and is memoised for the process.

### `AI_MAX_MODEL_GB`

Ceiling for *automatic* selection only, in decimal GB of on-disk size. Default 8
suits 16 GB of unified memory, where roughly 10.6 GB is usable as VRAM and the KV
cache has to fit alongside the weights. Machine-specific — override it per host
in `env.local.sh`.

### `AI_NUM_CTX`

Ollama defaults to a **4096-token** context regardless of what the model
supports. At `AI_MAX_DIFF=6000` bytes the diff alone is ~1.5–2k tokens and the
`git-aicommit` prompt is ~700 more, so the ceiling was close enough to silently
clip the tail of a large staged diff. Raising `AI_MAX_DIFF` without raising this
does nothing but truncate. Check what actually got loaded with `ollama ps` —
the `CONTEXT` column reflects this value.

Cost: KV-cache memory. On 16 GB of unified memory keep `AI_NUM_CTX` ≤ 16384 for
a 7–12b model, and confirm `ollama ps` still shows `100% GPU` — any `CPU` share
in that column means it spilled and generation will crawl.

### `AI_TEMPERATURE`

Sent explicitly rather than left to the model's own default, which is tuned for
chat and runs hot — qwen3.5 ships `temperature=1`, and at that setting it drifts
off the format the prompts pin down (headers past 72 chars, `*` bullets where the
prompt asks for `- `). These tools want a structured artifact, so the default
biases hard towards instruction-following. Raise it for prose.

### `AI_PRESENCE_PENALTY`

Pinned to `0`, and sent even at that value, because the model's own setting fights
these prompts head-on. qwen3.5 ships `presence_penalty=1.5`, but a commit body is
*meant* to repeat itself — every bullet opens with the same `- ` prefix. Penalised
that hard, the model abandons the list format and writes paragraphs instead.

This is independent of `AI_TEMPERATURE`: observed on qwen3.5:9b, dropping the
temperature to `0.3` fixed an over-long header but the bullets stayed gone until
the penalty was neutralised.

### `AI_THINK`

Defaults to `false` because the default `AI_MODEL` (qwen3.5) is thinking-capable,
and these tools want a terse artifact, not a monologue — the reasoning pass is
pure latency here.

Ollama rejects a `think` field outright on models *without* the capability, so
**emptying** the variable (`AI_THINK=`) drops the key from the payload entirely.
That is the escape hatch when pointing `AI_MODEL` at a non-thinking model such as
qwen2.5-coder. Check with `ollama show <model>`, which lists `thinking` among the
capabilities when it applies.

Independently of this flag, `ai_run` strips a `<think>…</think>` block from the
reply, since some models inline reasoning into `.response` rather than the
separate `.thinking` field. Without that, the reasoning lands verbatim in a
commit message.

The matcher is deliberately narrow — **only** a block that opens the response and
is properly closed is removed. Reasoning is always emitted first, never mid-answer,
so a tag further in is prose: a commit message describing `ai_strip_thinking`
itself legitimately contains the literal `<think>`, and a looser matcher truncated
the message at that point. An unclosed leading tag is left alone as well; that
response is degenerate either way, and returning it visibly beats silently
returning nothing.

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
