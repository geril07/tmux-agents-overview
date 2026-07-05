#!/usr/bin/env bash
# Interactive picker for tmux panes running or reporting a known coding agent
# (opencode, pi, codex, or claude).
#
#   picker.sh        fzf picker
#   picker.sh --list print rows only, used by fzf reload bindings

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

abs_diff() {
  local left="$1" right="$2"
  if [ "$left" -ge "$right" ]; then
    printf '%s' "$((left - right))"
  else
    printf '%s' "$((right - left))"
  fi
}

emit_rows_bash() {
  local process_registry host_registry

  [ -r "$DIR/rows.bash" ] || return 1

  process_registry="$(printf '%s\n' "${AGENT_PROCESS_NAMES[@]}")"
  host_registry="$(printf '%s\n' "${AGENT_HOST_PROCESS_NAMES[@]}")"

  AGENTS_OVERVIEW_AGENT_PROCESS_NAMES="$process_registry" \
    AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES="$host_registry" \
    bash "$DIR/rows.bash"
}

emit_rows_lua() {
  local process_registry host_registry

  command -v lua >/dev/null 2>&1 || return 1
  [ -r "$DIR/rows.lua" ] || return 1

  process_registry="$(printf '%s\n' "${AGENT_PROCESS_NAMES[@]}")"
  host_registry="$(printf '%s\n' "${AGENT_HOST_PROCESS_NAMES[@]}")"

  AGENTS_OVERVIEW_AGENT_PROCESS_NAMES="$process_registry" \
    AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES="$host_registry" \
    lua "$DIR/rows.lua"
}

emit_rows_python() {
  local process_registry host_registry

  command -v python3 >/dev/null 2>&1 || return 1
  [ -r "$DIR/rows.py" ] || return 1

  process_registry="$(printf '%s\n' "${AGENT_PROCESS_NAMES[@]}")"
  host_registry="$(printf '%s\n' "${AGENT_HOST_PROCESS_NAMES[@]}")"

  AGENTS_OVERVIEW_AGENT_PROCESS_NAMES="$process_registry" \
    AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES="$host_registry" \
    python3 "$DIR/rows.py"
}

emit_rows() {
  case "$(get_tmux_option @agents_overview_runtime 'bash')" in
  lua)
    emit_rows_lua || emit_rows_bash
    ;;
  python)
    emit_rows_python || emit_rows_bash
    ;;
  bash | *)
    emit_rows_bash
    ;;
  esac
}

initial_position_for_pane() {
  local current_pane="${1:-}"
  local rows_file="${2:-}"
  [ -z "$current_pane" ] && return 0
  [ -z "$rows_file" ] && return 0

  awk -F '\t' -v pane="$current_pane" '
    $3 == pane { print NR; found = 1; exit }
    END { if (!found) print "" }
  ' "$rows_file"
}

resolve_default_pane() {
  local current_pane="${1:-}"
  local rows_file="${2:-}"
  local current_session="${3:-}"
  local current_window_index="${4:-}"
  local current_pane_index="${5:-}"
  local current_meta
  local rank session pane window line detail candidate_window_index candidate_pane_index
  local window_distance pane_distance score best_score best_pane

  best_score=''
  best_pane=''

  [ -z "$current_pane" ] && return 0
  [ -z "$rows_file" ] && return 0

  if awk -F '\t' -v pane="$current_pane" '$3 == pane { found = 1; exit } END { exit found ? 0 : 1 }' "$rows_file"; then
    printf '%s' "$current_pane"
    return 0
  fi

  if [ -z "$current_session" ] || [ -z "$current_window_index" ] || [ -z "$current_pane_index" ]; then
    current_meta="$(tmux display-message -p -t "$current_pane" $'#{session_name}\t#{window_index}\t#{pane_index}' 2>/dev/null)" || return 0
    IFS=$'\t' read -r current_session current_window_index current_pane_index <<<"$current_meta"
  fi
  [ -z "$current_session" ] && return 0

  while IFS=$'\t' read -r rank session pane window line detail candidate_window_index candidate_pane_index; do
    [ "$session" = "$current_session" ] || continue
    [ -n "$candidate_window_index" ] && [ -n "$candidate_pane_index" ] || continue

    window_distance="$(abs_diff "$candidate_window_index" "$current_window_index")"
    pane_distance="$(abs_diff "$candidate_pane_index" "$current_pane_index")"
    score="$((window_distance * 1000 + pane_distance))"

    if [ -z "$best_score" ] || [ "$score" -lt "$best_score" ]; then
      best_score="$score"
      best_pane="$pane"
    fi
  done <"$rows_file"

  [ -n "$best_pane" ] && printf '%s' "$best_pane"
}

if [ "${1:-}" = '--list' ]; then
  emit_rows
  exit 0
fi

if ! command -v fzf >/dev/null 2>&1; then
  tmux display-message "tmux-agents-overview: fzf is required"
  exit 0
fi

self="${BASH_SOURCE[0]}"
current_pane="${1:-}"
current_session="${2:-}"
current_window_index="${3:-}"
current_pane_index="${4:-}"

rows_file="$(mktemp -t agents-overview.XXXXXX)" || exit 1
trap 'rm -f "$rows_file"' EXIT

emit_rows >"$rows_file"
default_pane="$(resolve_default_pane "$current_pane" "$rows_file" "$current_session" "$current_window_index" "$current_pane_index")"
initial_position="$(initial_position_for_pane "$default_pane" "$rows_file")"

header=$'Coding-agent panes  ·  enter: jump  ·  ctrl-x: kill pane  ·  ctrl-r: refresh'
fzf_args=(
  --ansi --delimiter=$'\t' --with-nth=5
  --height=100% --reverse --cycle
  --header="$header"
  --bind="ctrl-x:execute-silent(tmux kill-pane -t {3})+reload($self --list '$current_pane')"
  --bind="ctrl-r:reload($self --list '$current_pane')"
)

if [ -n "$initial_position" ]; then
  fzf_args+=(--bind="load:pos($initial_position)")
fi

sel=$(fzf "${fzf_args[@]}" <"$rows_file")

if [ -z "$sel" ]; then
  exit 0
fi

target_session="$(printf '%s' "$sel" | cut -f2)"
target_pane="$(printf '%s' "$sel" | cut -f3)"
target_window="$(printf '%s' "$sel" | cut -f4)"
  parent="$(tmux show-options -gqv @agents_overview_parent 2>/dev/null)"

case "$target_pane" in
%*) tmux select-pane -t "$target_pane" 2>/dev/null || true ;;
esac

target="$target_session"
[ -n "$target_window" ] && target="$target_window"

if [ -n "$parent" ]; then
  tmux switch-client -c "$parent" -t "$target" 2>/dev/null || true
else
  tmux switch-client -t "$target" 2>/dev/null || true
fi
