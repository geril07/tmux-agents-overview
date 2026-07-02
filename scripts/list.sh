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

if [ -n "$client" ]; then
  tmux set-option -g @opencode_overview_parent "$client"
  tmux display-popup -c "$client" -w "$w" -h "$h" -E "$DIR/picker.sh '$current_pane'"
else
  tmux display-popup -w "$w" -h "$h" -E "$DIR/picker.sh '$current_pane'"
fi
