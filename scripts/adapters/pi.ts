import { execFileSync, spawn } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const AGENT_ID = "pi";

const resolveTmuxStateScript = () => {
  if (!process.env.TMUX_PANE) return null;

  try {
    const candidate = execFileSync(
      "tmux",
      ["show-option", "-gqv", "@agents_overview_state_script"],
      { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
    ).trim();

    if (candidate && existsSync(candidate)) return candidate;
  } catch {
    // Fall back to resolving relative to this plugin file below.
  }

  return null;
};

const resolveStateScript = () => {
  if (process.env.TMUX_AGENTS_OVERVIEW_STATE) {
    return process.env.TMUX_AGENTS_OVERVIEW_STATE;
  }

  const tmuxStateScript = resolveTmuxStateScript();
  if (tmuxStateScript) return tmuxStateScript;

  let dir = dirname(realpathSync(fileURLToPath(import.meta.url)));
  for (let i = 0; i < 6; i += 1) {
    const candidate = resolve(dir, "../state.sh");
    if (existsSync(candidate)) return candidate;

    const parent = dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }

  return null;
};

const STATE_SCRIPT = resolveStateScript();

const report = (state: string, reason = "") => {
  if (!STATE_SCRIPT || !process.env.TMUX_PANE) return;

  try {
    const args = [STATE_SCRIPT, AGENT_ID, state];
    if (reason) args.push(reason);

    const child = spawn("bash", args, {
      stdio: "ignore",
      detached: true,
    });
    child.on("error", () => {});
    child.unref();
  } catch {
    // Pi should keep running if the tmux helper is missing or broken.
  }
};

export default function TmuxAgentsOverviewPi(pi: any) {
  if (!process.env.TMUX_PANE) return;

  let rootSession = false;

  pi.on("session_start", (_event: any, ctx: any) => {
    if (ctx?.hasUI !== true) return;
    rootSession = true;

    // A reload can replace the extension in the middle of a running turn.
    if (ctx?.isIdle?.() === false) {
      report("working", "busy");
    } else {
      report("idle", "done");
    }
  });

  pi.on("agent_start", () => {
    if (!rootSession) return;
    report("working", "busy");
  });

  pi.on("agent_end", () => {
    if (!rootSession) return;
    report("idle", "done");
  });

  pi.on("session_shutdown", (event: any) => {
    if (!rootSession) return;
    if (event?.reason === "quit") {
      report("clear");
    }
  });
}
