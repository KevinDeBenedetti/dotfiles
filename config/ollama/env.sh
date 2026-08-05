# shellcheck shell=bash
# shellcheck disable=SC2034  # assignments-only by design; consumed by ollama-setenv
# env.sh — Ollama server settings. Single source of truth for the values.
#
# Sourced, never executed. `ollama-setenv` reads this file and replays every
# OLLAMA_* assignment through `launchctl setenv`; the LaunchAgent in launchd/
# runs that script at login so the settings survive a reboot.
#
# Why not ~/.zshrc: Ollama runs here as the macOS menu-bar application, started
# by launchd, which never reads a login shell's rc files. An `export` there is
# silently ignored. `ollama serve` in a terminal is the only case where it works.
#
# Every variable below is documented in Ollama's own envconfig/config.go.
# Do not add one without checking it there first.
#
# The server reads its environment ONCE, at startup: quit and reopen Ollama.app
# after changing anything here.

# Maximum number of models resident at the same time. Decisive on 16 GB of
# unified memory, which is shared with macOS: a second resident model is what
# pushes the first out of the GPU and into a crawl. One at a time.
OLLAMA_MAX_LOADED_MODELS=1

# Default context when a request does not specify one. Ollama otherwise picks
# 4k, 32k or 256k based on available VRAM, and this machine lands on the 4k
# tier — the very ceiling the AI tooling had to work around before it started
# sending options.num_ctx. Setting it here fixes it for every other Ollama
# client too, not just scripts/ai/*.
OLLAMA_CONTEXT_LENGTH=16384

# Flash attention. Already enabled automatically on Metal (Ollama resolves it to
# "auto" when unset and the backend supports it), so this is not a speed-up —
# it is here because K/V cache quantization below requires it, and pinning it
# makes that dependency explicit rather than incidental.
OLLAMA_FLASH_ATTENTION=1

# K/V cache quantization. The real memory lever at this context size: q8_0 uses
# about half the memory of the f16 default, and Ollama's FAQ describes the
# precision loss as "very small […] usually no noticeable impact on the model's
# quality". q4_0 would halve it again but degrades noticeably at long contexts.
# Applies globally to every model.
OLLAMA_KV_CACHE_TYPE=q8_0

# How long a model stays resident after its last request. 5m is Ollama's own
# default, kept deliberately: shorter frees memory sooner but pays the reload
# cost on every `ai commit`, and a 9b model takes seconds to load.
OLLAMA_KEEP_ALIVE=5m
