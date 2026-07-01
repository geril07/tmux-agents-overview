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
- `alt-p` toggles a bottom preview for the selected OpenCode pane/session.
- `enter` jumps to the selected tmux session/pane.
- `ctrl-x` kills the selected tmux session.
- `ctrl-r` refreshes the list.
- Inherits `FZF_DEFAULT_OPTS`, but forces `--height=100%` so fzf fills the tmux popup.

## Requirements

- tmux >= 3.2 for `display-popup`
- `fzf`
- OpenCode
- bash

## Install as a tmux plugin

Add this to your tmux config with the path adjusted to this checkout:

```tmux
run-shell /home/geril/code/oss/herdr-to-tmux/tmux-opencode-session-overview/opencode_session_overview.tmux
```

Reload tmux config.

## Install the OpenCode bridge

OpenCode needs a small plugin so it can stamp status onto the current tmux
session. Symlink it into OpenCode's plugin directory:

```bash
mkdir -p ~/.config/opencode/plugins
ln -sf /home/geril/code/oss/herdr-to-tmux/tmux-opencode-session-overview/.opencode/plugins/tmux-opencode-session-overview.js \
  ~/.config/opencode/plugins/tmux-opencode-session-overview.js
```

The JS plugin resolves the real path of the symlink and finds
`scripts/state.sh` automatically. If you copy the JS file instead of symlinking
it, set this environment variable before starting OpenCode:

```bash
export TMUX_OPENCODE_OVERVIEW_STATE=/home/geril/code/oss/herdr-to-tmux/tmux-opencode-session-overview/scripts/state.sh
```

## Options

Set these before loading the plugin:

```tmux
set -g @opencode_overview_key 'o'
set -g @opencode_overview_popup_width '50%'
set -g @opencode_overview_popup_height '75%'
```

## State Model

The OpenCode bridge writes session-scoped tmux options:

```text
@opencode_state       working | waiting | idle | unknown
@opencode_state_at    unix timestamp
@opencode_session_id  native OpenCode session id, when available
@opencode_pane        tmux pane id that reported status
@opencode_window      tmux window id that reported status
@opencode_cwd         pane cwd
@opencode_reason      prompt | busy | retry | permission | question | done | error
@opencode_tool        reserved for future tool tracking
```

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
session.error          -> unknown / error
```

The bridge intentionally uses only OpenCode's `event` callback. This keeps the
integration small and avoids tool/prompt hooks until the overlay needs richer
activity details.

## Notes

This first version is session-scoped because the target workflow is usually one
OpenCode instance per tmux session. If you later run multiple OpenCode instances
inside one tmux session, the state should move to pane-scoped options.
