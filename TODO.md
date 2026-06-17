# TODO

## 🔴 En cours

## 🟡 À faire
- [ ] REFACTOR: nettoie le commentaire/réglage VSCode obsolète (`prepare-commit-msg` / `git.useEditorAsCommitInput`, settings.json:43-45) — le hook a été supprimé (géré par le skill `/commit`)
- [ ] CHORE: pin l'image de test `debian:bookworm-slim` par digest et l'installeur oh-my-zsh par tag dans `tests/docker/Dockerfile.test` — builds reproductibles
- [ ] TEST: ajoute un test (bats ou CI grep) qui échoue si un chemin absolu `/Users/<name>` est commité dans config/ — empêche la réintroduction de valeurs en dur
- [ ] FIX: ajoute `set -euo pipefail` aux scripts `os/*/setup-*.sh` (surtout `setup-security.sh`) — ils tournent en root et avalent silencieusement les échecs (curl|gpg, apt) car `set -e` du parent `init.sh` ne propage pas aux sous-shells
- [ ] FIX: garde la version k9s dans `os/debian/setup-kubernetes.sh:66` — si l'API GitHub échoue, `K9S_VERSION` vide → URL `download//k9s...` et `dpkg -i` cassés
- [ ] CHORE: pin les workflows réutilisables `KevinDeBenedetti/github-workflows/...@main` vers un tag/SHA — branche mutable injectée dans un pipeline avec `contents: write` + `secrets: inherit`
- [ ] CHORE: remplace `secrets: inherit` (job `security` de ci-cd.yml) par une allow-list explicite des secrets réellement consommés — moindre privilège
- [ ] CHORE: ajoute un `permissions: { contents: read }` par défaut au top-level de ci-cd.yml (le job `ci` n'en déclare aucun) — les autres jobs élargissent déjà au besoin
- [ ] CHORE: pin les versions dans `config/proto/.prototools` (bun/node/npm/pnpm/yarn en `latest` + `auto-install` = toolchain non reproductible) ; laisse Renovate les bumper
- [ ] FIX: utilise `read -r` et `printf` au lieu de `echo "\n"`/`read -p "\n"` dans `os/macos/init.sh:139-154` — SC2162 + échappements non portables
- [ ] CHORE: pin `npx shadcn@latest` dans `config/vscode/mcp.json` à une version figée — exécuté en auto-start MCP
- [ ] CHORE: envisage de sortir l'IP VPN privée `10.8.0.1` (config/claude/settings.json + managed-settings.json) vers une valeur locale non commitée — détail d'infra perso dans un repo public (LOW, RFC1918, non routable)

## 🟢 Idées / backlog

## 🤖 Claude — recommandations


## ✅ Fait
