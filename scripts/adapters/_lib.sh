#!/usr/bin/env bash
# Common helpers for adapter snippet generators.
#
# Source-of-truth table format shared by Claude/Codex adapters:
#   "EVENT:MATCHER:STATE:REASON"
# MATCHER may be empty (register with empty matcher) or "*" (catch-all).
# STATE  is one of working|waiting|idle|unknown|clear.
# REASON may be empty.
#
# Runtime note: Claude Code and Codex CLI hooks call state.sh directly with
# the (state, reason) baked into the settings.json / config.toml command
# string. There is no per-event bash runtime — state.sh IS the runtime.
# OpenCode is the exception: it uses a JS plugin (see adapters/opencode.js).

# parse_hook_row <row> [var_prefix]
# Splits a "EVENT:MATCHER:STATE:REASON" row into four global vars:
#   <prefix>_EVENT, <prefix>_MATCHER, <prefix>_STATE, <prefix>_REASON
parse_hook_row() {
  local row="$1" prefix="${2:-_PARSED}"
  local event rest sr
  event="${row%%:*}"
  rest="${row#*:}"
  printf -v "${prefix}_EVENT"   '%s' "$event"
  printf -v "${prefix}_MATCHER" '%s' "${rest%%:*}"
  sr="${rest#*:}"
  printf -v "${prefix}_STATE"   '%s' "${sr%%:*}"
  printf -v "${prefix}_REASON"  '%s' "${sr#*:}"
}

# hook_command <path> <agent> <state> <reason>
# Echoes "<path> <agent> <state> [reason]" with no trailing space when
# reason is empty. Designed to be embedded inside a JSON or TOML string.
hook_command() {
  local path="$1" agent="$2" state="$3" reason="$4"
  if [ -n "$reason" ]; then
    printf '%s %s %s %s' "$path" "$agent" "$state" "$reason"
  else
    printf '%s %s %s' "$path" "$agent" "$state"
  fi
}

# json_escape <string>
# Escapes a string for safe inclusion inside a JSON string literal.
json_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# toml_escape <string>
# Escapes a string for safe inclusion inside a TOML basic string literal.
toml_escape() {
  local s="${1-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}
