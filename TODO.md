# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] FEAT: ajoute message pre commit avec claude + purge de todo au commit & push
- [ ] CHORE: Passer `app-client-id` + secret `APP_PRIVATE_KEY` au job release (GitHub App déjà dispo via DOCS_APP_*) — le `GITHUB_TOKEN` par défaut ne déclenche pas la CI sur la PR de release et peut buter sur le gate d'approbation manuelle

## 🟢 Idées / backlog

## 🤖 Claude — recommandations
- [ ] TEST: Vérifier en réel le hook `ai-commit-msg` (consommé depuis github-workflows) par un commit dans dotfiles — non testable en sandbox (réseau bloqué)
- [ ] CHORE: Suivre les releases de github-workflows et bumper le `rev` épinglé dans prek.toml quand `ai-commit-msg` est inclus dans un tag (actuellement épinglé sur un SHA hors-tag)

## ✅ Fait
- [x] 2026-06-17 — REFACTOR: Consolidation des hooks de message de commit sur github-workflows — prek.toml consomme `ai-commit-msg` (épinglé au SHA `6253c93`) ; suppression des scripts locaux `scripts/todo-commit.sh` + `scripts/ai-commit-msg.sh`, du `.pre-commit-hooks.yaml` (provider), des tests associés et du hook prek local ; configs.bats et README mis à jour
- [x] 2026-06-17 — FEAT: Hook de commit IA réutilisable pour tous les repos — `scripts/ai-commit-msg.sh` (prepare-commit-msg générique, diff-driven via `claude -p`, fail-open : no-op si message présent/rien stagé/claude indispo) exposé en hook prek via `.pre-commit-hooks.yaml` (id `ai-commit-msg`) ⇒ dotfiles devient un provider prek réutilisable depuis n'importe quel repo ; env `AI_COMMIT_NO_AI`/`_MODEL`/`_TIMEOUT`/`_MAX_CHARS` ; tests tests/ai-commit-msg.bats + guards configs.bats ; README + mapping vers github-workflows
