local test_class        = require('busted.test')
local class             = require('pl.class')

-- module/object table
local pending = class(test_class)
package.loaded['busted.pending'] = pending  -- pre-set to prevent require loops

-- instance initialization
function pending:_init(context, desc, info)
  self:super(context, desc, function() end, info)   -- initialize ancestor; step object
  self.type = "pending"
end

-- added 'flushed' property
function pending:reset()
  assert(pending:class_of(self), "expected self to be a pending class")
  self:base("reset")          -- call ancestor
  self.status.type = 'pending'
end

-- pending test so execution doesn't do anything
function pending:_execute(execute_complete_cb)
  return execute_complete_cb()
end