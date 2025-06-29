-- MessagingManager
-- Ratchanon Suwatsiriphol

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Concur = require(script.Parent.Concur)
local Quid = require(script.Parent.Quid)
local Signal = require(script.Parent.Signal)
local messaging_metadata = require(script.messaging_metadata)

local Constants = require(script.Constants)
local MessagingManagerObject = require(script.MessagingManagerObject)
local next_number = require(script.next_number)

_G.Message = _G.Message or {}
_G.Invokes = _G.Invokes or {}
_G.LiveChannels = _G.LiveChannels or {}

-- @overwrite
local _print = print
local function print(...)
	if Constants.ENABLE_LOG then _print(...) end
end

-- @overwrite
local _warn = warn
local function warn(...)
	if Constants.ENABLE_WARN_LOG then _warn(...) end
end

--[=[
	@class MessagingManager
	A wrapper module dealing MessagingService better and efficient for Roblox
]=]
local MessagingManager = {}

-- Setup // MessagingService (Centralized)
-- An endpoint for receiving the message from the other server.
MessagingManager.factory_function = function(message)
	local data, sent = message.Data, message.Sent
	if type(data) == "buffer" then
		local ok: boolean, err: string, message_data
		do
			ok, err = pcall(function()
				message_data = HttpService:JSONDecode(buffer.tostring(data))
			end)
		end

		if ok then
			if type(messaging) == "table" then
				local topic = messaging[1] -- Topic
				local messaging_manager_object = _G.Message[topic]

				if messaging_manager_object then
					if type(messaging_manager_object.callback) == "function" then
						local request = messaging[2] -- Request
						local broadcaster_server_metadata = messaging[3] -- BroadcasterServerMetadata
						local current_server_metadata = messaging_metadata()
						local invoke_token = messaging[4] -- InvokeToken?

						-- do a safe callback and get info.
						local ok: boolean, err: string, response
						do
							ok, err = pcall(function(...)
								response = {
									messaging_manager_object.callback(
										request,
										messaging_metadata(current_server_metadata),
										messaging_metadata(broadcaster_server_metadata)
									),
								}
							end)
						end

						-- return a response cross-server to self :Invoke() identity from token.
						if type(invoke_token) == "string" then
							if type(response) == "table" and #response > 0 then
								local target_job_id: string = response[1]

								table.move(response, 2, #response, 1, response)
								response[#response] = nil

								MessagingManager.FireTo("messaging_invoke_receptor", {
									game.JobId,
									target_job_id,
									response,
									invoke_token,
								})
							end
						end
					end
				end
			end
		end
	end
end -- Blueprint

do
	print("MessagingManager is connecting.")
	if RunService:IsRunning() and RunService:IsServer() then
		local concurs = {}
		table.insert(
			concurs,
			Concur.spawn(function(...: any)
				local ok, err, response
				do
					ok, err = pcall(function()
						response = {}
						response.Key = `G{KEY_ENDPOINT}{Id}`
						response.Subscriber =
							MessagingService:SubscribeAsync(response.Key, MessagingManager.factory_function)
					end)
				end
				return { ok, response, err }
			end)
		)

		local all = Concur.all(concurs)
		all:OnCompleted(function(err, values)
			for i, concurResult in ipairs(values) do
				local _, result = table.unpack(concurResult)
				if result then
					local channelInfo = result[2]
					if channelInfo then _G.LiveChannels[channelInfo.Key] = channelInfo end
				end
			end
		end)

		local _, result = all:Await()
		if type(result) == "table" and result[3] then
			warn(`[MessagingManager]: Due to error {result[3]}, some channel will be missing.`)
		end

		table.clear(concurs)
	end
	print("MessagingManager is ready.")
end

--- Creating a MessagingManagerObject.
---
--- @within MessagingManager
--- @param topic string
--- @param callback (request: T, current_server_metadata: MessagingMetadata, broadcaster_server_metadata: MessagingMetadata) -> ()
--- @return MessagingManagerObject
function MessagingManager.new<T>(
	topic: string,
	callback: (
		request: T,
		current_server_metadata: messaging_metadata.MessagingMetadata,
		broadcaster_server_metadata: messaging_metadata.MessagingMetadata
	) -> ()
)
	local self = setmetatable({}, MessagingManagerObject)
	self.topic = topic
	self.callback = callback
	self._nextkey = nil

	local messaging_manager_object_exist = _G.Message[topic]
	if not messaging_manager_object_exist then
		-- :new()
		_G.Message[topic] = self
		return self
	else
		-- :get()
		warn("MessagingManager, topic is already exist. (Return Exist)")
		return messaging_manager_object_exist
	end
end

--- Destroy a MessagingManagerObject.
---
--- @within MessagingManager
--- @param topic string
function MessagingManager.DestroyTo(topic: string)
	local messaging_manager_object = _G.Message[topic]
	if messaging_manager_object then messaging_manager_object:Destroy() end
end

_G._NextGlobalKey = nil

--- (One-way communication) Messaging to topic to do an action (Not-Guaranteed).
---
--- @yields
--- @within MessagingManager
--- @param topic string
--- @param request T
--- @param including_metadata boolean? -- [default=false] including metadata example server jobId.
--- @error "MessagingManagerObject not found."
function MessagingManager.FireTo<T>(topic: string, request: T, including_metadata: boolean?)
	local broadcaster_server_metadata: messaging_metadata.MessagingMetadata? = if including_metadata
		then messaging_metadata()
		else nil

	local ok: boolean, err: string, next_key, next_channel_info
	do
		ok, err = pcall(function()
			next_key, next_channel_info = next(_G.LiveChannels, _G._NextGlobalKey)
		end)

		if not ok then
			next_key, next_channel_info = next(_G.LiveChannels)
		end
	end

	if type(next_channel_info) == "table" then
		if RunService:IsStudio() then
			-- In-Simulation
			local messaging_manager_object = _G.Message[topic]

			if messaging_manager_object then
				warn(
					`(Studio-Mode), MessagingManagerObject {messaging_manager_object.topic} is simulate not real production.`
				)

				task.wait(next_number(table.unpack(Constants.SIMULATE_DELAY)))

				local ok: boolean, err: string
				do
					ok, err = pcall(function(...)
						messaging_manager_object.callback(
							request,
							messaging_metadata(),
							messaging_metadata(broadcaster_server_metadata)
						)
					end)
				end

				if not ok then error(err) end
			else
				error("(Studio-Mode), MessagingManagerObject not found")
			end
		else
			-- In-Production
			local ok: boolean, err: string
			do
				ok, err = pcall(function(...)
					MessagingService:PublishAsync(
						next_channel_info.Key,
						buffer.fromstring(HttpService:JSONEncode({
							topic, -- [1] = Topic
							request, -- [2] = Request
							broadcaster_server_metadata, -- [3] = BroadcasterServerMetadata
						}))
					)
				end)
			end

			if not ok then error(err) end
		end
	end

	_G._NextGlobalKey = next_key
end

--- (Two-way communication) Messaging to topic to do an action and get the response (Not-Guaranteed).
---
--- @yields
--- @within MessagingManager
--- @param topic string
--- @param request T
--- @param approx_response_time number? -- [default=6] a waiting seconds before disconnect and return nil response.
--- @param including_metadata boolean? -- [default=false] including metadata example server jobId?
--- @return any
--- @error "MessagingManagerObject not found"
function MessagingManager.InvokeTo<T>(
	topic: string,
	request: T,
	approx_response_time: number?,
	including_metadata: boolean?
)
	local invoke_token = `{topic}-{Quid.next()}` -- 94^16 possibility.
	local signal = Signal.new()

	_G.Invokes[invoke_token] = signal

	local broadcaster_server_metadata: messaging_metadata.MessagingMetadata? = if including_metadata
		then messaging_metadata()
		else nil

	local ok: boolean, err: string, next_key, next_channel_info
	do
		ok, err = pcall(function()
			next_key, next_channel_info = next(_G.LiveChannels, _G._NextGlobalKey)
		end)

		if not ok then
			next_key, next_channel_info = next(_G.LiveChannels)
		end
	end

	if type(next_channel_info) == "table" then
		if RunService:IsStudio() then
			-- In-Simulation
			local messaging_manager_object = _G.Message[topic]
			if messaging_manager_object then
				warn(
					`(Studio-Mode), MessagingManagerObject {messaging_manager_object.topic} is simulate not real production.`
				)

				task.delay(next_number(table.unpack(Constants.SIMULATE_DELAY)), function()
					local ok: boolean, err: string, response
					do
						ok, err = pcall(function(...)
							response = {
								messaging_manager_object.callback(
									request,
									messaging_metadata(messaging_metadata()),
									messaging_metadata(broadcaster_server_metadata)
								),
							}
						end)
					end

					task.wait(next_number(table.unpack(Constants.SIMULATE_DELAY)))
					signal:Fire(response)
				end)

				task.delay(approx_response_time, function()
					signal:Fire()
				end)

				local response = signal:Wait()

				-- clean signal prevent memory leak.
				task.defer(function()
					if signal then signal:Destroy() end
					_G.Invokes[invoke_token] = nil
				end)

				if type(response) == "table" then return unpack(response) end

				return response
			else
				error("(Studio-Mode), MessagingManagerObject not found")
			end
		else
			-- In-Production
			task.spawn(function()
				MessagingService:PublishAsync(
					next_channel_info.Key,
					buffer.fromstring(HttpService:JSONEncode({
						topic,
						request,
						broadcaster_server_metadata,
						invoke_token,
					}))
				)
			end)

			if not ok then error(err) end

			task.delay(approx_response_time or Constants.DEFAULT_RESPONSE_TIME, function()
				signal:Fire()
			end)

			local response = signal:Wait()

			-- clean signal prevent memory leak.
			task.defer(function()
				if signal then signal:Destroy() end
				_G.Invokes[invoke_token] = nil
			end)

			if type(response) == "table" then return unpack(response) end

			return response
		end
	end

	_G._NextGlobalKey = next_key
end

--- Disconnect all of subscription.
---
--- @within MessagingManager
function MessagingManager:DisconnectAll()
	if typeof(player_added_connection) == "RBXScriptConnection" then
		player_added_connection:Disconnect()
		player_added_connection = nil
	end

	if typeof(player_removing_connection) == "RBXScriptConnection" then
		player_removing_connection:Disconnect()
		player_removing_connection = nil
	end

	for topic in _G.Message do
		MessagingManager.DestroyTo(topic)
	end

	for _, signal in _G.Invokes do
		if signal then signal:Destroy() end
	end

	table.clear(_G.Message)
	table.clear(_G.Invokes)
end

--- Aliase of `:DisconnectAll()` method.
---
--- @function Destroy
--- @within MessagingManager
MessagingManager.Destroy = MessagingManager.DisconnectAll

--- @within MessagingManager
--- @private
--- @prop _connections { RBXScriptConnection }
MessagingManager._connections = {}

--[=[
	@class Ports
	@private

	Module containing ports for the MessagingManager.
]=]
MessagingManager.ports = {}

--- MessagingPort: messaging_scaler
--- A port for scaling the subscription automatically.
--- Based current player count per server.
---
--- @within Ports
--- @prop messaging_scaler MessagingManagerObject
do
	MessagingManager.ports.messaging_scaler = MessagingManager.new("messaging_scaler", function(request, metadata)
		local toggle = request.Toggle
		local userId = request.UserId
		if toggle == true then
			-- Booting a new subscription. with Concur model.
			task.spawn(function()
				local concurs = {}

				for subChannel = 1, Constants.UNIT_SCALE_PER_PLAYER do
					table.insert(
						concurs,
						Concur.spawn(function()
							local ok, err, response
							do
								ok, err = pcall(function()
									response = {}
									response.Key = `@{userId}{Constants.KEY_ENDPOINT}{subChannel}`
									response.Subscriber =
										MessagingService:SubscribeAsync(response.Key, MessagingManager.factory_function)
								end)
							end

							return { ok, response, err }
						end)
					)

					local all = Concur.all(concurs)
					all:OnCompleted(function(_, values)
						for _, concurResult in ipairs(values) do
							local _, result = table.unpack(concurResult)
							if result then
								local channelInfo = result[2]
								if channelInfo then _G.LiveChannels[channelInfo.Key] = channelInfo end
							end
						end
						-- print(values) --> {{nil, 10}, {nil, 15}, {nil, 20}, {"failed", nil}}
					end)

					local _, result = all:Await()
					if type(result) == "table" and result[3] then
						warn(`[MessagingManager]: Due to error {result[3]}, some channel will be missing.`)
					end

					table.clear(concurs)
				end
			end)
		else
			for subChannel = 1, Constants.UNIT_SCALE_PER_PLAYER do
				local key = `@{userId}{Constants.KEY_ENDPOINT}{subChannel}`
				local channelInfo = _G.LiveChannels[key]

				if type(channelInfo) == "table" then
					pcall(channelInfo.Subscriber.Disconnect, channelInfo.Subscriber)
					table.clear(channelInfo)
					_G.LiveChannels[key] = nil
				end
			end
		end
	end)

	local function on_player_added(player: Player)
		MessagingManager.ports.messaging_scaler:Fire({
			UserId = player.UserId,
			Toggle = true,
		})
	end

	local function on_player_removing(player: Player)
		MessagingManager.ports.messaging_scaler:Fire({
			UserId = player.UserId,
			Toggle = false,
		})
	end

	for _, player in Players:GetPlayers() do
		task.spawn(on_player_added, player)
	end

	MessagingManager._connections.player_added = Players.PlayerAdded:Connect(on_player_added)
	MessagingManager._connections.player_removing = Players.PlayerRemoving:Connect(on_player_removing)
end

--- MessagingPort: messaging_invoke_receptor
--- A port for receiving the response from the other server.
--- Act like a router and [`RemoteFunction`](https://developer.roblox.com/en-us/api-reference/class/RemoteFunction) but for messaging.
---
--- @within Ports
--- @prop messaging_invoke_receptor MessagingManagerObject
do
	MessagingManager.ports.messaging_invoke_receptor = MessagingManager.new(
		"messaging_invoke_receptor",
		function(
			request,
			current_server_metadata: messaging_metadata.MessagingMetadata,
			broadcaster_server_metadata: messaging_metadata.MessagingMetadata
		)
			local from = request[1] -- [1] = From
			local to = request[2]
			local response = request[3]
			local invoke_token = request[4]
			if to == game.JobId then
				if type(invoke_token) == "string" then
					local invoke: Signal.Signal = _G.Invokes[invoke_token]
					if invoke then
						invoke:Fire(response)
						invoke:Destroy()
						_G.Invokes[invoke_token] = nil
					end
				end
			end
		end
	)
end

return MessagingManager
