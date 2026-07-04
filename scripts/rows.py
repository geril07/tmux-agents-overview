#!/usr/bin/env python3
"""Row generator for picker.sh --list (Python runtime).

Interface matches rows.lua and rows.bash:
  - Reads AGENTS_OVERVIEW_AGENT_PROCESS_NAMES env var (multi-line)
  - Reads AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES env var (multi-line)
  - Reads @agents_overview_columns from tmux
  - Calls tmux list-panes, ps internally
  - Prints tab-separated rows to stdout
"""

import os
import re
import subprocess
import sys
import time


DEFAULT_PROCESS_REGISTRY = """\
opencode opencode open-code
codex    codex
claude   claude"""

DEFAULT_HOST_REGISTRY = """\
codex node"""


def run(cmd, *args):
    try:
        return subprocess.check_output([cmd, *args], text=True, stderr=subprocess.DEVNULL)
    except Exception:
        return ""


def get_tmux_option(name, default):
    out = run("tmux", "show-option", "-gqv", name).strip()
    return out if out else default


def split_lines(text):
    return [line for line in text.strip("\n").split("\n") if line.strip()]


def parse_registries():
    raw_process = os.environ.get("AGENTS_OVERVIEW_AGENT_PROCESS_NAMES") or DEFAULT_PROCESS_REGISTRY
    raw_host = os.environ.get("AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES") or DEFAULT_HOST_REGISTRY

    agents = []
    agent_index = {}
    process_owner = {}
    host_owner = {}

    for line in split_lines(raw_process):
        parts = line.split()
        if not parts:
            continue
        aid = parts[0]
        if aid not in agent_index:
            agent_index[aid] = len(agents)
            agents.append(aid)
        for name in parts[1:]:
            process_owner[name] = aid

    for line in split_lines(raw_host):
        parts = line.split()
        if not parts:
            continue
        for name in parts[1:]:
            host_owner[name] = parts[0]

    return agents, agent_index, process_owner, host_owner


def normalize_ps_tty(tty):
    if not tty or tty == "?":
        return None
    if tty.startswith("/"):
        return tty
    return "/dev/" + tty


def process_line_matches_agent(command, agent, args):
    if command == agent:
        return True
    for arg in (args or "").split():
        base = arg.rstrip("/").rsplit("/", 1)[-1]
        if base == agent:
            return True
    return False


def rank_for_state(state):
    return {"waiting": 0, "idle": 1, "unknown": 2, "working": 3}.get(state, 2)


def icon_for_state(state):
    icons = {
        "waiting": "\033[33m●\033[0m waiting",
        "idle": "\033[32m●\033[0m idle   ",
        "working": "\033[35m●\033[0m working",
    }
    return icons.get(state, "\033[90m●\033[0m unknown")


def short_home_path(path):
    home = os.environ.get("HOME")
    if home and path.startswith(home):
        return "~" + path[len(home):]
    return path


def format_display_line(columns, label, status, ago, cwd, detail, command, pane, agent):
    cols = [c.strip() for c in (columns or "pane,status,age,cwd").split(",") if c.strip()]
    if not cols:
        cols = ["pane", "status", "age", "cwd"]

    parts = []
    for col in cols:
        if col in ("pane", "label"):
            parts.append(f"{label:<30}")
        elif col in ("status", "state"):
            parts.append(status)
        elif col in ("age", "ago"):
            parts.append(f"{ago:>5}")
        elif col in ("cwd", "path"):
            parts.append(cwd)
        elif col in ("detail", "reason"):
            parts.append(detail)
        elif col == "agent":
            parts.append(agent)
        elif col in ("command", "cmd"):
            parts.append(command)
        elif col in ("pane_id", "pane-id"):
            parts.append(pane)

    if not parts:
        return f"{label:<30}  {status}  {ago:>5}  {cwd}"

    return "  ".join(parts)


def build_tmux_format(agents):
    fmt = "#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_tty}"
    for agent in agents:
        fmt += f"\t#{{@agent_{agent}_state}}\t#{{@agent_{agent}_state_at}}\t#{{@agent_{agent}_reason}}"
    return fmt


def probe_host_agents(rows, agents, agent_index, host_owner):
    seen = set()
    host_ttys = []
    for fields in rows:
        tty = fields[7] if len(fields) > 7 else ""
        cmd = fields[5] if len(fields) > 5 else ""
        if cmd in host_owner and tty and tty not in seen:
            seen.add(tty)
            host_ttys.append(tty)

    if not host_ttys:
        return {}, {}

    probe = {}
    authoritative = {}

    ps_out = run("ps", "-C", ",".join(agents), "-o", "tty=,pgid=,tpgid=,comm=")
    for line in ps_out.splitlines():
        parts = line.strip().split(None, 3)
        if len(parts) < 4:
            continue
        tty = normalize_ps_tty(parts[0])
        if tty in seen and parts[1] == parts[2] and parts[3] in agent_index:
            probe[tty] = parts[3]
            authoritative[tty] = True

    argv_ttys = [t for t in host_ttys if t not in authoritative]
    if argv_ttys:
        argv_out = run("ps", "-t", ",".join(argv_ttys), "-o", "tty=,pgid=,tpgid=,comm=,args=")
        for t in argv_ttys:
            authoritative[t] = True
        for line in argv_out.splitlines():
            parts = line.strip().split(None, 4)
            if len(parts) < 5:
                continue
            tty = normalize_ps_tty(parts[0])
            if tty in seen and parts[1] == parts[2]:
                for agent in agents:
                    if process_line_matches_agent(parts[3], agent, parts[4] if len(parts) >= 5 else ""):
                        probe[tty] = agent
                        break

    return probe, authoritative


def has_agent_state(fields, agent, agent_index):
    idx = agent_index.get(agent)
    if idx is None:
        return False
    base = 8 + idx * 3
    return bool(fields[base]) if len(fields) > base else False


def main():
    agents, agent_index, process_owner, host_owner = parse_registries()
    columns = get_tmux_option("@agents_overview_columns", "pane,status,age,cwd")
    now = int(time.time())

    fmt = build_tmux_format(agents)
    raw = run("tmux", "list-panes", "-a", "-F", fmt)
    rows = [line.split("\t") for line in raw.splitlines() if line.strip()]

    host_probe, host_authoritative = probe_host_agents(rows, agents, agent_index, host_owner)

    out = []
    for fields in rows:
        if len(fields) < 8:
            continue
        session, window, window_index, pane, pane_index, command, cwd, tty = fields[:8]

        agent = process_owner.get(command)
        host_backed = False
        if agent is None:
            agent = host_owner.get(command)
            host_backed = agent is not None

        if host_backed and agent:
            if host_probe.get(tty) == agent:
                pass
            elif tty not in host_authoritative:
                if not has_agent_state(fields, agent, agent_index):
                    agent = None
            else:
                agent = None

        if agent is None:
            continue

        idx = agent_index.get(agent, 0)
        base = 8 + idx * 3
        state = fields[base] if len(fields) > base and fields[base] else "unknown"
        at = fields[base + 1] if len(fields) > base + 1 else ""
        reason = fields[base + 2] if len(fields) > base + 2 else ""

        ago = ""
        if at.isdigit():
            ago = f"{(now - int(at)) // 60}m"

        detail = reason
        if state == "unknown" and detail in ("session", "status"):
            detail = ""

        label = f"{session}:{window_index}.{pane_index}"
        line = format_display_line(columns, label, icon_for_state(state), ago, short_home_path(cwd), detail, command, pane, agent)

        out.append((
            rank_for_state(state),
            session,
            pane,
            window,
            line,
            detail,
            int(window_index or 0),
            int(pane_index or 0),
        ))

    out.sort(key=lambda x: (x[1], x[6], x[7]))

    for i, (rank, session, pane, window, line, detail, wi, pi) in enumerate(out, 1):
        print(f"{rank}\t{session}\t{pane}\t{window}\t{i}  {line}\t{detail}\t{wi}\t{pi}")


if __name__ == "__main__":
    main()
