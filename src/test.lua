local step_class        = require('busted.step')
local class             = require('pl.class')
local busted            = require('busted')

-- module/object table
local test = class(step_class)
package.loaded['busted.test'] = test  -- pre-set to prevent require loops

-- instance initialization
function test:_init(context, desc, f, info)
  self:super(context, desc, f, info)   -- initialize ancestor; step object
  self.type = "test"
  context:add_test(self)
end

-- added 'flushed' property
function test:reset()
  assert(test:class_of(self), "expected self to be a test class")
  self:base("reset")          -- call ancestor
  self.flushed = nil          -- if thruthy, then output was already written
end


-- execute before_each chain here
function test:before_execution()
  
  self.parent.before_each:execute()

  -- if an error in before_each, then copy it into test and do not execute test
  if self.parent.before_each.status.type == "failure" then
    self:mark_failed({
        type = self.parent.before_each.status.type,
        err = "Test not executed. "..self.parent.before_each.status.err,
        trace = self.parent.before_each.status.trace,
      }, true)
  end
end

-- execute after_each chain here
function test:after_execution()
  
  self.parent.after_each:execute()
  
  -- if an error in after_each, then copy it into test and do not execute test
  if self.parent.after_each.status.type == "failure" and self.status.type ~= "failure" then
    self:mark_failed({
        type = self.parent.after_each.status.type,
        err = "Test successful. "..self.parent.after_each.status.err,
        trace = self.parent.after_each.status.trace,
      }, true)
  end
end

-- flush test results to the outputter
-- because the errors of a teardown chain are reported in the last test before it
-- a test cannot write its output upon completion.
-- the context object should call flush when the test output can no longer
-- be altered by the teardown chain procedure
function test:flush_results()
  local o = self.parent:getoutput()
  if (not self.flushed) and o then
    self.status.description = self.description  -- TODO: double??? pass context to outputter??
    o.currently_executing(self.status, busted.options)
    self.parent:addresult(self.status.type)
    self.flushed = true
  end
end
