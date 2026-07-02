#!/usr/bin/env bash
# tmux-opencode-session-overview
#
# On-demand tmux popup that lists tmux sessions with OpenCode status.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

overview_key="$(get_tmux_option @opencode_overview_key 'o')"

tmux set-option -gq @opencode_overview_state_script "$CURRENT_DIR/scripts/state.sh"

tmux bind-key "$overview_key" \
  run-shell "$CURRENT_DIR/scripts/list.sh '#{client_name}'"
