local class = require('pl.class')
local context = class()
package.loaded['busted.context'] = context  -- pre-set to prevent require loops

local test_class        = require('busted.test')
local setup_class       = require('busted.setup')
local before_each_class = require('busted.before_each')
local after_each_class  = require('busted.after_each')
local teardown_class    = require('busted.teardown')

-- instance initialization
function context:_init(parent_context, desc)
  assert(context:class_of(parent_context) or (parent_context == nil), "Expected the parent to be a context class or nil")
  assert(desc, "Must provide a context description")
  local e = function() end
  self.parent = parent_context                  -- parent context, or nil if root-context
  self.setup = setup_class(self, e)             -- step obj containing setup procedure
  self.before_each = before_each_class(self, e) -- step obj containing before_each
  self.after_each = after_each_class(self, e)   -- step obj containing after_each
  self.teardown = teardown_class(self, e)       -- step obj containing teardown procedure
  self.list = {}                                -- list with test and context objects, in execution order
  self.description = desc                       -- textual description
  self.count = 0                                -- number of tests in context
  self.cumulative_count = 0                     -- number of tests, including nested contexts
  self:reset()
  if parent_context then parent_context:add_context(self) end
end

-- reset context
function context:reset()
  self.started = false                    -- has execution started
  self.finished = false                   -- has execution been completed
  self.loop = (self.parent or {}).loop or require('busted.loop.default')  -- contains the loop table to be used
end

-- executes context, starts with setup, then tests and nested describes, end with teardown
function context:execute(context_complete_cb)
  assert(context:class_of(self), "expected self to be a context class")
  
  local function on_teardown_complete()
    -- all is done, so call final callback to exit this context
    self.finished = true
    return context_complete_cb()
  end
  
  local index = 0
  local function do_next_step()
    index = index + 1
    if index > #self.list then
      -- list was completed, move on to teardown
      return self.teardown:execute(on_teardown_complete)
    end
    -- execute step
    local step = self.list[index]
    if not step.started then
      -- wasn't started yet, so start now
      return step:execute(do_next_step)
    elseif step.finished then
      -- already marked as started and completed, so move to next
      return do_next_step()
    else
      error("Current step, at index "..index.." of context '"..self.desc.."' was started, but not completed, so execution shouldn't be here")
    end
  end
  
  -- prepare for execution
  self:reset()
  self.started = true
  -- start chain by executing setup and start looping until done
  if not self:firsttest() then
    -- we have no tests to run, so do not execute anything, just finish
    return on_teardown_complete()
  else
    self.setup:execute(do_next_step)
    while not self.finished do
      self.loop.step()
    end
  end

end

-- mark all tests and sub-context as failed with a specific status
-- used for failing setup steps, marking everything underneath as failed
-- @param status table of original failing test
function context:mark_failed(status)
  assert(context:class_of(self), "expected self to be a context class")
  for _, step in ipairs(self.list) do 
    step:mark_failed(status)
  end
end


-- adds a test to this context
function context:add_test(test_obj)
  assert(context:class_of(self), "expected self to be a context class")
  assert(test_class:class_of(test_obj), "Can only add test classes")
  table.insert(self.list, test_obj)
  self.count = self.count + 1
  test_obj.parent = self
  local p = self
  while p do
    p.cumulative_count = p.cumulative_count + 1
    p = p.parent
  end
end

-- adds a sub context to this context
function context:add_context(context_obj)
  assert(context:class_of(self), "expected self to be a context class")
  assert(context:class_of(context_obj), "Can only add context classes")
  table.insert(self.list, context_obj)
  context_obj.parent = self
  local p = self
  while p do
    p.cumulative_count = p.cumulative_count + context_obj.cumulative_count
    p = p.parent
  end
end

-- returns the root-context of the tree this one lives in
function context:getroot()
  assert(context:class_of(self), "expected self to be a context class")
  local p = self
  while p.parent do p = p.parent end
  return p
end

-- returns the first test in the context, used to report the
-- runup error of a setup procedure in
-- note: returns nil if context contains no test (faulty situation!)
function context:firsttest()
  assert(context:class_of(self), "expected self to be a context class")
  local t = self.list[1]
  if context:class_of(t) then return t:firsttest() end
  return t
end

-- returns the last test in the context, used to report the
-- rundown error of a teardown procedure in
-- note: returns nil if context contains no test (faulty situation!)
function context:lasttest()
  assert(context:class_of(self), "expected self to be a context class")
  local t = self.list[#self.list]
  if context:class_of(t) then return t:lasttest() end
  return t
end

-- returns the currently executing step (can be setup, teardown, before_each, test, pending, etc.)
function context:currentstep()
  if not self.started or self.finished then return nil end
  if self.setup.started and not self.setup.finished then return self.setup end
  if self.before_each.started and not self.before_each.finished then return self.before_each end
  if self.after_each.started and not self.after_each.finished then return self.after_each end
  if self.teardown.started and not self.teardown.finished then return self.teardown end
  for _, elem in ipairs(self.list) do
    if elem.started and not elem.finished then
      if context:class_of(elem) then return elem:currentstep() end -- get it from a sub-context
      return elem 
    end
  end
end

return context