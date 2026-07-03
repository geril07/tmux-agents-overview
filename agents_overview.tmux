#!/usr/bin/env bash
# tmux-agents-overview
#
# On-demand tmux popup that lists tmux panes running a known coding-agent
# CLI (opencode, codex, or claude) and lets you jump or kill them.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

# Canonical install path. Snippets and the JS plugin always reference this
# location so users can paste a settings.json / config.toml fragment without
# rewriting paths. Matches tpm's default install location.
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

# All embedded paths in snippets, bindings, and the JS plugin go through
# this variable. It points at the canonical location so snippets stay valid
# even if the user moves the plugin dir (as long as the symlink follows).
PLUGIN_DIR="$CANONICAL_DIR"

overview_key="$(get_tmux_option @agents_overview_key 'o')"

# Publish state.sh path for the OpenCode JS plugin to find.
tmux set-option -gq @agents_overview_state_script "$PLUGIN_DIR/scripts/state.sh"

tmux bind-key "$overview_key" \
  run-shell "'$PLUGIN_DIR/scripts/list.sh' '#{client_name}' '#{pane_id}' '#{session_name}' '#{window_index}' '#{pane_index}'"

# Emit a snippet file under scripts/snippets/<name> for the given agent.
# The snippet is a self-contained config fragment users paste into the
# agent's config (Claude's settings.json or Codex's config.toml). The
# command path inside the snippet is the canonical PLUGIN_DIR, not the
# actual install dir.
write_snippet() {
  local agent="$1" file="$2" emit_fn="$3"
  local snippets_dir="$CURRENT_DIR/scripts/snippets"
  local snippet="$snippets_dir/$file"
  mkdir -p "$snippets_dir"
  . "$CURRENT_DIR/scripts/adapters/$agent.sh"
  "$emit_fn" "$PLUGIN_DIR/scripts/state.sh" >"$snippet"
  printf '%s' "$snippet"
}

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

install_claude_hint() {
  if [ "$(get_tmux_option @agents_overview_install_claude_hint 'on')" = "off" ]; then
    return 0
  fi
  [ -d "$HOME/.claude" ] || return 0

  local snippet
  snippet="$(write_snippet claude claude-settings.json emit_claude_settings_json)"

  tmux display-message "tmux-agents-overview: merge $snippet into ~/.claude/settings.json to enable Claude status"
}

install_codex_hint() {
  if [ "$(get_tmux_option @agents_overview_install_codex_hint 'on')" = "off" ]; then
    return 0
  fi
  [ -d "$HOME/.codex" ] || return 0

  local snippet
  snippet="$(write_snippet codex codex-config.toml emit_codex_config_toml)"

  tmux display-message "tmux-agents-overview: merge $snippet into ~/.codex/config.toml to enable Codex status"
}

install_opencode_plugin
install_claude_hint
install_codex_hint
