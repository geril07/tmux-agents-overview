#!/usr/bin/env bash
# Open the OpenCode session overview picker in a tmux popup.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

client="${1:-}"
current_pane="${2:-}"
w="$(get_tmux_option @opencode_overview_popup_width '50%')"
h="$(get_tmux_option @opencode_overview_popup_height '75%')"
list_start_ms="$(now_ms)"

perf_log "event=list_start client=$(perf_value "$client") current_pane=$(perf_value "$current_pane") width=$(perf_value "$w") height=$(perf_value "$h")"

if [ -n "$client" ]; then
  tmux set-option -g @opencode_overview_parent "$client"
  perf_log "event=display_popup_start elapsed_ms=$(( $(now_ms) - list_start_ms )) client=$(perf_value "$client") current_pane=$(perf_value "$current_pane")"
  tmux display-popup -c "$client" -w "$w" -h "$h" -E "$DIR/picker.sh '$current_pane'"
else
  perf_log "event=display_popup_start elapsed_ms=$(( $(now_ms) - list_start_ms )) client= current_pane=$(perf_value "$current_pane")"
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh '$current_pane'"
fi

perf_log "event=display_popup_done elapsed_ms=$(( $(now_ms) - list_start_ms )) client=$(perf_value "$client") current_pane=$(perf_value "$current_pane")"
