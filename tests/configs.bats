#!/usr/bin/env bats

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'
}

# --- Config files ---

@test "config/git/.gitconfig exists" {
  assert_file_exists "$CONFIG_DIR/git/.gitconfig"
}

@test "config/zsh/.zshrc exists" {
  assert_file_exists "$CONFIG_DIR/zsh/.zshrc"
}

@test "config/proto/.prototools exists" {
  assert_file_exists "$CONFIG_DIR/proto/.prototools"
}

@test "config/oh-my-zsh theme exists" {
  assert_file_exists "$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme"
}

@test "config/shell/env.sh exists" {
  assert_file_exists "$CONFIG_DIR/shell/env.sh"
}

@test "config/shell/functions.sh exists" {
  assert_file_exists "$CONFIG_DIR/shell/functions.sh"
}

@test "the configs links.sh links, and no other test names, exist" {
  local f
  for f in copilot/hooks/agent-guard.json ollama/launchd/local.ollama-env.plist \
           opencode/opencode.json ssh/config claude/commands/debug-action.md \
           claude/commands/explain.md; do
    assert_file_exists "$CONFIG_DIR/$f"
  done
}

@test "config/vscode/settings.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/settings.json"
}

@test "config/vscode/mcp.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/mcp.json"
}

@test "config/vscode/extensions.json exists" {
  assert_file_exists "$CONFIG_DIR/vscode/extensions.json"
}

@test "config/git/ignore exists" {
  assert_file_exists "$CONFIG_DIR/git/ignore"
}

@test "git global ignore covers claude settings.local.json" {
  run grep -q 'settings.local.json' "$CONFIG_DIR/git/ignore"
  assert_success
}

@test "config/claude/settings.json exists" {
  assert_file_exists "$CONFIG_DIR/claude/settings.json"
}

@test "claude settings.json is valid JSON" {
  run jq empty "$CONFIG_DIR/claude/settings.json"
  assert_success
}

@test "config/claude/managed-settings.json exists" {
  assert_file_exists "$CONFIG_DIR/claude/managed-settings.json"
}

@test "claude managed-settings.json is valid JSON" {
  run jq empty "$CONFIG_DIR/claude/managed-settings.json"
  assert_success
}

@test "claude managed settings keep git commit/push denied" {
  run jq -e '.permissions.deny | index("Bash(git push)")' "$CONFIG_DIR/claude/managed-settings.json"
  assert_success
}

@test "claude settings allow common non-critical commands" {
  for cmd in "Bash(ls *)" "Bash(grep *)" "Bash(cat *)" "Bash(basename *)" "Bash(jq *)"; do
    run jq -e --arg c "$cmd" '.permissions.allow | index($c)' "$CONFIG_DIR/claude/settings.json"
    assert_success
  done
}

@test "claude settings keep critical commands out of allow" {
  for cmd in "Bash(git push *)" "Bash(git commit *)" "Bash(rm *)" "Bash(terraform apply*)"; do
    run jq -e --arg c "$cmd" '.permissions.allow | index($c)' "$CONFIG_DIR/claude/settings.json"
    assert_failure
  done
}

@test "kubectl config view asks first (--raw dumps kubeconfig credentials)" {
  run jq -e '.permissions.allow | index("Bash(kubectl config view*)")' "$CONFIG_DIR/claude/settings.json"
  assert_failure
  run jq -e '.permissions.ask | index("Bash(kubectl config view*)")' "$CONFIG_DIR/claude/settings.json"
  assert_success
  run jq -r '.permission.bash["kubectl config view*"]' "$CONFIG_DIR/opencode/opencode.json"
  assert_output "ask"
}

@test "claude settings keep git commit/push denied" {
  run jq -e '.permissions.deny | index("Bash(git push)")' "$CONFIG_DIR/claude/settings.json"
  assert_success
}

@test "claude global settings do not hardcode the portfolio repo" {
  run grep -q 'portfolio' "$CONFIG_DIR/claude/settings.json"
  assert_failure
}

@test "claude global settings additionalDirectories is empty (machine-specific paths live in settings.local.json)" {
  run jq -e '.permissions.additionalDirectories | length == 0' "$CONFIG_DIR/claude/settings.json"
  assert_success
}

@test "claude global settings hardcode no /Users/ absolute paths" {
  run grep -q '/Users/' "$CONFIG_DIR/claude/settings.json"
  assert_failure
}

@test "no config/ file hardcodes a /Users/<name> absolute path" {
  # Machine-specific macOS home paths must never be committed: they break on
  # other machines and leak the username. Use $HOME / ${userHome} instead.
  # Guards against re-introducing hard-coded values anywhere under config/.
  run grep -rn '/Users/[A-Za-z0-9._-]' "$CONFIG_DIR"
  assert_failure
}

@test "claude env deny patterns are unified across settings and managed" {
  s=$(jq -c '[.permissions.deny[] | select(test("\\.env"))] | sort' "$CONFIG_DIR/claude/settings.json")
  m=$(jq -c '[.permissions.deny[] | select(test("\\.env"))] | sort' "$CONFIG_DIR/claude/managed-settings.json")
  [ "$s" = "$m" ]
}

@test "claude env deny uses working globs, not unsupported extglob" {
  # Claude Code permission globs follow gitignore syntax; extglob !(...) is a
  # silent no-op (matches nothing), so it must never be used to deny secrets.
  # Variants are listed explicitly instead of a blanket .env.* because deny
  # always wins over allow: .env.* would also lock out .env.example.
  for f in settings managed-settings; do
    # No Write(...) rules: Claude Code ignores them for file permission checks
    # (it warns "only Edit(path) rules are"); Edit covers every file-editing tool.
    run jq -e '[.permissions.deny[] | select(startswith("Write("))] | length == 0' "$CONFIG_DIR/claude/$f.json"
    assert_success
    for op in Read Edit; do
      for v in .env .env.local '.env.*.local' .env.development .env.production .env.staging .env.test; do
        run jq -e --arg r "$op(**/$v)" '.permissions.deny | index($r)' "$CONFIG_DIR/claude/$f.json"
        assert_success
      done
    done
    run jq -e '[.permissions.deny[] | select(test("!\\("))] | length > 0' "$CONFIG_DIR/claude/$f.json"
    assert_failure
    run jq -e '.permissions.deny | index("Read(**/.env.*)")' "$CONFIG_DIR/claude/$f.json"
    assert_failure
  done
}

@test "claude settings do not allow env/printenv (would dump secrets unprompted)" {
  for cmd in "Bash(env)" "Bash(printenv *)"; do
    run jq -e --arg c "$cmd" '.permissions.allow | index($c)' "$CONFIG_DIR/claude/settings.json"
    assert_failure
  done
}

@test "every private key under ~/.ssh is denied (keys are not all named id_*)" {
  for f in settings managed-settings; do
    run jq -e '.permissions.deny | index("Read(~/.ssh/**)")' "$CONFIG_DIR/claude/$f.json"
    assert_success
    run jq -e '.sandbox.filesystem.denyRead | index("~/.ssh/**")' "$CONFIG_DIR/claude/$f.json"
    assert_success
    run jq -e '.sandbox.filesystem.allowRead | index("~/.ssh/*.pub")' "$CONFIG_DIR/claude/$f.json"
    assert_success
    run jq -e '[.permissions.deny[], .sandbox.filesystem.denyRead[]] | map(select(test("id_\\*"))) | length == 0' \
      "$CONFIG_DIR/claude/$f.json"
    assert_success
  done
  run jq -r '.permission.read["~/.ssh/**"]' "$CONFIG_DIR/opencode/opencode.json"
  assert_output "deny"
}

@test "kubeconfig and the env.local.sh secrets file are denied everywhere" {
  local p
  for p in "~/.kube/config" "~/.config/dotfiles/env.local.sh"; do
    for f in settings managed-settings; do
      run jq -e --arg r "Read($p)" '.permissions.deny | index($r)' "$CONFIG_DIR/claude/$f.json"
      assert_success
      run jq -e --arg r "$p" '.sandbox.filesystem.denyRead | index($r)' "$CONFIG_DIR/claude/$f.json"
      assert_success
    done
    run jq -r --arg r "$p" '.permission.read[$r]' "$CONFIG_DIR/opencode/opencode.json"
    assert_output "deny"
  done
}

@test "gh is allowed read-only: no blanket gh *, gh api asks, token dumps denied" {
  run jq -e '.permissions.allow | index("Bash(gh *)")' "$CONFIG_DIR/claude/settings.json"
  assert_failure
  run jq -e '.permissions.ask | index("Bash(gh api *)")' "$CONFIG_DIR/claude/settings.json"
  assert_success
  for r in "Bash(gh auth token*)" "Bash(git credential*)"; do
    for f in settings managed-settings; do
      run jq -e --arg r "$r" '.permissions.deny | index($r)' "$CONFIG_DIR/claude/$f.json"
      assert_success
    done
  done
  run jq -r '.permission.bash["gh *"]' "$CONFIG_DIR/opencode/opencode.json"
  assert_output "null"
  run jq -r '.permission.bash["gh auth token*"]' "$CONFIG_DIR/opencode/opencode.json"
  assert_output "deny"
}

@test "kubectl get secret(s) is denied in claude and opencode" {
  run jq -e '.permissions.deny | index("Bash(kubectl get secrets *)")' "$CONFIG_DIR/claude/settings.json"
  assert_success
  run jq -r '.permission.bash["kubectl get secrets *"]' "$CONFIG_DIR/opencode/opencode.json"
  assert_output "deny"
}

@test "the live dotfiles checkout is write-denied to the sandbox" {
  run jq -e '.sandbox.filesystem.denyWrite | index("~/.dotfiles/**")' "$CONFIG_DIR/claude/settings.json"
  assert_success
}

@test "copilot terminal auto-approve has no universal prefixes" {
  # `command` prefixes any command; npx/bunx run any package; docker is host root.
  for k in '"command": true' '"npx": true' '"bunx": true' '"docker": true' '"go": true'; do
    run grep -qF "$k" "$CONFIG_DIR/vscode/settings.json"
    assert_failure
  done
  run grep -qE 'current-context\|view' "$CONFIG_DIR/vscode/settings.json"
  assert_failure
}

@test "copilot never auto-applies edits to the agent guardrails" {
  for g in '"**/config/copilot/**": false' '"**/config/claude/**": false' '"**/config/vscode/**": false'; do
    run grep -qF "$g" "$CONFIG_DIR/vscode/settings.json"
    assert_success
  done
}

@test "env.sh exports OPENCODE_CONFIG only when the local override exists" {
  local home="$BATS_TEST_TMPDIR/home"
  mkdir -p "$home/.config/opencode"
  run env -i HOME="$home" bash -c ". '$CONFIG_DIR/shell/env.sh' && printf '%s' \"\${OPENCODE_CONFIG-unset}\""
  assert_success
  assert_output "unset"
  touch "$home/.config/opencode/opencode.local.json"
  run env -i HOME="$home" bash -c ". '$CONFIG_DIR/shell/env.sh' && printf '%s' \"\$OPENCODE_CONFIG\""
  assert_success
  assert_output "$home/.config/opencode/opencode.local.json"
}

@test "VS Code commit message generation is pinned to Conventional Commits" {
  local s="$CONFIG_DIR/vscode/settings.json"
  run grep -q '"github.copilot.chat.commitMessageGeneration.instructions"' "$s"
  assert_success
  run grep -q "Conventional Commits format" "$s"
  assert_success
  # Same type list as the commit-types skill, and refactor is never emitted.
  run grep -q "feat, fix, perf, deps, revert, docs, style, chore, test, build, ci" "$s"
  assert_success
  run grep -q "Never use 'refactor'" "$s"
  assert_success
  run grep -q '^## Format (always)' "$CONFIG_DIR/skills/commit-types/SKILL.md"
  assert_success
  # Commit messages are English in every project, in both sources.
  run grep -q "Write the commit message in English" "$s"
  assert_success
  run grep -q '^- English, whatever the language' "$CONFIG_DIR/skills/commit-types/SKILL.md"
  assert_success
}

@test "claude Stop hook runs the docs/README sync check" {
  run jq -r '.hooks.Stop[0].hooks[0].command' "$CONFIG_DIR/claude/settings.json"
  assert_output --partial '.claude/hooks/docs-sync-check.sh'
  assert_file_exists "$CONFIG_DIR/claude/hooks/docs-sync-check.sh"
}

@test "claude Stop hook shows the next steps, synchronously" {
  local s="$CONFIG_DIR/claude/settings.json"
  run jq -r '[.hooks.Stop[].hooks[] | select(.command | contains(".claude/hooks/next-steps.sh"))] | length' "$s"
  assert_output "1"
  # An async hook would hand its systemMessage to Claude instead of the owner.
  run jq -r '[.hooks.Stop[].hooks[] | select(.command | contains("next-steps.sh")) | .async // false] | any' "$s"
  assert_output "false"
  assert_file_exists "$CONFIG_DIR/claude/hooks/next-steps.sh"
}

@test "claude skill hooks are wired: policy at SessionStart, routing on each prompt" {
  local s="$CONFIG_DIR/claude/settings.json"
  run jq -r '[.hooks.SessionStart[].hooks[] | select(.command | contains(".claude/hooks/skill-context.sh"))] | length' "$s"
  assert_output "1"
  run jq -r '[.hooks.UserPromptSubmit[].hooks[] | select(.command | contains(".claude/hooks/skill-router.sh"))] | length' "$s"
  assert_output "1"
  # Async hooks would deliver the context after Claude has started the turn.
  run jq -r '[(.hooks.SessionStart, .hooks.UserPromptSubmit)[].hooks[] | .async // false] | any' "$s"
  assert_output "false"
  assert_file_executable "$CONFIG_DIR/claude/hooks/skill-context.sh"
  assert_file_executable "$CONFIG_DIR/claude/hooks/skill-router.sh"
}

@test "every top-level script under scripts/ is used or documented somewhere" {
  # scripts/install.sh and scripts/packages.sh sat unused for months and kept
  # an unpinned Homebrew install alive (removed 2026-11-18).
  local script name
  for script in "$REPO_ROOT"/scripts/*.sh; do
    name="scripts/$(basename "$script")"
    # A mention in a comment is neither a caller nor documentation.
    grep -rnF "$name" "$REPO_ROOT/Makefile" "$REPO_ROOT/README.md" "$REPO_ROOT/AGENTS.md" \
      "$REPO_ROOT/docs" "$REPO_ROOT/os" "$REPO_ROOT/.github" "$REPO_ROOT/tests" --exclude=configs.bats \
      | grep -qvE '^[^:]+:[0-9]+:[[:space:]]*#' \
      || fail "$name has no caller and no documentation"
  done
}

@test "the public repo stays reusable: MIT LICENSE and a SECURITY.md exist" {
  assert_file_exists "$REPO_ROOT/LICENSE"
  run head -1 "$REPO_ROOT/LICENSE"
  assert_output "MIT License"
  assert_file_exists "$REPO_ROOT/SECURITY.md"
}

@test "claude permissions default to auto mode (user scope only; the managed floor pins no mode)" {
  run jq -r '.permissions.defaultMode' "$CONFIG_DIR/claude/settings.json"
  assert_output "auto"
  run jq -r '.permissions.defaultMode // "unset"' "$CONFIG_DIR/claude/managed-settings.json"
  assert_output "unset"
}

@test "every Bash rule has its rtk mirror in the same list (allow, ask and deny)" {
  # The `rtk hook claude` PreToolUse hook rewrites commands (git status → rtk
  # git status, cat f → rtk read f, gh api → rtk gh api, …) BEFORE the rules are
  # matched, so a rule without its rtk twin silently stops applying.
  local f list rule cmd rest mirror
  local re='^Bash\(([^[:space:])]+)(.*)\)$'
  for f in settings managed-settings; do
    for list in allow ask deny; do
      while IFS= read -r rule; do
        [[ "$rule" =~ $re ]] || continue
        cmd="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
        case "$cmd" in
          rtk*|*=*|command) continue ;;
          cat|head|tail) mirror='Bash(rtk read *)' ;;
          *) mirror="Bash(rtk ${cmd}${rest})" ;;
        esac
        run jq -e --arg r "$mirror" --arg l "$list" '.permissions[$l] | index($r)' "$CONFIG_DIR/claude/$f.json"
        assert_success || { echo "missing in $f.json $list: $mirror" >&2; return 1; }
      done < <(jq -r --arg l "$list" '.permissions[$l] // [] | .[]' "$CONFIG_DIR/claude/$f.json")
    done
  done
}

@test "kubectl read verbs are allowed with leading flags, mutating verbs never" {
  local v
  for v in get describe logs top explain; do
    run jq -e --arg r "Bash(kubectl * $v *)" '.permissions.allow | index($r)' "$CONFIG_DIR/claude/settings.json"
    assert_success
  done
  # No flag-tolerant allow may name a mutating verb (the hook denies them anyway).
  run jq -e '[.permissions.allow[] | select(test("^Bash\\((rtk )?kubectl \\* (apply|delete|patch|rollout|create|annotate|edit|scale|exec|debug|run|replace|set|label|taint|cordon|uncordon|drain|cp|expose|autoscale)"))] | length == 0' \
    "$CONFIG_DIR/claude/settings.json"
  assert_success
  # Secrets stay denied in the namespaced form too.
  run jq -e '.permissions.deny | index("Bash(kubectl * get secrets *)")' "$CONFIG_DIR/claude/settings.json"
  assert_success
}

@test "WebFetch allows the documentation hubs by wildcard" {
  local d
  for d in '*.github.io' 'github.com' '*.githubusercontent.com' 'ghcr.io'; do
    run jq -e --arg r "WebFetch(domain:$d)" '.permissions.allow | index($r)' "$CONFIG_DIR/claude/settings.json"
    assert_success
  done
  run jq -e '.permissions.allow | index("WebFetch(domain:*)")' "$CONFIG_DIR/claude/settings.json"
  assert_failure
}

@test "sandbox lets tools use their caches (no PATH=/… prefixes needed)" {
  local c
  for c in '~/.cache/**' '~/go/pkg/mod/**' '~/.bun/install/cache/**'; do
    run jq -e --arg r "$c" '.sandbox.filesystem.allowWrite | index($r)' "$CONFIG_DIR/claude/settings.json"
    assert_success
  done
}

@test "mattpocock-skills comes from the official marketplace, not a re-declared one" {
  run jq -r '.enabledPlugins["mattpocock-skills@claude-plugins-official"]' "$CONFIG_DIR/claude/settings.json"
  assert_output "true"
  # The built-in marketplace pins the plugin to a commit; a second
  # declaration of the repo would track its default branch instead.
  run jq -e '.extraKnownMarketplaces // {} | has("mattpocock")' "$CONFIG_DIR/claude/settings.json"
  assert_failure
}

@test "the ECC plugin is not enabled or declared" {
  run jq -e '(.enabledPlugins // {} | has("ecc@ecc")) or (.extraKnownMarketplaces // {} | has("ecc"))' "$CONFIG_DIR/claude/settings.json"
  assert_failure
}

@test "VS Code settings survive an unresolved shell env: \${userHome} paths, longer timeout" {
  local s="$CONFIG_DIR/vscode/settings.json"
  # The Python extension does not expand ~ (it looked for <workspace>/~/.proto/…).
  run grep -E '"python\.defaultInterpreterPath": *"~' "$s"
  assert_failure
  run grep -qF '"python.defaultInterpreterPath": "${userHome}/.proto/shims/python"' "$s"
  assert_success
  # proto shims need PATH from the login shell; 10 s (default) is too short on a busy startup.
  run grep -qE '"application\.shellEnvironmentResolutionTimeout": *(2[0-9]|[3-9][0-9]|1[01][0-9]|120),' "$s"
  assert_success
}

# --- OS scripts ---

@test "os/macos/init.sh exists and is executable" {
  assert_file_exists "$REPO_ROOT/os/macos/init.sh"
}

@test "os/debian/init.sh exists and is executable" {
  assert_file_exists "$REPO_ROOT/os/debian/init.sh"
}

@test "all macOS setup profiles exist" {
  for profile in ai base extras javascript python; do
    assert_file_exists "$REPO_ROOT/os/macos/setup-${profile}.sh"
  done
}

@test "all Debian setup profiles exist" {
  for profile in base kubernetes security; do
    assert_file_exists "$REPO_ROOT/os/debian/setup-${profile}.sh"
  done
}

@test "shared helper scripts exist" {
  for helper in completions fetch homebrew oh-my-zsh proto; do
    assert_file_exists "$REPO_ROOT/os/helpers/${helper}.sh"
  done
}

# --- Directory structure ---

@test "config/ directory exists" {
  assert_dir_exists "$CONFIG_DIR"
}

@test "os/macos/ directory exists" {
  assert_dir_exists "$REPO_ROOT/os/macos"
}

@test "os/debian/ directory exists" {
  assert_dir_exists "$REPO_ROOT/os/debian"
}

@test "scripts/ directory exists" {
  assert_dir_exists "$REPO_ROOT/scripts"
}

# --- Config content sanity checks ---

@test ".gitconfig contains [init] defaultBranch = main" {
  run grep -q 'defaultBranch = main' "$CONFIG_DIR/git/.gitconfig"
  assert_success
}

@test ".zshrc sources oh-my-zsh" {
  run grep -q 'source $ZSH/oh-my-zsh.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test ".zshrc sources env.sh" {
  run grep -q 'env.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test ".zshrc sources functions.sh" {
  run grep -q 'functions.sh' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test ".zshrc defines dc alias for docker compose" {
  run grep -qE '^alias dc="docker compose"' "$CONFIG_DIR/zsh/.zshrc"
  assert_success
}

@test "extensions.json contains recommendations array" {
  run grep -q '"recommendations"' "$CONFIG_DIR/vscode/extensions.json"
  assert_success
}

@test "mcp.json contains servers block" {
  run grep -q '"servers"' "$CONFIG_DIR/vscode/mcp.json"
  assert_success
}

# --- release-please ---

@test "release-please config exists with simple release-type" {
  assert_file_exists "$REPO_ROOT/.github/release/release-please-config.json"
  run grep -q '"release-type": "simple"' "$REPO_ROOT/.github/release/release-please-config.json"
  assert_success
}

@test "release-please manifest tracks a semver version for the root package" {
  # Don't pin a specific value: release-please bumps this on every release
  # (0.0.0 → 0.1.0 → …), so assert structure (a semver string under ".") instead.
  assert_file_exists "$REPO_ROOT/.github/release/.release-please-manifest.json"
  run jq -e '.["."] | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")' \
    "$REPO_ROOT/.github/release/.release-please-manifest.json"
  assert_success
}

@test "release config files are valid JSON" {
  run jq empty \
    "$REPO_ROOT/.github/release/release-please-config.json" \
    "$REPO_ROOT/.github/release/.release-please-manifest.json"
  assert_success
}

@test "ci-cd workflow calls the reusable release-please workflow" {
  run grep -q 'github-workflows/.github/workflows/release.yml@' "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_success
}

@test "reusable workflows are pinned to an immutable SHA, not a mutable branch" {
  # @main is a moving target injected into a pipeline with contents:write +
  # secrets:inherit — pin every reusable workflow to a 40-char commit SHA.
  run grep -nE 'github-workflows/\.github/workflows/[^@]+@(main|master|v?[0-9]+(\.[0-9]+)*)\b' \
    "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_failure
  run grep -cE 'github-workflows/\.github/workflows/[^@]+@[0-9a-f]{40}' \
    "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_output '5'
}

@test "no docs dispatch job: the docs hub polls on a cron schedule" {
  # kevindebenedetti.github.io regenerates the docs from a scheduled poll
  # (docs-poll.yml), so nothing listens for a repository_dispatch any more.
  run grep -qE 'cd-docs\.yml|DOCS_APP_' "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_failure
}

@test "release job is gated on push to main" {
  run grep -q "initial-version: '0.1.0'" "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_success
}

@test "release job runs on GITHUB_TOKEN, and the bot guards expect its author" {
  local wf="$REPO_ROOT/.github/workflows/ci-cd.yml"
  # No App token for releases: release-please authors its PR as github-actions[bot].
  run bash -c "sed -n '/^  release:/,\$p' '$wf' | grep -E 'app-client-id|APP_PRIVATE_KEY'"
  assert_failure
  # The PR guard admits exactly the release bots: github-actions[bot] (release
  # PRs) and release-please-global[bot] (the github-workflows bumps). Pinned so
  # that widening the allowlist is a deliberate, reviewed change.
  run grep -q "allowed-bots: '\[\"github-actions\[bot\]\", \"release-please-global\[bot\]\"\]'" "$wf"
  assert_success
  run grep -c "user.login == 'github-actions\[bot\]'" "$wf"
  assert_output "3"
}

# --- commit/TODO automation moved to the /commit skill ---

@test "no commit-message / TODO hook scripts remain (handled by the /commit skill)" {
  assert_file_not_exists "$REPO_ROOT/scripts/todo-commit.sh"
  assert_file_not_exists "$REPO_ROOT/scripts/ai-commit-msg.sh"
  assert_file_not_exists "$REPO_ROOT/scripts/check-todo-purged.sh"
  assert_file_not_exists "$REPO_ROOT/.pre-commit-hooks.yaml"
}

@test "prek no longer wires the commit-message / TODO hooks" {
  run grep -qE 'ai-commit-msg|purge-todo-done|check-todo-purged' "$REPO_ROOT/prek.toml"
  assert_failure
}

@test "prek wires the gitleaks hook at the pre-commit stage" {
  # Guards against a silent removal or stage change: gitleaks must scan for
  # secrets before every commit, not on push or any later stage.
  run grep -qE 'id = "gitleaks", stages = \["pre-commit"\]' "$REPO_ROOT/prek.toml"
  assert_success
}

@test "the prek bats hook hides git's hook environment from the suite" {
  # Committing from a linked worktree, git exports GIT_DIR to its hooks. Left
  # in place it overrides repository discovery: the fixtures' `git init` and
  # `git config` then act on the real repository instead of their temp dir.
  local entry bin="$BATS_TEST_TMPDIR/bin"
  entry=$(sed -n '/^id = "bats"$/,/^stages/s/^entry = "\(.*\)"$/\1/p' "$REPO_ROOT/prek.toml" | sed 's/\\"/"/g')
  [ -n "$entry" ]
  mkdir -p "$bin"
  printf '%s\n' '#!/bin/sh' \
    'echo "GIT_DIR=${GIT_DIR-unset} GIT_INDEX_FILE=${GIT_INDEX_FILE-unset} GIT_WORK_TREE=${GIT_WORK_TREE-unset}"' > "$bin/bats"
  chmod +x "$bin/bats"
  run env PATH="$bin:$PATH" GIT_DIR=/nonexistent/.git GIT_INDEX_FILE=/nonexistent/index \
    GIT_WORK_TREE=/nonexistent sh -c "$entry"
  assert_success
  assert_output "GIT_DIR=unset GIT_INDEX_FILE=unset GIT_WORK_TREE=unset"
}

@test "the tracked .gitconfig names Git Credential Manager only as 'manager'" {
  # `git-credential-manager configure` writes an absolute, machine-specific
  # helper path through the ~/.gitconfig symlink: it must not be committed.
  # An empty value resets the helpers inherited from the system config.
  run git config --file "$REPO_ROOT/config/git/.gitconfig" --get-all credential.helper
  assert_success
  assert_equal "${#lines[@]}" 1
  assert_line --index 0 "manager"
  run grep -nE '^[[:space:]]*helper[[:space:]]*=[[:space:]]*/' "$REPO_ROOT/config/git/.gitconfig"
  assert_failure
}

# --- Renovate keeps the prek.toml rev pins up to date ---

@test "renovate.json is valid JSON" {
  run jq empty "$REPO_ROOT/renovate.json"
  assert_success
}

@test "renovate has a customManager for prek.toml (built-in pre-commit manager ignores it)" {
  # The built-in pre-commit manager only matches .pre-commit-config.yaml, so the
  # `# renovate:` annotations on prek.toml's rev pins need a customManager to fire.
  run grep -q 'prek' "$REPO_ROOT/renovate.json"
  assert_success
  run grep -q '"customManagers"' "$REPO_ROOT/renovate.json"
  assert_success
}

@test "every prek.toml rev pin carries a renovate annotation" {
  # Count `rev = ` lines and `# renovate:` comments; they must match so no pin
  # silently drops out of Renovate's coverage.
  revs=$(grep -c '^rev = ' "$REPO_ROOT/prek.toml")
  notes=$(grep -c '^# renovate:' "$REPO_ROOT/prek.toml")
  [ "$revs" -eq "$notes" ]
}

# --- Agent instructions (AGENTS.md / CLAUDE.md) ---

@test "AGENTS.md exists and CLAUDE.md imports it" {
  assert_file_exists "$REPO_ROOT/AGENTS.md"
  run grep -qx '@AGENTS.md' "$REPO_ROOT/CLAUDE.md"
  assert_success
}

# --- Shared skills and commands (Claude Code, OpenCode, VS Code Copilot) ---

# Frontmatter keys of a Markdown file, sorted, on one line.
frontmatter_keys() {
  awk 'NR == 1 && $0 != "---" { exit }
       NR > 1 && $0 == "---" { exit }
       NR > 1 && /^[A-Za-z_-]+:/ { sub(/:.*/, ""); print }' "$1" | sort | tr '\n' ' '
}

# Headings of the layout block in the todo-md skill (the canonical TODO.md).
todo_layout() {
  awk '/^# TODO$/ { on = 1; next }
       on && /^```/ { exit }
       on && /^## / { print }' "$CONFIG_DIR/skills/todo-md/SKILL.md"
}

@test "shared skills keep a portable frontmatter: name (= folder) and description" {
  local skill name
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -f "$skill/SKILL.md" ] || continue
    run frontmatter_keys "$skill/SKILL.md"
    assert_output "description name "
    name=$(sed -n 's/^name: *//p' "$skill/SKILL.md" | head -n 1)
    [ "$name" = "$(basename "$skill")" ]
  done
}

@test "shared commands keep a portable frontmatter: description and argument-hint" {
  local cmd
  for cmd in "$CONFIG_DIR"/commands/*.md; do
    run frontmatter_keys "$cmd"
    assert_output --regexp '^(argument-hint )?description $'
  done
}

@test "the todo-md skill defines the English TODO.md layout" {
  run todo_layout
  assert_output "## 🔴 In progress
## 🟡 To do
## 🖐 Manual — do it yourself, in order
## 🟢 Ideas / backlog
## 🤖 Agent recommendations
## 🔒 Security audit
## ✅ Done"
}

@test "next-task defers the TODO.md format to the todo-md skill" {
  local cmd="$CONFIG_DIR/commands/next-task.md"
  run grep -q '`todo-md` skill' "$cmd"
  assert_success
  # The former French headings live only in the skill's migration table.
  run grep -E 'En cours|À faire|Fait|recommandations' "$cmd"
  assert_failure
}

@test "next-task manual hands the guided session to the manual-steps skill" {
  local cmd="$CONFIG_DIR/commands/next-task.md" skill="$CONFIG_DIR/skills/manual-steps/SKILL.md"
  assert_file_exists "$skill"
  run grep -q '^| `manual` or `manual all` ' "$cmd"
  assert_success
  run grep -q '`manual-steps` skill' "$cmd"
  assert_success
  # The skill keeps the TODO.md format in todo-md and never asks for a secret.
  run grep -q '`todo-md` skill defines the file' "$skill"
  assert_success
  run grep -q '^- Never ask for a secret value' "$skill"
  assert_success
  run grep -E 'En cours|À faire|Fait|recommandations' "$skill"
  assert_failure
}

@test "next-issue works GitHub issues by label and never closes or commits" {
  local cmd="$CONFIG_DIR/commands/next-issue.md"
  assert_file_exists "$cmd"
  run grep -q '^| `manual` ' "$cmd"
  assert_success
  # Approval is the owner's label; the issue closes when the owner merges.
  run grep -q '`ready-for-agent`' "$cmd"
  assert_success
  run grep -q 'Fixes #<number>' "$cmd"
  assert_success
  # Issues of a public repository are public: findings stay in the chat.
  run grep -q 'Security findings stay in the chat' "$cmd"
  assert_success
  run grep -E 'gh issue (close|delete)' "$cmd"
  assert_failure
}

@test "a shared command never takes the name of a Claude-only one" {
  # Both are linked to ~/.claude/commands/<name>.md: one would replace the other.
  local cmd
  for cmd in "$CONFIG_DIR"/commands/*.md; do
    [ ! -e "$CONFIG_DIR/claude/commands/$(basename "$cmd")" ]
  done
}

@test "audit inspects the whole repository read-only and files its findings for triage" {
  local cmd="$CONFIG_DIR/commands/audit.md" skill
  assert_file_exists "$cmd"
  run grep -q '^| `dry-run` ' "$cmd"
  assert_success
  # Findings become issues the owner triages, never approved work, never duplicates.
  run grep -q 'gh issue create --label needs-triage' "$cmd"
  assert_success
  run grep -q 'gh issue list --state open --search' "$cmd"
  assert_success
  run grep -E 'add-label ready-for-agent|gh issue (close|delete|edit)' "$cmd"
  assert_failure
  # Issues of a public repository are public: findings stay in the chat.
  run grep -q 'Security findings stay in the chat' "$cmd"
  assert_success
  # The audit changes nothing in the project.
  run grep -q '^The audit is read-only' "$cmd"
  assert_success
  # Each lens leans on a skill of the mattpocock-skills plugin when it is there.
  for skill in codebase-design domain-modeling code-review writing-for-agents diagnosing-bugs research; do
    run grep -q "^| \`$skill\` " "$cmd"
    assert_success
  done
  # The infrastructure checklist of the former Claude-only command is kept.
  run grep -q 'Terraform / OpenTofu' "$cmd"
  assert_success
}

@test "agents may comment on, label and create issues, in claude and opencode alike" {
  local verb
  for verb in comment edit create; do
    run jq -e --arg c "Bash(gh issue $verb *)" '.permissions.allow | index($c)' "$CONFIG_DIR/claude/settings.json"
    assert_success
    run jq -r --arg c "gh issue $verb *" '.permission.bash[$c]' "$CONFIG_DIR/opencode/opencode.json"
    assert_output "allow"
  done
  # Closing and deleting stay behind a confirmation (no allow rule).
  for verb in close delete; do
    run jq -e --arg v "$verb" '.permissions.allow | map(select(test("gh issue " + $v))) | length == 0' "$CONFIG_DIR/claude/settings.json"
    assert_success
    run jq -r --arg c "gh issue $verb *" '.permission.bash[$c]' "$CONFIG_DIR/opencode/opencode.json"
    assert_output "null"
  done
}

@test "AGENTS.md documents every shared skill" {
  local skill
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    run grep -q "\`$(basename "$skill")\`" "$REPO_ROOT/AGENTS.md"
    assert_success
  done
}

@test "AGENTS.md make targets exist in the Makefile" {
  local target
  for target in ci submodules help; do
    run grep -q "^$target:" "$REPO_ROOT/Makefile"
    assert_success
  done
}

@test "ssh config parses with the local OpenSSH (UseKeychain is macOS-only)" {
  command -v ssh >/dev/null || skip "ssh not installed"
  # Linux OpenSSH rejects UseKeychain unless IgnoreUnknown lists it first.
  run grep -n -m1 -E '^[[:space:]]*(IgnoreUnknown|UseKeychain)' "$REPO_ROOT/config/ssh/config"
  assert_output --partial 'IgnoreUnknown UseKeychain'
  run ssh -G -F "$REPO_ROOT/config/ssh/config" example.invalid
  assert_success
}

@test "the Docker stages install oh-my-zsh through init.sh, never from an installer script" {
  # A pre-installed oh-my-zsh would skip init.sh's own pinned clone, so the
  # stages would test a different install than the one users get.
  run grep -n 'ohmyzsh/ohmyzsh/.*/tools/install.sh' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_failure
  run grep -c 'oh-my-zsh at pinned commit' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_output "2"
}

@test "every pinned release version in the install scripts is tracked by Renovate" {
  # Each `local version=` pin carries a `# renovate:` annotation on the line
  # above, and renovate.json has a regex manager for that file and line shape.
  local f
  for f in os/debian/setup-kubernetes.sh os/debian/setup-base.sh os/helpers/proto.sh; do
    run awk '/^[[:space:]]*local version="/ { if (prev !~ /# renovate: datasource=[^ ]+ depName=[^ ]+/) bad++ } { prev = $0 } END { print bad + 0 }' "$REPO_ROOT/$f"
    assert_output "0"
    run grep -c '^[[:space:]]*local version="' "$REPO_ROOT/$f"
    refute_output "0"
    run jq -e --arg f "$f" '[.customManagers[] | select(.matchStrings[] | test("local version")) | .managerFilePatterns[] | ltrimstr("/") | rtrimstr("/") as $m | select($f | test($m))] | length > 0' "$REPO_ROOT/renovate.json"
    assert_success
  done
}

@test "the Renovate regex for release pins extracts each pinned version" {
  command -v perl >/dev/null || skip "perl not installed"
  local re f
  re=$(jq -r '.customManagers[] | select(.matchStrings[] | test("local version")) | .matchStrings[0]' "$REPO_ROOT/renovate.json")
  for f in os/debian/setup-kubernetes.sh os/debian/setup-base.sh os/helpers/proto.sh; do
    # Renovate's named groups are PCRE-compatible; perl applies the same regex.
    run perl -0ne 'while (/'"$re"'/g) { print "$+{depName} $+{currentValue}\n" }' "$REPO_ROOT/$f"
    assert_output --regexp '^(((helm/helm|moonrepo/proto|derailed/k9s|git-ecosystem/git-credential-manager) v[0-9]+\.[0-9]+\.[0-9]+|kubernetes/kubernetes v[0-9]+\.[0-9]+)
?)+$'
  done
}

@test "every Docker test stage is run by CI and has a make target and a compose service" {
  local stage
  for stage in $(sed -n 's/^FROM base AS \(test-[a-z-]*\)$/\1/p' "$REPO_ROOT/tests/docker/Dockerfile.test"); do
    run grep -q "\"$stage\"" "$REPO_ROOT/.github/workflows/ci-cd.yml"
    assert_success
    run grep -q "^  $stage:$" "$REPO_ROOT/tests/docker/docker-compose.test.yml"
    assert_success
    run grep -q "^docker-$stage:" "$REPO_ROOT/Makefile"
    assert_success
  done
}

@test "a Docker stage runs the full-mode security steps without swallowing failures" {
  run sed -n '/^FROM base AS test-security-full$/,/^FROM /p' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_output --partial "install_configure_crowdsec"
  # The stage runs the function on its own: it must load the helper that
  # holds install_apt_key (os/helpers/fetch.sh) first.
  assert_output --partial 'source /home/tester/.dotfiles/os/helpers/fetch.sh;'
  assert_output --partial "install_audit_tools"
  assert_output --partial "cscli version"
  refute_output --partial "|| true"
}

@test "CI and the Docker bats stage run every Bats directory make test runs" {
  # BATS_DIRS lists tests/ and its sub-suites; the reusable workflow and a
  # plain `bats tests/` both stop at the first level.
  local dirs dir docker_run matrix
  dirs=$(sed -n 's/^BATS_DIRS := //p' "$REPO_ROOT/Makefile" | sed 's/\$(TESTS_DIR)/tests/g')
  [ -n "$dirs" ] || fail "BATS_DIRS not found in the Makefile"
  docker_run=$(grep -E '^RUN .* bats ' "$REPO_ROOT/tests/docker/Dockerfile.test")
  matrix=$(grep -E '^ +tests-dir: \[' "$REPO_ROOT/.github/workflows/ci-cd.yml")
  for dir in $dirs; do
    [[ " $docker_run " == *" $dir "* ]] || fail "the Docker test-bats stage does not run $dir"
    [ "$dir" = tests/ ] && continue
    [[ "$matrix" == *"$dir"* ]] || fail "no CI job runs $dir"
  done
  # A failing sub-suite holds the release back like the main one.
  run grep -F "needs.ci-suites.result != 'failure'" "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_success
}

@test "the Docker stages that run a whole profile keep its exit status" {
  # `|| true` after the script made these stages pass whatever it did; the
  # checks that follow only look at files written early.
  local stage
  for stage in test-security test-full; do
    run sed -n "/^FROM base AS $stage\$/,/^FROM /p" "$REPO_ROOT/tests/docker/Dockerfile.test"
    assert_output --partial "os/debian/"
    refute_output --partial "|| true"
  done
}

@test "a Docker stage runs setup-kubernetes.sh in full mode, from an older kubectl channel" {
  run sed -n '/^FROM base AS test-kubernetes$/,/^FROM /p' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_success
  assert_output --partial "FULL_MODE_SETUP=true"
  assert_output --partial "os/debian/setup-kubernetes.sh"
  # It starts from the end-of-life channel, so the move is what gets checked.
  assert_output --partial "stable:/v1.32/"
  # The expected minor is read from the script, so a Renovate bump never breaks it.
  assert_output --partial 'local version="\(v1\.[0-9]*\)"'
  assert_output --partial "already installed from the"
  assert_output --partial "command -v helm"
  assert_output --partial "command -v k9s"
  refute_output --partial "|| true"
  # A fresh install comes first, on a system with no gpg: the script must
  # install gnupg itself, so the stage never does.
  assert_output --partial '! command -v gpg'
  refute_output --partial 'install-recommends gpg'
  local fresh old
  fresh=$(grep -n 'bash /home/tester/.dotfiles/os/debian/setup-kubernetes.sh' <<<"$output" | head -n1 | cut -d: -f1)
  old=$(grep -n 'stable:/v1.32/' <<<"$output" | head -n1 | cut -d: -f1)
  [ -n "$fresh" ] && [ -n "$old" ] && [ "$fresh" -lt "$old" ] \
    || fail "the stage must run setup-kubernetes.sh on the bare system before the v1.32 setup"
}

@test "the Docker kubectl check reads exactly the minor install_kubectl pins" {
  local cmd pin
  cmd=$(sed -n 's|^RUN pin=\$(\(sed .*\)) \\$|\1|p' "$REPO_ROOT/tests/docker/Dockerfile.test" | head -n 1)
  [ -n "$cmd" ] || fail "no pinned-minor extraction found in Dockerfile.test"
  cmd=${cmd//\/home\/tester\/.dotfiles/$REPO_ROOT}
  pin=$(eval "$cmd")
  run sed -n '/^install_kubectl()/,/^}/p' "$REPO_ROOT/os/debian/setup-kubernetes.sh"
  assert_output --partial "local version=\"$pin\""
  [[ $pin =~ ^v1\.[0-9]+$ ]] || fail "extracted '$pin', expected one v1.<minor>"
}

@test "the Docker oh-my-zsh check reads exactly the commit install_oh_my_zsh pins" {
  # Run the Dockerfile's own extraction against the repo's helper: it must yield
  # one hash (oh-my-zsh.sh also pins zsh-completions), the one cloned.
  local cmd pinned
  cmd=$(sed -n 's|^RUN pinned=\$(\(sed .*\)) \\$|\1|p' "$REPO_ROOT/tests/docker/Dockerfile.test" | head -n 1)
  [ -n "$cmd" ] || fail "no pinned-commit extraction found in Dockerfile.test"
  pinned=$(eval "${cmd//\/home\/tester\/.dotfiles/$REPO_ROOT}")
  [[ "$pinned" =~ ^[0-9a-f]{40}$ ]] || fail "extraction gave: '$pinned'"
  # Source first: the helper defines the real clone_at_commit, replaced after.
  run bash -c 'source "$1/os/helpers/oh-my-zsh.sh"; clone_at_commit() { echo "$3"; }; install_oh_my_zsh' _ "$REPO_ROOT"
  assert_output "$pinned"
}

@test "renovate.json uses no option Renovate has deprecated" {
  # renovate-config-validator --strict fails on fileMatch (now managerFilePatterns).
  run jq -e '[.. | objects | has("fileMatch")] | any' "$REPO_ROOT/renovate.json"
  assert_failure
}

# --- ShellCheck reaches every script, with or without a .sh suffix ---

@test "make lint hands every extensionless script under scripts/ to ShellCheck" {
  # The Docker test-bats image has no make; CI's Bats job and `make test` do.
  command -v make >/dev/null || skip "make is not installed"
  # A stand-in shellcheck that prints the files it was given.
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@"\n' > "$BATS_TEST_TMPDIR/bin/shellcheck"
  chmod +x "$BATS_TEST_TMPDIR/bin/shellcheck"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run make -s -C "$REPO_ROOT" --no-print-directory lint
  assert_success
  local f
  for f in "$REPO_ROOT"/scripts/*/*; do
    [[ "$f" == *.md ]] && continue
    assert_line "scripts/${f#"$REPO_ROOT"/scripts/}"
  done
  assert_line "os/helpers/links.sh"
  refute_line --regexp '^tests/test_helper/'
}

@test "make lint leaves out scripts under gitignored directories" {
  command -v make >/dev/null || skip "make is not installed"
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || skip "not a git checkout"
  mkdir -p "$BATS_TEST_TMPDIR/bin" "$REPO_ROOT/.scratch"
  printf '#!/bin/bash\nprintf "%%s\\n" "$@"\n' > "$BATS_TEST_TMPDIR/bin/shellcheck"
  chmod +x "$BATS_TEST_TMPDIR/bin/shellcheck"
  # .scratch/ is gitignored: a stale copy of a script there is not this branch's code.
  local probe="$REPO_ROOT/.scratch/lint-probe-$$.sh"
  echo '#!/bin/bash' > "$probe"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH" run make -s -C "$REPO_ROOT" --no-print-directory lint
  rm -f "$probe"
  assert_success
  refute_output --partial "lint-probe"
  assert_line "os/helpers/links.sh"
}

@test "the prek shellcheck hook matches the extensionless scripts under scripts/" {
  local pattern f
  pattern=$(sed -n '/id = "shellcheck"/,/}/s/^ *files = "\(.*\)",$/\1/p' "$REPO_ROOT/prek.toml" | sed 's/\\\\/\\/g')
  [ -n "$pattern" ] || fail "no files pattern found for the shellcheck hook"
  for f in "$REPO_ROOT"/scripts/*/* "$REPO_ROOT"/os/helpers/links.sh; do
    [[ "$f" == *.md ]] && continue
    run grep -qE "$pattern" <<<"${f#"$REPO_ROOT"/}"
    assert_success
  done
  # Markdown and data files next to them stay out.
  run grep -qE "$pattern" <<<"config/ollama/models.txt"
  assert_failure
}

@test ".zshrc enables the fzf plugin only where fzf is installed, before oh-my-zsh loads" {
  command -v zsh >/dev/null || skip "zsh not installed"
  local line
  line=$(grep -F 'plugins+=(fzf)' "$CONFIG_DIR/zsh/.zshrc")
  [ -n "$line" ] || fail "no fzf plugin line in .zshrc"
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\n' > "$BATS_TEST_TMPDIR/bin/fzf"
  chmod +x "$BATS_TEST_TMPDIR/bin/fzf"
  run zsh -fc "PATH='$BATS_TEST_TMPDIR/bin'; plugins=(git); $line; print -r -- \$plugins"
  assert_output "git fzf"
  # Without fzf the plugin would print an error at every shell start.
  run zsh -fc "PATH='$BATS_TEST_TMPDIR/empty'; plugins=(git); $line; print -r -- \$plugins"
  assert_output "git"
  # The plugin list is read when oh-my-zsh is sourced: the line comes first.
  local at loaded
  at=$(grep -nF 'plugins+=(fzf)' "$CONFIG_DIR/zsh/.zshrc" | cut -d: -f1)
  loaded=$(grep -n '^source \$ZSH/oh-my-zsh.sh' "$CONFIG_DIR/zsh/.zshrc" | cut -d: -f1)
  [ "$at" -lt "$loaded" ]
}
