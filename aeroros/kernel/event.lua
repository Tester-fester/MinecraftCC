--[[
  AeroOS · Event router

  Two flavours:
    - broadcast(name, payload): every process gets a copy in its inbox.
    - dispatch(name, raw_event): route a raw CC event to whoever cares.

  Subscriptions let processes filter by event name. This mirrors Phoenix's
  devlisten syscall — a process asks to hear about a class of events and the
  kernel forwards matching ones.

  Window ownership: keyboard / mouse / char events are routed to the window
  that currently has focus (set by the WM). Peripheral and network events
  are broadcast to listeners.
]]

local process = require("aeroros.kernel.process")

local event = {}

local listeners = {}      -- event_name -> { pid, pid, ...}
local focus_pid = nil     -- pid that receives keyboard/mouse events

function event.set_focus(pid)
  focus_pid = pid
end

function event.get_focus()
  return focus_pid
end

function event.listen(name, pid)
  pid = pid or process.current()
  if not pid then return end
  listeners[name] = listeners[name] or {}
  listeners[name][pid] = true
end

function event.ignore(name, pid)
  pid = pid or process.current()
  if listeners[name] then
    listeners[name][pid] = nil
  end
end

-- Broadcast to all subscribers of `name`.
function event.emit(name, payload)
  local subs = listeners[name]
  if not subs then return end
  for pid, _ in pairs(subs) do
    process.deliver(pid, { name, payload })
  end
end

-- Dispatch a raw CC event. Keyboard / mouse / char go to focus_pid AND
-- to listeners (the desktop listens for these so it can route them).
-- Everything else goes to listeners of that event name only.
function event.dispatch(name, raw)
  if name == "key" or name == "key_up"
  or name == "char" or name == "paste"
  or name == "mouse_click" or name == "mouse_up"
  or name == "mouse_scroll" or name == "mouse_drag"
  or name == "terminate" then
    -- Input events: deliver to focus_pid (the focused app) AND any explicit
    -- listeners (the desktop shell listens with pid 0 so it can route clicks).
    if focus_pid then
      process.deliver(focus_pid, raw)
    end
    local subs = listeners[name]
    if subs then
      for pid, _ in pairs(subs) do
        -- Avoid double-delivering to the focused pid if it's also a listener.
        if pid ~= focus_pid then
          process.deliver(pid, raw)
        end
      end
    end
  else
    -- Network / peripheral / etc: deliver to listeners exactly once.
    -- (Previously this delivered twice — once via the loop below and once
    -- via event.emit. Now we only loop.)
    local subs = listeners[name]
    if subs then
      for pid, _ in pairs(subs) do
        process.deliver(pid, raw)
      end
    end
  end
end

return event
