#!/usr/bin/env bash
# Codex CLI adapter.
#
# Single source of truth for which Codex hook events map to which picker
# state, plus a config.toml snippet emitter. The snippet is printed to the
# tmux message line on first run and saved under
# scripts/snippets/codex-config.toml so users can `cat` it.
#
# Runtime: state.sh is invoked directly by each hook command — no per-event
# bash runtime is needed here.
#
# Caveat: Codex has no `Notification` event for permission prompts — it
# uses `PermissionRequest`. There is no native question-asking event, so
# waiting/question is left out.

set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_lib.sh
. "$DIR/_lib.sh"

AGENT_ID=codex

# Event → state table. See _lib.sh for the row format.
CODEX_HOOKS=(
  "SessionStart:startup|resume:idle:done"
  "UserPromptSubmit::working:busy"
  "PermissionRequest::waiting:permission"
  "Stop::idle:done"
)

# emit_codex_config_toml <state.sh-path>
# Prints a Codex `[hooks]` table fragment suitable for merging into
# ~/.codex/config.toml. The fragment is wrapped in [hooks] and uses
# Codex's array-of-tables hook shape.
emit_codex_config_toml() {
  local path="${1:?missing path to state.sh}"
  local row first=1
  local C_EVENT C_MATCHER C_STATE C_REASON

  printf '[hooks]\n'
  for row in "${CODEX_HOOKS[@]}"; do
    parse_hook_row "$row" C
    printf '\n[[hooks.%s]]\n' "$(toml_escape "$C_EVENT")"
    if [ -n "$C_MATCHER" ]; then
      printf 'matcher = "%s"\n' "$(toml_escape "$C_MATCHER")"
    fi
    printf '\n[[hooks.%s.hooks]]\n' "$(toml_escape "$C_EVENT")"
    printf 'type = "command"\n'
    printf 'command = "%s"\n' \
      "$(toml_escape "$(hook_command "$path" "$AGENT_ID" "$C_STATE" "$C_REASON")")"
  done
}
