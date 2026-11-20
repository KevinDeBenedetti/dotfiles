#!/usr/bin/env bash
# Verified installs, shared by the setup scripts: downloads kept only when
# their SHA-256 is the pinned one, apt keys trusted only with their pinned
# fingerprint, and git clones at a pinned commit.
# Sourced, never executed.

# fetch_verified <url> <sha256> <dest>
# Download <url> to <dest> and keep it only if its SHA-256 is <sha256>. On any
# failure (HTTP error, truncated or tampered download) <dest> is removed and
# the function fails, so a caller can never use unverified bytes.
fetch_verified() {
  local url="$1" sha256="$2" dest="$3" actual
  # An empty or malformed pin must never compare equal to an empty result.
  [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || return 1
  if ! curl -fsSL -o "$dest" "$url"; then
    rm -f "$dest"
    return 1
  fi
  # macOS ships shasum; sha256sum is not guaranteed there.
  if command -v sha256sum >/dev/null 2>&1; then
    actual=$(sha256sum "$dest")
  elif command -v shasum >/dev/null 2>&1; then
    actual=$(shasum -a 256 "$dest")
  else
    actual=""
  fi
  if [ "${actual%% *}" != "$sha256" ]; then
    rm -f "$dest"
    return 1
  fi
}

# install_from_tarball [--sudo] <name> <url> <sha256> <dest_dir> <member>...
# Download a release tarball (any compression tar detects), keep it only if
# its SHA-256 is <sha256>, and install each <member> (a path inside the
# tarball) into <dest_dir> as an executable named after its last component.
# --sudo runs the install steps through $SUDO, for a system directory.
# Every step is checked explicitly, so the function is also correct where
# errexit is off; its temp dir is removed whatever happens.
install_from_tarball() {
  local run_as=""
  if [ "$1" = "--sudo" ]; then run_as="${SUDO:-}"; shift; fi
  local name="$1" url="$2" sha256="$3" dest_dir="$4"
  shift 4
  local tmp member rc=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/${name}.XXXXXX") || return 1
  if ! fetch_verified "$url" "$sha256" "$tmp/release.tar"; then
    printf '%b' "${red:-}[error]${no_color:-} $url could not be downloaded or does not match its pinned SHA-256 — $name not installed.\n"
    rc=1
  elif ! tar -xf "$tmp/release.tar" -C "$tmp" "$@"; then
    printf '%b' "${red:-}[error]${no_color:-} $name could not be extracted from its tarball — $name not installed.\n"
    rc=1
  elif ! $run_as mkdir -p "$dest_dir"; then
    printf '%b' "${red:-}[error]${no_color:-} $dest_dir could not be created — $name not installed.\n"
    rc=1
  else
    for member in "$@"; do
      if ! $run_as install -m 0755 "$tmp/$member" "$dest_dir/${member##*/}"; then
        printf '%b' "${red:-}[error]${no_color:-} ${member##*/} could not be installed into $dest_dir — $name not installed.\n"
        rc=1
        break
      fi
    done
  fi
  rm -rf "$tmp"
  return "$rc"
}

# install_deb_verified <name> <url> <sha256>
# Download a .deb, keep it only if its SHA-256 is <sha256>, and install it
# with apt-get through $SUDO (apt resolves its dependencies, unlike dpkg -i).
# Nothing reaches apt unless it matched; the temp dir is removed whatever
# happens.
install_deb_verified() {
  local name="$1" url="$2" sha256="$3" tmp rc=0
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/${name}.XXXXXX") || return 1
  # apt's download user (_apt) must be able to read the file.
  chmod 755 "$tmp"
  if ! fetch_verified "$url" "$sha256" "$tmp/$name.deb"; then
    printf '%b' "${red:-}[error]${no_color:-} $url could not be downloaded or does not match its pinned SHA-256 — $name not installed.\n"
    rc=1
  elif ! chmod 644 "$tmp/$name.deb" \
      || ! ${SUDO:-} apt-get install -y --no-install-recommends "$tmp/$name.deb"; then
    printf '%b' "${red:-}[error]${no_color:-} apt could not install $name — $name not installed.\n"
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

# install_apt_key <url> <fingerprint> <keyring>
# Download an apt repository key and write it into <keyring> (through $SUDO)
# only when it is the key with that fingerprint. Until 2026-11-12 the keys were
# piped from curl straight into `gpg --dearmor`: apt then trusted, for every
# package of that repository, whatever the URL served that day. A rotated or
# swapped key now fails here instead. The file must hold that one key only: an
# extra key appended to it would land in the keyring too. Every step is
# checked explicitly; the temp dir is removed whatever happens.
install_apt_key() {
  local url="$1" key_fpr="$2" keyring="$3"
  local tmp status=0
  # Without gpg the check below fails as a fingerprint mismatch: say what is
  # really missing, before anything is downloaded.
  if ! command -v gpg &>/dev/null; then
    printf '%b' "${red:-}[error]${no_color:-} gpg is not installed (apt package gnupg) — cannot check the apt key from $url.\n"
    return 1
  fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/apt-key.XXXXXX") || return 1
  if ! curl -fsSL -o "$tmp/key" "$url"; then
    printf '%b' "${red:-}[error]${no_color:-} apt key from $url could not be downloaded.\n"
    status=1
  elif ! GNUPGHOME="$tmp" gpg --show-keys --with-colons "$tmp/key" 2>/dev/null \
      | awk -F: '$1 == "pub" { n++ } $1 == "fpr" && !fpr { fpr = $10 } END { if (n == 1) print fpr }' \
      | grep -qx "$key_fpr"; then
    printf '%b' "${red:-}[error]${no_color:-} apt key from $url does not match fingerprint $key_fpr — not trusting it.\n"
    status=1
  elif ! GNUPGHOME="$tmp" gpg --dearmor < "$tmp/key" > "$tmp/keyring" \
      || ! ${SUDO:-} install -m 0755 -d "$(dirname "$keyring")" \
      || ! ${SUDO:-} install -m 0644 "$tmp/keyring" "$keyring"; then
    printf '%b' "${red:-}[error]${no_color:-} $keyring could not be written.\n"
    status=1
  fi
  rm -rf "$tmp"
  return "$status"
}

# clone_at_commit <name> <repo_url> <commit> <dest> [<git-config-key>=<value>...]
# Clone <repo_url> into <dest> at exactly <commit> (a full 40-hex hash: git
# verifies the content against it, so nothing unreviewed can come with it).
# <dest> must not exist. The clone is built next to it and moved into place
# only once complete, so a failed or interrupted run leaves no <dest> behind.
# The checkout is not group- or world-writable (zsh's compinit refuses such
# directories), keeps LF line endings, and sits on a `master` branch tracking
# origin, so a later `git pull` (oh-my-zsh's updater, a plugin update) works.
# Each extra <key>=<value> is set in the clone's git config before it is moved
# into place, so a failure there leaves no <dest> either.
clone_at_commit() {
  local name="$1" repo_url="$2" commit="$3" dest="$4" staging
  shift 4
  if [[ ! "$commit" =~ ^[0-9a-f]{40}$ ]]; then
    printf '%b' "${red:-}[error]${no_color:-} '$commit' is not a full commit hash — $name not installed.\n"
    return 1
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    printf '%b' "${red:-}[error]${no_color:-} $dest already exists — $name not installed.\n"
    return 1
  fi
  mkdir -p "$(dirname "$dest")" || return 1
  staging=$(mktemp -d "${dest}.XXXXXX") || return 1
  if ! (
    umask g-w,o-w
    chmod go-w "$staging" \
      && git init --quiet "$staging" \
      && git -C "$staging" config core.eol lf \
      && git -C "$staging" config core.autocrlf false \
      && git -C "$staging" config branch.master.remote origin \
      && git -C "$staging" config branch.master.merge refs/heads/master \
      && git -C "$staging" remote add origin "$repo_url" \
      && git -C "$staging" fetch --quiet --depth=1 origin "$commit" \
      && git -C "$staging" checkout --quiet -B master FETCH_HEAD \
      && [ "$(git -C "$staging" rev-parse HEAD)" = "$commit" ] \
      && for setting in "$@"; do
        git -C "$staging" config "${setting%%=*}" "${setting#*=}" || exit 1
      done
  ) || ! mv "$staging" "$dest"; then
    rm -rf "$staging"
    printf '%b' "${red:-}[error]${no_color:-} $repo_url could not be cloned at $commit — $name not installed.\n"
    return 1
  fi
}
