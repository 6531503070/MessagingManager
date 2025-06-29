local ServerScriptService = game:GetService("ServerScriptService")

local MessagingManager = require(ServerScriptService.ServerPackages.MessagingManager)

-- @storyboot
return function()
	-- @cleanup
	return function()
		for _, connection in ipairs(MessagingManager._connections) do
			connection:Disconnect()
		end
	end
end
