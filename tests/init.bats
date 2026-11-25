#!/usr/bin/env bats

# Tests for init.sh flag parsing and early-exit behavior.
# These tests only validate the argument handling logic — they do NOT
# run any actual install steps (brew, apt, proto, etc.).

setup() {
  DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
  REPO_ROOT="$(cd "$DIR/.." && pwd)"

  load 'test_helper/bats-support/load'
  load 'test_helper/bats-assert/load'
}

# --- macOS init.sh ---

@test "macos init.sh -h prints help and exits 0" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "This script aims to install"
}

@test "macos init.sh with no flags exits 1 with warning" {
  run bash "$REPO_ROOT/os/macos/init.sh"
  assert_failure 1
  assert_output --partial "No profile or action flag provided"
}

@test "macos init.sh -h output contains all documented flags" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "-a"
  assert_output --partial "-c"
  assert_output --partial "-d"
  assert_output --partial "-l"
  assert_output --partial "-p"
  assert_output --partial "-h"
}

@test "macos init.sh -h output lists all profiles" {
  run bash "$REPO_ROOT/os/macos/init.sh" -h
  assert_success
  assert_output --partial "ai"
  assert_output --partial "base"
  assert_output --partial "extras"
  assert_output --partial "javascript"
  assert_output --partial "python"
}

@test "init.sh fails on an unknown flag or a missing argument, after printing help" {
  # Automation must see a typo as a failure: only -h is a successful exit.
  local os
  for os in macos debian; do
    run bash "$REPO_ROOT/os/$os/init.sh" -x
    assert_failure 2
    assert_output --partial "This script aims to install"
    run bash "$REPO_ROOT/os/$os/init.sh" -p
    assert_failure 2
  done
}

# --- Debian init.sh ---

@test "debian init.sh -h prints help and exits 0" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "This script aims to install"
}

@test "debian init.sh with no flags exits 1 with warning" {
  run bash "$REPO_ROOT/os/debian/init.sh"
  assert_failure 1
  assert_output --partial "No profile or action flag provided"
}

@test "debian init.sh -h output contains all documented flags" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "-a"
  assert_output --partial "-c"
  assert_output --partial "-d"
  assert_output --partial "-l"
  assert_output --partial "-p"
  assert_output --partial "-h"
}

@test "debian init.sh -h output lists all profiles" {
  run bash "$REPO_ROOT/os/debian/init.sh" -h
  assert_success
  assert_output --partial "base"
  assert_output --partial "kubernetes"
  assert_output --partial "security"
}

# --- Debian setup-user.sh ---

@test "setup-user.sh rejects a user name with a dot before touching the system" {
  # sudo skips /etc/sudoers.d files whose name contains a dot.
  # SUDO=false: any privileged call that slipped past the check would fail.
  CREATE_USER="first.last" SUDO=false run bash "$REPO_ROOT/os/debian/setup-user.sh"
  assert_failure 1
  assert_output --partial "Invalid user name 'first.last'"
  refute_output --partial "already exists"
}

@test "setup-user.sh rejects a user name with uppercase or a leading digit" {
  for name in Deploy 1deploy "de ploy"; do
    CREATE_USER="$name" SUDO=false run bash "$REPO_ROOT/os/debian/setup-user.sh"
    assert_failure 1
    assert_output --partial "Invalid user name"
  done
}

@test "setup-user.sh validates the NOPASSWD sudoers rule with visudo before installing it" {
  run grep -F 'visudo -cqf "$sudoers_tmp"' "$REPO_ROOT/os/debian/setup-user.sh"
  assert_success
  run grep -F 'tee "/etc/sudoers.d/' "$REPO_ROOT/os/debian/setup-user.sh"
  assert_failure
}

# A sudo stand-in that runs the commands it is given inside $FAKE_ROOT: a path
# under /root/ maps to $FAKE_ROOT/root/, and the account steps (adduser,
# usermod, chown) are only logged. getent answers deploy's home: $USER_HOME.
fake_root_for_setup_user() {
  FAKE_ROOT="$BATS_TEST_TMPDIR/fsroot"
  USER_HOME="${USER_HOME:-$FAKE_ROOT/srv/deploy}"
  mkdir -p "$FAKE_ROOT/root/.ssh" "$BATS_TEST_TMPDIR/bin"
  cat > "$BATS_TEST_TMPDIR/bin/rootsudo" <<STUB
#!/bin/bash
echo "\$*" >> "$BATS_TEST_TMPDIR/sudo.log"
case "\$1" in adduser|usermod|chown) exit 0 ;; esac
args=()
for a in "\$@"; do args+=("\${a//\/root\//$FAKE_ROOT/root/}"); done
exec "\${args[@]}"
STUB
  printf '#!/bin/bash\n[ "$1 $2" = "passwd deploy" ] && echo "deploy:x:1000:1000::%s:/bin/bash"\n' "$USER_HOME" > "$BATS_TEST_TMPDIR/bin/getent"
  printf '#!/bin/bash\nexit 0\n' > "$BATS_TEST_TMPDIR/bin/id"
  chmod +x "$BATS_TEST_TMPDIR/bin/rootsudo" "$BATS_TEST_TMPDIR/bin/getent" "$BATS_TEST_TMPDIR/bin/id"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

run_setup_user() {
  CREATE_USER=deploy SUDO=rootsudo run bash "$REPO_ROOT/os/debian/setup-user.sh"
}

@test "setup-user.sh copies root's authorized_keys when only root can read /root" {
  # /root is mode 700: a sudo user cannot see the file, so the check has to go
  # through sudo like the copy does.
  fake_root_for_setup_user
  printf 'ssh-ed25519 AAAAroot root@vps\n' > "$FAKE_ROOT/root/.ssh/authorized_keys"
  run_setup_user
  assert_success
  run cat "$BATS_TEST_TMPDIR/sudo.log"
  assert_line "test -f /root/.ssh/authorized_keys"
  # The home comes from the passwd database, not from /home/<user>.
  run cat "$USER_HOME/.ssh/authorized_keys"
  assert_output "ssh-ed25519 AAAAroot root@vps"
}

@test "a re-run keeps the user's own keys and adds root's missing ones once" {
  fake_root_for_setup_user
  printf 'ssh-ed25519 AAAAroot root@vps\nssh-ed25519 AAAAnew root@laptop\n' > "$FAKE_ROOT/root/.ssh/authorized_keys"
  mkdir -p "$USER_HOME/.ssh"
  # The user's own key, saved without a final newline.
  printf 'ssh-ed25519 AAAAroot root@vps\nssh-ed25519 AAAAmine deploy@phone' > "$USER_HOME/.ssh/authorized_keys"
  run_setup_user
  assert_success
  run_setup_user
  assert_success
  run cat "$USER_HOME/.ssh/authorized_keys"
  assert_output $'ssh-ed25519 AAAAroot root@vps\nssh-ed25519 AAAAmine deploy@phone\nssh-ed25519 AAAAnew root@laptop'
}

@test "every key of root's file is added: the last one without a newline, a CRLF one once" {
  fake_root_for_setup_user
  printf 'ssh-ed25519 AAAAone root@vps\r\nssh-ed25519 AAAAlast root@vps' > "$FAKE_ROOT/root/.ssh/authorized_keys"
  run_setup_user
  run_setup_user
  run cat "$USER_HOME/.ssh/authorized_keys"
  assert_output $'ssh-ed25519 AAAAone root@vps\nssh-ed25519 AAAAlast root@vps'
}

@test "setup-user.sh skips the key copy when root has no authorized_keys" {
  fake_root_for_setup_user
  rmdir "$FAKE_ROOT/root/.ssh"
  run_setup_user
  assert_success
  assert_output --partial "skipping key copy"
  [ ! -e "$USER_HOME/.ssh" ] || fail "a key directory was created with no key to put in it"
}

# --- macOS toolchain profiles ---

@test "macOS sets up proto and its pinned versions before the toolchain profiles" {
  # setup-javascript.sh and setup-python.sh call `proto install`, which reads
  # ~/.proto/.prototools: both must exist first, with or without the base
  # profile (-p javascript alone on a fresh Mac).
  local init="$REPO_ROOT/os/macos/init.sh" block
  block=$(sed -n '/^# Proto for the toolchain profiles$/,/^fi$/p' "$init")
  [ -n "$block" ] || fail "no proto block for the toolchain profiles in $init"
  assert_equal "$(grep -c 'INSTALL_JAVASCRIPT' <<<"$block")" 1
  run grep -F 'bash "$HELPERS_DIR/proto.sh"' <<<"$block"
  assert_success
  run grep -F 'link_with_backup "$CONFIG_DIR/proto/.prototools" "$HOME/.proto/.prototools"' <<<"$block"
  assert_success
  local proto_line js_line py_line
  proto_line=$(grep -n '^# Proto for the toolchain profiles$' "$init" | cut -d: -f1)
  js_line=$(grep -n 'setup-javascript.sh' "$init" | head -n1 | cut -d: -f1)
  py_line=$(grep -n 'setup-python.sh' "$init" | head -n1 | cut -d: -f1)
  [ "$proto_line" -lt "$js_line" ] && [ "$proto_line" -lt "$py_line" ]
}

# --- Documented flags ---

@test "every flag init.sh parses has a row in its platform docs and in getting-started" {
  local os flags flag missing=()
  for os in debian macos; do
    flags=$(sed -n 's/^while getopts \([a-z:]*\) flag; do$/\1/p' "$REPO_ROOT/os/$os/init.sh" | tr -d ':' | fold -w1)
    [ -n "$flags" ] || fail "no getopts line in os/$os/init.sh"
    for flag in $flags; do
      grep -qE "^\| \`-$flag[\` ]" "$REPO_ROOT/docs/setup/$os.md" || missing+=("$os.md:-$flag")
      grep -qE "^\| \`-$flag[\` ]" "$REPO_ROOT/docs/getting-started.md" || missing+=("getting-started.md:-$flag")
    done
  done
  [ "${#missing[@]}" -eq 0 ] || fail "undocumented flags: ${missing[*]}"
}

# --- Flags that are gone, steps that run once (issue 128) ---

@test "-r is no longer a flag: it only ever printed that nothing was removed" {
  local os
  for os in debian macos; do
    run bash "$REPO_ROOT/os/$os/init.sh" -r
    assert_failure 2
    assert_output --partial "This script aims to install"
    refute_output --partial "Remove tmp files"
    run bash "$REPO_ROOT/os/$os/init.sh" -h
    refute_output --partial "  -r "
    run grep -c 'REMOVE_TMP_CONTENT' "$REPO_ROOT/os/$os/init.sh"
    assert_output 0
    run grep -cE '^\| `-r`' "$REPO_ROOT/docs/setup/$os.md"
    assert_output 0
  done
  run grep -cE '^\| `-r`' "$REPO_ROOT/docs/getting-started.md"
  assert_output 0
}

@test "Debian installs proto once per run, in the base profile or with the dotfiles" {
  # -a runs both steps: the dotfiles step leaves proto to the base profile.
  local init="$REPO_ROOT/os/debian/init.sh"
  run grep -c '^  bash "$HELPERS_DIR/proto.sh"$' "$init"
  assert_output 1
  run grep -c '^  \[\[ "$INSTALL_BASE" = "true" \]\] || bash "$HELPERS_DIR/proto.sh"$' "$init"
  assert_output 1
}

# --- Remote bootstrap ---

# bootstrap <os> [args...]: runs init.sh the way the remote one-liner does (no
# sub-script beside it), with a git that logs its calls to $GIT_LOG and whose
# clone leaves an init.sh printing the arguments it was re-run with.
bootstrap() {
  local os="$1"
  shift
  local work="$BATS_TEST_TMPDIR/remote" bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$work" "$bin"
  cp "$REPO_ROOT/os/$os/init.sh" "$work/init.sh"
  export GIT_LOG="$BATS_TEST_TMPDIR/git.log" BOOTSTRAP_OS="$os"
  export DOTFILES_INSTALL_DIR="${DOTFILES_INSTALL_DIR:-$BATS_TEST_TMPDIR/dotfiles}"
  cat > "$bin/git" <<'GIT'
#!/bin/bash
echo "$*" >> "$GIT_LOG"
if [ "$3" = rev-parse ]; then echo "${SHALLOW:-true}"; exit 0; fi
if [ "$1" = clone ]; then
  dest="${*: -1}"
  mkdir -p "$dest/os/$BOOTSTRAP_OS"
  printf '%s\n' '#!/bin/bash' 'echo "re-run with: $*"' > "$dest/os/$BOOTSTRAP_OS/init.sh"
fi
GIT
  chmod +x "$bin/git"
  PATH="$bin:$PATH" run "${BOOTSTRAP_BASH:-bash}" "$work/init.sh" "$@"
}

released_tag() {
  echo "v$(sed -n 's/.*"\.": "\([0-9.]*\)".*/\1/p' "$REPO_ROOT/.github/release/.release-please-manifest.json")"
}

@test "a fresh remote bootstrap clones the released tag, not the tip of main" {
  local os
  for os in debian macos; do
    rm -rf "$BATS_TEST_TMPDIR/dotfiles" "$BATS_TEST_TMPDIR/git.log"
    bootstrap "$os" -h
    assert_success
    assert_output --partial "re-run with: -h"
    run cat "$GIT_LOG"
    assert_output "clone --depth=1 --branch $(released_tag) https://github.com/KevinDeBenedetti/dotfiles.git $BATS_TEST_TMPDIR/dotfiles"
  done
}

@test "DOTFILES_REF overrides the ref the bootstrap clones" {
  local os
  for os in debian macos; do
    rm -rf "$BATS_TEST_TMPDIR/dotfiles" "$BATS_TEST_TMPDIR/git.log"
    DOTFILES_REF=main bootstrap "$os" -h
    assert_success
    run cat "$GIT_LOG"
    assert_output --partial "clone --depth=1 --branch main "
  done
}

@test "a re-run on an existing checkout fetches and checks out the ref instead of pulling main" {
  local os dest="$BATS_TEST_TMPDIR/dotfiles"
  for os in debian macos; do
    rm -rf "$dest" "$BATS_TEST_TMPDIR/git.log"
    mkdir -p "$dest/.git" "$dest/os/$os"
    printf '%s\n' '#!/bin/bash' 'echo "re-run with: $*"' > "$dest/os/$os/init.sh"
    DOTFILES_REF=v9.9.9 bootstrap "$os" -h
    assert_success
    assert_output --partial "re-run with: -h"
    run cat "$GIT_LOG"
    assert_line "-C $dest fetch --depth=1 origin v9.9.9"
    assert_line "-C $dest checkout --quiet --detach FETCH_HEAD"
    refute_output --partial "pull"
    # A full clone is not made shallow by the fetch.
    rm -f "$BATS_TEST_TMPDIR/git.log"
    SHALLOW=false DOTFILES_REF=v9.9.9 bootstrap "$os" -h
    assert_success
    run cat "$GIT_LOG"
    assert_line "-C $dest fetch origin v9.9.9"
  done
}

@test "release-please bumps the bootstrap's default ref and the documented one-liners" {
  local file config="$REPO_ROOT/.github/release/release-please-config.json"
  for file in os/debian/init.sh os/macos/init.sh; do
    run grep -c "^DOTFILES_REF=\"\${DOTFILES_REF:-$(released_tag)}\" # x-release-please-version$" "$REPO_ROOT/$file"
    assert_output 1
  done
  for file in os/debian/init.sh os/macos/init.sh README.md docs/getting-started.md docs/setup/debian.md docs/setup/macos.md; do
    run jq -e --arg f "$file" '.packages["."]["extra-files"] | index($f)' "$config"
    assert_success
  done
  # No one-liner fetches init.sh from a branch, and each sits in a block
  # release-please rewrites.
  for file in README.md docs/getting-started.md docs/setup/debian.md docs/setup/macos.md; do
    run grep -E 'raw\.githubusercontent\.com/KevinDeBenedetti/dotfiles/' "$REPO_ROOT/$file"
    assert_success
    refute_output --partial "/dotfiles/main/"
    assert_output --partial "/dotfiles/$(released_tag)/os/"
    run grep -c 'x-release-please-start-version' "$REPO_ROOT/$file"
    assert_success
  done
}
