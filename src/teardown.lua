local step_class        = require('busted.step')
local class             = require('pl.class')

-- module/object table
local teardown = class(step_class)
package.loaded['busted.teardown'] = teardown  -- pre-set to prevent require loops

-- instance initialization
function teardown:_init(context, f)
  self:super(context, "teardown handler", f)   -- initialize ancestor; step object
  self.type = "teardown"
  context.teardown = self
end

-- registers a teardown error properly
function teardown:after_execution()
  assert(teardown:class_of(self), "expected self to be a teardown class")
  
  if self.status.type == "failure" then
    -- if teardown failed, set error in last test, but only if it doesn't already have an error
    self.parent:lasttest():mark_failed({
        type = self.status.type,
        trace = self.status.trace,
        err = "Test succeeded, but the 'teardown' method of context '" .. self.parent.description.."' failed: " .. tostring(self.parent.teardown.status.err)
      }, true)  -- force overwriting existing success data
  end
  -- call ancestor method
  self:base("after_execution")
end
