# MessagingManager

A module centralized MessagingService topic subscription, by use one global endpoint.
And provide feature, share publish request and scalable based on player size per server.

# Exmaple
```lua
local MessagingManager = require(script.MessagingManager)

-- Messenger
local ShutdownMessenger = MessagingManager.new("Shutdown", function(Param)
    -- Receiver
	local function Kick(Player: Player, ...)
		Player:Kick(...)
	end
	for _, player in game.Players:GetPlayers() do
		Kick(player, `Server Shutting Down. (@{os.date("*t", Param.Date)})`)
	end
	game.Players.PlayerAdded:Connect(function(player: Player) 
		Kick(player, `Server Shutting Down. (@{os.date("*t", Param.Date)})`)
	end)
end)

-- Sender
ShutdownMessenger:Pub({
	Date = os.time()
})
```
