#!/usr/bin/env bash
# Record the current agent pane's state on the tmux pane.
# Usage: state.sh <agent> <state> [reason]
#        state.sh <agent> clear
#
# State is one of: working | waiting | idle | unknown
# Reason is a short free-form tag (e.g. busy | retry | permission | question |
# done | child | error). Omit or pass "" to clear the reason.
#
# State is written to the current tmux pane ($TMUX_PANE) under the canonical
# option names:
#   @agent_<id>_state
#   @agent_<id>_state_at
#   @agent_<id>_reason
#
# No-op outside tmux.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ -z "${TMUX_PANE:-}" ] && exit 0

agent="${1:-}"
state="${2:-}"
reason="$(sanitize_tmux_value "${3:-}")"

is_known_agent "$agent" || exit 0

case "$state" in
working | waiting | idle | unknown | clear) ;;
*) state="unknown" ;;
esac

pane="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null)" || exit 0
[ -z "$pane" ] && exit 0

state_opt="$(agent_option "$agent" state)"
at_opt="$(agent_option "$agent" state_at)"
reason_opt="$(agent_option "$agent" reason)"

if [ "$state" = "clear" ]; then
  tmux set-option -pu -t "$pane" "$state_opt" 2>/dev/null || true
  tmux set-option -pu -t "$pane" "$at_opt" 2>/dev/null || true
  tmux set-option -pu -t "$pane" "$reason_opt" 2>/dev/null || true
  exit 0
fi

tmux set-option -p -t "$pane" "$state_opt" "$state"
tmux set-option -p -t "$pane" "$at_opt" "$(date +%s)"

if [ -n "$reason" ]; then
  tmux set-option -p -t "$pane" "$reason_opt" "$reason"
else
  tmux set-option -pu -t "$pane" "$reason_opt" 2>/dev/null || true
fi

exit 0
