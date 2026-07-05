#!/usr/bin/env bash
# tmux-agents-overview
#
# On-demand tmux popup that lists tmux panes running a known coding-agent
# CLI (opencode, pi, codex, or claude) and lets you jump or kill them.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

# Canonical install path. The OpenCode plugin symlink and any per-agent
# hook commands embedded in user config all reference this location, so
# they stay valid even if the user moves the plugin dir (as long as the
# symlink follows). Matches tpm's default install location.
CANONICAL_DIR="$HOME/.tmux/plugins/tmux-agents-overview"

# If the canonical path is missing (or a broken symlink), point it at the
# actual install dir. Idempotent: real installs and working symlinks are
# left untouched. The override `TMUX_AGENTS_OVERVIEW_NO_SYMLINK=1` lets
# users skip the auto-link (e.g. when their canonical path is a real
# checkout managed by something else).
ensure_canonical_link() {
  [ "${TMUX_AGENTS_OVERVIEW_NO_SYMLINK:-}" = "1" ] && return 0
  [ -e "$CANONICAL_DIR" ] && return 0
  mkdir -p "$(dirname "$CANONICAL_DIR")"
  rm -f "$CANONICAL_DIR"
  ln -s "$CURRENT_DIR" "$CANONICAL_DIR"
}
ensure_canonical_link

# PLUGIN_DIR is the canonical install path. The OpenCode plugin symlink
# and any per-agent hook commands embedded in user config all reference
# this location, so they stay valid even if the user moves the plugin dir
# (as long as the symlink follows).
PLUGIN_DIR="$CANONICAL_DIR"

overview_key="$(get_tmux_option @agents_overview_key 'o')"

# Publish state.sh path for plugin-runtime adapters to find.
tmux set-option -gq @agents_overview_state_script "$PLUGIN_DIR/scripts/state.sh"

tmux bind-key "$overview_key" \
  run-shell "'$PLUGIN_DIR/scripts/list.sh' '#{client_name}' '#{pane_id}' '#{session_name}' '#{window_index}' '#{pane_index}'"

# Auto-install plugin-runtime adapters when the agent is installed.
# Claude and Codex have no plugin runtime — see README for how to wire
# their hooks manually.
install_opencode_plugin() {
  if [ "$(get_tmux_option @agents_overview_install_opencode 'on')" = "off" ]; then
    return 0
  fi
  local config_root plugins_dir source target
  config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  plugins_dir="$config_root/opencode/plugins"
  source="$PLUGIN_DIR/scripts/adapters/opencode.js"
  target="$plugins_dir/tmux-agents-overview.js"

  [ -f "$source" ] || return 0
  [ -d "$config_root/opencode" ] || return 0

  mkdir -p "$plugins_dir"
  rm -f "$target"
  ln -s "$source" "$target"
}

install_pi_extension() {
  if [ "$(get_tmux_option @agents_overview_install_pi 'on')" = "off" ]; then
    return 0
  fi
  local agent_dir extensions_dir source target
  agent_dir="${PI_CODING_AGENT_DIR:-$HOME/.pi/agent}"
  extensions_dir="$agent_dir/extensions"
  source="$PLUGIN_DIR/scripts/adapters/pi.ts"
  target="$extensions_dir/tmux-agents-overview.ts"

  [ -f "$source" ] || return 0
  [ -d "$agent_dir" ] || return 0

  mkdir -p "$extensions_dir"
  rm -f "$target"
  ln -s "$source" "$target"
}

install_opencode_plugin
install_pi_extension
