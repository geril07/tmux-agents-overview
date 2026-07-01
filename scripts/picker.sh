#!/usr/bin/env bash
# Interactive picker for tmux sessions that contain OpenCode.
#
#   picker.sh        fzf picker
#   picker.sh --list print rows only, used by fzf reload bindings

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

session_has_opencode_pane() {
  local session="$1"
  tmux list-panes -t "$session" -F '#{pane_id}\t#{window_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null |
    awk -F '\t' '$3 == "opencode" || $3 == "open-code" { print $1 "\t" $2 "\t" $4; exit }'
}

rank_for_state() {
  case "$1" in
  waiting) printf '0' ;;
  idle) printf '1' ;;
  unknown) printf '2' ;;
  working) printf '3' ;;
  *) printf '2' ;;
  esac
}

icon_for_state() {
  case "$1" in
  waiting) printf '\033[33m●\033[0m waiting' ;;
  idle) printf '\033[32m●\033[0m idle   ' ;;
  working) printf '\033[35m●\033[0m working' ;;
  unknown | *) printf '\033[90m●\033[0m unknown' ;;
  esac
}

emit_rows() {
  local now session state at pane window cwd detected target display_cwd rank icon ago reason session_id tool detail status line
  now=$(date +%s)

  tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r session; do
    state="$(tmux show-options -qv -t "$session" @opencode_state 2>/dev/null)"
    pane="$(tmux show-options -qv -t "$session" @opencode_pane 2>/dev/null)"
    window="$(tmux show-options -qv -t "$session" @opencode_window 2>/dev/null)"
    cwd="$(tmux show-options -qv -t "$session" @opencode_cwd 2>/dev/null)"
    at="$(tmux show-options -qv -t "$session" @opencode_state_at 2>/dev/null)"
    reason="$(tmux show-options -qv -t "$session" @opencode_reason 2>/dev/null)"
    tool="$(tmux show-options -qv -t "$session" @opencode_tool 2>/dev/null)"
    session_id="$(tmux show-options -qv -t "$session" @opencode_session_id 2>/dev/null)"

    detected=""
    if [ -z "$state" ] || [ -z "$pane" ]; then
      detected="$(session_has_opencode_pane "$session")"
    fi

    if [ -z "$state" ] && [ -z "$detected" ]; then
      continue
    fi

    [ -z "$state" ] && state="unknown"
    if [ -z "$pane" ] && [ -n "$detected" ]; then
      pane="$(printf '%s' "$detected" | cut -f1)"
    fi
    if [ -z "$window" ] && [ -n "$detected" ]; then
      window="$(printf '%s' "$detected" | cut -f2)"
    fi
    if [ -z "$cwd" ] && [ -n "$detected" ]; then
      cwd="$(printf '%s' "$detected" | cut -f3-)"
    fi

    target="$session"
    [ -n "$pane" ] && target="$pane"

    rank="$(rank_for_state "$state")"
    icon="$(icon_for_state "$state")"

    if [ -n "$at" ] && [ "$at" -eq "$at" ] 2>/dev/null; then
      ago="$(((now - at) / 60))m"
    else
      ago='-'
    fi

    detail="$reason"
    if [ -n "$tool" ]; then
      if [ -n "$detail" ]; then
        detail="$detail/$tool"
      else
        detail="$tool"
      fi
    fi
    [ -z "$detail" ] && detail='-'
    if [ "$state" = "unknown" ] && { [ "$detail" = "session" ] || [ "$detail" = "status" ]; }; then
      detail='-'
    fi

    status="$icon"

    display_cwd="$(short_home_path "$cwd")"
    [ -z "$display_cwd" ] && display_cwd='-'

    line="$(printf '%-24.24s  %s  %5s  %s' "$session" "$status" "$ago" "$display_cwd")"

    # rank, session, target, window, raw detail are hidden. Visible line is preformatted.
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$rank" "$session" "$target" "$window" "$line" "$detail"
  done | sort -t$'\t' -k1,1n -k5,5n
}

[ "${1:-}" = '--list' ] && {
  emit_rows
  exit 0
}

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-opencode-session-overview: fzf is required"
  exit 0
fi

self="${BASH_SOURCE[0]}"
header=$'OpenCode sessions\nenter: jump  ·  ctrl-x: kill session  ·  ctrl-r: refresh'

sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=5 \
  --height=100% --reverse --cycle \
  --header="$header" \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list)" \
  --bind="ctrl-r:reload($self --list)")

[ -z "$sel" ] && exit 0

target_session="$(printf '%s' "$sel" | cut -f2)"
target_pane="$(printf '%s' "$sel" | cut -f3)"
target_window="$(printf '%s' "$sel" | cut -f4)"
parent="$(tmux show-options -gqv @opencode_overview_parent 2>/dev/null)"

case "$target_pane" in
%*) tmux select-pane -t "$target_pane" 2>/dev/null || true ;;
esac

target="$target_session"
[ -n "$target_window" ] && target="$target_window"

if [ -n "$parent" ]; then
  tmux switch-client -c "$parent" -t "$target" 2>/dev/null || true
else
  tmux switch-client -t "$target" 2>/dev/null || true
fi
