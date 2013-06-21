local moon = require('busted.moon')
local path = require('pl.path')
local dir = require('pl.dir')
local tablex = require('pl.tablex')
local pretty = require('pl.pretty')

-- exported module table, pre-store in package.loaded to prevent 'require loops'
local busted = {}
package.loaded['busted'] = busted
package.loaded['busted.core'] = busted

busted._COPYRIGHT   = "Copyright (c) 2013 Olivine Labs, LLC."
busted._DESCRIPTION = "A unit testing framework with a focus on being easy to use. http://www.olivinelabs.com/busted"
busted._VERSION     = "Busted 1.9.0"

-- set defaults
busted.defaultoutput = path.is_windows and "plain_terminal" or "utf_terminal"
busted.defaultpattern = '_spec'
busted.defaultlua = 'luajit'
busted.defaulttimeout = 1  -- in seconds
busted.lpathprefix = "./src/?.lua;./src/?/?.lua;./src/?/init.lua"
busted.cpathprefix = path.is_windows and "./csrc/?.dll;./csrc/?/?.dll;" or "./csrc/?.so;./csrc/?/?.so;"
--busted.loop = require('busted.loop.default')
require('busted.languages.en')-- Load default language pack

local context_class     = require('busted.context')
local setup_class       = require('busted.setup')
local before_each_class = require('busted.before_each')
local test_class        = require('busted.test')
local pending_class     = require('busted.pending')
local after_each_class  = require('busted.after_each')
local teardown_class    = require('busted.teardown')

local root_context = context_class(nil, "Root-context")
local current_context = root_context
local options = {}


-- platform detection
local system, sayer_pre, sayer_post
if pcall(require, 'ffi') then
  system = require('ffi').os
elseif path.is_windows then
  system = 'Windows'
else
  system = io.popen('uname -s'):read('*l')
end

if system == 'Linux' then
  sayer_pre = 'espeak -s 160 '
  sayer_post = ' > /dev/null 2>&1'
elseif system and system:match('^Windows') then
  sayer_pre = 'echo '
  sayer_post = ' | ptts'
else
  sayer_pre = 'say '
  sayer_post = ''
end
system = nil


-- report a test-process error as a failed test
local err_context
local internal_error = function(description, err)
  local tag = ""
  if options.tags and #options.tags > 0 then
    -- tags specified; must insert a tag to make sure the error gets displayed
    tag = " #"..options.tags[1]
  end
  
  if not err_context then
    -- no error context yet, create it now
    local c = current_context
    current_context = root_context
    busted.describe("Busted process errors occured" .. tag, function()
      busted.it(description .. tag, function() error(err) end)
    end)
    err_context = current_context.list[#current_context.list]
    current_context = c
  else
    -- load error into the error context
    local c = current_context
    current_context = err_context
    busted.it(description .. tag, function() error(err) end)
    current_context = c
  end
end

-- returns current time in seconds
busted.gettime = os.clock
if pcall(require, "socket") then
  busted.gettime = package.loaded["socket"].gettime
end

local language = function(lang)
  if lang then
    busted.messages = require('busted.languages.'..lang)
    require('luassert.languages.'..lang)
  end
end

-- load the outputter as set in the options, revert to default if it fails
local getoutputter  -- define first to enable recursion
getoutputter = function(output, opath, default)
  local success, out, f
  if output:match(".lua$") then
    f = function()
      return loadfile(path.normpath(path.join(opath, output)))()
    end
  else
    f = function()
      return require('busted.output.'..output)()
    end
  end

  success, out = pcall(f)

  if not success then
    if not default then
      -- even default failed, so error out the hard way
      return error("Failed to open the busted default output; " .. tostring(output) .. ".\n"..out)
    else
      internal_error("Unable to open output module; requested option '--output=" .. tostring(output).."'.", out)
      -- retry with default outputter
      return getoutputter(default, opath)
    end
  end
  return out
end

-- acquire set of test files from the options specified
local gettestfiles = function(root_file, pattern)
  local filelist

  if path.isfile(root_file) then
    filelist = { root_file }
  elseif path.isdir(root_file) then
    local pattern = pattern ~= "" and pattern or busted.defaultpattern
    filelist = dir.getallfiles(root_file)

    filelist = tablex.filter(filelist, function(filename)
      return path.basename(filename):find(pattern)
    end)

    filelist = tablex.filter(filelist, function(filename)
      if path.is_windows then
        return not filename:find('%\\%.%w+.%w+')
      else
        return not filename:find('/%.%w+.%w+')
      end
    end)
  else
    filelist = {}
  end

  return filelist
end

local is_terra = function(fname)
  return fname:find(".t", #fname-2, true) and true or false
end

-- runs a testfile, loading its tests
local load_testfile = function(filename)
  local old_TEST = _TEST
  _TEST = busted._VERSION

  local success, err = pcall(function() 
    local chunk,err
    if moon.is_moon(filename) then
      if moon.has_moon then
        chunk,err = moon.loadfile(filename)
      else
        chunk = function()
          busted.describe("Moon script not installed", function()
            busted.pending("File not tested because 'moonscript' isn't installed; "..tostring(filename))
          end)
        end
      end
    elseif is_terra(filename) then
      if terralib then
        chunk,err = terralib.loadfile(filename)
      else
        chunk = function()
          busted.describe("Not running tests under Terra", function()
            busted.pending("File not tested because tests are not being run with 'terra'; "..tostring(filename))
          end)
        end
      end
    else
      chunk,err = loadfile(filename)
    end
    
    if not chunk then
      error(err,2)
    end
    chunk()
  end)

  if not success then
    internal_error("Failed executing testfile; " .. tostring(filename), err)
  end

  _TEST = old_TEST
end

local play_sound = function(failures)
  if busted.messages.failure_messages and #busted.messages.failure_messages > 0 and
    busted.messages.success_messages and #busted.messages.success_messages > 0 then

    math.randomseed(os.time())

    if failures and failures > 0 then
      io.popen(sayer_pre.."\""..busted.messages.failure_messages[math.random(1, #busted.messages.failure_messages)]:format(failures).."\""..sayer_post)
    else
      io.popen(sayer_pre.."\""..busted.messages.success_messages[math.random(1, #busted.messages.success_messages)].."\""..sayer_post)
    end
  end
end

local get_fname = function(short_src)
  return short_src:match('%"(.-)%"') -- matches first string within double quotes
end

--=============================
-- Test engine
--=============================

-- Required to use on async callbacks. So busted can catch any errors and mark test as failed
busted.async = function(f)
  local active_step = root_context:currentstep()
  assert(active_step, "currently no test-step is executing")
  active_step.step_is_async = true
  
  if not f then
    -- this allows async() to be called on its own to mark any test as async.
    return
  end

  local safef = function(...)
    local result = { active_step.parent.loop.pcall(f, ...) }

    if result[1] then
      return unpack(result, 2)
    else
      local err, stack_trace = result[2]
      if type(err) == "table" then
        err = pretty.write(err)
      end

      err, stack_trace = moon.rewrite_traceback(err, debug.traceback("", 2))

      active_step.status.type = 'failure'
      active_step.status.trace = stack_trace
      active_step.status.err = err
      active_step.done()
    end
  end

  return safef
end

local match_tags = function(testName)
  if #options.tags > 0 then

    for t = 1, #options.tags do
      if testName:find(options.tags[t]) then
        return true
      end
    end

    return false
  else
    -- default to true if no tags are set
    return true
  end
end

busted.describe = function(desc, more)
  local context = context_class(current_context, desc)
  
  current_context = context
  
  more()   -- load the context contents
  
  current_context = context.parent
  
  if not context:firsttest() then
    context:delete()  -- there is nothing to test, so delete it
  end
end

busted.setup = function(setup_func)
  setup_class(current_context, setup_func)
end

busted.before_each = function(before_func)
  before_each_class(current_context, before_func)
end

busted.teardown = function(teardown_func)
  teardown_class(current_context, teardown_func)
end

busted.after_each = function(after_func)
  after_each_class(current_context, after_func)
end

local function buildInfo(debug_info)
  local info = {
    source = debug_info.source,
    short_src = debug_info.short_src,
    linedefined = debug_info.linedefined,
  }

  local fname = get_fname(info.short_src)

  if fname and moon.is_moon(fname) then
    info.linedefined = moon.rewrite_linenumber(fname, info.linedefined) or info.linedefined
  end

  return info
end

busted.pending = function(name)
  if match_tags(name) then
    pending_class(current_context, name, buildInfo(debug.getinfo(2)))
  end
end

busted.it = function(name, test_func)
  if match_tags(name) then
    test_class(current_context, name, test_func, buildInfo(debug.getinfo(2)))
  end
end

busted.setloop = function(loop)
  if type(loop) == 'string' then
    loop = require('busted.loop.'..loop)
  end
  assert(type(loop) == "table", "Expected table got "..type(loop))
  assert(loop.step, "missing required loop method; 'step'")
  assert(loop.pcall, "missing required loop method; 'pcall'")
  current_context.loop = loop
end

-- Takes 1 parameter either:
--   string  : filename of test to load
--   function: function that runs a describe block
-- Returns: the context tree
busted.run_internal_test = function(describe_tests)
  local old_root, old_current = root_context, current_context
  
  root_context = context_class(nil, "Root-context")
  current_context = root_context
  root_context.output = require 'busted.output.stub'()
  local result = root_context
  
  pcall(function()
    if type(describe_tests) == 'function' then
       describe_tests()
    else
       load_testfile(describe_tests)
    end
    root_context:execute()
  end)

  root_context, current_context = old_root, old_current
  return result 
end

-- test runner
busted.run = function(got_options)
  options = got_options
  busted.options = options

  language(options.lang)
  busted.output = getoutputter(options.output, options.fpath, busted.defaultoutput)
  root_context.output = busted.output
  busted.output_reset = busted.output  -- store in case we need a reset
  -- if no filelist given, get them
  options.filelist = options.filelist or gettestfiles(options.root_file, options.pattern)

  local ms = busted.gettime()
  local tests, successes, pending, failures = 0,0,0,0

  -- load files, each inside its own context
  for _, filename in ipairs(options.filelist) do
    busted.describe("Context for '"..filename.."'", 
      function()
        load_testfile(filename)
      end)
  end

  tests = root_context:getcount()
  
  if not options.defer_print then
    print(busted.output.header('global', tests))
  end

  local old_TEST = _TEST
  _TEST = busted._VERSION
  root_context:execute()
  _TEST = old_TEST
  
  tests, successes, pending, failures = root_context:getcount()

  --final run time
  ms = busted.gettime() - ms

  local status_string = busted.output.formatted_status(root_context:getstatuses(), options, ms)

  if tests == 0 then failures = 1 end -- no tests found, so exitcode should be non-zero
  
  if options.sound then
    play_sound(failures)
  end

  return status_string, failures
end

return setmetatable(busted, {
  __call = function(self, ...)
    return busted.run(...)
  end
 })

