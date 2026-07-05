#!/usr/bin/env bash
# Standalone row generator for picker.sh --list (bash runtime).
# Emits the same tab-separated row contract as rows.lua.
# Reads registry from environment variables with built-in defaults.

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
. "$DIR/helpers.sh"

# ---- Built-in defaults (same as helpers.sh) ----
DEFAULT_AGENT_PROCESS_NAMES=(
  "opencode opencode"
  "pi       pi"
  "codex    codex"
  "claude   claude"
)
DEFAULT_AGENT_HOST_PROCESS_NAMES=(
  "codex node"
)

# ---- Parse registries from env or use defaults ----
parse_registries() {
  local line id names n

  if [ -n "${AGENTS_OVERVIEW_AGENT_PROCESS_NAMES:-}" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      names=($line)
      id="${names[0]}"
      [ -n "$id" ] || continue
      AGENT_PROCESS_NAMES+=("$line")
    done <<<"$AGENTS_OVERVIEW_AGENT_PROCESS_NAMES"
  fi

  if [ -n "${AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES:-}" ]; then
    AGENT_HOST_PROCESS_NAMES=()
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      AGENT_HOST_PROCESS_NAMES+=("$line")
    done <<<"$AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES"
  fi
}

# ---- Row-specific functions (mirror picker.sh) ----
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

normalize_ps_tty() {
  local tty="$1"
  case "$tty" in
  '' | \?) return 1 ;;
  /*) printf '%s' "$tty" ;;
  *) printf '/dev/%s' "$tty" ;;
  esac
}

# ---- Main ----
main() {
  local now columns fmt agent
  local -a agents=() rows=() host_ttys=() fallback_ttys=()
  local row entry agent_csv ps_output
  local ps_tty normalized_tty pgid tpgid proc_command host_agent
  local fallback_tty_csv
  declare -A seen_host_tty=()
  declare -A host_probe_agents=()
  declare -A host_probe_authoritative=()

  parse_registries

  now=$(date +%s)
  columns="$(get_tmux_option @agents_overview_columns 'pane,status,age,cwd')"

  for entry in "${AGENT_PROCESS_NAMES[@]}"; do
    agents+=("${entry%% *}")
  done

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
      fallback_ttys+=("$tty")
    done

    if [ "${#fallback_ttys[@]}" -gt 0 ]; then
      fallback_tty_csv="$(IFS=,; printf '%s' "${fallback_ttys[*]}")"
      if ps_output="$(ps -t "$fallback_tty_csv" -o tty=,comm= 2>/dev/null)"; then
        for tty in "${fallback_ttys[@]}"; do
          host_probe_authoritative["$tty"]=1
        done

        while IFS= read -r row; do
          [ -n "$row" ] || continue
          read -r ps_tty proc_command <<<"$row"
          normalized_tty="$(normalize_ps_tty "$ps_tty")" || continue
          [ -n "${seen_host_tty[$normalized_tty]:-}" ] || continue
          [ -n "$proc_command" ] || continue

          for agent in "${agents[@]}"; do
            if [ "$proc_command" = "$agent" ]; then
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

main "$@"
