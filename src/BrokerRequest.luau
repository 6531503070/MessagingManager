--!native
--!optimize 2

--[[
	BrokerRequest @Dev_Bas
	A module iteration async call in an efficient way.
--]]

local Signal = require(script.Parent.Signal)
local Module = {}
Module.__index = Module

function Module.new(ProccessPerIteration: number?, RequestAttemptLimit: number?)
	local self = setmetatable({}, Module)
	self.ProccessPerIteration = ProccessPerIteration or 4
	self.RequestAttemptLimit = RequestAttemptLimit or 3
	--// Output
	self.Requests = {}
	self.Responses = {}
	return self
end

function Module:AddRequest(Function: (Quota: number) -> ())
	table.insert(self.Requests, Function)
	return self
end

--// @yieldable
function Module:Run(Callback: (Success: boolean, Responsse: any, Error: string?) -> ()?): thread | any
	table.clear(self.Responses)
	local OverallSuccess = true
	local Responses = self.Responses
	local Requests = self.Requests
	local function Process()
		while (#Requests > 0) do
			local ChunkData = {
				OnComplete = Signal.new(),
				WorkLoad = math.min(table.maxn(Requests), self.ProccessPerIteration),
				WorkComplete = 0,
			}
			for Load = 1, ChunkData.WorkLoad do
				local GetPage = math.max(1, (table.maxn(Requests) - Load) + 1)
				local WorkNode = Requests[GetPage]
				if (WorkNode) then
					coroutine.wrap(function(Chunk, Quota: number)
						local Success, Response, Error repeat
							Success, Response, Error = unpack(WorkNode())
							if (not Success) then
								Quota -= 1
								task.wait(1)
							end
						until Success or (Quota <= 0)
						task.wait()
						--// @Promise
						if (not Success) then
							OverallSuccess = false
						end
						local Sent = {Success, Response, Error}
						Responses[GetPage] = Sent
						Requests[GetPage] = nil
						Chunk.WorkComplete += 1
						if (Chunk.WorkComplete == Chunk.WorkLoad) then
							Chunk.OnComplete:Fire()
							Chunk.OnComplete = nil
						end
						if (type(Callback) == "function") then
							Callback(unpack(Sent))
						end
					end)(ChunkData, self.RequestAttemptLimit)
				end
			end
			if (ChunkData.OnComplete) then
				ChunkData.OnComplete:Wait()
				ChunkData.OnComplete:Destroy()
				ChunkData.OnComplete = nil
			end
		end
	end
	if (type(Callback) == "function") then
		return task.spawn(Process) -- Async @no-yield
	else
		Process() -- Sync @yield
	end
	return Responses, OverallSuccess
end

function Module:Clear()
	table.clear(self.Requests)
	table.clear(self.Responses)
end

function Module:Destroy()
	setmetatable(self, nil)
	table.clear(self)
end

return Module