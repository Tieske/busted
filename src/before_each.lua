local step_class        = require('busted.step')
local class             = require('pl.class')

-- module/object table
local before_each = class(step_class)
package.loaded['busted.before_each'] = before_each  -- pre-set to prevent require loops

-- instance initialization
function before_each:_init(context, f)
  self:super(context, "before_each handler", f)   -- initialize ancestor; step object
  self.type = "before_each"
  context.before_each = self  
end

-- added 'copied_error' property
function before_each:reset()
  assert(before_each:class_of(self), "expected self to be a before_each class")
  self:base("reset")          -- call ancestor
  self.copied_error = nil     -- if set, it copied the error from an before_each upstream, so this one never got executed
end

-- Execute the entire before_each chain
function before_each:before_execution()
  
  if self.parent == self.parent:getroot() then return end

  -- not in root-context, so must first call parent before_each
  self.parent.parent.before_each:execute() 
  if self.parent.parent.before_each.status.type == "failure" then
    self:mark_failed({
        type = self.parent.parent.after_each.status.type,
        err = self.parent.parent.after_each.status.err,
        trace = self.parent.parent.after_each.status.trace,
      }, true)
    self.copied_error = true -- indicate we copied this error and our related after_each should not run
  end
end

