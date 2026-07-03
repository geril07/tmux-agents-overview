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
  run-shell "perf='#{@opencode_overview_perf}'; request_ms=''; case \"\$perf\" in 1|on|true|yes) request_ms=\$(perl -MTime::HiRes=time -e 'printf \"%.0f\", time() * 1000' 2>/dev/null || printf '%s000' \$(date +%s)) ;; esac; '$CURRENT_DIR/scripts/list.sh' '#{client_name}' '#{pane_id}' '#{session_name}' '#{window_index}' '#{pane_index}' \"\$request_ms\""
