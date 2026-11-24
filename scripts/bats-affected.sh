#!/usr/bin/env bash
# bats-affected.sh [--list] FILE... — run the Bats files that cover the given
# files: the pre-commit hook's fast path (prek.toml). The whole suite still
# runs at pre-push and in CI.
#
# A test file covers a changed file when it is that file, or when it names the
# file's path (the tests read what they test by path), its path without the
# leading config/ ($CONFIG_DIR/…), or its name for a helper under tests/. Code
# other files source or import (os/helpers/, the .mjs modules) is also covered
# by every test naming its directory: the tests of the files that use it. A
# file no test names falls back to the tests naming its directory. A file none of these find runs the whole suite: a missed
# test costs more than a slow commit.
#   --list  print the selected test files (or ALL) instead of running them
set -euo pipefail

# git exports GIT_DIR (and GIT_INDEX_FILE, …) to its hooks; the fixtures'
# `git init` / `git config` would act on this repository with them.
# shellcheck disable=SC2046 # one variable name per word
unset $(git rev-parse --local-env-vars)

list=false
if [ "${1:-}" = --list ]; then
  list=true
  shift
fi

cd "$(dirname "$0")/.."
suite=(tests/ tests/ai/ tests/ollama/)

# search -e PATTERN…: the test files naming one of the patterns. This script's
# own tests are left out: the paths they name are test data, not coverage.
search() {
  grep -rlF --include='*.bats' --exclude-dir=test_helper --exclude=bats-affected.bats "$@" tests || true
}

# covering FILE: the test files that cover FILE, one per line (none: empty).
covering() {
  local f="$1" dir hits patterns=()
  case "$f" in
    tests/test_helper/*) return 0 ;;
    tests/*.bats) # `*` matches `/` too: tests/ai/*.bats as well
      # A deleted test file selects nothing, so the whole suite runs.
      if [ -f "$f" ]; then echo "$f"; fi
      return 0 ;;
    scripts/bats-affected.sh)
      # Its tests name paths as data, so they are left out of every search.
      echo tests/bats-affected.bats
      return 0 ;;
  esac
  patterns=(-e "$f" -e "${f#config/}")
  [[ "$f" == tests/* ]] && patterns+=(-e "${f##*/}")
  # Code other files source or import (the shell helpers, the Worker's
  # modules) is tested through its users too: every test naming its directory.
  case "$f" in
    os/helpers/* | *.mjs) dir="${f%/*}"; patterns+=(-e "$dir") ;;
  esac
  hits=$(search "${patterns[@]}")
  # A file no test names: the tests naming its directory, two levels deep at
  # least (a docs/setup/ page, a .github/ module), before the whole suite.
  dir="${f%/*}"
  if [ -z "$hits" ] && [[ "$f" == */* && "$dir" == */* ]]; then
    hits=$(search -e "$dir")
  fi
  printf '%s' "$hits"
}

selected=""
for f in "$@"; do
  hits=$(covering "$f")
  if [ -z "$hits" ]; then
    selected=ALL
    break
  fi
  selected+="$hits"$'\n'
done
[ "$selected" = ALL ] || selected=$(printf '%s' "$selected" | sed '/^$/d' | sort -u)

if $list; then
  [ -z "$selected" ] || echo "$selected"
  exit 0
fi
[ -n "$selected" ] || exit 0
if [ "$selected" = ALL ]; then
  exec bash scripts/bats-run.sh "${suite[@]}"
fi
# shellcheck disable=SC2086 # one test file per word
exec bash scripts/bats-run.sh $selected
