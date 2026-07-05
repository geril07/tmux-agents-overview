#!/usr/bin/env bash
# Shared helpers for tmux-agents-overview.

# get_tmux_option <option-name> <default>
# Echoes the global tmux option value, or the default when unset/empty.
get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

# sanitize_tmux_value <string>
# Strips newlines/tabs and truncates so a value can live inside a tmux option.
sanitize_tmux_value() {
  printf '%s' "${1:-}" | tr '\n\r\t' '   ' | cut -c1-300
}

# short_home_path <path>
# Replaces $HOME prefix with ~ for compact display.
short_home_path() {
  local path="${1:-}"
  if [ -n "$HOME" ]; then
    printf '%s' "${path/#$HOME/~}"
  else
    printf '%s' "$path"
  fi
}

# -- Agent registry --------------------------------------------------------
# Single source of truth for which agents are supported, the tmux option
# prefix they use to stamp state, and the `pane_current_command` values used
# as a fallback when no agent state has been stamped yet.
#
# Add a new agent by appending unique commands to AGENT_PROCESS_NAMES and
# generic host commands to AGENT_HOST_PROCESS_NAMES, then dropping a
# scripts/adapters/<id>.sh (bash) or <id>.js/.ts (plugin runtime) into place. The
# picker, the install script, and the snippet generator all read from these
# tables — no other change is required.

AGENT_PROCESS_NAMES=(
  "opencode opencode"
  "pi       pi"
  "codex    codex"
  "claude   claude"
)

# Process names that are too broad to identify an agent by themselves. The
# picker only accepts these when a process probe or stamped state confirms the
# agent.
AGENT_HOST_PROCESS_NAMES=(
  "codex node"
)

# agent_process_names <agent>
# Echoes the space-separated fallback `pane_current_command` values for an agent.
agent_process_names() {
  local agent="$1" entry id n out=""
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    id="${entry%% *}"
    [ "$id" = "$agent" ] || continue
    for n in ${entry#* }; do
      [ -n "$out" ] && out="$out $n" || out="$n"
    done
  done
  printf '%s' "$out"
}

# all_agent_process_names
# Echoes the unique union of every agent's fallback process names.
all_agent_process_names() {
  local entry n out="" seen
  declare -A seen=()
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    for n in ${entry#* }; do
      [ -n "${seen[$n]:-}" ] && continue
      seen["$n"]=1
      [ -n "$out" ] && out="$out $n" || out="$n"
    done
  done
  printf '%s' "$out"
}

# agent_host_process_names <agent>
# Echoes generic host process names that require extra confirmation.
agent_host_process_names() {
  local agent="$1" entry id n out=""
  for entry in "${AGENT_HOST_PROCESS_NAMES[@]}"; do
    id="${entry%% *}"
    [ "$id" = "$agent" ] || continue
    for n in ${entry#* }; do
      [ -n "$out" ] && out="$out $n" || out="$n"
    done
  done
  printf '%s' "$out"
}

# registered_agents
# Echoes the space-separated list of agent ids known to this plugin.
registered_agents() {
  local entry id out=""
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    id="${entry%% *}"
    [ -n "$out" ] && out="$out $id" || out="$id"
  done
  printf '%s' "$out"
}

# is_known_agent <id>
# Returns 0 if the agent is in the registry, 1 otherwise.
is_known_agent() {
  local agent="$1" entry
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    [ "${entry%% *}" = "$agent" ] && return 0
  done
  return 1
}

# agent_option <agent> <suffix>
# Echoes the canonical tmux option name for an agent+state-suffix pair.
#   agent_option opencode state     -> @agent_opencode_state
#   agent_option opencode state_at  -> @agent_opencode_state_at
#   agent_option opencode reason    -> @agent_opencode_reason
agent_option() {
  local agent="$1" suffix="$2"
  printf '@agent_%s_%s' "$agent" "$suffix"
}
