# tmux-agents-overview

On-demand tmux popup for answering: which tmux panes have a coding-agent CLI
running, what state are they in, and where should I jump next?

Supports **OpenCode**, **Pi**, **Claude Code**, and **Codex CLI** out of the
box. Add another agent by dropping a single `scripts/adapters/<id>.sh` (or
`.js` / `.ts` for in-process plugin systems) and a row in
`scripts/helpers.sh` — nothing else needs to change.

This is intentionally smaller than a persistent sidebar. It uses tmux pane
options as the state store and `fzf` as the overlay UI.

## Features

- `prefix + o` opens the agent-pane picker.
- Lists tmux panes whose foreground command is `opencode`, `pi`, `codex`, or
  `claude`, plus panes running a registered host process such as `node` or
  `npm` when a tty process probe confirms the real agent — across all sessions
  and windows.
- Shows `working`, `waiting`, `idle`, or `unknown` for each.
- `enter` jumps to the selected tmux pane.
- `ctrl-x` kills the selected tmux pane.
- `ctrl-r` refreshes the list.
- Inherits `FZF_DEFAULT_OPTS`, but forces `--height=100%` so fzf fills the tmux popup.

## Requirements

- tmux >= 3.2 for `display-popup`
- [fzf](https://github.com/junegunn/fzf)
- One of:
  - [OpenCode](https://opencode.ai/) (auto-installed bridge)
  - [Pi](https://pi.dev) (auto-installed extension)
  - [Claude Code](https://claude.com/claude-code) (`claude` CLI, manual settings.json merge)
  - [Codex CLI](https://github.com/openai/codex) (`codex` CLI, manual config.toml merge)
- bash
- Optional: `lua` or `python3` for faster row generation (`@agents_overview_runtime 'lua'` or `'python'`)

The picker works for any of the four agents even without the optional hook
setup when tmux reports the CLI name as the foreground command — those panes
show as `unknown`. Hooks and extensions add the colors, the "needs attention"
classification, and a fallback detection signal for agents hosted under
another registered process name, such as panes launched through `node` or
`npm`.

## Install

### tpm

After publishing this repository, add it to your tmux config:

```tmux
set -g @plugin 'geril07/tmux-agents-overview'
```

Then press `prefix` + <kbd>I</kbd> to install.

On first load the plugin will:

- Symlink `scripts/adapters/opencode.js` into `~/.config/opencode/plugins/`
  (skipped silently if OpenCode isn't installed).
- Symlink `scripts/adapters/pi.ts` into `~/.pi/agent/extensions/`
  (or `$PI_CODING_AGENT_DIR/extensions/`, skipped silently if Pi isn't
  installed).
- Bind `prefix + o` to the picker.

Claude and Codex have no plugin runtime; the plugin does not touch
`~/.claude/settings.json` or `~/.codex/config.toml`. See
[Per-agent setup](#per-agent-setup) for the one-time merge step.

### Manual

Clone the repository to the **canonical install path**:

```sh
git clone https://github.com/geril07/tmux-agents-overview ~/.tmux/plugins/tmux-agents-overview
```

The canonical path `~/.tmux/plugins/tmux-agents-overview` is the install
location the OpenCode/Pi symlinks point at, so those bridges work without
further action. The Claude/Codex per-agent setup commands below also assume
this path; if you cloned somewhere else, the entry script will auto-create a
symlink from the canonical path to your checkout on first load and the
commands will work as written. Set
`TMUX_AGENTS_OVERVIEW_NO_SYMLINK=1` in the environment before sourcing
the entry script to opt out of the auto-symlink.

Add this to your tmux config:

```tmux
run-shell ~/.tmux/plugins/tmux-agents-overview/agents_overview.tmux
```

Reload tmux config with `tmux source-file ~/.tmux.conf`.

## Per-agent setup

The picker works for any of the four supported agents without further setup.
The colored state, however, requires the agent to stamp its status onto the
tmux pane. How that happens is different per agent:

### OpenCode (auto)

The JS plugin in `scripts/adapters/opencode.js` is symlinked into
`~/.config/opencode/plugins/` when the plugin loads, if `~/.config/opencode`
exists. The auto-install is idempotent and skipped on machines without
OpenCode. Opt out with:

```tmux
set -g @agents_overview_install_opencode 'off'
```

### Pi (auto)

The TS extension in `scripts/adapters/pi.ts` is symlinked into
`~/.pi/agent/extensions/` when the plugin loads, if `~/.pi/agent` exists.
Set `PI_CODING_AGENT_DIR` to use Pi's alternate config path. Opt out with:

```tmux
set -g @agents_overview_install_pi 'off'
```

### Claude Code (one-time manual merge)

Claude Code has no plugin runtime; the plugin does not touch
`~/.claude/settings.json`. Run the adapter to print a `hooks` block,
then merge it under your existing top-level keys:

```sh
bash ~/.tmux/plugins/tmux-agents-overview/scripts/adapters/claude.sh \
  ~/.tmux/plugins/tmux-agents-overview/scripts/state.sh \
  > /tmp/agents-overview-claude.json
```

The hook commands inside the fragment call
`scripts/state.sh claude <state> <reason>` directly — no extra wrapper,
no extra process. Re-run the command only if you change the plugin's
install path; the table that generates the fragment is the same one
that powers the picker.

### Codex CLI (one-time manual merge)

Codex CLI has no plugin runtime; the plugin does not touch
`~/.codex/config.toml`. Run the adapter to print a `[hooks]` table
fragment, then append it to your config:

```sh
bash ~/.tmux/plugins/tmux-agents-overview/scripts/adapters/codex.sh \
  ~/.tmux/plugins/tmux-agents-overview/scripts/state.sh \
  >> ~/.codex/config.toml
```

The Codex hook commands call `scripts/state.sh codex <state> <reason>`.

## Usage

| Key | Action |
| --- | --- |
| `prefix` + `o` | Open the agent-pane picker |

Inside the picker:

| Key | Action |
| --- | --- |
| `enter` | Jump to the selected pane |
| `ctrl-x` | Kill the selected tmux pane |
| `ctrl-r` | Refresh the list |
| type / arrows | Filter and navigate with fzf |

## Options

Set these before loading the plugin:

```tmux
set -g @agents_overview_key             'o'
set -g @agents_overview_popup_width     '50%'
set -g @agents_overview_popup_height    '50%'
set -g @agents_overview_columns         'pane,status,age,cwd'
set -g @agents_overview_runtime         'bash'
set -g @agents_overview_install_opencode    'on'
set -g @agents_overview_install_pi          'on'
```

`@agents_overview_columns` is a comma-separated list. Supported columns are
`pane`, `status`, `age`, `cwd`, `detail`, `command`, `agent`, and `pane_id`.

`@agents_overview_runtime` controls row generation. Supported values are
`bash`, `lua`, and `python`. `bash` is the default and has no extra
dependency. `lua` and `python` use `scripts/rows.lua` / `scripts/rows.py` for
faster list rendering and fall back to Bash if the runtime is missing.

### Performance

Measured on a session with 55 tmux panes (24 running Codex agents):

| Runtime | First invocation | Steady state |
| --- | ---: | ---: |
| `bash` | ~330ms | ~80ms |
| `python` | ~80ms | ~80ms |
| `lua` | ~55ms | ~55ms |

`lua` and `python` are consistently fast because they avoid the shell's
startup and parsing overhead. `bash` is competitive when warm (OS cache
hits) but the first `prefix + o` invocation is noticeably slower.

`lua` is the fastest option. `python` is a middle ground with similar
per-pane scaling and no JIT dependency.

- `agent` shows the resolved agent id from the registry (`opencode`, `pi`,
  `codex`, or `claude`), regardless of which process name matched.
- `command` shows the raw `pane_current_command` (e.g. `opencode`).

For example, to show which agent is running instead of the cwd:

```tmux
set -g @agents_overview_columns 'pane,status,age,agent'
```

## How it works

- `agents_overview.tmux` ensures `~/.tmux/plugins/tmux-agents-overview`
  points at the install (auto-symlink if missing), binds the key, publishes
  the `state.sh` path so plugin-runtime adapters can find it, and symlinks the
  OpenCode plugin / Pi extension if those agents are installed.
- `scripts/list.sh` opens the popup and runs `scripts/picker.sh`.
- `scripts/picker.sh` opens `fzf`, jumps to or kills panes based on the
  selected row, and dispatches row generation to Bash by default or Lua when
  `@agents_overview_runtime 'lua'` is set.
- The row generator reads tmux pane options in a single `list-panes -a` call,
  includes panes with a known foreground command or a confirmed generic host
  process, and formats rows for `fzf`.
- Each agent's adapter turns that agent's events into `state.sh` calls:
  - **OpenCode**: a JS plugin (`scripts/adapters/opencode.js`) listens to
     OpenCode's `event` callback and spawns `state.sh opencode <state> [reason]`.
  - **Pi**: a TS extension (`scripts/adapters/pi.ts`) listens to Pi's
    `session_start`, `agent_start`, `agent_end`, and `session_shutdown`
    events and spawns `state.sh pi <state> [reason]`.
  - **Claude Code**: a `hooks` block in `~/.claude/settings.json` runs
     `state.sh claude <state> [reason]` per event. The fragment is
     generated by running `bash scripts/adapters/claude.sh` — see
    [Per-agent setup](#per-agent-setup).
  - **Codex CLI**: a `[hooks]` table in `~/.codex/config.toml` runs
    `state.sh codex <state> [reason]` per event. The fragment is
    generated by running `bash scripts/adapters/codex.sh` — see
    [Per-agent setup](#per-agent-setup).
- `scripts/state.sh` writes the latest state into the tmux pane options
  `@agent_<id>_state` / `_state_at` / `_reason`.

The plugin does not launch any of the agents. Start them normally inside
tmux; the overview shows their panes as soon as the bridge reports state
or a pane running one of the four CLIs is detected.

## State Model

Each agent's adapter writes pane-scoped tmux options under a per-agent
prefix:

```text
@agent_<id>_state     working | waiting | idle | unknown
@agent_<id>_state_at  unix timestamp
@agent_<id>_reason    busy | retry | permission | question | done | child | error
```

`<id>` is one of `opencode`, `pi`, `codex`, `claude`.

State lives in tmux, not on disk. It survives tmux client disconnects
because it is attached to the tmux server, and it disappears when the
tmux server exits or the pane is killed.

The picker includes panes whose `pane_current_command` is one of the known
agent process names, even if no hook has fired yet. Those command-only rows
show as `unknown`. It also includes panes whose current command is a registered
host process, such as `node` or `npm`, when a tty process probe finds a
matching agent process name such as `codex`, `opencode`, `pi`, or `claude`. If
process probing is unavailable, it falls back to the most recently stamped
`@agent_<id>_state` option.
This avoids keeping a pane visible after an agent exits back to a shell or an
unrelated process.

## Event Mapping

OpenCode (`scripts/adapters/opencode.js`):

```text
plugin loaded          -> idle / done
session.created        -> idle / done
session.status busy    -> working / busy
session.status retry   -> working / retry
session.status idle    -> idle / done
session.idle           -> idle / done
permission.asked       -> waiting / permission
question.asked         -> waiting / question
permission.replied     -> working / busy
question.replied       -> working / busy
question.rejected      -> working / busy
session.compacted      -> working / busy
session.error          -> unknown / error
plugin dispose         -> clear
```

Pi (`scripts/adapters/pi.ts`):

```text
session_start idle      -> idle    / done
session_start busy      -> working / busy
agent_start             -> working / busy
agent_end               -> idle    / done
session_shutdown quit   -> clear
```

Claude Code (`scripts/adapters/claude.sh`):

```text
SessionStart                   -> idle    / done
UserPromptSubmit               -> working / busy
Notification:permission_prompt -> waiting / permission
PreToolUse:AskUserQuestion     -> waiting / question
Stop                           -> idle    / done
SessionEnd                     -> clear
```

Codex CLI (`scripts/adapters/codex.sh`):

```text
SessionStart:startup|resume   -> idle    / done
UserPromptSubmit              -> working / busy
PermissionRequest             -> waiting / permission
Stop                          -> idle    / done
```

Codex has no native "asking the user a question" event, so the
`waiting / question` state is left out for Codex panes.

## Adding a new agent

1. Append a row to `AGENT_PROCESS_NAMES` in `scripts/helpers.sh`:
   ```bash
   AGENT_PROCESS_NAMES=(
     "opencode opencode"
     "codex    codex"
     "claude   claude"
     "myagent  myagent-cli"
   )
   ```
2. If the agent is often hosted by a generic executable name, such as `node`
   or `npm`, add that host command to `AGENT_HOST_PROCESS_NAMES` instead of
   `AGENT_PROCESS_NAMES`, so it is only used with process/state confirmation.
3. Drop `scripts/adapters/<id>.sh` (or `.js` / `.ts` for a plugin-runtime
   system)
   that defines a registrations table the same way `claude.sh` and
   `codex.sh` do. If the adapter is a bash script, also add a
   `run-as-script` guard at the bottom that calls the snippet emitter
   when `$BASH_SOURCE` equals `$0`, so users can print the fragment
   with `bash scripts/adapters/<id>.sh <state.sh-path>`.
4. Document the merge step in **Per-agent setup** so users know how to
   wire the agent's hooks.

The picker, the OpenCode/Pi auto-install, and the manual hook fragment all
read from the registries and the per-adapter table.

## License

No license has been selected yet.
