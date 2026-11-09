#!/usr/bin/env bash
# Claude Code Stop hook — after each turn, show the owner what is left to do:
# the next actions read from the repository (resolve conflicts, re-stage,
# commit, push, unblock, resume or start the next task, triage, slim TODO.md)
# and the open steps of the `🖐 Manual` section of the project's TODO.md. It
# reads the English layout of the todo-md skill and the former French one.
#
# It only returns a `systemMessage`: shown to the owner, never sent to Claude
# and never blocking the stop, so it costs no extra turn. It must stay
# synchronous — an async hook hands its systemMessage to Claude instead.
#
#   DOTFILES_NEXT_STEPS         changed (default): show a message only when it
#                               differs from the session's previous one;
#                               always: after every turn; off: never.
#   DOTFILES_NEXT_STEPS_MANUAL  manual steps listed (default 10, 0 = all).

set -uo pipefail

mode=${DOTFILES_NEXT_STEPS:-changed}
[ "$mode" = off ] && exit 0
max_manual=${DOTFILES_NEXT_STEPS_MANUAL:-10}
[[ $max_manual =~ ^[0-9]+$ ]] || max_manual=10
command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)

dir=$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null)
[ -n "$dir" ] || dir=$PWD
session=$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null)
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || root=$dir

steps=()
add() { steps+=("• $*"); }
# plural <count> <word> [<plural>] — "1 file", "2 files".
plural() { if [ "$1" -eq 1 ]; then printf '%s %s' "$1" "$2"; else printf '%s %s' "$1" "${3:-$2s}"; fi; }
# clip <n> <text> — at most n characters (code points, not bytes), "…" when cut.
clip() { jq -rn --arg s "$2" --argjson n "$1" 'if ($s | length) > $n then $s[0:$n - 1] + "…" else $s end'; }
# first <n> <lines> — the first n lines joined with spaces, "…" when cut.
first() {
  local n=$1 list=$2 total
  total=$(grep -c . <<<"$list")
  printf '%s' "$(head -n "$n" <<<"$list" | tr '\n' ' ' | sed 's/ $//')"
  [ "$total" -gt "$n" ] && printf ' …'
  return 0
}

# --- Repository state ----------------------------------------------------------
if git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  status=$(git -C "$root" status --porcelain 2>/dev/null)
  conflict_re='^(DD|AU|UD|UA|DU|AA|UU) '
  conflicts=$(grep -E "$conflict_re" <<<"$status" | cut -c4-)
  status=$(grep -vE "$conflict_re" <<<"$status")
  partial=$(grep -E '^[MTARC][MTD] ' <<<"$status" | cut -c4- | sed 's/.* -> //')
  staged=$(grep -cE '^[MTADRC]' <<<"$status")
  pending=$(grep -cE '^(.[MTD]|\?\?)' <<<"$status")
  ahead=$(git -C "$root" rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)

  [ -n "$conflicts" ] && add "Resolve the merge conflicts: $(first 3 "$conflicts")"
  [ -n "$partial" ] && add "Re-stage what changed after git add: git add $(first 3 "$partial")"
  if [ "$staged" -gt 0 ]; then
    if [ "$pending" -gt 0 ]; then
      add "Commit: $(plural "$staged" file) staged, $pending more not staged"
    else
      add "Commit: $(plural "$staged" file) staged"
    fi
  elif [ "$pending" -gt 0 ]; then
    add "Review, stage and commit: $(plural "$pending" changed\ file)"
  fi
  [ "$ahead" -gt 0 ] && add "Push: $(plural "$ahead" commit) not pushed yet"
fi

# --- TODO.md ------------------------------------------------------------------
manual=()
todo=$root/TODO.md
if [ -f "$todo" ]; then
  # One "<section>\t<item>" line per open item, "done\t" per done entry.
  # Sections are told by emoji first, then by English or French words.
  parsed=$(awk '
    /^## / {
      h = tolower($0); sec = ""
      if      (h ~ /🖐|manual|manuel/)            sec = "manual"
      else if (h ~ /🔴|in progress|en cours/)      sec = "progress"
      else if (h ~ /🟡|to do|todo|à faire/)        sec = "todo"
      else if (h ~ /🤖|recomm/)                    sec = "rec"
      else if (h ~ /🔒|security/)                  sec = "sec"
      else if (h ~ /✅|done|fait/)                 sec = "done"
      next
    }
    sec == "done" && /^- \[[xX]\]/ { print "done\t"; next }
    sec != "" && sec != "done" && /^- \[ \] / { sub(/^- \[ \] /, ""); print sec "\t" $0 }
  ' "$todo")

  progress=() blocked=() next=() recs=0 secs=0 dones=0 urgent=""
  while IFS=$'\t' read -r kind item; do
    case $kind in
      manual) manual+=("$item") ;;
      progress | todo)
        if [[ $item == *BLOCKED* ]]; then blocked+=("$item")
        elif [ "$kind" = progress ]; then progress+=("$item")
        else
          next+=("$item")
          [ -z "$urgent" ] && [[ $item =~ ^[A-Z]+\(URGENT\) ]] && urgent=$item
        fi ;;
      rec) recs=$((recs + 1)) ;;
      sec) secs=$((secs + 1)) ;;
      done) dones=$((dones + 1)) ;;
    esac
  done <<<"$parsed"

  # What each blocked task waits for comes first, so line cuts keep it. Empty
  # arrays are never expanded: bash 3.2 (macOS) calls them unbound.
  i=0
  while [ "$i" -lt "${#blocked[@]}" ] && [ "$i" -lt 3 ]; do
    item=${blocked[$i]}
    need=${item#*BLOCKED} && need=${need#*: } && need=${need%.}
    add "Blocked — $(clip 60 "$need") → ${item%% — BLOCKED*}"
    i=$((i + 1))
  done
  [ "${#blocked[@]}" -gt 3 ] && add "… $((${#blocked[@]} - 3)) more blocked"
  if [ "${#progress[@]}" -gt 0 ]; then
    add "Resume: /next-task → ${progress[0]}"
  elif [ "${#next[@]}" -gt 0 ]; then
    add "Next task ($(plural "${#next[@]}" open\ task)): /next-task → ${urgent:-${next[0]}}"
  fi
  if [ $((recs + secs)) -gt 0 ]; then
    add "Triage: $(plural "$recs" recommendation), $(plural "$secs" security\ finding) → move the keepers to 🟡 To do"
  fi
  bytes=$(wc -c <"$todo" | tr -d ' ')
  if [ "$bytes" -gt 30000 ]; then
    add "Slim TODO.md: $((bytes / 1024)) KB, about $(((bytes / 4 + 500) / 1000))k tokens on every /next-task run ($(plural "$dones" "done entry" "done entries"))"
  fi
fi

# --- Message ------------------------------------------------------------------
msg=""
if [ "${#steps[@]}" -gt 0 ]; then
  msg="Next steps — $(basename "$root")"
  for line in "${steps[@]}"; do msg+=$'\n'"$line"; done
fi
if [ "${#manual[@]}" -gt 0 ]; then
  [ -n "$msg" ] && msg+=$'\n'
  msg+="🖐 Manual steps ($(plural "${#manual[@]}" open\ step)):"
  shown=${#manual[@]}
  [ "$max_manual" -gt 0 ] && [ "$shown" -gt "$max_manual" ] && shown=$max_manual
  for item in "${manual[@]:0:$shown}"; do msg+=$'\n'"  ◦ $item"; done
  [ "$shown" -lt "${#manual[@]}" ] && msg+=$'\n'"  … $((${#manual[@]} - shown)) more in TODO.md"
fi

# Show a message once per session until it changes (empty ones are recorded
# too, so a message that comes back is shown again).
if [ "$mode" != always ] && [ -n "$session" ]; then
  state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/next-steps
  state=$state_dir/$(printf '%s' "$session" | tr -c 'A-Za-z0-9_-' '_')
  if mkdir -p "$state_dir" 2>/dev/null; then
    [ -f "$state" ] && [ "$(cat "$state")" = "$msg" ] && exit 0
    printf '%s' "$msg" >"$state"
    find "$state_dir" -type f -mtime +7 -delete 2>/dev/null
  fi
fi

[ -n "$msg" ] || exit 0
# Lines are cut to 110 characters (jq counts code points, not bytes).
jq -n --arg m "$msg" \
  '{systemMessage: ($m | split("\n") | map(if length > 110 then .[0:109] + "…" else . end) | join("\n"))}'
