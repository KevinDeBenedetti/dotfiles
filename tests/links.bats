#!/usr/bin/env bats
# Functional tests for os/helpers/links.sh — the shared symlink logic used by
# scripts/symlink.sh and both OS init scripts. Runs against a throwaway HOME.

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"
  CONFIG_DIR="$REPO_ROOT/config"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
  load 'test_helper/bats-file/load'

  FAKE_HOME="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$FAKE_HOME"
}

run_link_shared_configs() {
  env -u XDG_STATE_HOME HOME="$FAKE_HOME" bash -c \
    "source '$REPO_ROOT/os/helpers/links.sh' && link_shared_configs '$CONFIG_DIR'"
}

@test "link_shared_configs links every shared config into HOME" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
  assert_symlink_to "$CONFIG_DIR/git/ignore" "$FAKE_HOME/.config/git/ignore"
  assert_symlink_to "$CONFIG_DIR/claude/settings.json" "$FAKE_HOME/.claude/settings.json"
  assert_symlink_to "$CONFIG_DIR/opencode/opencode.json" "$FAKE_HOME/.config/opencode/opencode.json"
  assert_symlink_to "$CONFIG_DIR/proto/.prototools" "$FAKE_HOME/.proto/.prototools"
  assert_symlink_to "$CONFIG_DIR/shell/functions.sh" "$FAKE_HOME/.config/dotfiles/functions.sh"
}

@test "link_shared_configs gives opencode a command for every user-invoked skill, and only those" {
  run run_link_shared_configs
  assert_success
  local skill name
  for skill in "$CONFIG_DIR"/skills/*/SKILL.md; do
    name=$(basename "$(dirname "$skill")")
    if grep -q '^disable-model-invocation: true$' "$skill"; then
      assert_symlink_to "$skill" "$FAKE_HOME/.config/opencode/commands/$name.md"
    else
      assert_not_exists "$FAKE_HOME/.config/opencode/commands/$name.md"
    fi
  done
  assert_symlink_to "$CONFIG_DIR/skills/next-task/SKILL.md" "$FAKE_HOME/.config/opencode/commands/next-task.md"
}

@test "link_shared_configs links no command or prompt file for claude and copilot: skills are their commands" {
  local vscode_user="$FAKE_HOME/.config/Code/User"
  [ "$(uname -s)" = "Darwin" ] && vscode_user="$FAKE_HOME/Library/Application Support/Code/User"
  mkdir -p "$vscode_user"
  run run_link_shared_configs
  assert_success
  assert_not_exists "$FAKE_HOME/.claude/commands"
  assert_not_exists "$vscode_user/prompts"
}

@test "link_shared_configs removes the links an earlier version left to the dropped command dirs" {
  local vscode_user="$FAKE_HOME/.config/Code/User"
  [ "$(uname -s)" = "Darwin" ] && vscode_user="$FAKE_HOME/Library/Application Support/Code/User"
  mkdir -p "$FAKE_HOME/.claude/commands" "$FAKE_HOME/.config/opencode/commands" "$vscode_user/prompts"
  ln -s "$CONFIG_DIR/commands/next-task.md" "$FAKE_HOME/.claude/commands/next-task.md"
  ln -s "$CONFIG_DIR/claude/commands/explain.md" "$FAKE_HOME/.claude/commands/explain.md"
  ln -s "$CONFIG_DIR/commands/pr.md" "$FAKE_HOME/.config/opencode/commands/pr-old.md"
  ln -s "$CONFIG_DIR/commands/pr.md" "$vscode_user/prompts/pr.prompt.md"
  # Not ours to remove: the owner's own command, and a dead link to elsewhere.
  echo "mine" > "$FAKE_HOME/.claude/commands/mine.md"
  ln -s "$FAKE_HOME/gone.md" "$FAKE_HOME/.claude/commands/elsewhere.md"
  run run_link_shared_configs
  assert_success
  assert_not_exists "$FAKE_HOME/.claude/commands/next-task.md"
  [ ! -L "$FAKE_HOME/.claude/commands/next-task.md" ]
  [ ! -L "$FAKE_HOME/.claude/commands/explain.md" ]
  [ ! -L "$FAKE_HOME/.config/opencode/commands/pr-old.md" ]
  [ ! -L "$vscode_user/prompts/pr.prompt.md" ]
  assert_file_exists "$FAKE_HOME/.claude/commands/mine.md"
  [ -L "$FAKE_HOME/.claude/commands/elsewhere.md" ]
  # The live opencode command link of the skill is untouched.
  assert_symlink_to "$CONFIG_DIR/skills/pr/SKILL.md" "$FAKE_HOME/.config/opencode/commands/pr.md"
}

@test "link_shared_configs links every shared skill into HOME" {
  run run_link_shared_configs
  assert_success
  local skill
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    assert_symlink_to "$skill" "$FAKE_HOME/.claude/skills/$(basename "$skill")"
  done
}

@test "link_shared_configs links every shared skill into copilot's personal skills" {
  run run_link_shared_configs
  assert_success
  local skill
  for skill in "$CONFIG_DIR"/skills/*/; do
    [ -d "$skill" ] || continue
    assert_symlink_to "$skill" "$FAKE_HOME/.copilot/skills/$(basename "$skill")"
  done
  # OpenCode reads ~/.agents/skills as well as ~/.claude/skills: a third copy
  # there would list every skill twice.
  assert_not_exists "$FAKE_HOME/.agents/skills"
}

@test "link_shared_configs links the global agent rules into the three tools" {
  run run_link_shared_configs
  assert_success
  local rules="$CONFIG_DIR/agents/AGENTS.md"
  # Claude Code reads an entry file of its own, which imports the shared rules
  # next to it and keeps the Claude-only imports out of them.
  assert_symlink_to "$rules" "$FAKE_HOME/.claude/AGENTS.md"
  assert_symlink_to "$CONFIG_DIR/claude/CLAUDE.md" "$FAKE_HOME/.claude/CLAUDE.md"
  assert_symlink_to "$rules" "$FAKE_HOME/.config/opencode/AGENTS.md"
  assert_symlink_to "$rules" "$FAKE_HOME/.copilot/copilot-instructions.md"
}

@test "link_shared_configs backs up an existing global rules file before linking" {
  mkdir -p "$FAKE_HOME/.claude"
  echo "mine" > "$FAKE_HOME/.claude/CLAUDE.md"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/claude/CLAUDE.md" "$FAKE_HOME/.claude/CLAUDE.md"
  run bash -c "cat '$FAKE_HOME'/.claude/CLAUDE.md.bak.*"
  assert_output "mine"
}

@test "link_shared_configs moves an existing regular skill dir out of the skills dir" {
  # ln cannot replace a directory: without the move, the link would land
  # INSIDE the stale dir and the repo's skill would never be installed.
  mkdir -p "$FAKE_HOME/.claude/skills/commit-types"
  echo "old" > "$FAKE_HOME/.claude/skills/commit-types/SKILL.md"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/skills/commit-types/" "$FAKE_HOME/.claude/skills/commit-types"
  # No backup copy left among the skills (it would load as a duplicate skill)…
  run bash -c "ls -d '$FAKE_HOME'/.claude/skills/commit-types.* 2>/dev/null"
  assert_output ""
  # …the old content is preserved under the state backup dir instead.
  run bash -c "cat '$FAKE_HOME'/.local/state/dotfiles/backup/.claude/skills/commit-types.*/SKILL.md"
  assert_output "old"
}

@test "link_shared_configs links every copilot hook into HOME" {
  run run_link_shared_configs
  assert_success
  local hook
  for hook in "$CONFIG_DIR"/copilot/hooks/*; do
    assert_symlink_to "$hook" "$FAKE_HOME/.copilot/hooks/$(basename "$hook")"
  done
}

@test "link_shared_configs links every claude hook script into HOME" {
  run run_link_shared_configs
  assert_success
  local hook
  for hook in "$CONFIG_DIR"/claude/hooks/*; do
    assert_symlink_to "$hook" "$FAKE_HOME/.claude/hooks/$(basename "$hook")"
  done
}

@test "link_shared_configs is idempotent" {
  run run_link_shared_configs
  assert_success
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
}

@test "link_shared_configs backs up an existing regular file" {
  echo "old content" > "$FAKE_HOME/.gitconfig"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
  run bash -c "cat '$FAKE_HOME'/.gitconfig.bak.*"
  assert_output "old content"
}

@test "link_shared_configs skips oh-my-zsh theme when omz is absent" {
  run run_link_shared_configs
  assert_success
  assert_not_exists "$FAKE_HOME/.oh-my-zsh"
}

@test "link_shared_configs links oh-my-zsh theme when omz is present" {
  mkdir -p "$FAKE_HOME/.oh-my-zsh"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/oh-my-zsh/kevin-de-benedetti.zsh-theme" \
    "$FAKE_HOME/.oh-my-zsh/custom/themes/kevin-de-benedetti.zsh-theme"
}

@test "link_shared_configs links ssh config and creates the local config.d dir" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/ssh/config" "$FAKE_HOME/.ssh/config"
  assert_dir_exists "$FAKE_HOME/.ssh/config.d"
}

@test "link_shared_configs leaves local ~/.ssh/config.d files untouched" {
  mkdir -p "$FAKE_HOME/.ssh/config.d"
  printf 'Host k3s\n    HostName 1.2.3.4\n' > "$FAKE_HOME/.ssh/config.d/infra.conf"
  run run_link_shared_configs
  assert_success
  assert_link_not_exists "$FAKE_HOME/.ssh/config.d/infra.conf"
  run cat "$FAKE_HOME/.ssh/config.d/infra.conf"
  assert_line "Host k3s"
}

@test "backup_if_exists keeps the first backup of the day when it runs twice" {
  # The init scripts copy .zshrc instead of linking it: a second run the same
  # day must not back up the installed copy over the user's original.
  echo "the user's original" > "$FAKE_HOME/.zshrc"
  run bash -c "source '$REPO_ROOT/os/helpers/links.sh'
    backup_if_exists '$FAKE_HOME/.zshrc'
    echo 'the repository copy' > '$FAKE_HOME/.zshrc'
    backup_if_exists '$FAKE_HOME/.zshrc'"
  assert_success
  assert_output --partial "already backed up today"
  run bash -c "cat '$FAKE_HOME'/.zshrc.bak.*"
  assert_output "the user's original"
}

@test "backup_if_exists leaves a symlink alone" {
  ln -s /dev/null "$FAKE_HOME/.zshrc"
  run bash -c "source '$REPO_ROOT/os/helpers/links.sh'; backup_if_exists '$FAKE_HOME/.zshrc'; ls -A '$FAKE_HOME'"
  assert_output ".zshrc"
}

# --- Every link group of links.sh (AGENTS.md: each config is wired and tested) ---

vscode_user_in_fake_home() {
  if [ "$(uname -s)" = "Darwin" ]; then
    echo "$FAKE_HOME/Library/Application Support/Code/User"
  else
    echo "$FAKE_HOME/.config/Code/User"
  fi
}

@test "link_shared_configs links the shell environment next to the functions" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/shell/env.sh" "$FAKE_HOME/.config/dotfiles/env.sh"
}

@test "link_shared_configs links the ai-tools and ollama config directories" {
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/ai-tools" "$FAKE_HOME/.config/ai-tools"
  assert_symlink_to "$CONFIG_DIR/ollama" "$FAKE_HOME/.config/ollama"
}

@test "link_shared_configs links every command of scripts/<domain>/ into ~/.local/bin, docs left out" {
  run run_link_shared_configs
  assert_success
  local script count=0
  for script in "$REPO_ROOT"/scripts/*/*; do
    [[ "$script" == *.md ]] && continue
    assert_symlink_to "$CONFIG_DIR/../scripts/${script#"$REPO_ROOT"/scripts/}" "$FAKE_HOME/.local/bin/$(basename "$script")"
    count=$((count + 1))
  done
  [ "$count" -gt 0 ] || fail "no script found under scripts/"
  run bash -c "ls '$FAKE_HOME/.local/bin' | grep -c '\.md$'"
  assert_output "0"
}

@test "link_shared_configs links the Ollama LaunchAgent on macOS only" {
  run run_link_shared_configs
  assert_success
  local plist
  for plist in "$CONFIG_DIR"/ollama/launchd/*.plist; do
    if [ "$(uname -s)" = "Darwin" ]; then
      assert_symlink_to "$plist" "$FAKE_HOME/Library/LaunchAgents/$(basename "$plist")"
    else
      assert_not_exists "$FAKE_HOME/Library/LaunchAgents/$(basename "$plist")"
    fi
  done
}

@test "link_shared_configs links the VS Code settings and MCP config when VS Code has a user dir" {
  local user_dir
  user_dir=$(vscode_user_in_fake_home)
  mkdir -p "$user_dir"
  echo '{"old": true}' > "$user_dir/settings.json"
  run run_link_shared_configs
  assert_success
  assert_symlink_to "$CONFIG_DIR/vscode/settings.json" "$user_dir/settings.json"
  assert_symlink_to "$CONFIG_DIR/vscode/mcp.json" "$user_dir/mcp.json"
  # The settings that were there are backed up, not lost.
  run bash -c "cat '$user_dir'/settings.json.bak.*"
  assert_output '{"old": true}'
}

@test "link_shared_configs creates no VS Code user dir on a machine without VS Code" {
  run run_link_shared_configs
  assert_success
  assert_not_exists "$(vscode_user_in_fake_home)"
}

@test "install_vscode_config creates the user dir and links through links.sh when code is installed" {
  local user_dir
  user_dir=$(vscode_user_in_fake_home)
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  # A code stand-in that reports every recommended extension as installed.
  printf '#!/bin/bash\n[ "$1" = --list-extensions ] && grep -v "//" "%s/vscode/extensions.json" | jq -r ".recommendations[]"\nexit 0\n' "$CONFIG_DIR" > "$BATS_TEST_TMPDIR/bin/code"
  chmod +x "$BATS_TEST_TMPDIR/bin/code"
  run env HOME="$FAKE_HOME" PATH="$BATS_TEST_TMPDIR/bin:$PATH" bash -c \
    "source '$REPO_ROOT/os/helpers/links.sh' && source '$REPO_ROOT/os/helpers/dotfiles.sh' && install_vscode_config '$CONFIG_DIR' '$user_dir'"
  assert_success
  assert_symlink_to "$CONFIG_DIR/vscode/settings.json" "$user_dir/settings.json"
  assert_symlink_to "$CONFIG_DIR/vscode/mcp.json" "$user_dir/mcp.json"
  refute_output --partial "install-extension"
}

@test "scripts/symlink.sh links .zshrc and the shared configs into HOME" {
  run env -u XDG_STATE_HOME HOME="$FAKE_HOME" bash "$REPO_ROOT/scripts/symlink.sh"
  assert_success
  assert_symlink_to "$CONFIG_DIR/zsh/.zshrc" "$FAKE_HOME/.zshrc"
  assert_symlink_to "$CONFIG_DIR/git/.gitconfig" "$FAKE_HOME/.gitconfig"
}
