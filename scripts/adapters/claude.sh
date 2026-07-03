#!/usr/bin/env bash
# Claude Code adapter.
#
# This file is the single source of truth for which Claude Code hook events
# map to which picker state, plus a settings.json snippet emitter. The
# settings.json snippet is printed to the tmux message line on first run
# and saved under scripts/snippets/claude-settings.json so users can
# `cat` it.
#
# Runtime: state.sh is invoked directly by each hook command — no per-event
# bash runtime is needed here.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"

AGENT_ID=claude

# Event → state table. See _lib.sh for the row format.
#   SessionStart           → idle / done
#   UserPromptSubmit       → working / busy
#   Notification (perm)    → waiting / permission
#   PreToolUse (question)  → waiting / question
#   Stop                   → idle / done
#   SessionEnd             → clear
CLAUDE_HOOKS=(
  "SessionStart::idle:done"
  "UserPromptSubmit::working:busy"
  "Notification:permission_prompt:waiting:permission"
  "PreToolUse:AskUserQuestion:waiting:question"
  "Stop::idle:done"
  "SessionEnd::clear:"
)

# emit_claude_settings_json <state.sh-path>
# Prints a Claude Code settings.json `hooks` block to stdout.
emit_claude_settings_json() {
  local path="${1:?missing path to state.sh}"
  local row first=1 i=0
  local total="${#CLAUDE_HOOKS[@]}"

  printf '{\n  "hooks": {\n'
  for row in "${CLAUDE_HOOKS[@]}"; do
    i=$((i + 1))
    parse_hook_row "$row" C
    if [ "$C_MATCHER" = "*" ]; then
      C_MATCHER=""
    fi
    [ $first -eq 0 ] && printf ',\n'
    first=0
    printf '    "%s": [\n' "$(json_escape "$C_EVENT")"
    printf '      {\n'
    printf '        "matcher": "%s",\n' "$(json_escape "$C_MATCHER")"
    printf '        "hooks": [\n'
    printf '          { "type": "command", "command": "%s" }\n' \
      "$(json_escape "$(hook_command "$path" "$AGENT_ID" "$C_STATE" "$C_REASON")")"
    printf '        ]\n'
    printf '      }\n'
    printf '    ]'
  done
  printf '\n  }\n}\n'
}
