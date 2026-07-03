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

count_rows() {
  awk 'END { print NR + 0 }' "$1"
}

count_tmux_panes() {
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | awk 'END { print NR + 0 }'
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
  local current_meta current_session current_window_index current_pane_index
  local rank session pane window line detail candidate_meta candidate_window_index candidate_pane_index
  local window_distance pane_distance score best_score best_pane

  best_score=''
  best_pane=''

  [ -z "$current_pane" ] && return 0
  [ -z "$rows_file" ] && return 0

  if awk -F '\t' -v pane="$current_pane" '$3 == pane { found = 1; exit } END { exit found ? 0 : 1 }' "$rows_file"; then
    printf '%s' "$current_pane"
    return 0
  fi

  current_meta="$(tmux display-message -p -t "$current_pane" $'#{session_name}\t#{window_index}\t#{pane_index}' 2>/dev/null)" || return 0
  IFS=$'\t' read -r current_session current_window_index current_pane_index <<<"$current_meta"
  [ -z "$current_session" ] && return 0

  while IFS=$'\t' read -r rank session pane window line detail; do
    [ "$session" = "$current_session" ] || continue

    candidate_meta="$(tmux display-message -p -t "$pane" $'#{window_index}\t#{pane_index}' 2>/dev/null)" || continue
    IFS=$'\t' read -r candidate_window_index candidate_pane_index <<<"$candidate_meta"
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

if [ "${1:-}" = '--perf-event' ]; then
  event="${2:-unknown}"
  shift 2 || true
  perf_log "event=$(perf_value "$event") $*"
  exit 0
fi

if [ "${1:-}" = '--list' ]; then
  if perf_trace_enabled; then
    list_rows_file="$(mktemp -t opencode-overview-list.XXXXXX)" || exit 1
    list_start_ms="$(now_ms)"
    emit_rows >"$list_rows_file"
    list_end_ms="$(now_ms)"
    perf_log "event=reload_list emit_rows_ms=$((list_end_ms - list_start_ms)) rows=$(count_rows "$list_rows_file") all_panes=$(count_tmux_panes) current_pane=$(perf_value "${2:-}")"
    cat "$list_rows_file"
    rm -f "$list_rows_file"
  else
    emit_rows
  fi
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-opencode-session-overview: fzf is required"
  exit 0
fi

self="${BASH_SOURCE[0]}"
current_pane="${1:-}"
picker_start_ms="$(now_ms)"
perf_log "event=picker_start current_pane=$(perf_value "$current_pane")"
rows_file="$(mktemp -t opencode-overview.XXXXXX)" || exit 1
trap 'rm -f "$rows_file"' EXIT

emit_start_ms="$(now_ms)"
emit_rows >"$rows_file"
emit_end_ms="$(now_ms)"
position_start_ms="$(now_ms)"
default_pane="$(resolve_default_pane "$current_pane" "$rows_file")"
initial_position="$(initial_position_for_pane "$default_pane" "$rows_file")"
position_end_ms="$(now_ms)"
perf_log "event=picker_ready emit_rows_ms=$((emit_end_ms - emit_start_ms)) initial_pos_ms=$((position_end_ms - position_start_ms)) rows=$(count_rows "$rows_file") all_panes=$(count_tmux_panes) current_pane=$(perf_value "$current_pane") default_pane=$(perf_value "$default_pane") initial_pos=$(perf_value "$initial_position")"
header=$'OpenCode panes\nenter: jump  ·  ctrl-x: kill pane  ·  ctrl-r: refresh'
fzf_args=(
  --ansi --delimiter=$'\t' --with-nth=5
  --height=100% --reverse --cycle
  --header="$header"
  --bind="start:execute-silent($self --perf-event fzf_start current_pane=$(perf_value "$current_pane"))"
  --bind="ctrl-x:execute-silent(tmux kill-pane -t {3})+reload($self --list '$current_pane')"
  --bind="ctrl-r:reload($self --list '$current_pane')"
)

if [ -n "$initial_position" ]; then
  fzf_args+=(--bind="load:pos($initial_position)+execute-silent($self --perf-event fzf_load current_pane=$(perf_value "$current_pane") default_pane=$(perf_value "$default_pane") initial_pos=$(perf_value "$initial_position"))")
else
  fzf_args+=(--bind="load:execute-silent($self --perf-event fzf_load current_pane=$(perf_value "$current_pane") default_pane= initial_pos=)")
fi

fzf_start_ms="$(now_ms)"
sel=$(fzf "${fzf_args[@]}" <"$rows_file")
fzf_end_ms="$(now_ms)"

if [ -z "$sel" ]; then
  perf_log "event=picker_cancel total_ms=$((fzf_end_ms - picker_start_ms)) fzf_ms=$((fzf_end_ms - fzf_start_ms))"
  exit 0
fi

target_session="$(printf '%s' "$sel" | cut -f2)"
target_pane="$(printf '%s' "$sel" | cut -f3)"
target_window="$(printf '%s' "$sel" | cut -f4)"
parent="$(tmux show-options -gqv @opencode_overview_parent 2>/dev/null)"
perf_log "event=picker_select total_ms=$((fzf_end_ms - picker_start_ms)) fzf_ms=$((fzf_end_ms - fzf_start_ms)) selected_pane=$(perf_value "$target_pane") selected_session=$(perf_value "$target_session")"

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
