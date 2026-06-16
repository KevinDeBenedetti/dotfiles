# TODO

## 🔴 En cours

## 🟡 À faire

## 🟢 Idées / backlog
- [ ] FEAT: replace all master branches with main

## 🤖 Claude — recommandations

## ✅ Fait
- [x] 2026-06-17 — FIX: Code-review fixes — replace no-op extglob `.env.!(example)` deny with working `**/.env.*` in settings + managed (was silently NOT denying `.env.local`/`.env.production`); drop dead `.env.example` allow entries (deny-wins precedence); remove `env`/`printenv` from allow (dumped secrets unprompted); update configs.bats accordingly
- [x] 2026-06-17 — CHORE: Move `github-workflows/.github/workflows` out of tracked `additionalDirectories` (now `[]`) into machine-local `~/.claude/settings.local.json`; add configs.bats guards (empty additionalDirectories + no `/Users/` paths)
- [x] 2026-06-17 — FIX: Unify `.env` deny patterns across settings.json & managed-settings.json (use `.env.!(example)` + add `*.env` triple + sandbox `.env.example` carve-out in managed); add configs.bats regression tests
- [x] 2026-06-17 — CHORE: Remove portfolio-specific paths from global `config/claude/settings.json` (Read glob + `additionalDirectories` entry); add configs.bats guard against hardcoding the portfolio repo
- [x] 2026-06-17 — FEAT: Audit Claude Code config — broaden global allowlist for non-critical commands (safe shell/text/hash/clipboard utils) while keeping git push/commit, rm, terraform apply denied/ask; add configs.bats coverage
- [x] 2026-06-17 — TEST: Add vpn() coverage in tests/functions.bats (export + help/no-arg/missing-tunnel/unknown-subcommand)
- [x] 2026-06-17 — FIX: Remove unused casks soulseek & transmission (not installed) from os/macos/setup-extras.sh + docs
- [x] 2026-06-17 — FEAT: Add docker compose aliases (`dc`, `dcu`, `dcd`, `dcl`) in .zshrc
- [x] 2026-06-17 — FEAT: Add `brewsuggest` command — curated Homebrew CLI tools with installed/missing status and an install command
- [x] 2026-06-16 — FEAT: Add macOS cleanup command (`cleanmac`: caches/logs/trash/brew/dns) — safe dry-run by default, `--yes` to apply
- [x] 2026-06-16 — FEAT: Add ansible & terraform to the install list (macOS via brew; Debian via apt + HashiCorp repo) — covered by docker test-base
- [x] 2026-06-16 — FEAT(URGENT): Add CLAUDE config (commands: `/next-task`, `/audit`, `/explain`, `/debug-action`) linked into `~/.claude/commands/`
