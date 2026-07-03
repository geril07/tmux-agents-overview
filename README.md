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

Then press `prefix` + <kbd>I</kbd> to install.

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

## Install the OpenCode bridge

OpenCode needs a small plugin so it can stamp status onto the current tmux
pane. Symlink it into OpenCode's plugin directory:

```bash
mkdir -p ~/.config/opencode/plugins
ln -sf ~/.tmux/plugins/tmux-opencode-session-overview/.opencode/plugins/tmux-opencode-session-overview.js \
  ~/.config/opencode/plugins/tmux-opencode-session-overview.js
```

The tmux plugin publishes its `scripts/state.sh` path in the tmux option
`@opencode_overview_state_script`, so the JS plugin can find it even if the JS
file is copied into OpenCode's plugin directory. Symlinking still works too: the
JS plugin can also resolve `scripts/state.sh` relative to the symlink target.

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
set -g @opencode_overview_perf 'off'
set -g @opencode_overview_perf_log '~/.cache/tmux-opencode-session-overview/perf.log'
```

`@opencode_overview_columns` is a comma-separated list. Supported columns are
`pane`, `status`, `age`, `cwd`, `detail`, `command`, and `pane_id`.

For example, to hide the cwd and show the OpenCode reason/tool detail instead:

```tmux
set -g @opencode_overview_columns 'pane,status,age,detail'
```

Enable perf tracing when the picker feels slow:

```tmux
set -g @opencode_overview_perf 'on'
```

Perf logs are append-only lines written to `@opencode_overview_perf_log`, for
example:

```text
2026-07-03T16:03:26Z ts_ms=1783094606907 event=fzf_load request_to_event_ms=347 current_pane=%16 default_pane=%10 initial_pos=4
```

Useful events:

- `list_start`: `scripts/list.sh` started after the tmux key binding.
- `display_popup_start`: `tmux display-popup` is about to run.
- `picker_start`: `scripts/picker.sh` started inside the popup.
- `picker_ready`: pane rows and default selection are ready.
- `fzf_start`: fzf started.
- `fzf_load`: fzf loaded the input rows.
- `reload_list`: fzf `ctrl-r` or kill-pane reload regenerated rows.
- `picker_select` / `picker_cancel`: picker finished.

`emit_rows_ms` measures tmux pane scanning and state lookup time. Compare
neighboring `ts_ms` values to find delays outside that scan, such as tmux popup
startup or fzf input loading.

For request-to-visible latency, use `event=fzf_load request_to_event_ms=...`.
This measures from the tmux key binding's shell command starting to fzf loading
the rows. The exact terminal paint time is not observable from the script.

## How it works

- `opencode_session_overview.tmux` installs the tmux key binding.
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
@opencode_session_id  native OpenCode session id, when available
@opencode_pane        tmux pane id that reported status
@opencode_window      tmux window id that reported status
@opencode_cwd         pane cwd
@opencode_reason      busy | retry | permission | question | done | child | error
@opencode_tool        reserved for future tool tracking
```

State lives in tmux, not on disk. It survives tmux client disconnects because it
is attached to the tmux server, and it disappears when the tmux server exits or
the pane is killed.

The picker also includes panes where the foreground command is
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
the parent OpenCode pane as waiting.

Because state is pane-scoped, multiple OpenCode instances can run inside one
tmux session without overwriting each other's status.

## License

No license has been selected yet.
