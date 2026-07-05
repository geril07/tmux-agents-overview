# Benchmarks

Reusable commands for measuring row-generation performance on a live tmux session.

## Session Shape

Count panes and see how many are using `node` as the foreground command:

```sh
tmux list-panes -a -F '#{pane_id}	#{pane_current_command}	#{pane_tty}'
```

## Runtime Benchmark

Runs each row generator once for a first-hit number, then 20 warm runs.

```sh
python3 -c 'import subprocess,time,statistics; cmds=[("bash",["bash","scripts/rows.bash"]),("python",["python3","scripts/rows.py"]),("lua",["lua","scripts/rows.lua"])]; print("runtime first_ms mean_ms median_ms min_ms max_ms runs");
for name,cmd in cmds:
    t=time.perf_counter(); subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True); first=(time.perf_counter()-t)*1000
    vals=[]
    for _ in range(20):
        t=time.perf_counter(); subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True); vals.append((time.perf_counter()-t)*1000)
    print(f"{name} {first:.1f} {statistics.mean(vals):.1f} {statistics.median(vals):.1f} {min(vals):.1f} {max(vals):.1f} {len(vals)}")'
```

## Entrypoint Benchmark

Measures the real picker row-entrypoint, respecting `@agents_overview_runtime`.

```sh
python3 -c 'import subprocess,time,statistics; cmd=["bash","scripts/picker.sh","--list"]; print("entrypoint first_ms mean_ms median_ms min_ms max_ms runs"); t=time.perf_counter(); subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True); first=(time.perf_counter()-t)*1000; vals=[];
for _ in range(20):
    t=time.perf_counter(); subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True); vals.append((time.perf_counter()-t)*1000)
print(f"picker.sh --list {first:.1f} {statistics.mean(vals):.1f} {statistics.median(vals):.1f} {min(vals):.1f} {max(vals):.1f} {len(vals)}")'
```

## Current Runtime

Shows which runtime the picker will use right now:

```sh
tmux show-option -gqv @agents_overview_runtime
```

## Codex TTY Trace

Useful when checking why a `node` pane resolves to `codex`:

```sh
tmux list-panes -a -F '#{pane_id}	#{session_name}:#{window_index}.#{pane_index}	#{pane_current_command}	#{pane_tty}	#{pane_current_path}'
ps -t pts/12 -o pid=,ppid=,pgid=,tpgid=,stat=,comm=,args=
ps -t pts/12 -o comm=
ps -C codex,opencode,claude -o tty=,pgid=,tpgid=,comm=
```

Replace `pts/12` with the tty you want to inspect.
