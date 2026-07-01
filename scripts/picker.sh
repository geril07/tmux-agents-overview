#!/usr/bin/env bash
# Interactive picker for tmux panes that contain OpenCode.
#
#   picker.sh        fzf picker
#   picker.sh --list print rows only, used by fzf reload bindings

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

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

format_display_line() {
  local columns="${1:-pane,status,age,cwd}"
  local label="$2" status="$3" ago="$4" display_cwd="$5" detail="$6" command="$7" pane="$8"
  local line='' column part
  local selected_columns=()

  columns="${columns// /}"
  [ -z "$columns" ] && columns='pane,status,age,cwd'

  IFS=',' read -r -a selected_columns <<<"$columns"
  for column in "${selected_columns[@]}"; do
    case "$column" in
    pane | label) part="$(printf '%-30.30s' "$label")" ;;
    status | state) part="$status" ;;
    age | ago) part="$(printf '%5s' "$ago")" ;;
    cwd | path) part="$display_cwd" ;;
    detail | reason) part="$detail" ;;
    command | cmd) part="$command" ;;
    pane_id | pane-id) part="$pane" ;;
    *) continue ;;
    esac

    if [ -n "$line" ]; then
      line="$line  $part"
    else
      line="$part"
    fi
  done

  if [ -z "$line" ]; then
    line="$(printf '%-30.30s  %s  %5s  %s' "$label" "$status" "$ago" "$display_cwd")"
  fi

  printf '%s' "$line"
}

emit_rows() {
  local now columns session window window_index pane pane_index command cwd state at display_cwd rank icon ago reason tool detail status label line saved_window saved_cwd
  now=$(date +%s)
  columns="$(get_tmux_option @opencode_overview_columns 'pane,status,age,cwd')"

  tmux list-panes -a -F $'#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}' 2>/dev/null |
    while IFS=$'\t' read -r session window window_index pane pane_index command cwd; do
      state="$(tmux show-options -pqv -t "$pane" @opencode_state 2>/dev/null)"

      if [ -z "$state" ] && [ "$command" != "opencode" ] && [ "$command" != "open-code" ]; then
        continue
      fi

      [ -z "$state" ] && state="unknown"
      at="$(tmux show-options -pqv -t "$pane" @opencode_state_at 2>/dev/null)"
      reason="$(tmux show-options -pqv -t "$pane" @opencode_reason 2>/dev/null)"
      tool="$(tmux show-options -pqv -t "$pane" @opencode_tool 2>/dev/null)"

      saved_window="$(tmux show-options -pqv -t "$pane" @opencode_window 2>/dev/null)"
      saved_cwd="$(tmux show-options -pqv -t "$pane" @opencode_cwd 2>/dev/null)"
      [ -n "$saved_window" ] && window="$saved_window"
      [ -n "$saved_cwd" ] && cwd="$saved_cwd"

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

      label="$session:$window_index.$pane_index"
      line="$(format_display_line "$columns" "$label" "$status" "$ago" "$display_cwd" "$detail" "$command" "$pane")"

      # rank, session, pane, window, raw detail are hidden. Visible line is preformatted.
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$session" "$pane" "$window" "$line" "$detail"
    done | sort -t$'\t' -k1,1n -k5,5
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
header=$'OpenCode panes\nenter: jump  ·  ctrl-x: kill pane  ·  ctrl-r: refresh'

sel=$(emit_rows | fzf --ansi --delimiter='\t' --with-nth=5 \
  --height=100% --reverse --cycle \
  --header="$header" \
  --bind="ctrl-x:execute-silent(tmux kill-pane -t {3})+reload($self --list)" \
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
