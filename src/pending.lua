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

-- pending test so execution doesn't do anything
function pending:_execute()
  -- don't call ancestor
  self.status.type = "pending"
end