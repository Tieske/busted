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
  self.output = nil                             -- the outputter to use
  self:reset()
  if parent_context then parent_context:add_context(self) end
end

-- reset context
function context:reset()
  self.started = false                    -- has execution started
  self.finished = false                   -- has execution been completed
  self.failure = 0                        -- failures encountered
  self.pending = 0                        -- pendings encountered
  self.success = 0                        -- successes encountered
  self.loop = (self.parent or {}).loop or require('busted.loop.default')  -- contains the loop table to be used
end

-- executes context, starts with setup, then tests and nested describes, end with teardown
function context:execute()
  assert(context:class_of(self), "expected self to be a context class")
  
  self:reset()
  self.started = true
  local last
  if self:firsttest() then  -- only if we have something to run
    self.setup:execute()
    if not self.finished then -- if setup fails, we're marked as finished
      for _, step in ipairs(self.list) do
        if last then  
          -- flush output of this one as it won't change anymore
          if context:class_of(last) then
            last:lasttest():flush_results()
          else
            last:flush_results() 
          end
        end 
        if not step.finished then step:execute() end
        last = step
      end
    end
    self.teardown:execute()
  end
  self.finished = true
  if self.parent == nil then
    -- I'm root context, so must flush last results
    self:lasttest():flush_results()
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
  self.started = true
  self.finished = true
end


-- adds a test to this context
function context:add_test(test_obj)
  assert(context:class_of(self), "expected self to be a context class")
  assert(test_class:class_of(test_obj), "Can only add test classes")
  table.insert(self.list, test_obj)
  self.count = self.count + 1
  test_obj.parent = self
end

-- adds a sub context to this context
function context:add_context(context_obj)
  assert(context:class_of(self), "expected self to be a context class")
  assert(context:class_of(context_obj), "Can only add context classes")
  table.insert(self.list, context_obj)
  context_obj.parent = self
end

-- removes a sub context from this context
function context:delete()
  assert(context:class_of(self), "expected self to be a context class")
  assert(self.parent, "Cannot delete a context without parent (root-context?)")
  local index
  for i, c in ipairs(self.parent.list) do
    if c == self then
      index = i 
      break
    end
  end
  table.remove(self.parent.list, index)
  self.parent = nil
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
  assert(context:class_of(self), "expected self to be a context class")
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

-- returns the outputter, cascades up to the root-context to get it
function context:getoutput()
  assert(context:class_of(self), "expected self to be a context class")
  if (not self.output) and self.parent then
    self.output = self.parent:getoutput()
  end
  return self.output
end

-- adds test results to the context
local types = { success = 1, pending = 2, failure = 3 }
function context:addresult(rtype)
  assert(context:class_of(self), "expected self to be a context class")
  assert(types[rtype], "expected result to be any one 'success', 'pending' or 'failure'")
  self[rtype] = self[rtype] + 1
  return context
end

-- returns cumulative counts, in order:
-- tests, successes, pendings, failures
-- NOTE: success, pending, failure, counts are only of the tests that already flushed their results!
-- hence:  tests ~= succes + pending + failure (unless all are finished)
function context:getcount()
  assert(context:class_of(self), "expected self to be a context class")
  local c, s, p, f = self.count, self.success, self.pending, self.failure
  for _, subcontext in ipairs(self.list) do
    if context:class_of(subcontext) then
      local t = { subcontext:getcount() }
      c = c + t[1]
      s = s + t[2]
      p = p + t[3]
      f = f + t[4]
    end
  end
  return c, s, p, f
end

-- gets a list of all statusses of all underlying tests
-- @param t: the table to add them to, or nil to create a new table
function context:getstatuses(t)
  assert(context:class_of(self), "expected self to be a context class")
  t = t or {}
  for _, elem in ipairs(self.list) do
    if context:class_of(elem) then
      elem:getstatuses(t)
    else
      elem.status.description = elem.description  -- TODO: double??? pass context to outputter??
      table.insert(t, elem.status)
    end
  end
  return t
end