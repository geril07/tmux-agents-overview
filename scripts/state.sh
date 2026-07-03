#!/usr/bin/env bash
# Record the current OpenCode pane's state on the tmux pane.
# Usage: state.sh <working|waiting|idle|unknown|session> [reason]

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ -z "${TMUX_PANE:-}" ] && exit 0

state="${1:-unknown}"
reason="$(sanitize_tmux_value "${2:-}")"

case "$state" in
working | waiting | idle | unknown | session) ;;
*) state="unknown" ;;
esac

pane="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null)" || exit 0
[ -z "$pane" ] && exit 0

cwd="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)"
window="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)"

[ -n "$cwd" ] && tmux set-option -p -t "$pane" @opencode_cwd "$(sanitize_tmux_value "$cwd")"
[ -n "$window" ] && tmux set-option -p -t "$pane" @opencode_window "$window"

if [ "$state" = "session" ]; then
  exit 0
fi

tmux set-option -p -t "$pane" @opencode_state "$state"
tmux set-option -p -t "$pane" @opencode_state_at "$(date +%s)"

if [ -n "$reason" ]; then
  tmux set-option -p -t "$pane" @opencode_reason "$reason"
else
  tmux set-option -pu -t "$pane" @opencode_reason 2>/dev/null || true
fi

exit 0
