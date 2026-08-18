#!/usr/bin/env bash
# Antigravity adapter.
#
# Single source of truth for which Antigravity hook events map to which
# picker state, plus a hooks.json snippet emitter. The emitter is run by
# the user, not by the plugin: invoke this script directly to print the
# hooks.json fragment to stdout, then merge it into ~/.gemini/config/hooks.json
# or your project's .agents/hooks.json.
#
# Runtime: state.sh is invoked directly by each hook command — no per-event
# bash runtime is needed here.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"

AGENT_ID=antigravity

# Event → state table. See _lib.sh for the row format.
#   PreInvocation           → working / busy
#   PreToolUse:ask_question → waiting / question
#   PostToolUse:*           → working / busy
#   Stop                    → idle / done
ANTIGRAVITY_HOOKS=(
  "PreInvocation::working:busy"
  "PreToolUse:ask_question:waiting:question"
  "PostToolUse:*:working:busy"
  "Stop::idle:done"
)

# emit_antigravity_hooks_json <state.sh-path>
# Prints an Antigravity hooks.json configuration block to stdout.
emit_antigravity_hooks_json() {
  local path="${1:?missing path to state.sh}"
  local row first=1
  local C_EVENT C_MATCHER C_STATE C_REASON

  printf '{\n  "tmux-agents-overview": {\n'
  for row in "${ANTIGRAVITY_HOOKS[@]}"; do
    parse_hook_row "$row" C
    [ $first -eq 0 ] && printf ',\n'
    first=0
    case "$C_EVENT" in
      PreToolUse|PostToolUse)
        printf '    "%s": [\n' "$(json_escape "$C_EVENT")"
        printf '      {\n'
        printf '        "matcher": "%s",\n' "$(json_escape "$C_MATCHER")"
        printf '        "hooks": [\n'
        printf '          {\n'
        printf '            "type": "command",\n'
        printf '            "command": "%s"\n' \
          "$(json_escape "$(hook_command "$path" "$AGENT_ID" "$C_STATE" "$C_REASON")")"
        printf '          }\n'
        printf '        ]\n'
        printf '      }\n'
        printf '    ]'
        ;;
      *)
        printf '    "%s": [\n' "$(json_escape "$C_EVENT")"
        printf '      {\n'
        printf '        "type": "command",\n'
        printf '        "command": "%s"\n' \
          "$(json_escape "$(hook_command "$path" "$AGENT_ID" "$C_STATE" "$C_REASON")")"
        printf '      }\n'
        printf '    ]'
        ;;
    esac
  done
  printf '\n  }\n}\n'
}

# When run as a script (not sourced), print the hooks.json fragment
# to stdout. The caller passes the path to state.sh as the first argument.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  emit_antigravity_hooks_json "${1:?usage: antigravity.sh <path-to-state.sh>}"
fi
