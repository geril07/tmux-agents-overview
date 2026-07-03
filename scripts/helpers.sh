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

now_ms() {
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'
  else
    printf '%s000\n' "$(date +%s)"
  fi
}

perf_trace_enabled() {
  if [ -n "${OPENCODE_OVERVIEW_PERF:-}" ]; then
    case "$OPENCODE_OVERVIEW_PERF" in
    1 | on | true | yes) return 0 ;;
    *) return 1 ;;
    esac
  fi

  case "$(get_tmux_option @opencode_overview_perf 'off')" in
  1 | on | true | yes) return 0 ;;
  *) return 1 ;;
  esac
}

perf_log_path() {
  local path
  path="${OPENCODE_OVERVIEW_PERF_LOG:-}"
  [ -z "$path" ] && path="$(get_tmux_option @opencode_overview_perf_log "${XDG_CACHE_HOME:-$HOME/.cache}/tmux-opencode-session-overview/perf.log")"

  case "$path" in
  '~') printf '%s' "$HOME" ;;
  '~/'*) printf '%s/%s' "$HOME" "${path#~/}" ;;
  *) printf '%s' "$path" ;;
  esac
}

perf_value() {
  printf '%s' "${1:-}" | tr ' \t\r\n' '____'
}

perf_log() {
  perf_trace_enabled || return 0

  local log_path log_dir
  log_path="$(perf_log_path)"
  log_dir="$(dirname "$log_path")"

  mkdir -p "$log_dir" 2>/dev/null || return 0
  printf '%s ts_ms=%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(now_ms)" "$*" >>"$log_path" 2>/dev/null || true
}
