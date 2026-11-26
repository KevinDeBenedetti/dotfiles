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
           opencode/opencode.json ssh/config skills/debug-action/SKILL.md \
           skills/explain/SKILL.md agents/AGENTS.md claude/CLAUDE.md; do
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
  local f list rule cmd rest mirror rules
  local re='^Bash\(([^[:space:])]+)(.*)\)$'
  for f in settings managed-settings; do
    for list in allow ask deny; do
      # The list is read once; each mirror is looked up in it as a whole line.
      rules=$(jq -r --arg l "$list" '.permissions[$l] // [] | .[]' "$CONFIG_DIR/claude/$f.json")
      while IFS= read -r rule; do
        [[ "$rule" =~ $re ]] || continue
        cmd="${BASH_REMATCH[1]}"; rest="${BASH_REMATCH[2]}"
        case "$cmd" in
          rtk*|*=*|command) continue ;;
          cat|head|tail) mirror='Bash(rtk read *)' ;;
          *) mirror="Bash(rtk ${cmd}${rest})" ;;
        esac
        [[ $'\n'"$rules"$'\n' == *$'\n'"$mirror"$'\n'* ]] || { echo "missing in $f.json $list: $mirror" >&2; return 1; }
      done <<< "$rules"
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

@test "the model-invoked engineering skills are owned; the plugin's copies are hidden from the model" {
  # They live in config/skills/, shared by the three tools. The plugin stays
  # for its user-invoked planning flows (triage, to-spec, to-tickets,
  # wayfinder): its copy of each owned skill would otherwise be listed to
  # Claude a second time, under the mattpocock-skills: prefix.
  local name
  for name in code-review codebase-design diagnosing-bugs domain-modeling grilling prototype research tdd writing-for-agents; do
    assert_file_exists "$CONFIG_DIR/skills/$name/SKILL.md"
    # Model-invoked: other skills and the hooks reach them by name.
    run grep -q '^disable-model-invocation:' "$CONFIG_DIR/skills/$name/SKILL.md"
    assert_failure
    run grep -q 'Adapted from mattpocock/skills (MIT)' "$CONFIG_DIR/skills/$name/SKILL.md"
    assert_success
    run jq -r --arg k "mattpocock-skills:$name" '.skillOverrides[$k]' "$CONFIG_DIR/claude/settings.json"
    assert_output "user-invocable-only"
  done
  # No override left for a skill that is not owned: it would hide the only copy.
  run bash -c "jq -r '.skillOverrides | keys[] | select(startswith(\"mattpocock-skills:\")) | sub(\"^mattpocock-skills:\"; \"\")' '$CONFIG_DIR/claude/settings.json' | while read -r n; do [ -f '$CONFIG_DIR/skills/'\$n/SKILL.md ] || echo \$n; done"
  assert_output ""
  # The licence notice the adaptation owes.
  run grep -q 'Copyright (c) 2026 Matt Pocock' "$CONFIG_DIR/skills/NOTICE.md"
  assert_success
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

@test "CI's ShellCheck checks the extensionless scripts make lint checks" {
  # make lint (and the prek hook) select `scripts/*/*` on top of `*.sh`; the
  # reusable workflow takes the same glob through shellcheck-extra-paths.
  run grep -F "'scripts/*/*'" "$REPO_ROOT/Makefile"
  assert_success
  run grep -E "^ +shellcheck-extra-paths: 'scripts/\*/\*'$" "$REPO_ROOT/.github/workflows/ci-cd.yml"
  assert_success
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
  # The PR guard admits exactly the bots that open pull requests here:
  # github-actions[bot] (release PRs), release-please-global[bot] (the
  # github-workflows bumps) and renovate[bot] (dependency updates, issue 60).
  # Pinned so that widening the allowlist is a deliberate, reviewed change.
  run grep -q "allowed-bots: '\[\"github-actions\[bot\]\", \"release-please-global\[bot\]\", \"renovate\[bot\]\"\]'" "$wf"
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
    GIT_WORK_TREE=/nonexistent sh -c "cd '$REPO_ROOT' && $entry"
  assert_success
  # One stub run per test file (or one for the suite with GNU parallel).
  assert_output --partial "GIT_DIR=unset GIT_INDEX_FILE=unset GIT_WORK_TREE=unset"
  refute_output --partial nonexistent
}

@test "~/.gitconfig.local can override every setting of the tracked .gitconfig" {
  # git keeps the last value it reads: the include must come after every
  # setting, or the local file loses to the ones below it.
  local home="$BATS_TEST_TMPDIR/home" key value
  mkdir -p "$home"
  while IFS= read -r key; do
    [ "$key" = include.path ] && continue
    printf '[%s]\n\t%s = local-override\n' "${key%.*}" "${key##*.}" > "$home/.gitconfig.local"
    value=$(HOME="$home" git config --file "$REPO_ROOT/config/git/.gitconfig" --includes --get-all "$key" | tail -n1)
    [ "$value" = local-override ] || fail "$key: the tracked value wins over ~/.gitconfig.local"
  # Plain section.key settings (a subsection such as credential."https://…"
  # cannot be rebuilt from its flattened name).
  done < <(git config --file "$REPO_ROOT/config/git/.gitconfig" --list --name-only | grep -E '^[^.]+\.[^.]+$' | sort -u)
}

@test "docs/config/git.md documents every setting of the tracked .gitconfig" {
  local key missing=()
  while IFS= read -r key; do
    [ "$key" = include.path ] && continue
    grep -qiF "$key" "$REPO_ROOT/docs/config/git.md" || missing+=("$key")
  done < <(git config --file "$REPO_ROOT/config/git/.gitconfig" --list --name-only | sort -u)
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented in git.md: ${missing[*]}"
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

@test ".zshrc points tldr at the pages of the running OS (issue 128)" {
  local block
  block=$(sed -n '/^# tldr++/,/^esac$/p' "$CONFIG_DIR/zsh/.zshrc")
  [ -n "$block" ] || fail "no tldr++ block in .zshrc"
  run bash -c "uname() { echo Darwin; }; $block; echo \"\$TLDR_OS\""
  assert_output "osx"
  run bash -c "uname() { echo Linux; }; $block; echo \"\$TLDR_OS\""
  assert_output "linux"
}

# --- Renovate keeps the prek.toml rev pins up to date ---

@test "renovate.json is valid JSON" {
  run jq empty "$REPO_ROOT/renovate.json"
  assert_success
}

@test "renovate.json extends the shared preset and keeps only this repository's rules" {
  local cfg="$REPO_ROOT/renovate.json"
  # The Monday window, the release age, the prek.toml manager and the
  # github-workflows rule come from KevinDeBenedetti/renovate-config (issue 142).
  run jq -c '.extends' "$cfg"
  assert_output '["github>KevinDeBenedetti/renovate-config"]'
  run jq -r 'has("schedule") or ([.customManagers[].managerFilePatterns[] | select(test("prek"))] | length > 0)
    or ([.packageRules[] | select((.matchPackageNames // []) | index("KevinDeBenedetti/github-workflows"))] | length > 0)' "$cfg"
  assert_output false
}

@test "renovate groups the prek hooks and the proto toolchain, and leaves the checksum-pinned tools alone" {
  local cfg="$REPO_ROOT/renovate.json"
  # One pull request for the prek hooks, one for the proto toolchain.
  run jq -r '[.packageRules[] | select(.matchFileNames == ["prek.toml"]) | .groupName] | first // empty' "$cfg"
  assert_output "prek hooks"
  run jq -r '[.packageRules[] | select(.matchFileNames == ["config/proto/.prototools"]) | .groupName] | first // empty' "$cfg"
  assert_output "proto toolchain"
  # The SHA-256 pinned release tools stay one pull request each: their sums are
  # copied by hand, one release at a time.
  # An explicit null: without it they join the preset's weekly group.
  run jq -c '[.packageRules[] | select((.matchPackageNames // []) | index("helm/helm")) | has("groupName"), .groupName]' "$cfg"
  assert_output '[true,null]'
}

@test "the docs give only proto commands the pinned proto has" {
  # proto 0.64 has no `list` or `use` (status / install --pin replace them).
  run grep -rnE 'proto (list|use)( |$)' "$REPO_ROOT/docs" "$REPO_ROOT/README.md"
  assert_failure
}

@test "the prek github-workflows hooks run the version CI runs" {
  # github-workflows' propagate-release job moves both together (since its
  # v0.55.0); Renovate is off for that package.
  local ci prek
  ci=$(grep -o 'github-workflows/.github/workflows/ci-shell.yml@[0-9a-f]\{40\} # v[0-9.]*' "$REPO_ROOT/.github/workflows/ci-cd.yml" | head -n1 | sed 's/.*# //')
  prek=$(sed -n '/KevinDeBenedetti\/github-workflows"$/,/^rev = /s/^rev = "\(.*\)"$/\1/p' "$REPO_ROOT/prek.toml")
  [ -n "$ci" ] || fail "no versioned ci-shell.yml pin in ci-cd.yml"
  assert_equal "$prek" "$ci"
}

@test "every prek.toml rev pin carries a renovate annotation" {
  # Count `rev = ` lines and `# renovate:` comments; they must match so no pin
  # silently drops out of Renovate's coverage.
  revs=$(grep -c '^rev = ' "$REPO_ROOT/prek.toml")
  notes=$(grep -c '^# renovate:' "$REPO_ROOT/prek.toml")
  [ "$revs" -eq "$notes" ]
}

@test "prek validates renovate.json with Renovate's own validator" {
  # The jq tests above know the shape of the file, not Renovate's options: an
  # unknown one, or one that needs a migration (--strict), fails the commit
  # (issue 146). renovate.json is repository config, not self-hosted global
  # config (--no-global).
  run grep -A4 '^repo = "https://github.com/renovatebot/pre-commit-hooks"$' "$REPO_ROOT/prek.toml"
  assert_success
  assert_line '# renovate: datasource=github-tags depName=renovatebot/pre-commit-hooks'
  assert_line --regexp '^rev = "[0-9a-f]{40}"  # frozen: [0-9]+\.[0-9]+\.[0-9]+$'
  assert_line '  { id = "renovate-config-validator", args = ["--strict", "--no-global"], files = "^renovate\\.json$" },'
}

# --- The board Worker is deployed by CI (issues 131, 137) ---

@test "the board Worker is deployed once the CI/CD of a push to main passed, after its tests" {
  local wf="$REPO_ROOT/.github/workflows/project-board.yml"
  assert_file_exists "$wf"
  # After the whole CI/CD of main, never on a push or a pull request directly.
  run sed -n '/^on:$/,/^[a-z]/p' "$wf"
  assert_line "  workflow_run:"
  assert_line "    workflows: [CI/CD]"
  assert_line "    types: [completed]"
  assert_line "    branches: [main]"
  refute_line "  push:"
  refute_output --partial "pull_request"
  # Only a green run, of a push, in this repository: a fork's pull request from
  # a branch named main also completes a CI/CD run "on main".
  run grep -c "github.event.workflow_run.conclusion == 'success'\|github.event.workflow_run.event == 'push'\|github.event.workflow_run.head_repository.full_name == github.repository" "$wf"
  assert_output 3
  # The commit CI tested is the one checked out and deployed, with its history
  # (changed.sh compares it to the deployed commit).
  run grep -c 'ref: ${{ github.event.workflow_run.head_sha || github.sha }}\|fetch-depth: 0' "$wf"
  assert_output 2
  run grep -c 'VERSION:$HEAD_SHA"' "$wf"
  assert_output 1
  # The change check, the tests, then the deploy, in the same job.
  local changed tests deploy
  changed=$(grep -n 'bash .github/project-board/changed.sh' "$wf" | head -n1 | cut -d: -f1)
  tests=$(grep -n 'bats tests/project-board.bats' "$wf" | head -n1 | cut -d: -f1)
  deploy=$(grep -n 'wrangler@[0-9.]* deploy --config .github/project-board/wrangler.toml --var "VERSION:' "$wf" | head -n1 | cut -d: -f1)
  [ -n "$changed" ] && [ -n "$tests" ] && [ -n "$deploy" ] || fail "the workflow lacks the change check, the tests or the deploy command"
  [ "$changed" -lt "$tests" ] && [ "$tests" -lt "$deploy" ] || fail "the change check, the tests and the deploy are out of order"
}

# board_history: a repository in $BATS_TEST_TMPDIR/board whose commits are
# $base (the Worker), $docs (another file), $worker (the Worker again), $wf
# (the deploy workflow) and, on a branch off $base, $side.
board_history() {
  # git exports GIT_DIR to its hooks: the fixture would act on this repository.
  # shellcheck disable=SC2046 # one variable name per word
  unset $(git rev-parse --local-env-vars)
  cd "$BATS_TEST_TMPDIR" && git init -q -b main board && cd board || return 1
  git config user.name test && git config user.email test@example.com
  git config commit.gpgsign false && git config core.hooksPath /dev/null
  mkdir -p .github/project-board .github/workflows
  record() { echo "$2" >>"$1" && git add "$1" && git commit -qm "$2" && git rev-parse HEAD; }
  base=$(record .github/project-board/worker.mjs base)
  git checkout -q -b side
  side=$(record .github/project-board/worker.mjs side)
  git checkout -q main
  docs=$(record README.md docs)
  worker=$(record .github/project-board/worker.mjs worker)
  wf=$(record .github/workflows/project-board.yml workflow)
}

@test "the board Worker is deployed when its code changed since the deployed commit" {
  board_history
  # A commit that failed CI in between is covered: the range starts at the
  # deployed commit, not at the pushed one's parent.
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$base" "$wf"
  assert_success
  assert_output --partial "deploy: "
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$docs" "$worker"
  assert_output --partial "deploy: "
  # The deploy workflow is part of the Worker's deploy.
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$worker" "$wf"
  assert_output --partial "deploy: "
}

@test "the board Worker is not deployed when nothing of it changed since the deployed commit" {
  board_history
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$base" "$docs"
  assert_success
  assert_output --partial "skip: "
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$wf" "$wf"
  assert_output --partial "skip: "
}

@test "a CI run that ends late does not put an older board Worker back" {
  board_history
  run bash "$REPO_ROOT/.github/project-board/changed.sh" "$wf" "$base"
  assert_success
  assert_output --partial "skip: "
}

@test "the board Worker is deployed when the deployed commit cannot be compared" {
  board_history
  local deployed
  # Never deployed by CI, an answer that is no commit, a commit that is not in
  # main's history: deploying again is safe, missing a change is not.
  for deployed in "" unknown 0123456789abcdef0123456789abcdef01234567 "$side" "--help"; do
    run bash "$REPO_ROOT/.github/project-board/changed.sh" "$deployed" "$wf"
    assert_success
    assert_output --partial "deploy: "
  done
}

@test "the board deploy job has read-only contents, pinned actions and its secrets from the repository" {
  local wf="$REPO_ROOT/.github/workflows/project-board.yml"
  run grep -A1 '^permissions:$' "$wf"
  assert_line "  contents: read"
  run grep -c 'contents: write\|id-token\|secrets: inherit' "$wf"
  assert_output 0
  # Every action by full commit SHA.
  run grep -E '^ +(- )?uses: ' "$wf"
  assert_success
  run bash -c "grep -E '^ +(- )?uses: ' '$wf' | grep -vE '@[0-9a-f]{40} # v[0-9.]+$'"
  assert_failure
  run grep -c 'secrets.CLOUDFLARE_API_TOKEN\|secrets.CLOUDFLARE_ACCOUNT_ID' "$wf"
  assert_output 2
}

@test "the prek hook repositories are pinned by commit SHA, the tag kept as a comment" {
  # A tag can be moved or pushed again; a full SHA cannot (issue 127). The
  # owner's own github-workflows hooks stay on their tag: its propagate-release
  # job moves that pin with each release, and reads a tag there. Renovate's
  # hooks tag their releases without a `v`.
  local repo rev pinned=0
  while IFS=$'\t' read -r repo rev; do
    [ "$repo" = "https://github.com/KevinDeBenedetti/github-workflows" ] && continue
    [[ "$rev" =~ ^rev\ =\ \"[0-9a-f]{40}\"\ \ #\ frozen:\ v?[0-9][0-9.]*$ ]] || fail "$repo is not pinned by SHA: $rev"
    pinned=$((pinned + 1))
  done < <(awk -F'"' '/^repo = "https:/ { repo = $2 } /^rev = / { print repo "\t" $0 }' "$REPO_ROOT/prek.toml")
  assert_equal "$pinned" 6
}

@test "the shared Renovate preset reads every prek pin, a SHA with its tag comment" {
  # The prek.toml manager is the preset's (KevinDeBenedetti/renovate-config,
  # default.json). Its two matchStrings are copied here: the frozen form reads
  # the SHA as the digest and the `# frozen:` comment as the version, the tag
  # form reads a tag. Run on the real file: one match per pin.
  # Python reads Renovate's named groups; the Docker test image has none.
  command -v python3 >/dev/null 2>&1 || skip "python3 not installed"
  run python3 - "$REPO_ROOT/prek.toml" <<'PY'
import re, sys
head = r'#\s*renovate:\s*datasource=(?P<datasource>\S+)\s+depName=(?P<depName>\S+)(?:\s+packageName=(?P<packageName>\S+))?(?:\s+versioning=(?P<versioning>\S+))?(?:\s+extractVersion=(?P<extractVersion>\S+))?\s*\n\s*rev\s*=\s*'
tag = head + r'"(?P<currentValue>[^"]*[^"0-9a-f][^"]*)"'
frozen = head + r'"(?P<currentDigest>[0-9a-f]{40})"[ \t]*#[ \t]*frozen:[ \t]*(?P<currentValue>\S+)'
text = open(sys.argv[1]).read()
for m in re.finditer(frozen, text):
    print("frozen", m["depName"], m["currentValue"], len(m["currentDigest"]))
for m in re.finditer(tag, text):
    print("tag", m["depName"], m["currentValue"])
PY
  assert_success
  assert_line "frozen pre-commit/pre-commit-hooks v5.0.0 40"
  assert_line "frozen gitleaks/gitleaks v8.30.1 40"
  assert_line --regexp '^tag KevinDeBenedetti/github-workflows v[0-9.]+$'
  assert_equal "${#lines[@]}" "$(grep -c '^rev = ' "$REPO_ROOT/prek.toml")"
}

# --- Agent instructions (AGENTS.md / CLAUDE.md) ---

@test "AGENTS.md exists and CLAUDE.md imports it" {
  assert_file_exists "$REPO_ROOT/AGENTS.md"
  run grep -qx '@AGENTS.md' "$REPO_ROOT/CLAUDE.md"
  assert_success
}

# --- Global agent rules (Claude Code, OpenCode, VS Code Copilot) ---

@test "the global agent rules carry the hard rules and stay short" {
  local rules="$CONFIG_DIR/agents/AGENTS.md"
  run grep -q 'The owner stages, commits and pushes' "$rules"
  assert_success
  run grep -q 'no AI attribution' "$rules"
  assert_success
  run grep -q 'Secrets stay unread and unwritten' "$rules"
  assert_success
  # Read on every turn by every tool: a budget, not a manual.
  [ "$(wc -l < "$rules")" -le 60 ]
}

@test "Claude Code's global entry file only imports: the shared rules, then the Claude-only files" {
  # Home-relative imports: the file is reached through a symlink, and a
  # relative import would depend on which side of the link it resolves from.
  run grep -v '^@~/\.claude/[A-Za-z.-]*\.md$' "$CONFIG_DIR/claude/CLAUDE.md"
  assert_output ""
  run head -n 1 "$CONFIG_DIR/claude/CLAUDE.md"
  assert_output "@~/.claude/AGENTS.md"
  # An import syntax only Claude Code reads stays out of the shared rules.
  run grep -n '^@' "$CONFIG_DIR/agents/AGENTS.md"
  assert_failure
}

@test "the pull request body rule lives in git-workflow: the plugin's pr skill is hidden, not referred to" {
  run jq -r '.skillOverrides["mattpocock-skills:pr"]' "$CONFIG_DIR/claude/settings.json"
  assert_output "user-invocable-only"
  run grep -n 'mattpocock' "$CONFIG_DIR/skills/git-workflow/SKILL.md"
  assert_failure
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

@test "shared skills keep a portable frontmatter: name (= folder), description, and the invocation keys" {
  # name and description are the Agent Skills spec. argument-hint and
  # disable-model-invocation are read by Claude Code and VS Code; OpenCode
  # ignores them and takes its own switches from metadata.
  local skill name
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -f "$skill/SKILL.md" ] || continue
    run frontmatter_keys "$skill/SKILL.md"
    assert_output --regexp '^(argument-hint )?description (disable-model-invocation metadata )?name $'
    name=$(sed -n 's/^name: *//p' "$skill/SKILL.md" | head -n 1)
    [ "$name" = "$(basename "$skill")" ]
  done
}

@test "a user-invoked skill is closed to the model in the three tools" {
  # disable-model-invocation covers Claude Code and VS Code. OpenCode ignores
  # it: opencode/autoinvoke keeps the skill out of its model's reach, and
  # opencode/slash off leaves /<name> to the command file links.sh installs.
  local skill found=0
  for skill in "$CONFIG_DIR"/skills/*/SKILL.md; do
    grep -q '^disable-model-invocation:' "$skill" || continue
    found=$((found + 1))
    run grep -c -E '^disable-model-invocation: true$|^  opencode/slash: "false"$|^  opencode/autoinvoke: "false"$' "$skill"
    assert_output 3
  done
  [ "$found" -ge 7 ]
}

@test "the workflow commands are user-invoked skills, none left as a command file" {
  local name
  for name in audit commit explain new-issue next-issue next-task pr; do
    run grep -q '^disable-model-invocation: true$' "$CONFIG_DIR/skills/$name/SKILL.md"
    assert_success
  done
  assert_not_exists "$CONFIG_DIR/commands"
  assert_not_exists "$CONFIG_DIR/claude/commands"
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
  local cmd="$CONFIG_DIR/skills/next-task/SKILL.md"
  run grep -q '`todo-md` skill' "$cmd"
  assert_success
  # The former French headings live only in the skill's migration table.
  run grep -E 'En cours|À faire|Fait|recommandations' "$cmd"
  assert_failure
}

@test "next-task manual hands the guided session to the manual-steps skill" {
  local cmd="$CONFIG_DIR/skills/next-task/SKILL.md" skill="$CONFIG_DIR/skills/manual-steps/SKILL.md"
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
  local cmd="$CONFIG_DIR/skills/next-issue/SKILL.md"
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

@test "git-workflow hands the owner runnable commands: branch first, then commit, push and pull request" {
  local skill="$CONFIG_DIR/skills/git-workflow/SKILL.md"
  assert_file_exists "$skill"
  # Runnable from the chat: one-line bash blocks, single-quoted text, no editor.
  run grep -q '^## Runnable commands' "$skill"
  assert_success
  run grep -qF '```bash' "$skill"
  assert_success
  run grep -qF "\$'…'" "$skill"
  assert_success
  run grep -qF 'in a terminal' "$skill"
  assert_success
  # Work on a shared branch moves to a new one before the commit, its
  # unpushed commits too.
  run grep -qE '`main`, `master`, `dev`, `develop`' "$skill"
  assert_success
  run grep -qE '^[[:space:]]*git branch -f main origin/main$' "$skill"
  assert_success
  # In that order: the branch, the commit and the push (the owner's), then the
  # pull request — synced in place when open, the owner's command when new.
  local branch commit push create edit
  branch=$(grep -nE '^[[:space:]]*git checkout -b [a-z]+/' "$skill" | head -n 1 | cut -d: -f1)
  commit=$(grep -nE "^[[:space:]]*git add [^&]+ && git commit -m '" "$skill" | head -n 1 | cut -d: -f1)
  push=$(grep -nE '^[[:space:]]*git push -u origin ' "$skill" | head -n 1 | cut -d: -f1)
  edit=$(grep -nE '^gh pr edit [0-9]+ --title .* --body-file "\$\(git rev-parse --absolute-git-dir\)/PR_BODY\.md"$' "$skill" | cut -d: -f1)
  create=$(grep -nE '^gh pr create --base [a-z]+ --title .* --body-file "\$\(git rev-parse --absolute-git-dir\)/PR_BODY\.md"$' "$skill" | cut -d: -f1)
  # One test per line: bats ignores a failure inside an && list.
  [ -n "$branch" ]
  [ -n "$commit" ]
  [ -n "$push" ]
  [ -n "$edit" ]
  [ -n "$create" ]
  [ "$branch" -lt "$commit" ]
  [ "$commit" -lt "$push" ]
  [ "$push" -lt "$edit" ]
  # The sections follow the same order.
  run bash -c "grep -n '^## ' '$skill' | cut -d' ' -f2- | tr '\n' '|'"
  assert_output 'Runnable commands|Branch first|Session branch|Commit hand-over|Pull request|After a commit or push|'
  # Two cases only some sessions meet live in reference files beside the
  # skill, each behind a pointer under its heading.
  local session="$CONFIG_DIR/skills/git-workflow/session-branch.md"
  local rebase="$CONFIG_DIR/skills/git-workflow/rebase.md"
  run grep -qF '](./session-branch.md)' "$skill"
  assert_success
  run grep -qF '](./rebase.md)' "$skill"
  assert_success
  # The app's generated session branch: the agent renames it, unpushed only.
  run grep -qE '^git branch -m [a-z]+/[a-z0-9-]+$' "$session"
  assert_success
  run grep -qF 'no upstream' "$session"
  assert_success
  # A pull request in conflict with its base: the owner rebases, with no
  # editor, then forces the push with a lease.
  run grep -qE '^git rebase origin/main$' "$rebase"
  assert_success
  run grep -qE '^git add [^&]+ && GIT_EDITOR=true git rebase --continue$' "$rebase"
  assert_success
  run grep -qE '^git push --force-with-lease$' "$rebase"
  assert_success
  # The body fills the pull request template and keeps a workflow's block.
  run grep -qF '<!-- pr-description:start -->' "$skill"
  assert_success
  run grep -qE 'gh pr merge|git add (-A|\.)( |$)|git push (-f|--force)( |$)' "$skill" "$session" "$rebase"
  assert_failure
}

@test "agent-run gh commands pass their bodies through a file, never a heredoc the guard would read" {
  # The PreToolUse guard reads the whole command line: a body quoting git's
  # commit or push subcommand would get the command denied.
  local file
  for file in skills/next-issue/SKILL.md skills/audit/SKILL.md skills/new-issue/SKILL.md; do
    run grep -F "<<'EOF'" "$CONFIG_DIR/$file"
    assert_failure
    run grep -qF -- '--body-file "$(git rev-parse --absolute-git-dir)/ISSUE_BODY.md"' "$CONFIG_DIR/$file"
    assert_success
  done
}

@test "the pr command brings the branch's pull request up to date through git-workflow" {
  local cmd="$CONFIG_DIR/skills/pr/SKILL.md"
  assert_file_exists "$cmd"
  run grep -q '`git-workflow` skill' "$cmd"
  assert_success
  run grep -q 'gh pr merge' "$cmd"
  assert_failure
}

@test "the commit command hands a Conventional Commit that closes its issues, never commits itself" {
  local cmd="$CONFIG_DIR/skills/commit/SKILL.md"
  assert_file_exists "$cmd"
  run grep -q '`git-workflow` skill' "$cmd"
  assert_success
  run grep -q '`commit-types` skill' "$cmd"
  assert_success
  # Each piece of work is tied to the issue it closes, in commit and PR.
  run grep -qF 'Fixes #<number>' "$cmd"
  assert_success
  run grep -qF 'gh issue list' "$cmd"
  assert_success
  # The owner runs the commit: the command never closes, merges or bypasses.
  run grep -E 'gh issue (close|delete)|gh pr merge|--no-verify' "$cmd"
  assert_failure
}

@test "next-issue, next-task and manual-steps hand the owner's commands over through git-workflow" {
  local file
  for file in skills/next-issue/SKILL.md skills/next-task/SKILL.md skills/manual-steps/SKILL.md; do
    run grep -q '`git-workflow`' "$CONFIG_DIR/$file"
    assert_success
  done
  # A picked issue on a shared branch gets its branch command first.
  run bash -c "sed -n '/^## 3\\. Pick/,/^## Agent skills/p' '$CONFIG_DIR/skills/next-issue/SKILL.md' | grep -q 'branch command'"
  assert_success
  # git add -p prompts for each hunk: it cannot run from the chat.
  for file in next-issue next-task; do
    run grep -F '`git add -p`' "$CONFIG_DIR/skills/$file/SKILL.md"
    assert_output --partial 'in a terminal'
  done
}

@test "commit-types keeps message-only output for generators and defers hand-over to git-workflow" {
  local skill="$CONFIG_DIR/skills/commit-types/SKILL.md" rule
  # The message-only rule stays, scoped to generators (git aicommit, the
  # commit-message box) ...
  rule=$(awk '/^- When the message is the whole output/ { on = 1 } on && /^$/ { exit } on' "$skill")
  run grep -F '`git aicommit`' <<<"$rule"
  assert_success
  run grep -F 'output only the message' <<<"$rule"
  assert_success
  # ... and a commit proposed to the owner is a runnable command.
  run grep -F '`git-workflow` skill' <<<"$rule"
  assert_success
  run grep -qx -- '- Output only the message: no code fences, quotes, emojis or preamble.' "$skill"
  assert_failure
}

@test "new-issue files the owner's requests as grouped issues, never duplicates" {
  local cmd="$CONFIG_DIR/skills/new-issue/SKILL.md"
  assert_file_exists "$cmd"
  run grep -q '^| `dry-run <requests>` ' "$cmd"
  assert_success
  # The owner's own requests: approved when specified, blocked when not.
  run grep -q 'gh issue create --label ready-for-agent' "$cmd"
  assert_success
  run grep -q 'gh issue create --label needs-info' "$cmd"
  assert_success
  # Related requests share one issue; an existing issue is reused.
  run grep -qi 'group' "$cmd"
  assert_success
  run grep -q 'gh issue list --state open --search' "$cmd"
  assert_success
  # It files: it never changes, closes or deletes an existing issue.
  run grep -E 'gh issue (close|delete|edit)' "$cmd"
  assert_failure
  # Listed where the other issue commands are.
  run grep -q '`/new-issue`' "$REPO_ROOT/AGENTS.md"
  assert_success
  run grep -q '`/new-issue`' "$REPO_ROOT/docs/config/issue-workflow.md"
  assert_success
}

@test "audit inspects the whole repository read-only and files its findings for triage" {
  local cmd="$CONFIG_DIR/skills/audit/SKILL.md" skill
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
  # Each lens leans on one of the engineering skills.
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

@test "the Docker build context leaves out what git ignores, and local secrets" {
  # The test image copies the whole context (COPY . …): a local build must see
  # the tracked files only, as CI's checkout does.
  local pattern missing=()
  while IFS= read -r pattern; do
    grep -qxF -- "$pattern" "$REPO_ROOT/.dockerignore" || missing+=("$pattern")
  done < <(grep -vE '^(#|$)' "$REPO_ROOT/.gitignore"; printf '%s\n' .git '.env*' '.dev.vars*')
  [ "${#missing[@]}" -eq 0 ] || fail "missing from .dockerignore: ${missing[*]}"
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

@test "a Docker stage runs init.sh's security profile on a node the infra repo manages" {
  run sed -n '/^FROM base AS test-security-infra$/,/^FROM /p' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_success
  # The marker exists before init.sh runs, and the whole entry point runs (the
  # sourcing of os/helpers/infra.sh is what the Bats stubs cannot cover).
  local marker run
  marker=$(grep -n '00-infra-hardening.conf' <<<"$output" | head -n1 | cut -d: -f1)
  run=$(grep -n 'init.sh -p security' <<<"$output" | head -n1 | cut -d: -f1)
  [ -n "$marker" ] && [ -n "$run" ] && [ "$marker" -lt "$run" ]
  # sshd, the firewall and Fail2Ban are left alone; the rest still applies.
  assert_output --partial '! sudo test -e /etc/ssh/sshd_config.d/00-hardening.conf'
  assert_output --partial '! dpkg -s ufw'
  assert_output --partial '! sudo test -e /etc/fail2ban/jail.local'
  assert_output --partial 'test -f /etc/sysctl.d/99-security.conf'
  assert_output --partial 'test -f /etc/apt/apt.conf.d/52dotfiles-unattended-upgrades'
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

@test "batch mode proposes one grouped commit, in next-issue and next-task alike" {
  # One commit per issue made the owner pick hunks in the files several issues
  # share, with hooks that test the staged content only (issue 73).
  local cmd summary
  for cmd in next-issue next-task; do
    summary=$(sed -n '/^## 12\. Summary/,$p' "$CONFIG_DIR/skills/$cmd/SKILL.md")
    [ -n "$summary" ] || fail "$cmd.md has no Summary section"
    run grep -F 'one grouped commit' <<<"$summary"
    assert_success
    # The grouped commit takes the type with the highest release impact.
    run grep -F 'highest release impact' <<<"$summary"
    assert_success
    # Per-item commits remain, on request only.
    run grep -E 'only when the owner asks' <<<"$summary"
    assert_success
  done
  # Every issue of the batch still closes on merge.
  run bash -c "sed -n '/^## 12\\. Summary/,\$p' '$CONFIG_DIR/skills/next-issue/SKILL.md' | grep -c 'Fixes #<number>'"
  [ "$output" -ge 2 ]
}

# --- The shell reference pages list everything the config defines ---

@test "docs/config/zsh.md documents every alias and plugin .zshrc defines" {
  local name missing=()
  for name in $(sed -n 's/^ *alias \([A-Za-z0-9_-]*\)=.*/\1/p' "$CONFIG_DIR/zsh/.zshrc") \
    $(sed -n '/^plugins=(/,/^)/s/^  \([a-z-]*\)$/\1/p' "$CONFIG_DIR/zsh/.zshrc"); do
    grep -qE "^\| \`$name\` " "$REPO_ROOT/docs/config/zsh.md" || missing+=("$name")
  done
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented in zsh.md: ${missing[*]}"
}

@test "docs/config/shell.md documents every function functions.sh defines" {
  local name missing=()
  for name in $(sed -n 's/^\([a-z][a-z0-9_]*\)() {$/\1/p' "$CONFIG_DIR/shell/functions.sh"); do
    grep -qF "#### \`$name\`" "$REPO_ROOT/docs/config/shell.md" || missing+=("$name")
  done
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented in shell.md: ${missing[*]}"
}

@test ".zshrc aliases gs to git status on macOS only" {
  # Inside the Darwin block: Linux keeps whatever gs is there.
  run sed -n '/^if \[ "$(uname)" = "Darwin" \]; then$/,/^fi$/p' "$CONFIG_DIR/zsh/.zshrc"
  assert_line '  alias gs="git status"'
  run grep -c '^alias gs=' "$CONFIG_DIR/zsh/.zshrc"
  assert_output "0"
}

# --- The issue commands and the board's columns ---

@test "every label the issue commands set puts the issue in a board column" {
  # The board Worker maps these to its Stage columns (.github/project-board/plan.mjs).
  local columns='needs-triage needs-info ready-for-agent ready-for-human wontfix done' label missing=()
  for label in $(grep -ohE -- '--(add-)?label [a-z-]+' "$CONFIG_DIR"/skills/*/SKILL.md | awk '{print $2}' | sort -u); do
    [[ " $columns " == *" $label "* ]] || missing+=("$label")
    grep -qF "\"$label\"" "$REPO_ROOT/.github/project-board/plan.mjs" || missing+=("$label (plan.mjs)")
  done
  [ "${#missing[@]}" -eq 0 ] || fail "labels with no column: ${missing[*]}"
}

@test "/next-issue records a finished issue as done, so its card moves to Done" {
  run grep -F -- '--remove-label ready-for-agent --add-label done' "$CONFIG_DIR/skills/next-issue/SKILL.md"
  assert_success
  # The label exists before it is set: creating it is safe to repeat.
  run grep -F 'gh label create done --force' "$CONFIG_DIR/skills/next-issue/SKILL.md"
  assert_success
  # Removing ready-for-agent alone would send the card back to Needs triage.
  run grep -nE -- '--remove-label ready-for-agent`' "$CONFIG_DIR/skills/next-issue/SKILL.md"
  assert_failure
}

@test "the docs list every label the board knows, done included" {
  local label
  for label in needs-triage needs-info ready-for-agent ready-for-human wontfix done; do
    grep -qE "gh label create $label " "$REPO_ROOT/docs/config/issue-workflow.md" || fail "no gh label create for $label"
    grep -qF "\`$label\`" "$REPO_ROOT/.agents/triage-labels.md" || fail "triage-labels.md misses $label"
  done
}

@test "every relative link of the docs reaches a file inside docs/" {
  # CI's lychee job checks the same, but the prek hook skips without lychee: a
  # moved page (docs/agents/ to .agents/) broke two links unseen. Outside
  # docs/ is unpublished on the documentation hub (docs-hub skill).
  local file link target bad=""
  while IFS= read -r file; do
    while IFS= read -r link; do
      target=${link%%#*}
      [ -n "$target" ] || continue
      # The target's directory, resolved (macOS has no realpath -m).
      target=$(cd "$(dirname "$REPO_ROOT/$file")" && cd "$(dirname "$target")" 2>/dev/null && echo "$(pwd -P)/$(basename "$target")") || target=""
      [ -n "$target" ] && [ -e "$target" ] || { bad+="$file: $link"$'\n'; continue; }
      case "$target" in "$(cd "$REPO_ROOT" && pwd -P)/docs/"*) ;; *) bad+="$file: $link (outside docs/)"$'\n' ;; esac
    done < <(grep -oE '\]\([^)[:space:]]+\)' "$REPO_ROOT/$file" | sed 's/^](//; s/)$//' | grep -vE '^([a-z]+:|#|/)')
  done < <(cd "$REPO_ROOT" && git ls-files 'docs/*.md')
  [ -z "$bad" ] || fail "broken links:"$'\n'"$bad"
}

@test "make validate lints every tracked YAML file, as the prek hook does" {
  run sed -n '/^validate:/,/^$/p' "$REPO_ROOT/Makefile"
  assert_output --partial "git ls-files"
  refute_output --partial "yamllint --strict .github/workflows/"
  # The rest needs git: the Docker test image has no .git (.dockerignore).
  git -C "$REPO_ROOT" rev-parse --git-dir >/dev/null 2>&1 || skip "not a git checkout"
  # The files it reaches pass, the compose file of the Docker rig included.
  run bash -c "cd '$REPO_ROOT' && git ls-files '*.yml' '*.yaml' | grep -c docker-compose"
  assert_output "1"
  # yamllint is a local extra: CI installs it, so the lint still runs there.
  command -v yamllint >/dev/null 2>&1 || skip "yamllint not installed"
  run bash -c "cd '$REPO_ROOT' && git ls-files -z '*.yml' '*.yaml' | xargs -0 yamllint --strict --config-file .yamllint.yml"
  assert_success
}

@test "the Docker test-bats stage runs the zsh half of the shell function tests" {
  run sed -n '/^FROM base AS test-bats$/,/^FROM /p' "$REPO_ROOT/tests/docker/Dockerfile.test"
  assert_output --regexp 'apt-get install [^|]* zsh'
  # Required there: a missing zsh fails the stage instead of skipping.
  assert_output --partial 'REQUIRE_ZSH=1 bats'
  run grep -F 'REQUIRE_ZSH' "$REPO_ROOT/tests/functions.bats"
  assert_success
}

# --- The owner's work carries no AI attribution ---

@test "AGENTS.md and the commit rules keep AI attribution out of the owner's work" {
  run grep -qi 'no AI attribution' "$REPO_ROOT/AGENTS.md"
  assert_success
  run grep -qi 'no AI attribution' "$CONFIG_DIR/skills/commit-types/SKILL.md"
  assert_success
  # Its copy for VS Code's commit-message button says the same.
  # (settings.json is JSON with comments: read as text.)
  run grep -F 'commit message in English' "$CONFIG_DIR/vscode/settings.json"
  assert_output --partial "no AI attribution"
  # Every command writing to GitHub or proposing a commit says it too.
  local cmd
  for cmd in audit next-issue new-issue next-task pr; do
    grep -qi 'no AI attribution' "$CONFIG_DIR/skills/$cmd/SKILL.md" || fail "$cmd.md says nothing about attribution"
  done
}

@test "Claude Code adds no attribution to commits or pull requests" {
  local settings="$CONFIG_DIR/claude/settings.json"
  run jq -r '.attribution.commit' "$settings"
  assert_output ""
  # A missing key means Claude Code's default footer, so check presence too.
  run jq -r '.attribution | has("commit") and has("pr")' "$settings"
  assert_output "true"
  run jq -r '.attribution.pr' "$settings"
  assert_output ""
}
