#!/usr/bin/env bash
# Record the current OpenCode pane's state on its tmux session.
# Usage: state.sh <working|waiting|idle|error|unknown> [reason] [session_id] [tool]

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

[ -z "${TMUX_PANE:-}" ] && exit 0

state="${1:-unknown}"
reason="$(sanitize_tmux_value "${2:-}")"
session_id="$(sanitize_tmux_value "${3:-}")"
tool="$(sanitize_tmux_value "${4:-}")"

case "$state" in
working | waiting | idle | error | unknown) ;;
*) state="unknown" ;;
esac

session="$(tmux display-message -p -t "$TMUX_PANE" '#{session_name}' 2>/dev/null)" || exit 0
[ -z "$session" ] && exit 0

cwd="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)"
window="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)"

tmux set-option -t "$session" @opencode_state "$state"
tmux set-option -t "$session" @opencode_state_at "$(date +%s)"
tmux set-option -t "$session" @opencode_pane "$TMUX_PANE"

[ -n "$cwd" ] && tmux set-option -t "$session" @opencode_cwd "$(sanitize_tmux_value "$cwd")"
[ -n "$window" ] && tmux set-option -t "$session" @opencode_window "$window"

if [ -n "$session_id" ]; then
  tmux set-option -t "$session" @opencode_session_id "$session_id"
fi

if [ -n "$reason" ]; then
  tmux set-option -t "$session" @opencode_reason "$reason"
else
  tmux set-option -ut "$session" @opencode_reason 2>/dev/null || true
fi

if [ -n "$tool" ]; then
  tmux set-option -t "$session" @opencode_tool "$tool"
else
  tmux set-option -ut "$session" @opencode_tool 2>/dev/null || true
fi

exit 0
