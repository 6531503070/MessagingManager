--!native
--!optimize 2

--[[
	MessagingManager @Dev_Bas
	A module centralized MessagingService topic subscription, by use one global endpoint.
	And provide freature, share publish request and scalable based on player size per server.
--]] 

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
local BrokerRequest = require(script.BrokerRequest)

_G.Message = _G.Message or {}
_G.LiveChannels = _G.LiveChannels or {}

KeyEndpoint = "/"
DefaultMaxChannel = 15 -- Max is 20 (Based from MessagingService)
UnitScalePerPlayer = 5 -- Max is 8 (Based from MessagingService)
ShowLog = false

local DefaultWarn = warn
local function warn(...)
	if ShowLog then
		DefaultWarn(...)
	end
end
do -- @Setup // MessagingService (Centralized)
	CentralizedEndpoint = function(Message)
		local Data, Sent = Message.Data, Message.Sent
		local Success, Batch = pcall(HttpService.JSONDecode, HttpService, Data)
		if (Success and typeof(Batch) == "table") then
			local Topic = Batch.Topic
			local Param = Batch.Param
			local MessagingManagerObject = _G.Message[Topic]
			if (MessagingManagerObject) then
				if (typeof(MessagingManagerObject.Callback) == "function") then
					pcall(MessagingManagerObject.Callback, Param)
				end
			end
		end
	end -- Blueprint
	do
		print("MessagingManager is connecting.")
		if (RunService:IsRunning() and RunService:IsServer()) then
			local Broker = BrokerRequest.new(20, 10)
			for Id = 1, DefaultMaxChannel do
				Broker:AddRequest(function()
					local Success, Error, Response do
						Success, Error = pcall(function()
							Response = {}
							Response.Key = (`G{KeyEndpoint}{Id}`)
							Response.Subscriber = MessagingService:SubscribeAsync(Response.Key, CentralizedEndpoint)
						end)
					end
					return {Success, Response, Error}
				end)
			end
			local ResponseBlock, OverallSuccess = Broker:Run()
			if (not OverallSuccess) then
				warn("MessagingManager, some channel are missing.")
			end
			for _, Wrap in ResponseBlock do
				local ChannelInfo = Wrap[2]
				if (ChannelInfo) then
					_G.LiveChannels[ChannelInfo.Key] = ChannelInfo
				end
			end
		end
		print("MessagingManager is ready.")
	end
end

--//////////////////////////////////////////////////////////////////////
--//////////////////////////////////////////////////////////////////////

local MessagingManagerObject = {}
MessagingManagerObject.__index = MessagingManagerObject

function MessagingManagerObject:Rename(NewTopic: string)
	if (_G.Message[NewTopic]) then
		warn("MessagingManagerObject, new topic was used. (Proccess Skipped)")
		return self
	end
	local PreviousTopic = self.Topic
	if (_G.Message[PreviousTopic] == self) then
		_G.Message[PreviousTopic] = nil
		self.Topic = NewTopic
		_G.Message[NewTopic] = self
	end
	return self
end

function MessagingManagerObject:Disconnect()
	local Topic = self.Topic
	local MessagingManagerObject = _G.Message[Topic]
	table.clear(MessagingManagerObject)
	_G.Message[Topic] = nil
end

function MessagingManagerObject:Destroy()
	self:Disconnect()
end

function MessagingManagerObject:Pub(Param: {})
	if (self.Topic == nil) then
		local Catuion = "MessagingManagerObject, was already destroy."
		return false, Catuion, warn(Catuion)
	end
	if (RunService:IsStudio()) then
		-- Simulate
		warn(`(Studio-Mode), MessagingManagerObject {self.Topic} is simulate not real production.`)
		return pcall(function()
			self.Callback(Param)
		end)
	else 
		-- Real - Production
		return pcall(function()
			local NextKey, NextChannelInfo = next(_G.LiveChannels, self._NextKey)
			if (type(NextChannelInfo) == "table") then
				MessagingService:PublishAsync(NextChannelInfo.Key, HttpService:JSONEncode({
					Topic = self.Topic,
					Param = Param,
				}))
			end
			self._NextKey = NextKey
		end)
	end
end

--//////////////////////////////////////////////////////////////////////
--//////////////////////////////////////////////////////////////////////

local MessagingManager = {}

function MessagingManager.new <T> (Topic: string, Callback: (Param: T) -> ())
	local self = {}
	setmetatable(self, MessagingManagerObject)
	self.Topic = Topic
	self.Callback = Callback
	self._NextKey = nil
	local MessagingManagerObjectExist = _G.Message[Topic]
	if (not MessagingManagerObjectExist) then
		--// new MessagingManagerObject()
		_G.Message[Topic] = self
		return self
	else
		--// return exist
		warn("MessagingManager, topic is already exist. (Return Exist)")
		return MessagingManagerObjectExist
	end
end

function MessagingManager.DestroyTo(Topic: string)
	local MessagingManagerObject = _G.Message[Topic]
	if (MessagingManagerObject) then
		MessagingManagerObject:Destroy()
	end
end

_G._NextGlobalKey = nil
function MessagingManager.PubTo(Topic: string, Param: {})
	return pcall(function()
		local Success, Error, NextKey, NextChannelInfo do
			Success, Error = pcall(function()
				NextKey, NextChannelInfo = next(_G.LiveChannels, _G._NextGlobalKey)
			end)
			if (not Success) then
				NextKey, NextChannelInfo = next(_G.LiveChannels)
			end
		end
		if (type(NextChannelInfo) == "table") then
			if (RunService:IsStudio()) then
				-- Simulate
				local MessagingManagerObject = _G.Message[Topic]
				if (MessagingManagerObject) then
					warn(`(Studio-Mode), MessagingManagerObject {MessagingManagerObject.Topic} is simulate not real production.`)
					return pcall(function()
						MessagingManagerObject.Callback(Param)
					end)
				else
					warn(`(Studio-Mode), MessagingManagerObject {MessagingManagerObject.Topic} not found.`)
				end
			else
				-- Real - Production
				MessagingService:PublishAsync(NextChannelInfo.Key, HttpService:JSONEncode({
					Topic = Topic,
					Param = Param,
				}))
			end
		end
		_G._NextGlobalKey = NextKey
	end)
end

--//////////////////////////////////////////////////////////////////////
--//////////////////////////////////////////////////////////////////////

do
	local MessagingScaler = MessagingManager.new("MessagingScaler", function(Param)
		local Toggle = Param.Toggle
		local UserId = Param.UserId
		if (Toggle == true) then
			spawn(function()
				local Broker = BrokerRequest.new(20, 10)
				for SubChannel = 1, UnitScalePerPlayer do
					Broker:AddRequest(function()
						local Success, Error, Response do
							Success, Error = pcall(function()
								Response = {}
								Response.Key = `@{UserId}{KeyEndpoint}{SubChannel}`
								Response.Subscriber = MessagingService:SubscribeAsync(Response.Key, CentralizedEndpoint)
							end)
						end
						return {Success, Response, Error}
					end)
				end
				local ResponseBlock, OverallSuccess = Broker:Run()
				if (not OverallSuccess) then
					warn("MessagingManager, some channel are missing.")
				end
				for _, Wrap in ResponseBlock do
					print(Wrap)
					local ChannelInfo = Wrap[2]
					if (ChannelInfo) then
						_G.LiveChannels[ChannelInfo.Key] = ChannelInfo
					end
				end
			end)
		else
			for SubChannel = 1, UnitScalePerPlayer do
				local Key = `@{UserId}{KeyEndpoint}{SubChannel}`
				local ChannelInfo = _G.LiveChannels[Key]
				if (type(ChannelInfo) == "table") then
					pcall(ChannelInfo.Subscriber.Disconnect, ChannelInfo.Subscriber)
					table.clear(ChannelInfo)
					_G.LiveChannels[Key] = nil
				end
			end
		end
	end)
	local function OnPlayerAdded(player: Player)
		MessagingScaler:Pub({
			UserId = player.UserId,
			Toggle = true,
		})
	end
	local function OnPlayerRemoving(player: Player)
		MessagingScaler:Pub({
			UserId = player.UserId,
			Toggle = false,
		})
	end
	for _, Player in Players:GetPlayers() do
		task.spawn(OnPlayerAdded, Player)
	end
	MessagingManager._PlayerAdded = Players.PlayerAdded:Connect(OnPlayerAdded)
	MessagingManager._PlayerRemoving = Players.PlayerRemoving:Connect(OnPlayerRemoving)
end

function MessagingManager:Destroy()
	MessagingManager._PlayerAdded:Disconnect()
	MessagingManager._PlayerRemoving:Disconnect()
	for Topic in _G.Message do
		MessagingManager.DestroyTo(Topic)
	end
	table.clear(MessagingManager)
end

return MessagingManager