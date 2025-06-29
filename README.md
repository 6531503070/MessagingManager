# MessagingManager

A typed roblox module for dealing MessagingService with an efficient way.

# Exmaple
```lua
local Players = game:GetService("Players")
local MessagingManager = require(path.to.MessagingManager)

local ShutdownMessenger = MessagingManager.new("Shutdown", function(request, currentServerMetadata: MessagingManager.MessagingMetadata, broadcasterServerMetadata: MessagingManager.MessagingMetadata) 
	-- receiver()
	for _, player in game.Players:GetPlayers() do
		player:Kick(player, `Server Shutting Down. (@{os.date("*t", request.Date)})`)
	end
	
	game.Players.PlayerAdded:Connect(function(player: Player) 
		player:Kick(player, `Server Shutting Down. (@{os.date("*t", request.Date)})`)
	end)
end)

-- sender()
ShutdownMessenger:Fire({
	Date = os.time()
})
```
