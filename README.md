# tmux-opencode-session-overview

On-demand tmux popup for answering: which tmux sessions have OpenCode running,
what state are they in, and where should I jump next?

This is intentionally smaller than a persistent sidebar. It uses tmux session
options as the state store and `fzf` as the overlay UI.

## Features

- `prefix + o` opens an OpenCode overview popup.
- Lists tmux sessions that have OpenCode status or a detectable OpenCode pane.
- Shows `working`, `waiting`, `idle`, or `unknown`.
- Sorts sessions needing attention first.
- `enter` jumps to the selected tmux session/pane.
- `ctrl-x` kills the selected tmux session.
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
set -g @plugin '<github-user>/tmux-opencode-session-overview'
```

Then press `prefix` + <kbd>I</kbd> to install.

### Manual

Clone the repository:

```sh
git clone https://github.com/<github-user>/tmux-opencode-session-overview ~/.tmux/plugins/tmux-opencode-session-overview
```

Add this to your tmux config:

```tmux
run-shell ~/.tmux/plugins/tmux-opencode-session-overview/opencode_session_overview.tmux
```

Reload tmux config with `tmux source-file ~/.tmux.conf`.

## Install the OpenCode bridge

OpenCode needs a small plugin so it can stamp status onto the current tmux
session. Symlink it into OpenCode's plugin directory:

```bash
mkdir -p ~/.config/opencode/plugins
ln -sf ~/.tmux/plugins/tmux-opencode-session-overview/.opencode/plugins/tmux-opencode-session-overview.js \
  ~/.config/opencode/plugins/tmux-opencode-session-overview.js
```

The JS plugin resolves the real path of the symlink and finds
`scripts/state.sh` automatically. If you copy the JS file instead of symlinking
it, set this environment variable before starting OpenCode:

```bash
export TMUX_OPENCODE_OVERVIEW_STATE=$HOME/.tmux/plugins/tmux-opencode-session-overview/scripts/state.sh
```

## Usage

| Key | Action |
| --- | --- |
| `prefix` + `o` | Open the OpenCode session picker |

Inside the picker:

| Key | Action |
| --- | --- |
| `enter` | Jump to the selected session/pane |
| `ctrl-x` | Kill the selected tmux session |
| `ctrl-r` | Refresh the list |
| type / arrows | Filter and navigate with fzf |

## Options

Set these before loading the plugin:

```tmux
set -g @opencode_overview_key 'o'
set -g @opencode_overview_popup_width '50%'
set -g @opencode_overview_popup_height '75%'
```

## How it works

- `opencode_session_overview.tmux` installs the tmux key binding.
- `scripts/list.sh` opens the popup and runs `scripts/picker.sh`.
- `scripts/picker.sh` reads tmux session options, formats rows for `fzf`, and jumps or kills sessions based on the selected row.
- `.opencode/plugins/tmux-opencode-session-overview.js` listens to OpenCode events and runs `scripts/state.sh` in the background.
- `scripts/state.sh` writes the latest OpenCode state into tmux session options.

The plugin does not launch OpenCode. Start OpenCode normally inside tmux; the
overview will show sessions once the bridge reports state or a pane running
`opencode` / `open-code` is detected.

## State Model

The OpenCode bridge writes session-scoped tmux options:

```text
@opencode_state       working | waiting | idle | unknown
@opencode_state_at    unix timestamp
@opencode_session_id  native OpenCode session id, when available
@opencode_pane        tmux pane id that reported status
@opencode_window      tmux window id that reported status
@opencode_cwd         pane cwd
@opencode_reason      busy | retry | permission | question | done | child | error
@opencode_tool        reserved for future tool tracking
```

State lives in tmux, not on disk. It survives tmux client disconnects because it
is attached to the tmux server, and it disappears when the tmux server exits or
the session is killed.

The picker also includes sessions where a pane's foreground command is
`opencode` or `open-code`, even if the bridge has not reported yet. Those rows
show as `unknown`.

## Event Mapping

```text
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
```

The bridge intentionally uses only OpenCode's `event` callback. This keeps the
integration small and avoids tool/prompt hooks until the overlay needs richer
activity details.

Child OpenCode sessions are tracked so subagent events do not overwrite the root
session id. Child `permission.asked` and `question.asked` events can still mark
the parent tmux session as waiting.

## Notes

This first version is session-scoped because the target workflow is usually one
OpenCode instance per tmux session. If you later run multiple OpenCode instances
inside one tmux session, the state should move to pane-scoped options.

## License

No license has been selected yet.
