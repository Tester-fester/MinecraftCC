--[[
  AeroOS · Process & PID management
  Inspired by Phoenix's process table, simplified for clarity.

  A "process" is a userland coroutine with:
    - a unique PID
    - a name (for taskbar / kill menus)
    - a parent PID
    - an environment table
    - an inbox of pending events
    - a state: 'running' | 'blocked' | 'dead' | 'zombie'
    - an owning window (optional, set by WM on creation)

  The kernel hands events to processes via inbox; the scheduler picks them up.
]]

local process = {}

local next_pid = 1
local table_pid = {}          -- pid -> process record
local table_name = {}        -- name -> pid (last wins; not enforced unique)
local current_pid = 0        -- 0 == kernel context

-- Build a fresh process record.
local function make_record(name, parent, entry, env)
  local pid = next_pid
  next_pid = next_pid + 1
  local co = coroutine.create(entry)
  local rec = {
    pid       = pid,
    name      = name or ("pid" .. tostring(pid)),
    parent    = parent or 0,
    env       = env or {},
    co        = co,
    state     = 'running',
    inbox     = {},         -- queued events
    window    = nil,         -- set by WM
    exit_code = nil,
    started   = os.clock(),
    cpu_time  = 0,
  }
  table_pid[pid] = rec
  table_name[rec.name] = pid
  return rec
end

function process.spawn(name, entry, env)
  local rec = make_record(name, current_pid, entry, env)
  return rec.pid
end

function process.kill(pid, code)
  local rec = table_pid[pid]
  if not rec then return false end
  rec.state = 'dead'
  rec.exit_code = code or 0
  return true
end

function process.get(pid)
  return table_pid[pid or current_pid]
end

function process.current()
  return current_pid
end

function process.set_current(pid)
  current_pid = pid
end

function process.list()
  local out = {}
  for pid, rec in pairs(table_pid) do
    if rec.state ~= 'dead' then
      out[#out+1] = rec
    end
  end
 table.sort(out, function(a,b) return a.pid < b.pid end)
  return out
end

function process.by_name(name)
  local pid = table_name[name]
  return pid and table_pid[pid] or nil
end

-- Reap dead processes so we don't leak memory across reboots.
function process.reap()
  for pid, rec in pairs(table_pid) do
    if rec.state == 'dead' then
      table_pid[pid] = nil
      if table_name[rec.name] == pid then
        table_name[rec.name] = nil
      end
    end
  end
end

-- Deliver an event to a process's inbox.
function process.deliver(pid, event)
  local rec = table_pid[pid]
  if not rec or rec.state ~= 'running' then return false end
  table.insert(rec.inbox, event)
  return true
end

return process
