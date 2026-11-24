#!/usr/bin/env bash
# bats-run.sh PATH... — run the given Bats files and directories (each
# directory's *.bats, not recursive, like bats) in parallel: the runner of the
# git hooks (prek.toml, scripts/bats-affected.sh). Same verdict as a plain
# `bats PATH...`: any failing test fails the run.
#
# With GNU parallel installed (brew install parallel), bats itself runs the
# tests in parallel, within the files too. Without it, the files run side by
# side, one bats process each, and their output is printed file by file.
#   BATS_RUN_JOBS  parallel jobs (default: the number of CPUs)
set -euo pipefail

# git exports GIT_DIR (and GIT_INDEX_FILE, …) to its hooks; the fixtures'
# `git init` / `git config` would act on this repository with them.
# shellcheck disable=SC2046 # one variable name per word
unset $(git rev-parse --local-env-vars)

if ! command -v bats >/dev/null 2>&1; then
  echo "⚠️  bats not installed — skipping (brew install bats-core)"
  exit 0
fi

jobs="${BATS_RUN_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
case "$jobs" in
  '' | *[!0-9]*) echo "bats-run.sh: BATS_RUN_JOBS must be a number, not '$jobs'" >&2; exit 2 ;;
esac

if parallel --version 2>/dev/null | grep -q '^GNU parallel'; then
  exec bats --jobs "$jobs" "$@"
fi

files=()
for p in "$@"; do
  if [ -d "$p" ]; then
    for f in "${p%/}"/*.bats; do
      if [ -f "$f" ]; then files+=("$f"); fi
    done
  else
    files+=("$p")
  fi
done
if [ "${#files[@]}" -le 1 ] || [ "$jobs" -le 1 ]; then
  exec bats "$@"
fi

out=$(mktemp -d "${TMPDIR:-/tmp}/bats-run.XXXXXX")
trap 'rm -rf "$out"' EXIT

# One bats process per file, the largest first: the long files start early.
# Output goes to $out/<index>; a failing file's index lands in $out/failed.
for i in "${!files[@]}"; do
  printf '%s %s\n' "$(wc -c < "${files[$i]}")" "$i"
done | sort -rn | while read -r _ i; do
  printf '%s\0%s\0' "$i" "${files[$i]}"
done | xargs -0 -n 2 -P "$jobs" bash -c '
  bats --formatter tap "$3" > "$1/$2" 2>&1 || echo "$2" >> "$1/failed"
' _ "$out"

status=0
for i in "${!files[@]}"; do
  echo "# ${files[$i]}"
  cat "$out/$i"
done
if [ -s "$out/failed" ]; then
  status=1
  echo "# failed:"
  sort -n "$out/failed" | while read -r i; do echo "#   ${files[$i]}"; done
fi
exit "$status"
