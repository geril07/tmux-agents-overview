#!/usr/bin/env bash
# Open the OpenCode session overview picker in a tmux popup.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

client="${1:-}"
current_pane="${2:-}"
current_session="${3:-}"
current_window_index="${4:-}"
current_pane_index="${5:-}"
request_ms="${6:-}"
w="$(get_tmux_option @opencode_overview_popup_width '50%')"
h="$(get_tmux_option @opencode_overview_popup_height '75%')"
perf_enabled=0

if perf_trace_enabled; then
  perf_enabled=1
  export OPENCODE_OVERVIEW_PERF=1
  export OPENCODE_OVERVIEW_PERF_LOG="$(perf_log_path)"

  list_start_ms="$(now_ms)"
  case "$request_ms" in
  '' | *[!0-9]*) request_ms="$list_start_ms" ;;
  esac

  perf_log "event=list_start request_ms=$request_ms request_to_list_ms=$((list_start_ms - request_ms)) client=$(perf_value "$client") current_pane=$(perf_value "$current_pane") width=$(perf_value "$w") height=$(perf_value "$h")"
fi

picker_command="$DIR/picker.sh '$current_pane' '$current_session' '$current_window_index' '$current_pane_index' '$request_ms'"

if [ -n "$client" ]; then
  tmux set-option -g @opencode_overview_parent "$client"
  if [ "$perf_enabled" -eq 1 ]; then
    display_start_ms="$(now_ms)"
    perf_log "event=display_popup_start elapsed_ms=$((display_start_ms - list_start_ms)) request_to_display_popup_start_ms=$((display_start_ms - request_ms)) client=$(perf_value "$client") current_pane=$(perf_value "$current_pane")"
  fi
  tmux display-popup -c "$client" -w "$w" -h "$h" -E "$picker_command"
else
  if [ "$perf_enabled" -eq 1 ]; then
    display_start_ms="$(now_ms)"
    perf_log "event=display_popup_start elapsed_ms=$((display_start_ms - list_start_ms)) request_to_display_popup_start_ms=$((display_start_ms - request_ms)) client= current_pane=$(perf_value "$current_pane")"
  fi
  tmux display-popup -w "$w" -h "$h" -E "$picker_command"
fi

if [ "$perf_enabled" -eq 1 ]; then
  display_done_ms="$(now_ms)"
  perf_log "event=display_popup_done elapsed_ms=$((display_done_ms - list_start_ms)) request_to_display_popup_done_ms=$((display_done_ms - request_ms)) client=$(perf_value "$client") current_pane=$(perf_value "$current_pane")"
fi
