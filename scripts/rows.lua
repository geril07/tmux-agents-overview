#!/usr/bin/env lua
-- Fast row generator for picker.sh --list.
-- Emits the same tab-separated row contract as emit_rows_bash in picker.sh.

local DEFAULT_PROCESS_REGISTRY = [[
opencode opencode
codex codex
claude claude
]]

local DEFAULT_HOST_REGISTRY = [[
codex node
]]

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

local function run(command)
  local handle = io.popen(command .. " 2>/dev/null")
  if not handle then
    return "", false
  end

  local output = handle:read("*a") or ""
  local ok = handle:close()
  return output, ok == true or ok == 0
end

local function trim_trailing_newlines(value)
  return (value or ""):gsub("[\r\n]+$", "")
end

local function get_tmux_option(name, default)
  local output = trim_trailing_newlines(run("tmux show-option -gqv " .. shell_quote(name)))
  if output ~= "" then
    return output
  end
  return default
end

local function split_lines(value)
  local result = {}
  for line in tostring(value or ""):gmatch("[^\n]+") do
    if line:match("%S") then
      table.insert(result, line)
    end
  end
  return result
end

local function split_words(value)
  local result = {}
  for word in tostring(value or ""):gmatch("%S+") do
    table.insert(result, word)
  end
  return result
end

local function split_tabs(value)
  local result = {}
  local start = 1
  while true do
    local index = value:find("\t", start, true)
    if not index then
      table.insert(result, value:sub(start))
      return result
    end
    table.insert(result, value:sub(start, index - 1))
    start = index + 1
  end
end

local function parse_registries()
  local process_registry = os.getenv("AGENTS_OVERVIEW_AGENT_PROCESS_NAMES")
  local host_registry = os.getenv("AGENTS_OVERVIEW_AGENT_HOST_PROCESS_NAMES")
  if not process_registry or process_registry == "" then
    process_registry = DEFAULT_PROCESS_REGISTRY
  end
  if not host_registry or host_registry == "" then
    host_registry = DEFAULT_HOST_REGISTRY
  end

  local agents = {}
  local agent_index = {}
  local process_owner = {}
  local host_owner = {}

  for _, line in ipairs(split_lines(process_registry)) do
    local fields = split_words(line)
    local agent = fields[1]
    if agent and agent ~= "" then
      if not agent_index[agent] then
        table.insert(agents, agent)
        agent_index[agent] = #agents
      end
      for index = 2, #fields do
        process_owner[fields[index]] = agent
      end
    end
  end

  for _, line in ipairs(split_lines(host_registry)) do
    local fields = split_words(line)
    local agent = fields[1]
    if agent and agent ~= "" then
      for index = 2, #fields do
        host_owner[fields[index]] = agent
      end
    end
  end

  return agents, agent_index, process_owner, host_owner
end

local function normalize_ps_tty(tty)
  if not tty or tty == "" or tty == "?" then
    return nil
  end
  if tty:sub(1, 1) == "/" then
    return tty
  end
  return "/dev/" .. tty
end

local function rank_for_state(state)
  if state == "waiting" then
    return 0
  elseif state == "idle" then
    return 1
  elseif state == "working" then
    return 3
  end
  return 2
end

local function icon_for_state(state)
  if state == "waiting" then
    return "\27[33m●\27[0m waiting"
  elseif state == "idle" then
    return "\27[32m●\27[0m idle   "
  elseif state == "working" then
    return "\27[35m●\27[0m working"
  end
  return "\27[90m●\27[0m unknown"
end

local function short_home_path(path)
  local home = os.getenv("HOME")
  if home and home ~= "" and path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

local function split_columns(columns)
  local result = {}
  columns = (columns or ""):gsub("%s+", "")
  if columns == "" then
    columns = "pane,status,age,cwd"
  end
  for column in (columns .. ","):gmatch("([^,]*),") do
    if column ~= "" then
      table.insert(result, column)
    end
  end
  return result
end

local function format_display_line(columns, label, status, ago, display_cwd, detail, command, pane, agent)
  local parts = {}

  for _, column in ipairs(split_columns(columns)) do
    local part = nil
    if column == "pane" or column == "label" then
      part = string.format("%-30s", label)
    elseif column == "status" or column == "state" then
      part = status
    elseif column == "age" or column == "ago" then
      part = string.format("%5s", ago)
    elseif column == "cwd" or column == "path" then
      part = display_cwd
    elseif column == "detail" or column == "reason" then
      part = detail
    elseif column == "agent" then
      part = agent
    elseif column == "command" or column == "cmd" then
      part = command
    elseif column == "pane_id" or column == "pane-id" then
      part = pane
    end

    if part then
      table.insert(parts, part)
    end
  end

  if #parts == 0 then
    return string.format("%-30s  %s  %5s  %s", label, status, ago, display_cwd)
  end
  return table.concat(parts, "  ")
end

local function build_tmux_format(agents)
  local format = "#{session_name}\t#{window_id}\t#{window_index}\t#{pane_id}\t#{pane_index}\t#{pane_current_command}\t#{pane_current_path}\t#{pane_tty}"
  for _, agent in ipairs(agents) do
    format = format .. string.format("\t#{@agent_%s_state}\t#{@agent_%s_state_at}\t#{@agent_%s_reason}", agent, agent, agent)
  end
  return format
end

local function read_panes(format)
  local output = run("tmux list-panes -a -F " .. shell_quote(format))
  local rows = {}
  for _, line in ipairs(split_lines(output)) do
    table.insert(rows, split_tabs(line))
  end
  return rows
end

local function probe_host_agents(rows, agents, agent_index, host_owner)
  local seen_host_tty = {}
  local host_ttys = {}
  local host_probe_agents = {}
  local host_probe_authoritative = {}

  for _, fields in ipairs(rows) do
    local command = fields[6] or ""
    local tty = fields[8] or ""
    if host_owner[command] and tty ~= "" and not seen_host_tty[tty] then
      seen_host_tty[tty] = true
      table.insert(host_ttys, tty)
    end
  end

  if #host_ttys == 0 then
    return host_probe_agents, host_probe_authoritative
  end

  local output = run("ps -C " .. shell_quote(table.concat(agents, ",")) .. " -o tty=,pgid=,tpgid=,comm=")
  for _, line in ipairs(split_lines(output)) do
    local ps_tty, pgid, tpgid, command = line:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)")
    local tty = normalize_ps_tty(ps_tty)
    if tty and seen_host_tty[tty] and pgid == tpgid and agent_index[command] then
      host_probe_agents[tty] = command
      host_probe_authoritative[tty] = true
    end
  end

  local fallback_ttys = {}
  for _, tty in ipairs(host_ttys) do
    if not host_probe_authoritative[tty] then
      table.insert(fallback_ttys, tty)
    end
  end

  if #fallback_ttys == 0 then
    return host_probe_agents, host_probe_authoritative
  end

  local fallback_output, ok = run("ps -t " .. shell_quote(table.concat(fallback_ttys, ",")) .. " -o tty=,comm=")
  if ok then
    for _, tty in ipairs(fallback_ttys) do
      host_probe_authoritative[tty] = true
    end

    for _, line in ipairs(split_lines(fallback_output)) do
      local ps_tty, command = line:match("^%s*(%S+)%s+(%S+)")
      local tty = normalize_ps_tty(ps_tty)
      if tty and seen_host_tty[tty] and agent_index[command] then
        host_probe_agents[tty] = command
      end
    end
  end

  return host_probe_agents, host_probe_authoritative
end

local function has_agent_state(fields, agent, agent_index)
  local index = agent_index[agent]
  if not index then
    return false
  end
  local base = 9 + (index - 1) * 3
  return (fields[base] or "") ~= ""
end

local function main()
  local agents, agent_index, process_owner, host_owner = parse_registries()
  local columns = get_tmux_option("@agents_overview_columns", "pane,status,age,cwd")
  local rows = read_panes(build_tmux_format(agents))
  local host_probe_agents, host_probe_authoritative = probe_host_agents(rows, agents, agent_index, host_owner)
  local now = os.time()
  local output_rows = {}

  for _, fields in ipairs(rows) do
    local session = fields[1] or ""
    local window = fields[2] or ""
    local window_index = fields[3] or ""
    local pane = fields[4] or ""
    local pane_index = fields[5] or ""
    local command = fields[6] or ""
    local cwd = fields[7] or ""
    local tty = fields[8] or ""
    local agent = process_owner[command]
    local host_backed = false

    if not agent then
      agent = host_owner[command]
      host_backed = agent ~= nil
    end

    if host_backed and agent then
      if host_probe_agents[tty] == agent then
        -- confirmed by process probe
      elseif not host_probe_authoritative[tty] then
        if not has_agent_state(fields, agent, agent_index) then
          agent = nil
        end
      else
        agent = nil
      end
    end

    if agent then
      local index = agent_index[agent]
      local base = 9 + (index - 1) * 3
      local state = fields[base] or ""
      local at = fields[base + 1] or ""
      local reason = fields[base + 2] or ""

      if state == "" then
        state = "unknown"
      end

      local ago = ""
      if at:match("^%d+$") then
        ago = tostring(math.floor((now - tonumber(at)) / 60)) .. "m"
      end

      local detail = reason
      if state == "unknown" and (detail == "session" or detail == "status") then
        detail = ""
      end

      local label = string.format("%s:%s.%s", session, window_index, pane_index)
      local line = format_display_line(
        columns,
        label,
        icon_for_state(state),
        ago,
        short_home_path(cwd),
        detail,
        command,
        pane,
        agent
      )

      table.insert(output_rows, {
        rank = rank_for_state(state),
        session = session,
        pane = pane,
        window = window,
        line = line,
        detail = detail,
        window_index = window_index,
        pane_index = pane_index,
        window_index_num = tonumber(window_index) or 0,
        pane_index_num = tonumber(pane_index) or 0,
      })
    end
  end

  table.sort(output_rows, function(left, right)
    if left.session ~= right.session then
      return left.session < right.session
    end
    if left.window_index_num ~= right.window_index_num then
      return left.window_index_num < right.window_index_num
    end
    return left.pane_index_num < right.pane_index_num
  end)

  for index, row in ipairs(output_rows) do
    io.write(string.format(
      "%s\t%s\t%s\t%s\t%d  %s\t%s\t%s\t%s\n",
      row.rank,
      row.session,
      row.pane,
      row.window,
      index,
      row.line,
      row.detail,
      row.window_index,
      row.pane_index
    ))
  end
end

main()
