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
  run-shell "'$CURRENT_DIR/scripts/list.sh' '#{client_name}' '#{pane_id}' '#{session_name}' '#{window_index}' '#{pane_index}'"

install_opencode_bridge() {
  local config_root plugins_dir source target
  config_root="${XDG_CONFIG_HOME:-$HOME/.config}"
  plugins_dir="$config_root/opencode/plugins"
  source="$CURRENT_DIR/.opencode/plugins/tmux-opencode-session-overview.js"
  target="$plugins_dir/tmux-opencode-session-overview.js"

  [ -f "$source" ] || return 0
  [ -d "$config_root/opencode" ] || return 0

  mkdir -p "$plugins_dir"
  ln -sf "$source" "$target"
}

if [ "$(get_tmux_option @opencode_overview_install_bridge 'on')" != "off" ]; then
  install_opencode_bridge
fi
