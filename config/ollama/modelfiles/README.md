# modelfiles

Custom models built on top of a base model, one `<name>.Modelfile` per file.
`ollama-bootstrap` runs `ollama create <name> -f <name>.Modelfile` for each,
after pulling everything in `../models.txt`.

Empty for now — the AI tooling drives sampling per request (`options.temperature`,
`options.num_ctx`, …) rather than baking it into a derived model, so nothing here
is needed yet. See `config/ai-tools/README.md`.

A Modelfile earns its place when a setting has to follow the model everywhere,
including for clients that do not send options of their own — a system prompt,
for instance.

```
FROM qwen3.5:9b
PARAMETER temperature 0.3
SYSTEM """You are …"""
```

Note the base model must also be listed in `../models.txt`: `ollama create` does
not pull what it builds from.
