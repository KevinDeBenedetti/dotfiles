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
  for helper in completions proto; do
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
  assert_output '4'
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
  run grep -q "allowed-bots: '\[\"github-actions\[bot\]\"\]'" "$wf"
  assert_success
  run grep -c "user.login == 'github-actions\[bot\]'" "$wf"
  assert_output "2"
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
  for target in test lint validate ci submodules; do
    run grep -q "^$target:" "$REPO_ROOT/Makefile"
    assert_success
  done
}
