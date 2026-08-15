--[[
  AeroOS · Pre-emptive scheduler

  Classic CC:Tweaked trick: hook os.pullEvent so user coroutines yield back to
  the kernel every time they wait for input. Combined with a timer tick
  (0.05s) we get time-sliced pre-emption that feels real to the user.

  The scheduler is the kernel main loop. It:
    1. picks the next runnable process
    2. resumes it with the next event from its inbox (or a 'tick')
    3. handles 'yield', 'event', 'terminate'
    4. re-queues the process
]]

local process = require("aeroros.kernel.process")
local event   = require("aeroros.kernel.event")
local debug   = require("aeroros.kernel.debug")

local scheduler = {}

local queue = {}              -- array of pids in run order
local timers = {}             -- cc_timer_id -> callback
local heartbeat_id = nil     -- CC's timer ID for the 0.05s heartbeat
local quit = false

-- Add a pid to the back of the run queue.
local function enqueue(pid)
  queue[#queue+1] = pid
end

-- Start a new process.
function scheduler.spawn(name, entry, env)
  local pid = process.spawn(name, entry, env)
  enqueue(pid)
  debug.info("kernel", string.format("spawned pid=%d name=%s", pid, name))
  return pid
end

-- Time-based callback. The returned id is CC's own timer id (so callers can
-- cancel via os.cancelTimer if they want).
function scheduler.timer(seconds, callback)
  local id = os.startTimer(seconds)
  timers[id] = callback
  return id
end

function scheduler.cancel_timer(id)
  timers[id] = nil
  os.cancelTimer(id)
end

function scheduler.shutdown()
  quit = true
end

-- Main loop. Returns when all processes are dead or shutdown is called.
function scheduler.run()
  -- Always start the heartbeat that drives pre-emption.
  heartbeat_id = os.startTimer(0.05)

  while not quit do
    -- 1. Pull the next raw CC event (this is the kernel's only blocking call).
    local ev = { os.pullEventRaw() }
    local name = ev[1]

    -- 2. Route timers.
    if name == "timer" then
      local cc_id = ev[2]
      if timers[cc_id] then
        -- User-registered timer: fire its callback and remove.
        local cb = timers[cc_id]
        timers[cc_id] = nil
        cb()
      elseif cc_id == heartbeat_id then
        -- Heartbeat fired: re-arm so pre-emption continues.
        heartbeat_id = os.startTimer(0.05)
        -- Don't dispatch this event to processes; it's internal.
      else
        -- Stale timer from a cancelled timer; ignore.
      end
      -- Don't fall through to event dispatch for timer events — they're
      -- either user callbacks (handled above) or the heartbeat (internal).
      -- (Previous version incorrectly dispatched timer events to processes,
      -- which caused apps to receive spurious 'tick' events.)
    else
      -- 3. Route every other event to listeners + focus_pid.
      event.dispatch(name, ev)
    end

    -- 4. Run a slice of every ready process.
    local this_tick = queue
    queue = {}
    for i = 1, #this_tick do
      local pid = this_tick[i]
      local rec = process.get(pid)
      if not rec or rec.state == 'dead' then
        -- skip
      elseif coroutine.status(rec.co) == 'dead' then
        rec.state = 'dead'
      else
        process.set_current(pid)
        local inbox_event = table.remove(rec.inbox, 1) or { 'tick' }
        local ok, yielded = coroutine.resume(rec.co, unpack(inbox_event))
        process.set_current(0)
        rec.cpu_time = rec.cpu_time + 1
        if not ok then
          -- Process crashed. Mark dead and notify WM.
          rec.state = 'dead'
          rec.exit_code = -1
          debug.error("kernel", string.format(
            "process pid=%d name=%s crashed: %s", pid, rec.name, tostring(yielded)))
          event.emit('process_died', { pid = pid, name = rec.name, error = yielded })
        elseif coroutine.status(rec.co) ~= 'dead' then
          -- Re-queue if it's still alive.
          if rec.state == 'running' then
            enqueue(pid)
          end
        else
          rec.state = 'dead'
          debug.debug("kernel", string.format(
            "process pid=%d name=%s exited normally", pid, rec.name))
        end
      end
    end

    -- 5. Reap the dead.
    process.reap()

    -- 6. If nothing is alive and nothing in the queue, idle.
    if #queue == 0 and #process.list() == 0 then
      break
    end
  end
end

return scheduler
