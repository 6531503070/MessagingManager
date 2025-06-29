--!strict

local random = Random.new()
local NextNumber = random.NextNumber

local next_number = function(min: number, max: number)
	return NextNumber(random, min, max)
end

return next_number
