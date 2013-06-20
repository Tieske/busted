local step_class        = require('busted.step')
local class             = require('pl.class')

-- module/object table
local setup = class(step_class)
package.loaded['busted.setup'] = setup  -- pre-set to prevent require loops

-- instance initialization
function setup:_init(context, f)
  self:super(context, "setup handler", f)   -- initialize ancestor; step object
  self.type = "setup"
  context.setup = self
end

-- registers a setup error properly
function setup:after_execution()
  assert(setup:class_of(self), "expected self to be a setup class")
  
  if self.status.type == "failure" then
    -- setup failed, set error in first test
    self.parent:firsttest():mark_failed({
        type = self.status.type,
        trace = self.status.trace,
        err = "Test not executed, the 'setup' method of context '"..self.parent.description.."' failed: "..tostring(self.parent.setup.status.err)
      }, true) -- force overwriting existing success status
    -- update all other tests underneith as well
    self.parent:mark_failed({
        type = self.parent.setup.status.type,
        trace = "",
        err = "Test not executed, due to failing 'setup' chain",
      }) 
  end
  -- call ancestor method
  self:base("after_execution")
end