#!/usr/bin/env bash
# Shared helpers for tmux-opencode-session-overview.

get_tmux_option() {
  local value
  value="$(tmux show-option -gqv "$1" 2>/dev/null)"
  if [ -n "$value" ]; then
    printf '%s' "$value"
  else
    printf '%s' "$2"
  fi
}

sanitize_tmux_value() {
  printf '%s' "${1:-}" | tr '\n\r\t' '   ' | cut -c1-300
}

short_home_path() {
  local path="${1:-}"
  if [ -n "$HOME" ]; then
    printf '%s' "${path/#$HOME/~}"
  else
    printf '%s' "$path"
  fi
}
