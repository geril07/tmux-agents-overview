#!/usr/bin/env bash
# Interactive picker for tmux panes running or reporting a known coding agent
# (opencode, codex, or claude).
#
#   picker.sh        fzf picker
#   picker.sh --list print rows only, used by fzf reload bindings

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

rank_for_state() {
  case "$1" in
  waiting) printf '0' ;;
  idle) printf '1' ;;
  unknown) printf '2' ;;
  working) printf '3' ;;
  *) printf '2' ;;
  esac
}

icon_for_state() {
  case "$1" in
  waiting) printf '\033[33m●\033[0m waiting' ;;
  idle) printf '\033[32m●\033[0m idle   ' ;;
  working) printf '\033[35m●\033[0m working' ;;
  unknown | *) printf '\033[90m●\033[0m unknown' ;;
  esac
}

abs_diff() {
  local left="$1" right="$2"
  if [ "$left" -ge "$right" ]; then
    printf '%s' "$((left - right))"
  else
    printf '%s' "$((right - left))"
  fi
}

format_display_line() {
  local columns="${1:-pane,status,age,cwd}"
  local label="$2" status="$3" ago="$4" display_cwd="$5" detail="$6" command="$7" pane="$8" agent="$9"
  local line='' column part
  local selected_columns=()

  columns="${columns// /}"
  [ -z "$columns" ] && columns='pane,status,age,cwd'

  IFS=',' read -r -a selected_columns <<<"$columns"
  for column in "${selected_columns[@]}"; do
    case "$column" in
    pane | label) part="$(printf '%-30s' "$label")" ;;
    status | state) part="$status" ;;
    age | ago) part="$(printf '%5s' "$ago")" ;;
    cwd | path) part="$display_cwd" ;;
    detail | reason) part="$detail" ;;
    agent) part="$agent" ;;
    command | cmd) part="$command" ;;
    pane_id | pane-id) part="$pane" ;;
    *) continue ;;
    esac

    if [ -n "$line" ]; then
      line="$line  $part"
    else
      line="$part"
    fi
  done

  if [ -z "$line" ]; then
    line="$(printf '%-30s  %s  %5s  %s' "$label" "$status" "$ago" "$display_cwd")"
  fi

  printf '%s' "$line"
}

# pane_owned_by <command>
# Echoes the agent id whose process-name list contains the given command,
# or empty string when no registered agent owns it.
pane_owned_by() {
  local command="$1" entry id n
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    id="${entry%% *}"
    for n in ${entry#* }; do
      if [ "$n" = "$command" ]; then
        printf '%s' "$id"
        return 0
      fi
    done
  done
  return 1
}

# pane_host_owned_by <command>
# Echoes the agent id whose generic host process-name list contains the given
# command, or empty string when the command is not enough by itself.
pane_host_owned_by() {
  local command="$1" entry id n
  for entry in "${AGENT_HOST_PROCESS_NAMES[@]}"; do
    id="${entry%% *}"
    for n in ${entry#* }; do
      if [ "$n" = "$command" ]; then
        printf '%s' "$id"
        return 0
      fi
    done
  done
  return 1
}

# normalize_ps_tty <ps-tty>
# Converts ps' tty column (for example, pts/15) to tmux's /dev/pts/15 form.
normalize_ps_tty() {
  local tty="$1"
  case "$tty" in
  '' | \?) return 1 ;;
  /*) printf '%s' "$tty" ;;
  *) printf '/dev/%s' "$tty" ;;
  esac
}

# process_line_matches_agent <command> <agent> <args>
# Returns 0 when the process command or any argv path basename is the agent id.
process_line_matches_agent() {
  local proc_command="$1" agent="$2" args="${3:-}"
  local arg base

  [ "$proc_command" = "$agent" ] && return 0

  for arg in $args; do
    base="${arg##*/}"
    [ "$base" = "$agent" ] && return 0
  done

  return 1
}

emit_rows_bash() {
  local now columns fmt agent
  local -a agents=() rows=() host_ttys=() argv_ttys=()
  local row entry agent_csv ps_output
  local ps_tty normalized_tty pgid tpgid proc_command args host_agent
  local argv_tty_csv
  declare -A seen_host_tty=()
  declare -A host_probe_agents=()
  declare -A host_probe_authoritative=()
  now=$(date +%s)
  columns="$(get_tmux_option @agents_overview_columns 'pane,status,age,cwd')"

  # Snapshot the registry order so per-pane indexing is stable.
  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    agents+=("${entry%% *}")
  done

  # Build the tmux format string: shared columns, then 3 option columns
  # per registered agent (state, state_at, reason).
  fmt=$'#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_tty}'
  for agent in "${agents[@]}"; do
    fmt+=$(printf '\t#{@agent_%s_state}\t#{@agent_%s_state_at}\t#{@agent_%s_reason}' \
      "$agent" "$agent" "$agent")
  done

  mapfile -t rows < <(tmux list-panes -a -F "$fmt" 2>/dev/null | tr '\t' '\037')

  for row in "${rows[@]}"; do
    local -a probe_fields=()
    IFS=$'\037' read -r -a probe_fields <<<"$row"
    host_agent="$(pane_host_owned_by "${probe_fields[5]:-}")" || host_agent=''
    [ -n "$host_agent" ] || continue
    tty="${probe_fields[7]:-}"
    [ -n "$tty" ] || continue
    [ -n "${seen_host_tty[$tty]:-}" ] && continue
    seen_host_tty["$tty"]=1
    host_ttys+=("$tty")
  done

  if [ "${#host_ttys[@]}" -gt 0 ] && command -v ps >/dev/null 2>&1; then
    agent_csv="$(IFS=,; printf '%s' "${agents[*]}")"
    if ps_output="$(ps -C "$agent_csv" -o tty=,pgid=,tpgid=,comm= 2>/dev/null)"; then
      while IFS= read -r row; do
        [ -n "$row" ] || continue
        read -r ps_tty pgid tpgid proc_command <<<"$row"
        normalized_tty="$(normalize_ps_tty "$ps_tty")" || continue
        [ -n "${seen_host_tty[$normalized_tty]:-}" ] || continue
        [ -n "$pgid" ] && [ -n "$tpgid" ] && [ -n "$proc_command" ] || continue
        [ "$tpgid" != "-1" ] || continue
        [ "$pgid" = "$tpgid" ] || continue

        for agent in "${agents[@]}"; do
          if [ "$proc_command" = "$agent" ]; then
            host_probe_agents["$normalized_tty"]="$agent"
            host_probe_authoritative["$normalized_tty"]=1
            break
          fi
        done
      done <<<"$ps_output"
    fi

    for tty in "${host_ttys[@]}"; do
      [ -n "${host_probe_authoritative[$tty]:-}" ] && continue
      argv_ttys+=("$tty")
    done

    if [ "${#argv_ttys[@]}" -gt 0 ]; then
      argv_tty_csv="$(IFS=,; printf '%s' "${argv_ttys[*]}")"
      if ps_output="$(ps -t "$argv_tty_csv" -o tty=,pgid=,tpgid=,comm=,args= 2>/dev/null)"; then
        for tty in "${argv_ttys[@]}"; do
          host_probe_authoritative["$tty"]=1
        done

        while IFS= read -r row; do
          [ -n "$row" ] || continue
          read -r ps_tty pgid tpgid proc_command args <<<"$row"
          normalized_tty="$(normalize_ps_tty "$ps_tty")" || continue
          [ -n "${seen_host_tty[$normalized_tty]:-}" ] || continue
          [ -n "$pgid" ] && [ -n "$tpgid" ] && [ -n "$proc_command" ] || continue
          [ "$tpgid" != "-1" ] || continue
          [ "$pgid" = "$tpgid" ] || continue

          for agent in "${agents[@]}"; do
            if process_line_matches_agent "$proc_command" "$agent" "$args"; then
              host_probe_agents["$normalized_tty"]="$agent"
              break
            fi
          done
        done <<<"$ps_output"
      fi
    fi
  fi

  {
    for row in "${rows[@]}"; do
      local -a fields=()
      IFS=$'\037' read -r -a fields <<<"$row"
      local session window window_index pane pane_index command cwd tty
      local label display_cwd line detail state at reason
      local icon ago rank status
      local idx base host_backed
      session="${fields[0]}"
      window="${fields[1]}"
      window_index="${fields[2]}"
      pane="${fields[3]}"
      pane_index="${fields[4]}"
      command="${fields[5]}"
      cwd="${fields[6]}"
      tty="${fields[7]}"

      host_backed=0
      agent="$(pane_owned_by "$command")" || agent=''
      if [ -z "$agent" ]; then
        agent="$(pane_host_owned_by "$command")" || agent=''
        host_backed=1
      fi

      if [ "$host_backed" -eq 1 ] && [ -n "$agent" ]; then
        if [ "${host_probe_agents[$tty]:-}" = "$agent" ]; then
          :
        elif [ -z "${host_probe_authoritative[$tty]:-}" ]; then
          for idx in "${!agents[@]}"; do
            [ "${agents[$idx]}" = "$agent" ] || continue
            base=$((8 + idx * 3))
            [ -n "${fields[$base]:-}" ] || agent=''
            break
          done
        else
          agent=''
        fi
      fi

      [ -n "$agent" ] || continue

      # Find this agent's index in the registry so we can index into fields[].
      for idx in "${!agents[@]}"; do
        [ "${agents[$idx]}" = "$agent" ] && break
      done
      base=$((8 + idx * 3))
      state="${fields[$base]:-}"
      at="${fields[$((base + 1))]:-}"
      reason="${fields[$((base + 2))]:-}"

      [ -z "$state" ] && state="unknown"

      rank="$(rank_for_state "$state")"
      icon="$(icon_for_state "$state")"

      if [ -n "$at" ] && [ "$at" -eq "$at" ] 2>/dev/null; then
        ago="$(((now - at) / 60))m"
      else
        ago=''
      fi

      detail="$reason"
      if [ "$state" = "unknown" ] && { [ "$detail" = "session" ] || [ "$detail" = "status" ]; }; then
        detail=''
      fi

      status="$icon"

      display_cwd="$(short_home_path "$cwd")"

      label="$session:$window_index.$pane_index"
      line="$(format_display_line "$columns" "$label" "$status" "$ago" "$display_cwd" "$detail" "$command" "$pane" "$agent")"

      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$rank" "$session" "$pane" "$window" "$line" "$detail" "$window_index" "$pane_index"
    done
  } | sort -t$'\t' -k2,2 -k7,7n -k8,8n | awk -F '\t' 'BEGIN { OFS = "\t"; c = 0 } { c++; $5 = c "  " $5; print }'
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

emit_rows() {
  case "$(get_tmux_option @agents_overview_runtime 'bash')" in
  lua)
    emit_rows_lua || emit_rows_bash
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
