# tmux-agents-overview

On-demand tmux popup for answering: which tmux panes have a coding-agent CLI
running, what state are they in, and where should I jump next?

Supports **OpenCode**, **Claude Code**, and **Codex CLI** out of the box. Add
another agent by dropping a single `scripts/adapters/<id>.sh` (or `.js` for
in-process plugin systems) and a row in `scripts/helpers.sh` — nothing else
needs to change.

This is intentionally smaller than a persistent sidebar. It uses tmux pane
options as the state store and `fzf` as the overlay UI.

## Features

- `prefix + o` opens the agent-pane picker.
- Lists tmux panes whose foreground command is `opencode` / `open-code`,
  `codex`, or `claude` — across all sessions and windows.
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
  - [Claude Code](https://claude.com/claude-code) (`claude` CLI, manual settings.json merge)
  - [Codex CLI](https://github.com/openai/codex) (`codex` CLI, manual config.toml merge)
- bash

The picker works for any of the three agents even without the optional hook
setup — those panes just show as `unknown`. Hooks add the colors and the
"needs attention" classification.

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
- Write `scripts/snippets/claude-settings.json` and
  `scripts/snippets/codex-config.toml` and tell you to merge them into
  `~/.claude/settings.json` and `~/.codex/config.toml` respectively.

### Manual

Clone the repository to the **canonical install path**:

```sh
git clone https://github.com/geril07/tmux-agents-overview ~/.tmux/plugins/tmux-agents-overview
```

The canonical path `~/.tmux/plugins/tmux-agents-overview` is used in the
generated Claude/Codex snippets and in the OpenCode plugin symlink, so the
files you paste into `~/.claude/settings.json` and `~/.codex/config.toml`
work without rewriting any paths.

If you cloned somewhere else (e.g. `~/code/my/tmux-agents-overview`),
the entry script will auto-create a symlink from the canonical path to
your checkout on first load — snippets and the OpenCode bridge will then
work without any further action. Set `TMUX_AGENTS_OVERVIEW_NO_SYMLINK=1`
in the environment before sourcing the entry script to opt out of the
auto-symlink.

Add this to your tmux config:

```tmux
run-shell ~/.tmux/plugins/tmux-agents-overview/agents_overview.tmux
```

Reload tmux config with `tmux source-file ~/.tmux.conf`.

## Per-agent setup

The picker works for any of the three supported agents without further setup.
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

### Claude Code (one-time manual merge)

The plugin writes a settings fragment to
`scripts/snippets/claude-settings.json` on every load (when `~/.claude`
exists). Merge it into your existing `~/.claude/settings.json` so that
the plugin's `hooks` block is added under your existing top-level keys.
To opt out of the snippet being (re)written:

```tmux
set -g @agents_overview_install_claude_hint 'off'
```

The hook commands inside the snippet call `scripts/state.sh claude <state>
<reason>` directly — no extra wrapper, no extra process.

### Codex CLI (one-time manual merge)

The plugin writes a `[hooks]` table fragment to
`scripts/snippets/codex-config.toml` on every load (when `~/.codex`
exists). Append it to your `~/.codex/config.toml`. To opt out:

```tmux
set -g @agents_overview_install_codex_hint 'off'
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
set -g @agents_overview_popup_height    '75%'
set -g @agents_overview_columns         'pane,status,age,cwd'
set -g @agents_overview_install_opencode    'on'
set -g @agents_overview_install_claude_hint 'on'
set -g @agents_overview_install_codex_hint  'on'
```

`@agents_overview_columns` is a comma-separated list. Supported columns are
`pane`, `status`, `age`, `cwd`, `detail`, `command`, `agent`, and `pane_id`.

For example, to show which agent is running instead of the cwd:

```tmux
set -g @agents_overview_columns 'pane,status,age,agent'
```

## How it works

- `agents_overview.tmux` ensures `~/.tmux/plugins/tmux-agents-overview`
  points at the install (auto-symlink if missing), binds the key, publishes
  the `state.sh` path so the OpenCode plugin can find it, symlinks the
  OpenCode plugin if OpenCode is installed, and writes the Claude/Codex
  snippet files if their config dirs exist.
- `scripts/list.sh` opens the popup and runs `scripts/picker.sh`.
- `scripts/picker.sh` reads tmux pane options in a single `list-panes -a`
  call, formats rows for `fzf`, and jumps to or kills panes based on the
  selected row.
- Each agent's adapter turns that agent's events into `state.sh` calls:
  - **OpenCode**: a JS plugin (`scripts/adapters/opencode.js`) listens to
    OpenCode's `event` callback and spawns `state.sh opencode <state> [reason]`.
  - **Claude Code**: a `hooks` block in `~/.claude/settings.json` (generated
    from the table in `scripts/adapters/claude.sh`) runs `state.sh claude
    <state> [reason]` per event.
  - **Codex CLI**: a `[hooks]` table in `~/.codex/config.toml` (generated
    from the table in `scripts/adapters/codex.sh`) runs `state.sh codex
    <state> [reason]` per event.
- `scripts/state.sh` writes the latest state into the tmux pane options
  `@agent_<id>_state` / `_state_at` / `_reason`.

The plugin does not launch any of the agents. Start them normally inside
tmux; the overview shows their panes as soon as the bridge reports state
or a pane running one of the three CLIs is detected.

## State Model

Each agent's adapter writes pane-scoped tmux options under a per-agent
prefix:

```text
@agent_<id>_state     working | waiting | idle | unknown
@agent_<id>_state_at  unix timestamp
@agent_<id>_reason    busy | retry | permission | question | done | child | error
```

`<id>` is one of `opencode`, `codex`, `claude`.

State lives in tmux, not on disk. It survives tmux client disconnects
because it is attached to the tmux server, and it disappears when the
tmux server exits or the pane is killed.

The picker also includes panes whose `pane_current_command` is one of the
known agent process names, even if no hook has fired yet. Those rows show
as `unknown`.

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
     "opencode opencode open-code"
     "codex    codex"
     "claude   claude"
     "myagent  myagent-cli"
   )
   ```
2. Drop `scripts/adapters/<id>.sh` (or `.js` for a plugin-runtime system)
   that defines a registrations table the same way `claude.sh` and
   `codex.sh` do.
3. If the agent uses a bash hook, add a `install_<id>_hint` function to
   `agents_overview.tmux` that calls `write_snippet` and prints a
   one-liner via `tmux display-message`.

The picker, the install, and the snippet generator all read from the
registry and the per-adapter table — no other change is required.

## License

No license has been selected yet.
