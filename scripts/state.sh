#!/usr/bin/env bash
# Record the current OpenCode pane's state on the tmux pane.
# Usage: state.sh <working|waiting|idle|unknown|session> [reason] [session_id] [tool]

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
working | waiting | idle | unknown | session) ;;
*) state="unknown" ;;
esac

pane="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_id}' 2>/dev/null)" || exit 0
[ -z "$pane" ] && exit 0

cwd="$(tmux display-message -p -t "$TMUX_PANE" '#{pane_current_path}' 2>/dev/null)"
window="$(tmux display-message -p -t "$TMUX_PANE" '#{window_id}' 2>/dev/null)"

tmux set-option -p -t "$pane" @opencode_pane "$pane"

[ -n "$cwd" ] && tmux set-option -p -t "$pane" @opencode_cwd "$(sanitize_tmux_value "$cwd")"
[ -n "$window" ] && tmux set-option -p -t "$pane" @opencode_window "$window"

if [ -n "$session_id" ]; then
  tmux set-option -p -t "$pane" @opencode_session_id "$session_id"
fi

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

if [ -n "$tool" ]; then
  tmux set-option -p -t "$pane" @opencode_tool "$tool"
else
  tmux set-option -pu -t "$pane" @opencode_tool 2>/dev/null || true
fi

exit 0
