--[[
  AeroOS · Syscall layer

  A thin wrapper that userland calls instead of touching CC's APIs directly.
  This is what lets the kernel enforce permissions, route I/O, and survive
  process crashes.

  Right now it's a stub — it just delegates to fs / peripheral / etc —
  but the indirection is here so we can later add permission checks,
  capability tokens, and audit logging without rewriting userland.

  Mirrors Phoenix's libsystem namespace: system.process, system.filesystem, ...
  but inlined into one module for the demo.
]]

local syscall = {}

-- Filesystem — wraps CC's `fs` API, but allows the kernel to enforce
-- per-process path roots in the future.
function syscall.fs_list(path)
  return fs.list(path)
end
function syscall.fs_open(path, mode)
  return fs.open(path, mode)
end
function syscall.fs_exists(path)
  return fs.exists(path)
end
function syscall.fs_isDir(path)
  return fs.isDir(path)
end
function syscall.fs_makeDir(path)
  return fs.makeDir(path)
end
function syscall.fs_delete(path)
  return fs.delete(path)
end
function syscall.fs_combine(base, child)
  return fs.combine(base, child)
end
function syscall.fs_getDir(path)
  return fs.getDir(path)
end
function syscall.fs_getName(path)
  return fs.getName(path)
end
function syscall.fs_copy(src, dst)
  return fs.copy(src, dst)
end
function syscall.fs_move(src, dst)
  return fs.move(src, dst)
end
function syscall.fs_size(path)
  return fs.getSize(path)
end

-- Peripheral discovery.
function syscall.peripheral_find(typ)
  return peripheral.find(typ)
end
function syscall.peripheral_wrap(side)
  return peripheral.wrap(side)
end
function syscall.peripheral_getNames()
  return peripheral.getNames()
end
function syscall.peripheral_getType(side)
  return peripheral.getType(side)
end

-- Network — wraps `rednet` if it's available.
function syscall.rednet_host(protocol)
  if rednet then rednet.host(protocol, os.getComputerLabel() or "aeroros") end
end
function syscall.rednet_send(target, msg, protocol)
  if rednet then rednet.send(target, msg, protocol) end
end
function syscall.rednet_broadcast(msg, protocol)
  if rednet then rednet.broadcast(msg, protocol) end
end

-- HTTP — sandboxed outbound.
function syscall.http_get(url)
  if not http then return nil, "http disabled" end
  local r, err = http.get(url)
  if not r then return nil, err end
  local body = r.readAll()
  r.close()
  return body
end

return syscall
