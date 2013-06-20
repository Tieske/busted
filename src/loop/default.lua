local busted = require('busted')
local loop = {}
local timers = {}

local pack = table.pack or function(...) return {n = select("#", ...), ...} end
local unpack = table.unpack or unpack


-- the timers implemented here will not be useful within the 
-- context of the 'default' loop (this file). But they can be used
-- in combination with coroutine schedulers, see 'busted.loop.copas.lua'
-- for an example of how the timer code here can be reused.

local checktimers = function()
  local now = busted.gettime()
  for _,t in pairs(timers) do
    if now > t.timeout then
      t.on_timeout()
      t:stop()
    end
  end
end

loop.create_timer = function(secs,on_timeout)
  local timer = {
    timeout = busted.gettime() + secs,
    on_timeout = on_timeout,
    stop = function(self)
      timers[self] = nil
    end,
  }
  timers[timer] = timer
  return timer
end

-- modified pcall:
-- same args as pcall, but differs on return values of failure
--  true, results...           --> on success
--  false, error, stacktrace   --> on failure
loop.pcall = function(f, ...)
  local params = pack(...)
  local err, trace
  
  local errhandler = function(eobject)
    err = eobject
    trace = debug.traceback("",2)
  end
  local result = pack(xpcall(function() return f(unpack(params, 1, params.n)) end, errhandler))
  if result[1] then
    return unpack(result, 1, result.n)
  else
    return false, err, trace
  end
end

loop.step = function()
  checktimers()
end

return loop
