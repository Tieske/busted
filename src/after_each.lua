local step_class        = require('busted.step')
local class             = require('pl.class')

-- module/object table
local after_each = class(step_class)
package.loaded['busted.after_each'] = after_each  -- pre-set to prevent require loops

-- instance initialization
function after_each:_init(context, f)
  self:super(context, "after_each handler", f)   -- initialize ancestor; step object
  self.type = "after_each"
  context.after_each = self
end


function after_each:before_execution()
  if self.parent.before_each.copied_error then
    -- companion before_each did not run, so neither should we
    self.status.started = true
    self.status.finished = true
  end
end

-- Execute the entire after_each chain
function after_each:after_execution()
  
  if self.parent == self.parent:getroot() then return end
  
  -- not in root-context, so must call parent after_each
  self.parent.parent.after_each:execute()
  
  if self.parent.parent.after_each.status.type == "failure" and self.status.type ~= "failure" then
    self:mark_failed({
        type = self.parent.parent.after_each.status.type,
        err = self.parent.parent.after_each.status.err,
        trace = self.parent.parent.after_each.status.trace,
      }, true)
  end
  
end

