#!/usr/bin/env bash
# Open the agents-overview picker in a tmux popup.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

client="${1:-}"
current_pane="${2:-}"
current_session="${3:-}"
current_window_index="${4:-}"
current_pane_index="${5:-}"
w="$(get_tmux_option @agents_overview_popup_width '50%')"
h="$(get_tmux_option @agents_overview_popup_height '75%')"

picker_command="$DIR/picker.sh '$current_pane' '$current_session' '$current_window_index' '$current_pane_index'"

if [ -n "$client" ]; then
  tmux set-option -g @agents_overview_parent "$client"
  tmux display-popup -c "$client" -w "$w" -h "$h" -E "$picker_command"
else
  tmux display-popup -w "$w" -h "$h" -E "$picker_command"
fi
