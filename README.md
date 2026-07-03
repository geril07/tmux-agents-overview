# tmux-opencode-session-overview

On-demand tmux popup for answering: which tmux panes have OpenCode running,
what state are they in, and where should I jump next?

This is intentionally smaller than a persistent sidebar. It uses tmux pane
options as the state store and `fzf` as the overlay UI.

## Features

- `prefix + o` opens an OpenCode overview popup.
- Lists tmux panes that have OpenCode status or a detectable OpenCode process.
- Shows `working`, `waiting`, `idle`, or `unknown`.
- Sorts panes needing attention first.
- `enter` jumps to the selected tmux pane.
- `ctrl-x` kills the selected tmux pane.
- `ctrl-r` refreshes the list.
- Inherits `FZF_DEFAULT_OPTS`, but forces `--height=100%` so fzf fills the tmux popup.

## Requirements

- tmux >= 3.2 for `display-popup`
- [fzf](https://github.com/junegunn/fzf)
- [OpenCode](https://opencode.ai/)
- bash

## Install

### tpm

After publishing this repository, add it to your tmux config:

```tmux
set -g @plugin 'geril07/tmux-opencode-session-overview'
```

Then press `prefix` + <kbd>I</kbd> to install. That's it — the OpenCode
bridge is symlinked into `~/.config/opencode/plugins/` automatically
when the plugin loads (skipped silently if you don't use OpenCode).

### Manual

Clone the repository:

```sh
git clone https://github.com/geril07/tmux-opencode-session-overview ~/.tmux/plugins/tmux-opencode-session-overview
```

Add this to your tmux config:

```tmux
run-shell ~/.tmux/plugins/tmux-opencode-session-overview/opencode_session_overview.tmux
```

Reload tmux config with `tmux source-file ~/.tmux.conf`.

## Bridge install (optional)

The bridge is a small OpenCode plugin that stamps status onto the current tmux
pane. Without it the picker still works — panes running `opencode` or
`open-code` are listed as `unknown`. With it, you get the `working` /
`waiting` / `idle` colors and the "needs attention" sort.

When the tmux plugin loads, it symlinks the bridge into
`~/.config/opencode/plugins/` automatically. The auto-install only runs if
`~/.config/opencode` already exists (so it never creates state on machines
where OpenCode isn't installed) and is idempotent.

To opt out, set this before loading the plugin:

```tmux
set -g @opencode_overview_install_bridge 'off'
```

To install it manually instead:

```bash
mkdir -p ~/.config/opencode/plugins
ln -sf ~/.tmux/plugins/tmux-opencode-session-overview/.opencode/plugins/tmux-opencode-session-overview.js \
  ~/.config/opencode/plugins/tmux-opencode-session-overview.js
```

The tmux plugin publishes its `scripts/state.sh` path in the tmux option
`@opencode_overview_state_script`, so the JS plugin can find it even if the JS
file is copied (not symlinked) into OpenCode's plugin directory. The JS plugin
can also resolve `scripts/state.sh` relative to the symlink target.

For unusual installs, override the state script path before starting OpenCode:

```bash
export TMUX_OPENCODE_OVERVIEW_STATE=$HOME/.tmux/plugins/tmux-opencode-session-overview/scripts/state.sh
```

## Usage

| Key | Action |
| --- | --- |
| `prefix` + `o` | Open the OpenCode pane picker |

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
set -g @opencode_overview_key 'o'
set -g @opencode_overview_popup_width '50%'
set -g @opencode_overview_popup_height '75%'
set -g @opencode_overview_columns 'pane,status,age,cwd'
set -g @opencode_overview_install_bridge 'on'
```

`@opencode_overview_columns` is a comma-separated list. Supported columns are
`pane`, `status`, `age`, `cwd`, `detail`, `command`, and `pane_id`.

For example, to hide the cwd and show the OpenCode reason/tool detail instead:

```tmux
set -g @opencode_overview_columns 'pane,status,age,detail'
```

## How it works

- `opencode_session_overview.tmux` installs the tmux key binding and, if `~/.config/opencode` exists, symlinks the OpenCode bridge into `~/.config/opencode/plugins/`.
- `scripts/list.sh` opens the popup and runs `scripts/picker.sh`.
- `scripts/picker.sh` reads tmux pane options, formats rows for `fzf`, and jumps to or kills panes based on the selected row.
- `.opencode/plugins/tmux-opencode-session-overview.js` listens to OpenCode events and runs `scripts/state.sh` in the background.
- `scripts/state.sh` writes the latest OpenCode state into tmux pane options.

The plugin does not launch OpenCode. Start OpenCode normally inside tmux; the
overview will show panes once the bridge reports state or a pane running
`opencode` / `open-code` is detected.

## State Model

The OpenCode bridge writes pane-scoped tmux options:

```text
@opencode_state       working | waiting | idle | unknown
@opencode_state_at    unix timestamp
@opencode_reason      busy | retry | permission | question | done | child | error
```

State lives in tmux, not on disk. It survives tmux client disconnects because it
is attached to the tmux server, and it disappears when the tmux server exits or
the pane is killed.

The picker also includes panes where the foreground command is
`opencode` or `open-code`, even if the bridge has not reported yet. Those rows
show as `unknown`.

## Event Mapping

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
plugin dispose         -> clear all state
```

The bridge intentionally uses only OpenCode's `event` callback. This keeps the
integration small and avoids tool/prompt hooks until the overlay needs richer
activity details.

Child OpenCode sessions are tracked so subagent events do not overwrite the root
session id. Child `permission.asked` and `question.asked` events can still mark
the parent OpenCode pane as waiting.

Because state is pane-scoped, multiple OpenCode instances can run inside one
tmux session without overwriting each other's status.

## License

No license has been selected yet.
