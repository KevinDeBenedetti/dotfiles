# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] CHORE: Passer `app-client-id` + secret `APP_PRIVATE_KEY` au job release (GitHub App déjà dispo via DOCS_APP_*) — le `GITHUB_TOKEN` par défaut ne déclenche pas la CI sur la PR de release et peut buter sur le gate d'approbation manuelle

## 🟢 Idées / backlog

## 🤖 Claude — recommandations
- [ ] CHORE: Garder le `rev` github-workflows à jour dans prek.toml (commentaire `renovate:` en place) — actuellement `v0.17.0`, plus que `check-docs-links` consommé
- [ ] CHORE: Désinstaller le hook git `prepare-commit-msg` devenu inutile : `prek install` (régénère selon default_install_hook_types) ou `prek uninstall -t prepare-commit-msg`

## ✅ Fait
