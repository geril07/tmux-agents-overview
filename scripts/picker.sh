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
  tmux list-panes -t "$session" -F '#{pane_id}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null |
    awk -F '\t' '$2 == "opencode" || $2 == "open-code" { print $1 "\t" $3; exit }'
}

rank_for_state() {
  case "$1" in
  waiting) printf '0' ;;
  idle) printf '1' ;;
  error) printf '2' ;;
  unknown) printf '3' ;;
  working) printf '4' ;;
  *) printf '3' ;;
  esac
}

icon_for_state() {
  case "$1" in
  waiting) printf '\033[33m●\033[0m waiting' ;;
  idle) printf '\033[32m●\033[0m idle   ' ;;
  error) printf '\033[31m●\033[0m error  ' ;;
  working) printf '\033[35m●\033[0m working' ;;
  unknown | *) printf '\033[90m●\033[0m unknown' ;;
  esac
}

emit_rows() {
  local now session state at pane cwd detected target display_cwd rank icon ago reason session_id tool detail
  now=$(date +%s)

  tmux list-sessions -F '#{session_name}' 2>/dev/null | while IFS= read -r session; do
    state="$(tmux show-options -qv -t "$session" @opencode_state 2>/dev/null)"
    pane="$(tmux show-options -qv -t "$session" @opencode_pane 2>/dev/null)"
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
    if [ -z "$cwd" ] && [ -n "$detected" ]; then
      cwd="$(printf '%s' "$detected" | cut -f2-)"
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

    display_cwd="$(short_home_path "$cwd")"
    [ -z "$display_cwd" ] && display_cwd='-'

    # rank, session, target are hidden. Visible: state, age, session, cwd, detail.
    printf '%s\t%s\t%s\t%s\t%5s\t%s\t%s\t%s\n' \
      "$rank" "$session" "$target" "$icon" "$ago" "$session" "$display_cwd" "$detail"
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
export FZF_DEFAULT_OPTS=''

sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=4,5,6,7,8 \
  --reverse --cycle \
  --header='OpenCode sessions · enter: jump · ctrl-x: kill session · ctrl-r: refresh' \
  --preview='tmux capture-pane -ept {3}' --preview-window='right,62%,wrap' \
  --bind="ctrl-x:execute-silent(tmux kill-session -t {2})+reload($self --list)" \
  --bind="ctrl-r:reload($self --list)")

[ -z "$sel" ] && exit 0

target_session="$(printf '%s' "$sel" | cut -f2)"
target_pane="$(printf '%s' "$sel" | cut -f3)"
parent="$(tmux show-options -gqv @opencode_overview_parent 2>/dev/null)"

if [ -n "$parent" ]; then
  tmux switch-client -c "$parent" -t "$target_session" 2>/dev/null || true
else
  tmux switch-client -t "$target_session" 2>/dev/null || true
fi

case "$target_pane" in
%*) tmux select-pane -t "$target_pane" 2>/dev/null || true ;;
esac
