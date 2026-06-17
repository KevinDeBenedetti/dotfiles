# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] CHORE: Passer `app-client-id` + secret `APP_PRIVATE_KEY` au job release (GitHub App déjà dispo via DOCS_APP_*) — le `GITHUB_TOKEN` par défaut ne déclenche pas la CI sur la PR de release et peut buter sur le gate d'approbation manuelle

## 🟢 Idées / backlog

## 🤖 Claude — recommandations





## ✅ Fait
- [x] 2026-06-17 — FEAT: Messages de commit générés par Claude — `todo-commit.sh` appelle le CLI `claude -p` (mode headless, `--strict-mcp-config` pour rester léger) sur la section ✅ Fait pour produire un message Conventional Commits propre, avec repli déterministe si Claude est indispo/hors-ligne (`TODO_COMMIT_NO_AI` / `_CLAUDE_MODEL` / `_AI_TIMEOUT`) ; conserve strip + re-stage de TODO.md ; sous-commande `ai` + tests ; README mis à jour. (NB : un hook *git*, pas un hook Claude — ces derniers ne s'exécutent pas sur un `git commit` terminal)
- [x] 2026-06-17 — FIX: Gérer le cas `git commit <pathspec>` / `-o` dans todo-commit.sh — détection de l'index temporaire via `GIT_INDEX_FILE` (`is_temp_index`) ⇒ le hook devient un no-op (pas de pré-remplissage ni de strip) plutôt que de laisser le strip orphelin dans le working tree ; 3 tests `hook` ajoutés (full/partial/-m) dans tests/todo-commit.bats
- [x] 2026-06-17 — DOCS: Documenter le hook `todo-commit-msg` dans le README — nouvelle section « Git hooks (prek) » (install prek, comportement du hook prepare-commit-msg, génération du message depuis ✅ Fait + strip/re-stage, garde-fous, caveat pathspec)
- [x] 2026-06-17 — FEAT: Releases via release-please — appelle le workflow réutilisable `github-workflows/release.yml@main` depuis ci-cd.yml (push sur main) ; config/manifest dans `.github/release/` (release-type `simple`, manifest seedé à `0.0.0` ⇒ première release `v0.1.0`, bump-minor-pre-major) ; couverture configs.bats
- [x] 2026-06-17 — FEAT: Hook `prepare-commit-msg` (`scripts/todo-commit.sh` + prek) — pré-remplit l'éditeur de commit avec un message conventionnel construit depuis la section ✅ Fait de TODO.md, puis supprime ces entrées et re-stage TODO.md ; couverture bats (tests/todo-commit.bats)
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
