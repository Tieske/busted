local copas = require'copas'
local super = require'busted.loop.default'
require'coxpcall'

local pack = table.pack or function(...) return {n = select("#", ...), ...} end
local unpack = table.unpack or unpack

local xpcall = xpcall
if _VERSION == 'Lua 5.1' then
  xpcall = coxpcall
end

-- same as in loop.default, but now xpcall is a local pointing to coxpcall
local copas_pcall = function(f, ...)
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

-- create OO table, using `loop.default` as the ancestor/super class
return setmetatable({ 
    step = function()
      copas.step(0)
      super.step()  -- call ancestor to check for timers 
    end,
    pcall = copas_pcall
  }, { __index = super})

