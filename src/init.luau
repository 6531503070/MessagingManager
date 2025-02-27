--[[
	@Dev_Bas
	MessagingManager v2.0.1:
	A typed roblox module for dealing MessagingService with an efficient way.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Token = require(script.Token)
local LemonSignal = require(script.LemonSignal)
local BrokerRequest = require(script.BrokerRequest)

_G.Message = _G.Message or {}
_G.Invokes = _G.Invokes or {}
_G.LiveChannels = _G.LiveChannels or {}

-- .DevConfigs
local KEY_ENDPOINT = "/"
local DEFAULT_RESPONSE_TIME = 6 -- 6 Seconds, Automatic Disconnect :Invoke().
local DEFAULT_MAX_CHANNEL = 15 -- Max is 20 (Based from MessagingService).
local UNIT_SCALE_PER_PLAYER = 5 -- Max is 8 (Based from MessagingService).
local SIMULATE_DELAY = { 0.5, 1.5 } -- Simulate delay when testing on studio.
local SHOW_LOG = false

local _warn = warn
local function warn(...)
	if SHOW_LOG then
		_warn(...)
	end
end
local random = Random.new()

local function listPlayers()
	local getPlayers = Players:GetPlayers()
	local dictOfUserIds = {}

	for _, player in ipairs(getPlayers) do
		dictOfUserIds[`{player.UserId}`] = 0
	end

	return dictOfUserIds, #getPlayers
end

type UserId = {}

local function messagingMetadata<T>(rawServerMetadata: T)
	if type(rawServerMetadata) == "table" then
		return {
			GameId = rawServerMetadata[1] :: number,
			PlaceId = rawServerMetadata[2] :: number,
			PlaceVersion = rawServerMetadata[3] :: number,
			JobId = rawServerMetadata[4] :: string,
			Players = rawServerMetadata[5] :: { [UserId]: any },
			TotalPlayers = rawServerMetadata[6] :: number,
		}
	end

	local dictOfUserIds, currentNumPlayers = listPlayers()

	return {
		game.GameId,
		game.PlaceId,
		game.PlaceVersion,
		game.JobId,
		dictOfUserIds,
		currentNumPlayers,
	}
end

export type MessagingMetadata = typeof(messagingMetadata())

--[=[
	@class MessagingManager
]=]
local MessagingManager = {}

do -- @Setup // MessagingService (Centralized)
	CentralizedEndpoint = function(message)
		local data, sent = message.Data, message.Sent

		if type(data) == "buffer" then
			local ok: boolean, err: string, messaging
			do
				ok, err = pcall(function(...)
					messaging = HttpService:JSONDecode(buffer.tostring(data))
				end)
			end

			if ok then
				if type(messaging) == "table" then
					local topic = messaging[1] -- Topic
					local messagingManagerObject = _G.Message[topic]

					if messagingManagerObject then
						if type(messagingManagerObject.Callback) == "function" then
							local request = messaging[2] -- Request
							local broadcasterServerMetadata = messaging[3] -- BroadcasterServerMetadata
							local currentServerMetadata = messagingMetadata()
							local invokeToken = messaging[4] -- InvokeToken?

							-- do a safe callback and get info.
							local ok: boolean, err: string, response
							do
								ok, err = pcall(function(...)
									response = {
										messagingManagerObject.Callback(
											request,
											messagingMetadata(currentServerMetadata),
											messagingMetadata(broadcasterServerMetadata)
										),
									}
								end)
							end

							-- return a response cross-server to self :Invoke() identity from token.
							if type(invokeToken) == "string" then
								if type(response) == "table" and #response > 0 then
									local targetJobId: string = response[1]

									table.move(response, 2, #response, 1, response)
									response[#response] = nil

									MessagingManager.FireTo("MessagingInvokeReceptor", {
										game.JobId,
										targetJobId,
										response,
										invokeToken,
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
			local Broker = BrokerRequest.new(20, 10)

			for Id = 1, DEFAULT_MAX_CHANNEL do
				Broker:AddRequest(function()
					local ok, err, response
					do
						ok, err = pcall(function()
							response = {}
							response.Key = `G{KEY_ENDPOINT}{Id}`
							response.Subscriber = MessagingService:SubscribeAsync(response.Key, CentralizedEndpoint)
						end)
					end
					return { ok, response, err }
				end)
			end

			local responseBlock, overallSuccess = Broker:Run()
			if not overallSuccess then
				warn("MessagingManager, some channel are missing.")
			end

			for _, wrap in responseBlock do
				local channelInfo = wrap[2]

				if channelInfo then
					_G.LiveChannels[channelInfo.Key] = channelInfo
				end
			end
		end

		print("MessagingManager is ready.")
	end
end

--[=[
	@class MessagingManagerObject
]=]
local MessagingManagerObject = {}
MessagingManagerObject.__index = MessagingManagerObject

--[=[
	Rename entry point of the MessagingService subscription.
]=]
function MessagingManagerObject:Rename(newTopic: string)
	if _G.Message[newTopic] then
		warn("MessagingManagerObject, new topic was used. (Proccess Skipped)")
		return self
	end

	local previousTopic = self.Topic

	if _G.Message[previousTopic] == self then
		_G.Message[previousTopic] = nil
		self.Topic = newTopic
		_G.Message[newTopic] = self
	end

	return self
end

--[=[
	Disconnect to the MessagingService subscription.
]=]
function MessagingManagerObject:Disconnect()
	local topic = self.Topic
	local messagingManagerObject = _G.Message[topic]

	table.clear(messagingManagerObject)
	_G.Message[topic] = nil
end

--[=[
	Aliase of `:Disconnect()` method.
]=]
function MessagingManagerObject:Destroy()
	self:Disconnect()
end

--[=[
	(One-way communication) Messaging to topic to do an action (Not-Guaranteed)
<strong>
	@yields
	
	@param request: T
	@param includingMetadata: boolean? -- [default=false] including metadata example server jobId.
	
	@error
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManagerObject:Fire<T>(request: T)
	if self.Topic == nil then
		error(`MessagingManagerObject not found.`)
	end

	local broadcasterServerMetadata: MessagingMetadata = messagingMetadata()

	if RunService:IsStudio() then
		-- In-Simulation
		warn(`(Studio-Mode), MessagingManagerObject {self.Topic} is simulate not real production.`)

		task.wait(random:NextNumber(unpack(SIMULATE_DELAY)))

		local ok: boolean, err: string
		do
			ok, err = pcall(function(...)
				self.Callback(
					request,
					messagingMetadata(messagingMetadata()),
					messagingMetadata(broadcasterServerMetadata)
				)
			end)
		end

		if not ok then
			error(err)
		end
	else
		-- In-Production
		local NextKey, NextChannelInfo = next(_G.LiveChannels, self._NextKey)

		if type(NextChannelInfo) == "table" then
			local ok: boolean, err: string
			do
				ok, err = pcall(function(...)
					MessagingService:PublishAsync(
						NextChannelInfo.Key,
						buffer.fromstring(HttpService:JSONEncode({
							self.Topic, -- [1] = Topic
							request, -- [2] = Request
							broadcasterServerMetadata, -- [3] = BroadcasterServerMetadata
						}))
					)
				end)
			end

			if not ok then
				error(err)
			end
		end

		self._NextKey = NextKey
	end
end

--[=[
	(Two-way communication) Messaging to topic to do an action and get the response (Not-Guaranteed).
<strong>
	@yields
	
	@param request: T
	@param approxResponseTime: number? -- [default=6] a waiting seconds before disconnect and return nil response.
	@param includingMetadata: boolean? -- [default=false] including metadata example server jobId?
	@return any
	
	@error
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManagerObject:Invoke<T>(request: T, approxResponseTime: number?)
	if self.Topic == nil then
		error(`MessagingManagerObject not found.`)
	end

	local invokeToken = `{self.Topic}-{Token:NextBase94JSONSAFE(16)}` -- 94^16 possibility.
	local signal = LemonSignal.new()

	_G.Invokes[invokeToken] = signal

	local broadcasterServerMetadata: MessagingMetadata = messagingMetadata()

	if RunService:IsStudio() then
		-- In-Simulation
		task.delay(random:NextNumber(unpack(SIMULATE_DELAY)), function()
			local ok: boolean, err: string, response
			do
				ok, err = pcall(function(...)
					response = {
						self.Callback(
							request,
							messagingMetadata(messagingMetadata()),
							messagingMetadata(broadcasterServerMetadata)
						),
					}
				end)
			end

			task.wait(random:NextNumber(unpack(SIMULATE_DELAY)))
			signal:Fire(response)
		end)

		task.delay(approxResponseTime or DEFAULT_RESPONSE_TIME, function()
			signal:Fire()
		end)

		local response = signal:Wait()

		-- clean signal prevent memory leak.
		task.defer(function()
			if signal then
				signal:Destroy()
			end

			_G.Invokes[invokeToken] = nil
		end)

		if type(response) == "table" then
			return unpack(response)
		end

		return response
	else
		-- In-Production
		task.spawn(function()
			local NextKey, NextChannelInfo = next(_G.LiveChannels, self._NextKey)

			if type(NextChannelInfo) == "table" then
				MessagingService:PublishAsync(
					NextChannelInfo.Key,
					buffer.fromstring(HttpService:JSONEncode({
						self.Topic, -- [1] = Topic
						request, -- [2] = Request
						broadcasterServerMetadata, -- [3] = BroadcasterServerMetadata
						invokeToken, -- [4] = InvokeToken?
					}))
				)
			end

			self._NextKey = NextKey
		end)

		task.delay(approxResponseTime or DEFAULT_RESPONSE_TIME, function()
			signal:Fire()
		end)

		local response = signal:Wait()

		-- clean signal prevent memory leak.
		task.defer(function()
			if signal then
				signal:Destroy()
			end

			_G.Invokes[invokeToken] = nil
		end)

		if type(response) == "table" then
			return unpack(response)
		end

		return response
	end
end

--////////////////////////////////////////////////////////////////////////////////////////////////////
-- @class MessagingManager
--\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

--[=[
	Creating a MessagingManagerObject.
<strong>
	@param topic: string
	@param callback: (...) -> ()
	
	@return MessagingManagerObject
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManager.new<T>(
	topic: string,
	callback: (
		request: T,
		currentServerMetadata: MessagingMetadata,
		broadcasterServerMetadata: MessagingMetadata
	) -> ()
)
	local self = setmetatable({}, MessagingManagerObject)
	self.Topic = topic
	self.Callback = callback
	self._NextKey = nil

	local MessagingManagerObjectExist = _G.Message[topic]

	if not MessagingManagerObjectExist then
		-- :new()
		_G.Message[topic] = self
		return self
	else
		-- :get()
		warn("MessagingManager, topic is already exist. (Return Exist)")
		return MessagingManagerObjectExist
	end
end

--[=[
	Creating a MessagingManagerObject.
<strong>
	@param topic: string
	@param callback: (...) -> ()
	
	@return MessagingManagerObject
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManager.DestroyTo(topic: string)
	local messagingManagerObject = _G.Message[topic]

	if messagingManagerObject then
		messagingManagerObject:Destroy()
	end
end

_G._NextGlobalKey = nil

--[=[
	(One-way communication) Messaging to topic to do an action (Not-Guaranteed)
<strong>
	@yields
	
	@param topic: string
	@param request: T
	@param includingMetadata: boolean? -- [default=false] including metadata example server jobId.
	
	@error
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManager.FireTo<T>(topic: string, request: T)
	local broadcasterServerMetadata: MessagingMetadata? = messagingMetadata()

	local ok: boolean, err: string, nextKey, nextChannelInfo
	do
		ok, err = pcall(function()
			nextKey, nextChannelInfo = next(_G.LiveChannels, _G._NextGlobalKey)
		end)

		if not ok then
			nextKey, nextChannelInfo = next(_G.LiveChannels)
		end
	end

	if type(nextChannelInfo) == "table" then
		if RunService:IsStudio() then
			-- In-Simulation
			local messagingManagerObject = _G.Message[topic]

			if messagingManagerObject then
				warn(
					`(Studio-Mode), MessagingManagerObject {messagingManagerObject.Topic} is simulate not real production.`
				)

				task.wait(random:NextNumber(unpack(SIMULATE_DELAY)))

				local ok: boolean, err: string
				do
					ok, err = pcall(function(...)
						messagingManagerObject.Callback(
							request,
							messagingMetadata(),
							messagingMetadata(broadcasterServerMetadata)
						)
					end)
				end

				if not ok then
					error(err)
				end
			else
				error(`(Studio-Mode), MessagingManagerObject {topic} not found.`)
			end
		else
			-- In-Production
			local ok: boolean, err: string
			do
				ok, err = pcall(function(...)
					MessagingService:PublishAsync(
						nextChannelInfo.Key,
						buffer.fromstring(HttpService:JSONEncode({
							topic, -- [1] = Topic
							request, -- [2] = Request
							broadcasterServerMetadata, -- [3] = BroadcasterServerMetadata
						}))
					)
				end)
			end

			if not ok then
				error(err)
			end
		end
	end

	_G._NextGlobalKey = nextKey
end

--[=[
	(Two-way communication) Messaging to topic to do an action and get the response (Not-Guaranteed).
<strong>
	@yields
	
	@param topic: string
	@param request: T
	@param approxResponseTime: number? -- [default=6] a waiting seconds before disconnect and return nil response.
	@param includingMetadata: boolean? -- [default=false] including metadata example server jobId?
	@return any
	
	@error
</strong><p><em>--Style: Moonwave Documentation</em>
]=]
function MessagingManager.InvokeTo<T>(topic: string, request: T, approxResponseTime: number)
	local invokeToken = `{topic}-{Token:NextBase94JSONSAFE(16)}` -- 94^16 possibility.
	local signal = LemonSignal.new()

	_G.Invokes[invokeToken] = signal

	local broadcasterServerMetadata: MessagingMetadata? = messagingMetadata()

	local ok: boolean, err: string, nextKey, nextChannelInfo
	do
		ok, err = pcall(function()
			nextKey, nextChannelInfo = next(_G.LiveChannels, _G._NextGlobalKey)
		end)

		if not ok then
			nextKey, nextChannelInfo = next(_G.LiveChannels)
		end
	end

	if type(nextChannelInfo) == "table" then
		if RunService:IsStudio() then
			-- In-Simulation
			local messagingManagerObject = _G.Message[topic]

			if messagingManagerObject then
				warn(
					`(Studio-Mode), MessagingManagerObject {messagingManagerObject.Topic} is simulate not real production.`
				)

				task.delay(random:NextNumber(unpack(SIMULATE_DELAY)), function()
					local ok: boolean, err: string, response
					do
						ok, err = pcall(function(...)
							response = {
								messagingManagerObject.Callback(
									request,
									messagingMetadata(messagingMetadata()),
									messagingMetadata(broadcasterServerMetadata)
								),
							}
						end)
					end

					task.wait(random:NextNumber(unpack(SIMULATE_DELAY)))
					signal:Fire(response)
				end)

				task.delay(approxResponseTime, function()
					signal:Fire()
				end)

				local response = signal:Wait()

				-- clean signal prevent memory leak.
				task.defer(function()
					if signal then
						signal:Destroy()
					end

					_G.Invokes[invokeToken] = nil
				end)

				if type(response) == "table" then
					return unpack(response)
				end

				return response
			else
				error(`(Studio-Mode), MessagingManagerObject {topic} not found.`)
			end
		else
			-- In-Production
			task.spawn(function()
				MessagingService:PublishAsync(
					nextChannelInfo.Key,
					buffer.fromstring(HttpService:JSONEncode({
						topic,
						request,
						broadcasterServerMetadata,
						invokeToken,
					}))
				)
			end)

			if not ok then
				error(err)
			end

			task.delay(approxResponseTime or DEFAULT_RESPONSE_TIME, function()
				signal:Fire()
			end)

			local response = signal:Wait()

			-- clean signal prevent memory leak.
			task.defer(function()
				if signal then
					signal:Destroy()
				end
				_G.Invokes[invokeToken] = nil
			end)

			if type(response) == "table" then
				return unpack(response)
			end

			return response
		end
	end

	_G._NextGlobalKey = nextKey
end

local playerAddedConnection
local playerRemovingConnection

--[=[
	Disconnect all of subscription.
]=]
function MessagingManager:DisconnectAll()
	if typeof(playerAddedConnection) == "RBXScriptConnection" then
		playerAddedConnection:Disconnect()
		playerAddedConnection = nil
	end

	if typeof(playerRemovingConnection) == "RBXScriptConnection" then
		playerRemovingConnection:Disconnect()
		playerRemovingConnection = nil
	end

	for topic in _G.Message do
		MessagingManager.DestroyTo(topic)
	end

	for _, signal in _G.Invokes do
		if signal then
			signal:Destroy()
		end
	end

	table.clear(_G.Message)
	table.clear(_G.Invokes)
end

--[=[
	Aliase of `:DisconnectAll()` method.
]=]
MessagingManager.Destroy = MessagingManager.DisconnectAll
--MessagingManager:DisconnectAll()

do -- MessagingScaler
	local MessagingScaler = MessagingManager.new("MessagingScaler", function(request, metadata)
		local toggle = request.Toggle
		local userId = request.UserId

		if toggle == true then
			task.spawn(function()
				local Broker = BrokerRequest.new(20, 10)

				for SubChannel = 1, UNIT_SCALE_PER_PLAYER do
					Broker:AddRequest(function()
						local ok, err, response
						do
							ok, err = pcall(function()
								response = {}
								response.Key = `@{userId}{KEY_ENDPOINT}{SubChannel}`
								response.Subscriber = MessagingService:SubscribeAsync(response.Key, CentralizedEndpoint)
							end)
						end

						return { ok, response, err }
					end)
				end

				local responseBlock, overallSuccess = Broker:Run()

				if not overallSuccess then
					warn("MessagingManager, some channel are missing.")
				end

				for _, wrap in responseBlock do
					local channelInfo = wrap[2]

					if channelInfo then
						_G.LiveChannels[channelInfo.Key] = channelInfo
					end
				end
			end)
		else
			for subChannel = 1, UNIT_SCALE_PER_PLAYER do
				local key = `@{userId}{KEY_ENDPOINT}{subChannel}`
				local channelInfo = _G.LiveChannels[key]

				if type(channelInfo) == "table" then
					pcall(channelInfo.Subscriber.Disconnect, channelInfo.Subscriber)
					table.clear(channelInfo)
					_G.LiveChannels[key] = nil
				end
			end
		end
	end)

	local function onPlayerAdded(player: Player)
		MessagingScaler:Fire({
			UserId = player.UserId,
			Toggle = true,
		})
	end

	local function onPlayerRemoving(player: Player)
		MessagingScaler:Fire({
			UserId = player.UserId,
			Toggle = false,
		})
	end

	for _, Player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, Player)
	end

	playerAddedConnection = Players.PlayerAdded:Connect(onPlayerAdded)
	playerRemovingConnection = Players.PlayerRemoving:Connect(onPlayerRemoving)
end

do -- MessagingInvokeReceptor
	local MessagingInvokeReceptor = MessagingManager.new(
		"MessagingInvokeReceptor",
		function(request, currentServerMetadata: MessagingMetadata, broadcasterServerMetadata: MessagingMetadata?)
			local from = request[1] -- [1] = From
			local to = request[2]
			local response = request[3]
			local invokeToken = request[4]

			if to == game.JobId then
				if type(invokeToken) == "string" then
					local invoke: LemonSignal.Signal = _G.Invokes[invokeToken]

					if invoke then
						invoke:Fire(response)
						invoke:Destroy()
						_G.Invokes[invokeToken] = nil
					end
				end
			end
		end
	)
end

return MessagingManager