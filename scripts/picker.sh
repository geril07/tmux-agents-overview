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

abs_diff() {
  local left="$1" right="$2"
  if [ "$left" -ge "$right" ]; then
    printf '%s' "$((left - right))"
  else
    printf '%s' "$((right - left))"
  fi
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
    pane | label) part="$(printf '%-30s' "$label")" ;;
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
    line="$(printf '%-30s  %s  %5s  %s' "$label" "$status" "$ago" "$display_cwd")"
  fi

  printf '%s' "$line"
}

emit_rows() {
  local now columns session window window_index pane pane_index command cwd state at display_cwd rank icon ago reason detail status label line
  now=$(date +%s)
  columns="$(get_tmux_option @opencode_overview_columns 'pane,status,age,cwd')"

  tmux list-panes -a -F $'#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{@opencode_state}\t#{@opencode_state_at}\t#{@opencode_reason}' 2>/dev/null |
    tr '\t' '\037' |
    while IFS=$'\037' read -r session window window_index pane pane_index command cwd state at reason; do
      if [ "$command" != "opencode" ]; then
        continue
      fi

      [ -z "$state" ] && state="unknown"

      rank="$(rank_for_state "$state")"
      icon="$(icon_for_state "$state")"

      if [ -n "$at" ] && [ "$at" -eq "$at" ] 2>/dev/null; then
        ago="$(((now - at) / 60))m"
      else
        ago='-'
      fi

      detail="$reason"
      [ -z "$detail" ] && detail='-'
      if [ "$state" = "unknown" ] && { [ "$detail" = "session" ] || [ "$detail" = "status" ]; }; then
        detail='-'
      fi

      status="$icon"

      display_cwd="$(short_home_path "$cwd")"
      [ -z "$display_cwd" ] && display_cwd='-'

      label="$session:$window_index.$pane_index"
      line="$(format_display_line "$columns" "$label" "$status" "$ago" "$display_cwd" "$detail" "$command" "$pane")"

      # rank, session, pane, window, raw detail, and indexes are hidden. Visible line is preformatted.
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$session" "$pane" "$window" "$line" "$detail" "$window_index" "$pane_index"
    done | sort -t$'\t' -k2,2 -k7,7n -k8,8n | awk -F '\t' 'BEGIN { OFS = "\t"; c = 0 } { c++; $5 = c "  " $5; print }'
}

initial_position_for_pane() {
  local current_pane="${1:-}"
  local rows_file="${2:-}"
  [ -z "$current_pane" ] && return 0
  [ -z "$rows_file" ] && return 0

  awk -F '\t' -v pane="$current_pane" '
    $3 == pane { print NR; found = 1; exit }
    END { if (!found) print "" }
  ' "$rows_file"
}

resolve_default_pane() {
  local current_pane="${1:-}"
  local rows_file="${2:-}"
  local current_session="${3:-}"
  local current_window_index="${4:-}"
  local current_pane_index="${5:-}"
  local current_meta
  local rank session pane window line detail candidate_window_index candidate_pane_index
  local window_distance pane_distance score best_score best_pane

  best_score=''
  best_pane=''

  [ -z "$current_pane" ] && return 0
  [ -z "$rows_file" ] && return 0

  if awk -F '\t' -v pane="$current_pane" '$3 == pane { found = 1; exit } END { exit found ? 0 : 1 }' "$rows_file"; then
    printf '%s' "$current_pane"
    return 0
  fi

  if [ -z "$current_session" ] || [ -z "$current_window_index" ] || [ -z "$current_pane_index" ]; then
    current_meta="$(tmux display-message -p -t "$current_pane" $'#{session_name}\t#{window_index}\t#{pane_index}' 2>/dev/null)" || return 0
    IFS=$'\t' read -r current_session current_window_index current_pane_index <<<"$current_meta"
  fi
  [ -z "$current_session" ] && return 0

  while IFS=$'\t' read -r rank session pane window line detail candidate_window_index candidate_pane_index; do
    [ "$session" = "$current_session" ] || continue
    [ -n "$candidate_window_index" ] && [ -n "$candidate_pane_index" ] || continue

    window_distance="$(abs_diff "$candidate_window_index" "$current_window_index")"
    pane_distance="$(abs_diff "$candidate_pane_index" "$current_pane_index")"
    score="$((window_distance * 1000 + pane_distance))"

    if [ -z "$best_score" ] || [ "$score" -lt "$best_score" ]; then
      best_score="$score"
      best_pane="$pane"
    fi
  done <"$rows_file"

  [ -n "$best_pane" ] && printf '%s' "$best_pane"
}

if [ "${1:-}" = '--list' ]; then
  emit_rows
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-opencode-session-overview: fzf is required"
  exit 0
fi

self="${BASH_SOURCE[0]}"
current_pane="${1:-}"
current_session="${2:-}"
current_window_index="${3:-}"
current_pane_index="${4:-}"

rows_file="$(mktemp -t opencode-overview.XXXXXX)" || exit 1
trap 'rm -f "$rows_file"' EXIT

emit_rows >"$rows_file"
default_pane="$(resolve_default_pane "$current_pane" "$rows_file" "$current_session" "$current_window_index" "$current_pane_index")"
initial_position="$(initial_position_for_pane "$default_pane" "$rows_file")"

header=$'OpenCode panes\nenter: jump  ·  ctrl-x: kill pane  ·  ctrl-r: refresh'
fzf_args=(
  --ansi --delimiter=$'\t' --with-nth=5
  --height=100% --reverse --cycle
  --header="$header"
  --bind="ctrl-x:execute-silent(tmux kill-pane -t {3})+reload($self --list '$current_pane')"
  --bind="ctrl-r:reload($self --list '$current_pane')"
)

if [ -n "$initial_position" ]; then
  fzf_args+=(--bind="load:pos($initial_position)")
fi

sel=$(fzf "${fzf_args[@]}" <"$rows_file")

if [ -z "$sel" ]; then
  exit 0
fi

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
