--[=[
	@class MessagingManagerObject
	An object for managing the MessagingService subscription.
]=]

--- @within MessagingManagerObject
--- @prop topic string

--- @within MessagingManagerObject
--- @prop callback (request: T, current_server_metadata: MessagingMetadata, broadcaster_server_metadata: MessagingMetadata) -> ()

--- @within MessagingManagerObject
--- @private
--- @prop _nextkey string?

local HttpService = game:GetService("HttpService")
local MessagingService = game:GetService("MessagingService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local Constants = require(script.Parent.Constants)
local Quid = require(ServerScriptService.ServerPackages.Quid)
local Signal = require(ServerScriptService.ServerPackages.Signal)
local messaging_metadata = require(script.Parent.messaging_metadata)
local next_number = require(script.Parent.next_number)

local MessagingManagerObject = {}
MessagingManagerObject.__index = MessagingManagerObject

--- Rename entry point of the MessagingService subscription.
---
--- @within MessagingManagerObject
--- @param new_topic string
--- @return MessagingManagerObject
function MessagingManagerObject:Rename(new_topic: string)
	if _G.Message[new_topic] then
		warn("MessagingManagerObject, new topic was used. (Proccess Skipped)")
		return self
	end

	local previous_topic = self.topic
	if _G.Message[previous_topic] == self then
		_G.Message[previous_topic] = nil
		self.topic = new_topic
		_G.Message[new_topic] = self
	end

	return self
end

--- Disconnect to the MessagingService subscription.
---
--- @within MessagingManagerObject
function MessagingManagerObject:Disconnect()
	local topic = self.topic
	local messaging_manager_object = _G.Message[topic]

	table.clear(messaging_manager_object)
	_G.Message[topic] = nil
end

--- Aliase of `:Disconnect()` method.
---
--- @within MessagingManagerObject
function MessagingManagerObject:Destroy()
	self:Disconnect()
end

--- (One-way communication) Messaging to topic to do an action (Not-Guaranteed)
---
--- @yields
--- @within MessagingManagerObject
--- @param request T
--- @param including_metadata boolean? -- [default=false] including metadata example server jobId.
--- @error "MessagingManagerObject not found."
function MessagingManagerObject:Fire<T>(request: T, including_metadata: boolean?)
	if self.topic == nil then error(`MessagingManagerObject not found.`) end

	local broadcaster_server_metadata: messaging_metadata.MessagingMetadata? = if including_metadata
		then messaging_metadata()
		else nil

	if RunService:IsStudio() then
		-- In-Simulation
		warn(`(Studio-Mode), MessagingManagerObject {self.topic} is simulate not real production.`)
		task.wait(next_number(table.unpack(Constants.SIMULATE_DELAY)))

		local ok: boolean, err: string
		do
			ok, err = pcall(function(...)
				self.callback(
					request,
					messaging_metadata(messaging_metadata()),
					messaging_metadata(broadcaster_server_metadata)
				)
			end)
		end

		if not ok then error(err) end
	else
		-- In-Production
		local next_key, next_channel_info = next(_G.LiveChannels, self._nextkey)

		if type(next_channel_info) == "table" then
			local ok: boolean, err: string
			do
				ok, err = pcall(function(...)
					MessagingService:PublishAsync(
						next_channel_info.Key,
						buffer.fromstring(HttpService:JSONEncode({
							self.topic, -- [1] = Topic
							request, -- [2] = Request
							broadcaster_server_metadata, -- [3] = BroadcasterServerMetadata
						}))
					)
				end)
			end

			if not ok then error(err) end
		end

		self._nextkey = next_key
	end
end

--- (Two-way communication) Messaging to topic to do an action and get the response (Not-Guaranteed).
---
--- @yields
--- @within MessagingManagerObject
--- @param request T
--- @param approx_response_time number? -- [default=6] a waiting seconds before disconnect and return nil response.
--- @param including_metadata boolean? -- [default=false] including metadata example server jobId?
--- @return any
--- @error "MessagingManagerObject not found."
function MessagingManagerObject:Invoke<T>(request: T, approx_response_time: number?, including_metadata: boolean?)
	if self.topic == nil then error(`MessagingManagerObject not found.`) end

	local invoke_token = `{self.topic}-{Quid.next()}` -- 94^16 possibility.
	local signal = Signal.new()

	_G.Invokes[invoke_token] = signal

	local broadcaster_server_metadata: messaging_metadata.MessagingMetadata? = if including_metadata
		then messaging_metadata()
		else nil

	if RunService:IsStudio() then
		-- In-Simulation
		task.delay(next_number(table.unpack(Constants.SIMULATE_DELAY)), function()
			local ok: boolean, err: string, response
			do
				ok, err = pcall(function(...)
					response = {
						self.callback(
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
	else
		-- In-Production
		task.spawn(function()
			local next_key, next_channel_info = next(_G.LiveChannels, self._nextkey)
			if type(next_channel_info) == "table" then
				MessagingService:PublishAsync(
					next_channel_info.Key,
					buffer.fromstring(HttpService:JSONEncode({
						self.topic, -- [1] = Topic
						request, -- [2] = Request
						broadcaster_server_metadata, -- [3] = BroadcasterServerMetadata
						invoke_token, -- [4] = InvokeToken?
					}))
				)
			end

			self._nextkey = next_key
		end)

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

return MessagingManagerObject
